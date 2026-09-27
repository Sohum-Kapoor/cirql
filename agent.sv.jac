"""Agent inbox (SOH-223): RunAgent composes GoalRank / GapFinder / PathFinder /
Tend / incoming asks into evidence-backed AgentActions; a human approves,
dismisses or snoozes each one. Nothing sends.

OWNER: Person A. Report shapes: contracts/walkers.md (SOH-223 block).
Rules this file obeys:
  - Own root only. Every walker is `:priv`; every id a caller passes is
    resolved through `reads.my_node` (readable AND owned by the caller).
  - No evidence, no action: a finding with zero resolvable evidence ids is
    dropped before it becomes an AgentAction, and `why` quotes evidence text.
  - Relationships never decay: nothing here reads `Knows.last_contact`;
    reconnect/follow_up come only from Tend's reason-based items.
  - No person-level score anywhere: a strength is always (Person, Goal).
  - Every step is deterministic this weekend (no `by llm` in this module).
    The throttle (one model-backed run per account per 10 minutes) is kept
    and every run is recorded as an AgentRun, so a model step can slot in.
  - Approve performs at most one in-app step (PostRequest, ReplyToRequest,
    CompletePromise) through the plain defs those walkers use. Drafts only.
"""

import json;
import from datetime { datetime, timedelta }
import from schema {
    Me, Person, Goal, Intent, Owns, HasGoal, RelevantTo, Reported, Knows,
    AgentAction, AgentRun, HasAction, HasAgentRun, IntroRequest, Promise,
    Note, Fact, Asserts, FactAbout, AssertsPromise, PromiseTo, Mentions
}
import from reads { my_node, receipt_for }
import from goals { evidence_item_from_jid, goal_noun_phrase }
import from gaps { warm_lines_for }
import from paths { find_path }
import from tend { tend_for }
import from drafts { gather_follow_up_evidence, fallback_draft, first_name }
import from scoring { collect_candidates, fallback_tokens, polish_reason }
import from exchange {
    all_requests, shared_replies, owner_root, visible_to_me, now_iso,
    post_request, reply_to_request
}

glob AGENT_THROTTLE_MINUTES: int = 10;
glob AGENT_RUNS_KEPT: int = 20;
glob AGENT_MAX_REQUESTS: int = 10;   # requests scanned per run (search-space cap)
glob AGENT_MAX_ANSWERS: int = 5;     # answer_ask findings proposed per run (SOH-223 tune)
glob AGENT_KINDS: list[str] = [
    "new_match", "ask_network", "route", "promise_due", "follow_up", "reconnect", "answer_ask"
];

# ---------------------------------------------------------------- small helpers

def _rank(strength: str) -> int {
    if strength == "strong" {
        return 2;
    }
    if strength == "medium" {
        return 1;
    }
    return 0;
}

def _clip(text: str, n: int) -> str {
    t = text.strip();
    if len(t) <= n {
        return t;
    }
    return t[:n - 3].rstrip() + "...";
}

"""One finding, before it becomes (or refreshes) an AgentAction. `propose`
False means "refresh an open action with this key, but never create one"."""
def make_finding(
    kind: str, title: str, why: str, evidence: list[str],
    person_id: str, goal_id: str, request_id: str, draft: str,
    payload: dict[str, any], source_walker: str, extra: str, propose: bool
) -> dict[str, any] {
    # SOH-226: product copy, not model narration - polished once, here, so
    # every step (`new_match`/`ask_network`/`route`/`promise_due`/`follow_up`/
    # `reconnect`/`answer_ask`) gets the same cleanup without repeating it.
    return {
        "kind": kind, "title": polish_reason(title), "why": polish_reason(why), "evidence": evidence,
        "person_id": person_id, "goal_id": goal_id, "request_id": request_id,
        "draft": draft, "payload_json": json.dumps(payload),
        "source_walker": source_walker,
        "dedup_key": f"{kind}|{person_id}|{goal_id}|{request_id}|{extra}",
        "propose": propose
    };
}

def active_goals(me: Me) -> list[Goal] {
    return [g for g in [me ->:HasGoal:->] if g.active];
}

"""Evidence ids that resolve, via reads.my_node (readable AND owned by the
caller), to one of the caller's own Fact/Intent/Note/Goal/Promise nodes."""
def resolvable(ids: list[str]) -> list[str] {
    out: list[str] = [];
    for i in ids {
        if not i or i in out {
            continue;
        }
        n = my_node(i);   # readable AND owned by the caller's root, else None
        if n is None {
            continue;
        }
        if isinstance(n, Fact) or isinstance(n, Intent) or isinstance(n, Note) or isinstance(n, Goal) or isinstance(n, Promise) {
            out.append(i);
        }
    }
    return out;
}

"""The one line about me an ask carries: Card headline, else the first
sentence of Me.about. Never a name from anyone's graph."""
def about_line_for(me: Me) -> str {
    for c in [me ->:Owns:->] {
        if c.headline {
            return _clip(c.headline, 140);
        }
    }
    first = me.about.split(".")[0] if me.about else "";
    return _clip(first, 140);
}

# ---------------------------------------------------------------- AgentRun (throttle + strength memory)

def agent_runs(me: Me) -> list[AgentRun] {
    return sorted([r for r in [me ->:HasAgentRun:->]], key=_run_key);
}

def _run_key(r: AgentRun) -> str {
    return r.ran_at;
}

"""The strengths the previous run saw, or None on the first run."""
def prior_strengths(me: Me) -> dict[str, str] | None {
    runs = agent_runs(me);
    if not runs {
        return None;
    }
    last = runs[-1];
    if not last.strengths_json {
        return {};
    }
    try {
        loaded = json.loads(last.strengths_json);
    } except Exception {
        return {};
    }
    out: dict[str, str] = {};
    for k in list(loaded.keys()) {
        out[str(k)] = str(loaded[k]);
    }
    return out;
}

"""False when a model-backed run happened for this account in the last
AGENT_THROTTLE_MINUTES minutes."""
def model_run_allowed(me: Me, now: datetime) -> bool {
    cutoff = (now - timedelta(minutes=AGENT_THROTTLE_MINUTES)).isoformat();
    for r in [me ->:HasAgentRun:->] {
        if r.model_backed and r.ran_at >= cutoff {
            return False;
        }
    }
    return True;
}

def record_run(me: Me, now: datetime, reason: str, model_backed: bool, strengths: dict[str, str]) -> AgentRun {
    run = (me +>:HasAgentRun:+> AgentRun(
        ran_at=now.isoformat(), reason=reason, model_backed=model_backed,
        strengths_json=json.dumps(strengths)
    ))[0];
    runs = agent_runs(me);
    if len(runs) > AGENT_RUNS_KEPT {
        for old in runs[:len(runs) - AGENT_RUNS_KEPT] {
            del old;
        }
    }
    return run;
}

# ---------------------------------------------------------------- steps (all deterministic)

"""Sort key for the first-run new_match cap: strong before medium (higher
rank first), tie-break by newest evidence (observed_at, ISO string sorts
lexically). Used with `sorted(..., reverse=True)`."""
def _new_match_sort_key(c: dict[str, any]) -> tuple[int, str] {
    return (c["rank"] as int, str(c["observed_at"]));
}

"""True when the caller has ever had a new_match AgentAction (any status —
open, approved, dismissed, snoozed): a proposal the human has actually seen.
SOH-223 review fix #5: an early AgentRun whose `current` strengths came back
empty (no active goal yet, or a goal with zero RelevantTo edges at all) is
still recorded, so `prior_strengths` reads back `{}` next time — not None —
and `step_new_match` would otherwise treat that as real history and skip the
first-run cap entirely, proposing every match that "rose from empty". The
cap must stay on until the user has actually seen a new_match proposal, not
merely until an AgentRun row exists."""
def has_new_match_action(me: Me) -> bool {
    for a in [me ->:HasAction:->] {
        if a.kind == "new_match" {
            return True;
        }
    }
    return False;
}

"""new_match: RelevantTo edges on the active goal(s). strong/medium with
resolvable evidence only. FIRST run (prior is None, OR the account has never
had a new_match action proposed yet — SOH-223 review fix #5, see
`has_new_match_action`): propose at most the top 3 candidates across every
active goal, strong before medium, ties broken by newest evidence. Later
runs: propose only when the (person, goal) strength rose since the previous
run (SOH-223: no cap once the account has a history — a real rise is always
worth a look). `current` is filled with every strength seen (including
weak/below-threshold — SOH-223 tune verified this is what `prior_strengths`
reads back next run), for the next run's comparison."""
def step_new_match(goals: list[Goal], prior: dict[str, str] | None, current: dict[str, str], seen_before: bool) -> list[dict[str, any]] {
    raw: list[dict[str, any]] = [];
    for goal in goals {
        gid = jid(goal);
        for p in [goal <-:RelevantTo:<-] {
            if p.archived {
                continue;
            }
            for e in [edge p ->:RelevantTo:-> goal] {
                pid = jid(p);
                key = f"{pid}|{gid}";
                current[key] = e.strength;
                if e.strength != "strong" and e.strength != "medium" {
                    continue;
                }
                ev = resolvable(list(e.evidence));
                if not ev {
                    continue;
                }
                prev = "";
                if prior is not None and key in prior {
                    prev = (prior as dict[str, str])[key];
                }
                first = evidence_item_from_jid(ev[0]);
                observed_at = str(first["observed_at"]) if first is not None else "";
                goal_phrase = goal_noun_phrase(goal.text);
                reason = e.reason or f"Relevant to your goal, '{goal_phrase}'.";
                raw.append({
                    "key": key, "rank": _rank(e.strength), "observed_at": observed_at,
                    "rose": _rank(e.strength) > _rank(prev),
                    # SOH-226: first name only + a noun-phrase goal, never the
                    # raw first-person goal sentence spliced into a title.
                    "title": f"{first_name(p.name)}: {e.strength} match for '{goal_phrase}'",
                    "why": reason,
                    "evidence": ev, "person_id": pid, "goal_id": gid, "draft": e.opener,
                    "payload": {"strength": e.strength, "prev_strength": prev}
                });
            }
        }
    }

    first_run = prior is None or not seen_before;
    if first_run {
        top_keys: list[str] = [];
        for c in sorted(raw, key=_new_match_sort_key, reverse=True) {
            if len(top_keys) >= 3 {
                break;
            }
            top_keys.append(str(c["key"]));
        }
        for c in raw {
            c["propose"] = str(c["key"]) in top_keys;
        }
    } else {
        for c in raw {
            c["propose"] = bool(c["rose"]);
        }
    }

    out: list[dict[str, any]] = [];
    for c in raw {
        out.append(make_finding(
            "new_match", str(c["title"]), str(c["why"]), c["evidence"] as list[str],
            str(c["person_id"]), str(c["goal_id"]), "", str(c["draft"]),
            c["payload"] as dict[str, any], "GoalRank", "", bool(c["propose"])
        ));
    }
    return out;
}

"""Deterministic gap listing: an active goal with no warm (known/route,
strong/medium) path in the caller's graph (gaps.warm_lines_for is empty).
GapFinder's per-kind breakdown needs the model, so RunAgent asks for the
goal itself."""
def gap_goals(me: Me, goals: list[Goal]) -> list[Goal] {
    return [g for g in goals if not warm_lines_for(me, g)];
}

def step_ask_network(me: Me, gaps: list[Goal]) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    about = about_line_for(me);
    for goal in gaps {
        # SOH-226: `goal_noun_phrase` is a no-op on a goal already stored as
        # a noun phrase (the common case, going forward) - defense-in-depth
        # for goals stored before this fix landed.
        need = _clip(goal_noun_phrase(goal.text), 140);
        out.append(make_finding(
            "ask_network",
            f"Ask the network: {need}",
            f"Your goal '{need}' has no warm path in your graph yet. No strong or medium match you know or can reach.",
            [jid(goal)], "", jid(goal), "", need,
            {"need": need, "about_line": about},
            "GapFinder", "", True
        ));
    }
    return out;
}

"""The first person reachable only through a Reported edge whose org/title/
facts share a token with the goal text. Deterministic; never a direct Knows."""
def _route_target(me: Me, goal: Goal) -> Person | None {
    tokens = fallback_tokens(goal.text);
    if not tokens {
        return None;
    }
    known_ids = [jid(p) for p in [me ->:Knows:->]];
    for p in [me ->:Knows:->] {
        for q in [p ->:Reported:->] {
            if jid(q) in known_ids or q.archived {
                continue;
            }
            text = f"{q.title} {q.org}";
            for t in fallback_tokens(text) {
                if t in tokens {
                    return q;
                }
            }
        }
    }
    return None;
}

"""route: top 2 gaps x top 1 evidenced route (paths.find_path)."""
def step_route(me: Me, gaps: list[Goal]) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for goal in gaps[:2] {
        t = _route_target(me, goal);
        if t is None {
            continue;
        }
        target = t as Person;
        path = find_path(me, target, 3);
        if not path["found"] {
            continue;
        }
        hops = path["hops"] as list[dict[str, any]];
        if len(hops) < 2 {
            continue;
        }
        connector = hops[0]["person"] as Person;
        ev_ids: list[str] = [];
        span = "";
        for h in hops[1:] {
            hev = h["evidence"];
            if hev is not None {
                hd = hev as dict[str, str];
                ev_ids.append(hd["id"]);
                if not span {
                    span = hd["span"];
                }
            }
        }
        ev = resolvable(ev_ids);
        if not ev {
            continue;
        }
        where = f"at {target.org}" if target.org else (target.title or "who fits");
        at_org = f" at {target.org}" if target.org else "";
        # SOH-226: quote the noun phrase rather than splicing a raw
        # (possibly first-person) goal sentence into the draft's own grammar.
        goal_phrase = _clip(goal_noun_phrase(goal.text), 120);
        draft = (
            f"Hi {connector.name}, you mentioned {target.name}{at_org}. "
            f"I'm looking for '{goal_phrase}'. Would you be open to introducing us? "
            "Happy to write a short note you can forward."
        );
        told = f"\"{_clip(span, 160)}\"" if span else "a note you captured";
        out.append(make_finding(
            "route",
            f"{connector.name} knows someone {where}. Ask {connector.name}?",
            f"{path['reason']} You were told: {told}. Your goal '{goal_phrase}' has no warm path yet.",
            ev, jid(connector), jid(goal), "", draft,
            {"target_id": jid(target), "connector_id": jid(connector)},
            "PathFinder", jid(target), True
        ));
    }
    return out;
}

"""promise_due / follow_up / reconnect from Tend (reason-based, never decay).
Tend's newly_relevant is covered by new_match."""
def step_tend(me: Me, now: datetime) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for it in tend_for(me, now, 50) {
        tkind = str(it["kind"]);
        kind = "";
        if tkind == "open_promise" {
            kind = "promise_due";
        } elif tkind == "expiring_intent" {
            kind = "follow_up";
        } elif tkind == "stale_fact" {
            kind = "reconnect";
        }
        if not kind {
            continue;
        }
        p = it["person"] as Person;
        if p.archived {
            continue;
        }
        evd = it["evidence"] as dict[str, any];
        eid = str(evd["id"]);
        span = str(evd["span"]);
        if not eid {
            continue;
        }
        fb = fallback_draft(p, gather_follow_up_evidence(p, now));
        draft = str(fb["draft"]);
        payload: dict[str, any] = {"evidence_kind": str(evd["kind"])};
        if kind == "promise_due" {
            title = f"Keep your promise to {p.name}: {_clip(span, 80)}";
            payload = {"promise_id": eid, "complete": False, "due": ""};
            pn = my_node(eid);
            if pn is not None and isinstance(pn, Promise) {
                payload["due"] = (pn as Promise).due;
            }
        } elif kind == "follow_up" {
            title = f"Follow up with {p.name} before \"{_clip(span, 60)}\" lapses";
        } else {
            title = f"Reconnect with {p.name}: check \"{_clip(span, 60)}\"";
        }
        out.append(make_finding(
            kind, title, str(it["reason"]), [eid], jid(p), "", "", draft,
            payload, "Tend", eid, True
        ));
    }
    return out;
}

"""True when `a` and `b` (each already fallback_tokens: lowercased, alnum,
>= 4 chars, not a stopword) name the same idea allowing for a simple plural/
suffix (`nurse` <-> `nurses`): equal, or one is a prefix of the other."""
def _tok_match(a: str, b: str) -> bool {
    if a == b {
        return True;
    }
    return a.startswith(b) or b.startswith(a);
}

"""Collapse `need`'s own tokens onto one representative per `_tok_match`
family, so a plural/singular pair IN THE NEED ITSELF (e.g. "nurse nurses")
never counts as two independent signals against a candidate (SOH-223 review
fix #3). First token seen for a family wins; order otherwise preserved."""
def _dedupe_need_tokens(tokens: list[str]) -> list[str] {
    out: list[str] = [];
    for t in tokens {
        dup = False;
        for o in out {
            if _tok_match(t, o) {
                dup = True;
                break;
            }
        }
        if not dup {
            out.append(t);
        }
    }
    return out;
}

"""The distinct tokens of `need` (fallback_tokens, deduped by `_tok_match`
family — SOH-223 review fix #3) that also name something in THIS ONE
candidate's own facts/intents/title/org text — never anywhere else on the
root. Order follows the need's own token order."""
def _answer_ask_match_tokens(need: str, cand: dict[str, any]) -> list[str] {
    p = cand["person"] as Person;
    text = f"{p.title} {p.org}";
    for e in cand["evidence"] as list[dict[str, str]] {
        text = text + " " + e["text"];
    }
    cand_tokens = fallback_tokens(text);
    matched: list[str] = [];
    for nt in _dedupe_need_tokens(fallback_tokens(need)) {
        for ct in cand_tokens {
            if _tok_match(nt, ct) {
                if nt not in matched {
                    matched.append(nt);
                }
                break;
            }
        }
    }
    return matched;
}

"""Evidence items from THIS candidate that name something in `need`,
allowing the same plural/prefix match `_answer_ask_match_tokens` uses."""
def _answer_ask_evidence_hits(need: str, cand: dict[str, any]) -> list[dict[str, str]] {
    need_tokens = _dedupe_need_tokens(fallback_tokens(need));
    hits: list[dict[str, str]] = [];
    for e in cand["evidence"] as list[dict[str, str]] {
        for ct in fallback_tokens(e["text"]) {
            found = False;
            for nt in need_tokens {
                if _tok_match(nt, ct) {
                    found = True;
                    break;
                }
            }
            if found {
                hits.append(e);
                break;
            }
        }
    }
    return hits;
}

"""Tighter than a bare keyword scan (SOH-223 tune, B's live feedback:
"experienced nurses" was answered by an account with no nurses). A candidate
is KEPT only when at least 2 DISTINCT (by `_tok_match` family — SOH-223
review fix #3) need tokens name something in that candidate's OWN
facts/intents/title/org text. SOH-223 review fix #2: scans `candidates`
directly with `_answer_ask_match_tokens`/`_answer_ask_evidence_hits` —
never scoring.fallback_results' EXACT-token pre-filter, which dropped a
candidate that matched only by prefix (need "nurses", fact "nurse") before
`_answer_ask_match_tokens` ever saw it. Each kept item carries its `matched`
tokens for `why`."""
def _answer_ask_hits(candidates: list[dict[str, any]], need: str) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for cand in candidates {
        matched = _answer_ask_match_tokens(need, cand);
        if len(matched) < 2 {
            continue;
        }
        hits = _answer_ask_evidence_hits(need, cand);
        evidence = cand["evidence"] as list[dict[str, str]];
        source = hits if hits else evidence;
        evidence_ids: list[str] = [];
        for e in source {
            evidence_ids.append(e["jid"]);
        }
        out.append({"person_id": jid(cand["person"] as Person), "evidence_ids": evidence_ids, "matched": matched});
    }
    return out;
}

"""answer_ask: incoming Exchange requests visible to me (same filter as
ListIncomingRequests), newest first, where `_answer_ask_hits` (the tightened
deterministic candidate filter) finds >= 1 candidate. Capped at
AGENT_MAX_ANSWERS proposals per run. The title and why carry the need, the
matched tokens, and my own evidence text — never the requester's identity
beyond what the request already shows."""
def step_answer_ask(me: Me, now: datetime) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    me_root = jid(root);
    now_s = now_iso();
    answered = [r.request_id for r in shared_replies() if owner_root(r) == me_root];
    seen = 0;
    for req in sorted(all_requests(), key=_req_key, reverse=True) {
        if len(out) >= AGENT_MAX_ANSWERS {
            break;
        }
        if seen >= AGENT_MAX_REQUESTS {
            break;
        }
        if owner_root(req) == me_root {
            continue;
        }
        if not visible_to_me(req) {
            continue;
        }
        if req.status == "declined" or (req.expires_at and req.expires_at < now_s) {
            continue;
        }
        rid = jid(req);
        if rid in answered {
            continue;
        }
        seen += 1;
        candidates = collect_candidates(me, [req.from_handle], now);
        hits = _answer_ask_hits(candidates, req.need);
        if not hits {
            continue;
        }
        text_by_id: dict[str, str] = {};
        for c in candidates {
            for e in c["evidence"] as list[dict[str, str]] {
                text_by_id[e["jid"]] = e["text"];
            }
        }
        picked = _first_resolvable_hit(hits);
        if picked is None {
            continue;
        }
        top = picked["hit"] as dict[str, any];
        ev = picked["evidence"] as list[str];
        quote = text_by_id[ev[0]] if ev[0] in text_by_id else "";
        matched = top["matched"] as list[str];
        matches_note = f" (matches: {', '.join(matched)})" if matched else "";
        n = len(hits);
        word = "person" if n == 1 else "people";
        af = make_finding(
            "answer_ask",
            f"Answer an ask: {_clip(req.need, 100)}",
            f"{req.from_handle} is looking for \"{_clip(req.need, 120)}\"; {n} {word} in your graph may fit: \"{_clip(quote, 160)}\"{matches_note}. Replying shares a count and a strength, no names.",
            ev, str(top["person_id"]), "", rid, "",
            {"need": req.need, "from_handle": req.from_handle, "top_person_id": str(top["person_id"]), "matched": matched},
            "ReplyToRequest", "", True
        );
        # One key per request: a dismissed ask stays dismissed even when the top candidate changes.
        af["dedup_key"] = "answer_ask|" + rid;
        out.append(af);
    }
    return out;
}

def _req_key(r: IntroRequest) -> str {
    return r.created_at;
}

"""The first hit in `hits` (already ordered by `_answer_ask_hits`) whose
evidence ids (capped at 4, deduped) resolve via `resolvable`; None when none
do. SOH-223 review fix #4: the old code took `hits[0]` unconditionally, so
one bad evidence id on the top hit silently dropped the whole request even
when a lower-ranked hit's evidence was perfectly fine."""
def _first_resolvable_hit(hits: list[dict[str, any]]) -> dict[str, any] | None {
    for h in hits {
        ev_ids: list[str] = [];
        for i in h["evidence_ids"] as list[str] {
            if i not in ev_ids and len(ev_ids) < 4 {
                ev_ids.append(i);
            }
        }
        resolved = resolvable(ev_ids);
        if resolved {
            return {"hit": h, "evidence": resolved};
        }
    }
    return None;
}

# ---------------------------------------------------------------- upsert

"""Create or refresh one finding. Returns 1 when an action became newly
visible (created), else 0. SOH-223 tune: a key already tracked by an
AgentAction is NEVER re-proposed while that action is open, approved,
dismissed or stale — open is refreshed in place (title/why/evidence/payload)
but stays the same action; approved/dismissed/stale are left alone entirely
(a human decision, or the agent's own `stale_ask_network_actions` below, was
already recorded for it). Only `run_agent_for`'s snoozed-reopen path and a
fresh key create/reopen an action."""
def upsert(me: Me, f: dict[str, any], by_key: dict[str, AgentAction], now_s: str) -> int {
    key = str(f["dedup_key"]);
    ev = f["evidence"] as list[str];
    if not ev {
        return 0;
    }
    propose = bool(f["propose"]);
    if key in by_key {
        a = by_key[key];
        if a.status == "open" {
            a.title = str(f["title"]);
            a.why = str(f["why"]);
            a.evidence = ev;
            a.payload_json = str(f["payload_json"]);
            if not a.draft {
                a.draft = str(f["draft"]);
            }
        }
        return 0;   # approved / dismissed: never re-proposed
    }
    if not propose {
        return 0;
    }
    a = (me +>:HasAction:+> AgentAction(
        kind=str(f["kind"]), title=str(f["title"]), why=str(f["why"]),
        evidence=ev, person_id=str(f["person_id"]), goal_id=str(f["goal_id"]),
        request_id=str(f["request_id"]), draft=str(f["draft"]),
        payload_json=str(f["payload_json"]), status="open", created_at=now_s,
        source_walker=str(f["source_walker"]), dedup_key=key
    ))[0];
    by_key[key] = a;
    return 1;
}

"""SOH-212 (judge3): an `ask_network` proposal for a goal must not stay
`open` once that goal gets a warm path — otherwise the Inbox shows "no warm
path" (the `ask_network` card's own `why`) directly under the `new_match`
card(s) that just gave it one. Uses the exact same test that gates creating
the action in the first place (`gaps.warm_lines_for`, via `gap_goals`): any
still-`open` `ask_network` action whose `goal_id` is one of the caller's
ACTIVE goals but is no longer in `gaps` is marked `status = "stale"` with
`resolved_at` = now and `approval_source = "agent:warm_path_found"`.
Idempotent — a goal that never had an `ask_network` action, or one already
resolved (approved/dismissed/snoozed/stale), is untouched; once stale, the
same goal's `ask_network` finding is never generated again by `step_ask_network`
(it only proposes for goals still in `gaps`), so nothing re-opens it while
the warm path holds."""
def stale_ask_network_actions(me: Me, goals: list[Goal], gaps: list[Goal], now_s: str) -> int {
    active_goal_ids = [jid(g) for g in goals];
    gap_goal_ids = [jid(g) for g in gaps];
    count = 0;
    for a in [me ->:HasAction:->] {
        if a.kind != "ask_network" or a.status != "open" {
            continue;
        }
        if not a.goal_id or a.goal_id not in active_goal_ids {
            continue;
        }
        if a.goal_id in gap_goal_ids {
            continue;   # still no warm path -> stays open
        }
        a.status = "stale";
        a.resolved_at = now_s;
        a.approval_source = "agent:warm_path_found";
        count += 1;
    }
    return count;
}

"""Deterministic core of RunAgent, callable on any `me` (tests)."""
def run_agent_for(me: Me, reason: str, now: datetime) -> dict[str, any] {
    now_s = now.isoformat();
    skipped: list[str] = ["serendipity"];
    model_steps: list[str] = [];   # none this weekend; a model step appends its name here
    model_ok = model_run_allowed(me, now);
    if model_steps and not model_ok {
        skipped.append("throttled");
    }

    new_count = 0;
    by_key: dict[str, AgentAction] = {};
    for a in [me ->:HasAction:->] {
        if a.status == "snoozed" {
            a.status = "open";
            a.resolved_at = "";
            new_count += 1;
        }
        by_key[a.dedup_key] = a;
    }

    goals = active_goals(me);
    prior = prior_strengths(me);
    current: dict[str, str] = {};
    seen_before = has_new_match_action(me);
    findings: list[dict[str, any]] = [];
    findings.extend(step_new_match(goals, prior, current, seen_before));
    gaps = gap_goals(me, goals);
    stale_ask_network_actions(me, goals, gaps, now_s);
    findings.extend(step_ask_network(me, gaps));
    findings.extend(step_route(me, gaps));
    findings.extend(step_tend(me, now));
    findings.extend(step_answer_ask(me, now));

    for f in findings {
        new_count += upsert(me, f, by_key, now_s);
    }

    run = record_run(me, now, reason, bool(model_steps) and model_ok, current);
    total_open = len([a for a in [me ->:HasAction:->] if a.status == "open"]);
    return {
        "run_id": jid(run), "ran_at": now_s, "new": new_count,
        "total_open": total_open, "skipped": skipped
    };
}

# ---------------------------------------------------------------- list

def evidence_view(ids: list[str]) -> list[dict[str, str]] {
    out: list[dict[str, str]] = [];
    for i in ids {
        n = my_node(i);
        if n is None {
            continue;
        }
        if isinstance(n, Goal) {
            g = n as Goal;
            out.append({"id": jid(g), "kind": "goal", "observed_at": g.created_at, "span": g.text});
            continue;
        }
        r = receipt_for(n);
        if "error" in r {
            continue;
        }
        span = r["span"] or _clip(r["text"], 120);
        out.append({"id": r["id"], "kind": r["kind"], "observed_at": r["captured_at"], "span": span});
    }
    return out;
}

"""Newest first by minute; promise_due first within the same minute."""
def _action_key(a: AgentAction) -> tuple[str, int, str] {
    return (a.created_at[:16], 1 if a.kind == "promise_due" else 0, a.created_at);
}

def list_actions_for(me: Me, status: str, limit: int) -> list[dict[str, any]] {
    st = status.strip().lower();
    acts = [a for a in [me ->:HasAction:->] if st in ["all", ""] or a.status == st];
    ordered = sorted(acts, key=_action_key, reverse=True);
    lim = min(max(limit, 1), 100);
    out: list[dict[str, any]] = [];
    for a in ordered[:lim] {
        person: Person | None = None;
        if a.person_id {
            n = my_node(a.person_id);
            if isinstance(n, Person) {
                person = n as Person;
            }
        }
        out.append({"action": a, "person": person, "evidence": evidence_view(list(a.evidence))});
    }
    return out;
}

# ---------------------------------------------------------------- resolve

def _payload(a: AgentAction) -> dict[str, any] {
    if not a.payload_json {
        return {};
    }
    try {
        d = json.loads(a.payload_json);
    } except Exception {
        return {};
    }
    if isinstance(d, dict) {
        return d;
    }
    return {};
}

def _mark(a: AgentAction, status: str) {
    a.status = status;
    a.resolved_at = now_iso();
    if status == "approved" {
        a.approval_source = "in_app";
    }
}

"""Approve performs the mapped in-app step; nothing sends. Returns the
`result` dict; the action is marked approved only when the step succeeded."""
def approve(a: AgentAction, edited_draft: str, complete: bool) -> dict[str, any] {
    if edited_draft.strip() {
        a.draft = edited_draft.strip();
    }
    pl = _payload(a);
    if a.kind == "ask_network" {
        need = str(pl["need"]) if "need" in pl else a.draft;
        if edited_draft.strip() {
            need = edited_draft.strip();
        }
        about = str(pl["about_line"]) if "about_line" in pl else "";
        posted = post_request(need, about, 7, "everyone");
        if isinstance(posted, dict) and "error" in posted {
            return posted;
        }
        _mark(a, "approved");
        a.request_id = jid(posted);
        return {"step": "posted", "request": posted};
    }
    if a.kind == "answer_ask" {
        replied = reply_to_request(a.request_id);
        if isinstance(replied, dict) and "error" in replied {
            return replied;
        }
        _mark(a, "approved");
        return {"step": "replied", "reply": replied};
    }
    if a.kind == "promise_due" {
        if complete {
            pl["complete"] = True;
            a.payload_json = json.dumps(pl);
        }
        if "complete" in pl and bool(pl["complete"]) and "promise_id" in pl {
            n = my_node(str(pl["promise_id"]));
            if n is None or not isinstance(n, Promise) {
                return {"error": "not_found"};
            }
            pr = n as Promise;
            pr.done = True;
            _mark(a, "approved");
            return {"step": "CompletePromise", "promise": pr};
        }
        _mark(a, "approved");
        return {"step": "none", "draft": a.draft};
    }
    _mark(a, "approved");
    return {"step": "draft_saved", "draft": a.draft};
}

# ---------------------------------------------------------------- walkers

walker:priv RunAgent {
    """Upsert one AgentAction per finding in the caller's own graph. Reports
    one {run_id, ran_at, new, total_open, skipped}; nothing when no Me."""
    has reason: str = "manual";
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report {"error": "not_found"};
            return;
        }
        report run_agent_for(existing[0], self.reason or "manual", datetime.now());
    }
}

walker:priv ListAgentActions {
    """The caller's AgentActions with status `status` ("all" for every
    status), newest first, each with its person and resolved evidence."""
    has status: str = "open";
    has limit: int = 30;
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            return;
        }
        for row in list_actions_for(existing[0], self.status, self.limit) {
            report row;
        }
    }
}

walker:priv ResolveAgentAction {
    """approve | dismiss | snooze one of the caller's own AgentActions.
    `complete` (additive) marks a promise_due's Promise done on approve."""
    has action_id: str;
    has decision: str;
    has edited_draft: str = "";
    has complete: bool = False;
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        n = my_node(self.action_id);
        if n is None or not isinstance(n, AgentAction) {
            report {"error": "not_found"};
            return;
        }
        a = n as AgentAction;
        d = self.decision.strip().lower();
        if d not in ["approve", "dismiss", "snooze"] {
            report {"error": "invalid_state"};
            return;
        }
        if a.status != "open" and a.status != "snoozed" {
            report {"error": "invalid_state"};
            return;
        }
        result: dict[str, any] = {};
        if d == "approve" {
            result = approve(a, self.edited_draft, self.complete);
        } elif d == "dismiss" {
            if self.edited_draft.strip() {
                a.draft = self.edited_draft.strip();
            }
            _mark(a, "dismissed");
            result = {"step": "dismissed"};
        } else {
            _mark(a, "snoozed");
            result = {"step": "snoozed"};
        }
        report {"action": a, "result": result};
    }
}

walker:priv DevSeedAgent {
    """DEV-ONLY (tests and the live check): seeds the caller's own root with
    what RunAgent looks for. Creates Me if missing, a goal with a strong
    evidenced RelevantTo edge, a second active goal with no warm path, a
    reported route toward it, and an open promise with its Note. Reports the
    ids. Never call this from the client."""
    has tag: str = "";
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        me: Me = existing[0] if existing else (root ++> Me(name="Agent Dev", about="Building a battery-recycling startup."))[0];
        now = datetime.now().isoformat();
        t = self.tag;
        note = (root ++> Note(text=f"Met Maya {t} at the climate meetup. She is a partner at Seedling Climate Fund and invests in battery startups. I promised to send her our deck. Dev {t} said his cousin Sam {t} works at Northwind Robotics.", kind="debrief", captured_at=now))[0];
        maya = (me +>:Knows(how_met="climate meetup", source_note=jid(note)):+> Person(name=f"Maya {t}".strip(), org="Seedling Climate Fund", title="Partner"))[0];
        dev = (me +>:Knows(how_met="school", source_note=jid(note)):+> Person(name=f"Dev {t}".strip(), org="Umich", title="Student"))[0];
        sam = (dev +>:Reported(source_note=jid(note), span="his cousin Sam works at Northwind Robotics"):+> Person(name=f"Sam {t}".strip(), org="Northwind Robotics", title="Robotics engineer"))[0];
        note +>:Mentions(span="Maya"):+> maya;
        fact = (note +>:Asserts(span="invests in battery startups"):+> Fact(text="Maya invests in climate battery startups", observed_at=now))[0];
        fact +>:FactAbout:+> maya;
        pr = (note +>:AssertsPromise(span="send her our deck"):+> Promise(text="send Maya our deck"))[0];
        pr +>:PromiseTo:+> maya;
        g1 = (me +>:HasGoal:+> Goal(text=f"raise a climate seed round {t}".strip(), created_at=now))[0];
        maya +>:RelevantTo(reason="Maya invests in climate battery startups", strength="strong", evidence=[jid(fact)], label="known"):+> g1;
        g2 = (me +>:HasGoal:+> Goal(text=f"find a robotics engineer for pilots {t}".strip(), created_at=now))[0];
        report {
            "me_id": jid(me), "goal_id": jid(g1), "gap_goal_id": jid(g2), "maya_id": jid(maya),
            "dev_id": jid(dev), "sam_id": jid(sam), "fact_id": jid(fact), "promise_id": jid(pr), "note_id": jid(note)
        };
    }
}
