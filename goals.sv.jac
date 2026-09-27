"""Goals — GoalRank, SetGoal, CloseGoal (SOH-169).

OWNER: Person A. See contracts/walkers.md for the exact walker/report shapes
and AGENTS.md for the working rules this file must obey:
  - Relationships never decay: `Knows.last_contact` is display only. Nothing
    in here reads it to raise or lower a score; it may only break display
    ties (see `_sort_key`).
  - Relevance lives on the `RelevantTo` edge (Person -> Goal), never on the
    Person node itself. `GoalRank` rebuilds it in full on every call;
    `CloseGoal` deletes it, never the Goal node.
  - `by llm` returns plain `obj`s, never nodes/edges — copy fields out before
    persisting (see `materialize`).
  - Every walker is `:priv` (own-root only, JWT required).

Label rule (SOH-169, amended after Capture landed — Capture gives every
person it creates a Knows edge from Me, marking people it only heard about
as `Person.status == "proposed"` with `Knows.status == "proposed"`):
  - known: a Knows edge exists AND Person.status == "confirmed" AND
    Knows.status != "proposed".
  - route: the person is one Reported hop from a known person and is not
    itself known — whether or not it also has its own (proposed) Knows
    edge, or no Knows edge at all. `via` = that known person's name.
  - cold: has a proposed Knows edge (proposed Person or proposed edge
    status) and is NOT reachable by a Reported hop from any known person.
"""

import from datetime { datetime }
import from jaclang { JacRuntime as Jac }
import from schema { Me, Person, Note, Fact, Intent, Goal, Knows, Reported, HasGoal, FactAbout, IntentAbout, Mentions, AssertsIntent, RelevantTo }
import from llm { llm }
import time;

# ---------------------------------------------------------------- LLM batch

obj RankedItem {
    has index: int;
    has strength: str;
    has reason: str;
    has evidence_indices: list[int];
    has opener: str;
}
sem RankedItem.index = "The candidate's # number from the input, copied exactly.";
sem RankedItem.strength = "strong only when a listed fact or intent directly serves the goal; medium when the person's org/role plausibly helps and one piece of evidence points that way; weak when only a job title or org is similar. A matching title alone is never more than weak.";
sem RankedItem.reason = "One sentence citing the specific evidence, e.g. 'Her note says she wants feedback from wheelchair users, which is what your goal needs.' Never mention how long since you last spoke.";
sem RankedItem.evidence_indices = "The evidence numbers you relied on for this candidate; empty if none.";
sem RankedItem.opener = "A two-sentence message opener to this person that mentions one specific thing from the evidence; friendly, no flattery, no mention of the goal being a 'goal'.";

obj RankResult {
    has items: list[RankedItem];
}
sem RankResult.items = "One item for every candidate in the input, none skipped, none invented.";

def rank_candidates(goal: str, candidates_text: str) -> RankResult by llm(temperature=0.2);

# ---------------------------------------------------------------- plain data

obj EvidenceItem {
    has id: str;
    has kind: str;
    has observed_at: str;
    has span: str;
}

obj Candidate {
    has person: Person;
    has label: str;
    has via: str = "";
    has evidence_items: list[EvidenceItem] = [];
    has days_since_contact: int | None = None;
}

# ---------------------------------------------------------------- deterministic helpers
# (no LLM; each is a plain `def` so a test block can call it directly on
# hand-built objs/nodes attached under root.)

"""Parse an ISO-8601 timestamp permissively: strips a trailing "Z" and drops
any tzinfo so comparisons against `datetime.now()` (naive) never raise.
Returns None on anything unparsable instead of propagating."""
def _parse_naive_utc(ts: str) -> datetime | None {
    if not ts {
        return None;
    }
    cleaned = ts;
    if cleaned.endswith("Z") {
        cleaned = cleaned[:-1];
    }
    try {
        dt = datetime.fromisoformat(cleaned);
    } except (ValueError, TypeError) {
        return None;
    }
    if dt.tzinfo is not None {
        dt = dt.replace(tzinfo=None);
    }
    return dt;
}

def compute_days_since_contact(last_contact: str, now: datetime) -> int | None {
    dt = _parse_naive_utc(last_contact);
    if dt is None {
        return None;
    }
    delta = now - dt;
    return delta.days;
}

"""Facts, then intents, then notes mentioning `p` — capped at 8 total.
Intents whose `expires_at` is non-empty and already in the past are skipped."""
def gather_evidence(p: Person, now: datetime) -> list[EvidenceItem] {
    items: list[EvidenceItem] = [];

    for f in [p <-:FactAbout:<-] {
        if len(items) >= 8 {
            break;
        }
        items.append(EvidenceItem(id=jid(f), kind="fact", observed_at=f.observed_at, span=f.text));
    }

    for i in [p <-:IntentAbout:<-] {
        if len(items) >= 8 {
            break;
        }
        if i.expires_at {
            exp_dt = _parse_naive_utc(i.expires_at);
            if exp_dt is None {
                continue;   # unparsable expires_at -> skip this intent
            }
            if exp_dt < now {
                continue;   # expired -> skip
            }
        }
        observed_at = "";
        notes_for_intent = [i <-:AssertsIntent:<-];
        if notes_for_intent {
            observed_at = notes_for_intent[0].captured_at;
        }
        items.append(EvidenceItem(id=jid(i), kind="intent", observed_at=observed_at, span=i.text));
    }

    for n in [p <-:Mentions:<-] {
        if len(items) >= 8 {
            break;
        }
        items.append(EvidenceItem(id=jid(n), kind="note", observed_at=n.captured_at, span=n.text[:120]));
    }

    return items;
}

"""Resolve one evidence jid (from a `RelevantTo.evidence` list) back to the
report shape `{id, kind, observed_at, span}`. Mirrors `gather_evidence`'s
per-item construction so a cached serve and a fresh rebuild produce identical
evidence shapes for the same underlying Fact/Intent/Note. `jobj` never
authorizes (see `jac-sv-persistence`), so every resolution is gated by
`check_read_access` AND an exact match on the caller's own root — a jid that
doesn't resolve, isn't readable, isn't owned by this root, or isn't a
Fact/Intent/Note is simply dropped (returns None) rather than raising."""
def evidence_item_from_jid(some_id: str) -> dict[str, any] | None {
    try {
        n = jobj(some_id);
    } except Exception {
        return None;
    }
    if n is None {
        return None;
    }
    if not Jac.check_read_access(getattr(n, "__jac__")) {  # jac:ignore[E1053]
        return None;
    }
    owner = str(getattr(n, "__jac__").root).replace("-", "");
    if owner != jid(root) {
        return None;
    }

    if isinstance(n, Fact) {
        f = n as Fact;
        return {"id": jid(f), "kind": "fact", "observed_at": f.observed_at, "span": f.text};
    }
    if isinstance(n, Intent) {
        i = n as Intent;
        observed_at = "";
        notes_for_intent = [i <-:AssertsIntent:<-];
        if notes_for_intent {
            observed_at = notes_for_intent[0].captured_at;
        }
        return {"id": jid(i), "kind": "intent", "observed_at": observed_at, "span": i.text};
    }
    if isinstance(n, Note) {
        note = n as Note;
        return {"id": jid(note), "kind": "note", "observed_at": note.captured_at, "span": note.text[:120]};
    }
    return None;
}

"""Candidate collection — deterministic, no LLM. See the module docstring
for the known / route / cold rule."""
glob RANK_CAP: int = 60;

def collect_candidates(me: Me, now: datetime) -> list[Candidate] {
    all_c = collect_all_candidates(me, now);
    if len(all_c) > RANK_CAP {
        return all_c[:RANK_CAP];
    }
    return all_c;
}

"""Every candidate (known, then route, then cold), deduped, uncapped -
`GoalRank` ranks the first `RANK_CAP` and reports how many it left out."""
def collect_all_candidates(me: Me, now: datetime) -> list[Candidate] {
    known: list[Candidate] = [];
    known_jids: list[str] = [];
    proposed_people: list[Person] = [];
    proposed_edges: list[Knows] = [];

    for p in [me ->:Knows:->] {
        if p.archived {
            continue;   # SOH-220: archived people are never candidates
        }
        # Never zip parallel node/edge queries by index (no order guarantee
        # across the two separate traversals) - look up each person's own
        # Knows edge directly instead.
        matched = [edge me ->:Knows:-> p];
        e = matched[0];
        if p.status == "confirmed" and e.status != "proposed" {
            days = compute_days_since_contact(e.last_contact, now);
            known.append(Candidate(person=p, label="known", evidence_items=gather_evidence(p, now), days_since_contact=days));
            known_jids.append(jid(p));
        } else {
            proposed_people.append(p);
            proposed_edges.append(e);
        }
    }

    route_jids: list[str] = [];
    route_via: dict[str, str] = {};
    route_people: dict[str, Person] = {};

    for kc in known {
        p = kc.person;
        for q in [p ->:Reported:->] {
            if q.archived {
                continue;
            }
            qid = jid(q);
            if qid in known_jids {
                continue;
            }
            if qid in route_jids {
                continue;
            }
            route_jids.append(qid);
            route_via[qid] = p.name;
            route_people[qid] = q;
        }
    }

    route: list[Candidate] = [];
    for qid in route_jids {
        q = route_people[qid];
        route.append(Candidate(person=q, label="route", via=route_via[qid], evidence_items=gather_evidence(q, now), days_since_contact=None));
    }

    cold: list[Candidate] = [];
    for i in range(len(proposed_people)) {
        p = proposed_people[i];
        e = proposed_edges[i];
        pid = jid(p);
        if pid in known_jids {
            continue;   # already surfaced as known
        }
        if pid in route_jids {
            continue;   # already surfaced as a route candidate
        }
        days = compute_days_since_contact(e.last_contact, now);
        cold.append(Candidate(person=p, label="cold", evidence_items=gather_evidence(p, now), days_since_contact=days));
    }

    all_candidates = known + route + cold;

    result: list[Candidate] = [];
    seen: list[str] = [];
    for c in all_candidates {
        cid = jid(c.person);
        if cid in seen {
            continue;
        }
        seen.append(cid);
        result.append(c);
    }

    return result;
}

"""How many distinct people `collect_all_candidates` would consider (every
`Knows` person plus every person reported by a confirmed-known one), without
gathering evidence - cheap enough for the cached path."""
def count_candidate_people(me: Me) -> int {
    ids: list[str] = [];
    for p in [me ->:Knows:->] {
        if p.archived {
            continue;
        }
        pid = jid(p);
        if pid not in ids {
            ids.append(pid);
        }
        matched = [edge me ->:Knows:-> p];
        if matched and p.status == "confirmed" and matched[0].status != "proposed" {
            for q in [p ->:Reported:->] {
                if q.archived {
                    continue;
                }
                qid = jid(q);
                if qid not in ids {
                    ids.append(qid);
                }
            }
        }
    }
    return len(ids);
}

"""True when any of `notes` was captured after `ranked_at` (or when the
ranking has no `ranked_at` at all - a ranking from before SOH-212 has
unknown freshness). Unparsable captured_at values are ignored."""
def ranking_is_stale(ranked_at: str, notes: list[Note]) -> bool {
    ranked_dt = _parse_naive_utc(ranked_at);
    if ranked_dt is None {
        return True;
    }
    for n in notes {
        dt = _parse_naive_utc(n.captured_at);
        if dt is not None and dt > ranked_dt {
            return True;
        }
    }
    return False;
}

"""Adds `stale`, `ranked_at`, `truncated`, `total_people` to every item."""
def annotate_ranking(items: list[dict[str, any]], stale: bool, ranked_at: str, total_people: int) -> list[dict[str, any]] {
    for item in items {
        item["stale"] = stale;
        item["ranked_at"] = ranked_at;
        item["truncated"] = total_people > RANK_CAP;
        item["total_people"] = total_people;
    }
    return items;
}

"""One compact line per candidate for the single batched `by llm` call."""
def build_candidates_text(candidates: list[Candidate]) -> str {
    lines: list[str] = [];
    idx = 0;
    for c in candidates {
        ev_parts: list[str] = [];
        ei = 0;
        for item in c.evidence_items {
            ev_parts.append(f"[{ei}] {item.kind}: {item.span} ({item.observed_at})");
            ei += 1;
        }
        ev_str = " ".join(ev_parts) if ev_parts else "(no evidence)";
        label_str = c.label;
        if c.label == "route" and c.via {
            label_str = f"route via {c.via}";
        }
        lines.append(f"#{idx} {c.person.name} | org: {c.person.org} | title: {c.person.title} | label: {label_str} | evidence: {ev_str}");
        idx += 1;
    }
    return "\n".join(lines);
}

"""Deterministic fallback used when the batched `by llm` call fails (after
one retry, see GoalRank). Never reports "medium" with empty evidence:
evidence_indices names the exact fact/intent items that produced the signal,
so `materialize`'s evidence-gate (a candidate with no mapped evidence is
always "weak") holds. The opener names the first evidence item's span when
one exists, so the fallback still reads as specific rather than generic."""
def fallback_rank(candidates: list[Candidate]) -> list[RankedItem] {
    ranked: list[RankedItem] = [];
    idx = 0;
    for c in candidates {
        signal_indices: list[int] = [];
        ei = 0;
        for item in c.evidence_items {
            if item.kind == "intent" or item.kind == "fact" {
                signal_indices.append(ei);
            }
            ei += 1;
        }
        opener = "";
        if c.evidence_items {
            first_span = c.evidence_items[0].span;
            opener = f"Hi {c.person.name}, I was thinking about what you mentioned about {first_span[:80]}.";
        }
        ranked.append(RankedItem(
            index=idx,
            strength="medium" if signal_indices else "weak",
            reason="Ranking unavailable right now; ordered by the evidence in your notes.",
            evidence_indices=signal_indices,
            opener=opener
        ));
        idx += 1;
    }
    return ranked;
}

def _sort_key(item: dict[str, any]) -> tuple[int, int, int] {
    strength = item["strength"];
    label = item["label"];
    days = item["days_since_contact"];

    strength_rank = 2;
    if strength == "strong" {
        strength_rank = 0;
    } elif strength == "medium" {
        strength_rank = 1;
    }

    label_rank = 2;
    if label == "known" {
        label_rank = 0;
    } elif label == "route" {
        label_rank = 1;
    }

    days_rank = 999999999;
    if days is not None {
        days_rank = days as int;
    }

    return (strength_rank, label_rank, days_rank);
}

"""Serve the goal's ranking straight off its existing `RelevantTo` edges, no
LLM call. One entry per edge, evidence rebuilt from each edge's `evidence`
jid list via `evidence_item_from_jid` (unknown/foreign jids silently
dropped), `days_since_contact` recomputed from the caller's own `Knows` edge
to that person as of now (route candidates have no `Knows` edge from `me`,
so they get `None`, same as a fresh run), ordered with the same `_sort_key`
a fresh `materialize` call uses. Returns `[]` when the goal has no incoming
`RelevantTo` edges yet, so `GoalRank` can fall through to the full rebuild."""
def serve_cached(goal: Goal, me: Me) -> list[dict[str, any]] {
    people = [goal <-:RelevantTo:<-];
    if not people {
        return [];
    }

    now = datetime.now();
    report_items: list[dict[str, any]] = [];

    for p in people {
        if p.archived {
            continue;   # SOH-220: a cached ranking never shows an archived person
        }
        matched = [edge p ->:RelevantTo:-> goal];
        if not matched {
            continue;
        }
        e = matched[0];

        ev_out: list[dict[str, any]] = [];
        for eid in e.evidence {
            item = evidence_item_from_jid(eid);
            if item is not None {
                ev_out.append(item);
            }
        }

        knows_matches = [edge me ->:Knows:-> p];
        days = compute_days_since_contact(knows_matches[0].last_contact, now) if knows_matches else None;

        report_items.append({
            "person": p,
            "label": e.label,
            "strength": e.strength,
            "reason": e.reason,
            "evidence": ev_out,
            "days_since_contact": days,
            "opener": e.opener,
            "cached": True
        });
    }

    return sorted(report_items, key=_sort_key);
}

"""Deterministic materialization: delete this goal's existing RelevantTo
edges, create fresh ones, and return the report shape ordered best-first —
exactly one entry per candidate, regardless of what `ranked` contains.
`ranked[i].index` selects `candidates[i]`; indices out of range are dropped;
duplicate indices keep the first occurrence; a candidate `ranked` never
mentions gets a default weak/no-ranking entry; strength not in the enum
normalizes to "weak"; and — the product rule that a matching title alone is
never more than weak — any candidate whose mapped evidence ends up empty is
forced back down to "weak" even if the ranker said otherwise."""
def materialize(goal: Goal, ranked: list[RankedItem], candidates: list[Candidate]) -> list[dict[str, any]] {
    for e in [edge goal <-:RelevantTo:<-] {
        del e;
    }

    n = len(candidates);
    by_index: dict[int, RankedItem] = {};
    for item in ranked {
        if item.index < 0 or item.index >= n {
            continue;
        }
        if item.index in by_index {
            continue;   # dedupe by index: first wins
        }
        by_index[item.index] = item;
    }

    report_items: list[dict[str, any]] = [];

    for idx in range(n) {
        c = candidates[idx];

        if idx in by_index {
            item = by_index[idx];
            strength = item.strength if item.strength in ["strong", "medium", "weak"] else "weak";
            reason = item.reason;
            opener = item.opener;
            evidence_indices = item.evidence_indices;
        } else {
            strength = "weak";
            reason = "No ranking returned for this person.";
            opener = "";
            evidence_indices = [];
        }

        ev_out: list[dict[str, any]] = [];
        ev_ids: list[str] = [];
        for ei in evidence_indices {
            if ei >= 0 and ei < len(c.evidence_items) {
                it = c.evidence_items[ei];
                ev_ids.append(it.id);
                ev_out.append({"id": it.id, "kind": it.kind, "observed_at": it.observed_at, "span": it.span});
            }
        }

        if not ev_ids {
            strength = "weak";   # strong/medium requires at least one evidence item
        }

        p = c.person;
        p +>:RelevantTo(reason=reason, strength=strength, evidence=ev_ids, opener=opener, label=c.label):+> goal;

        report_items.append({
            "person": p,
            "label": c.label,
            "strength": strength,
            "reason": reason,
            "evidence": ev_out,
            "days_since_contact": c.days_since_contact,
            "opener": opener,
            "cached": False
        });
    }

    return sorted(report_items, key=_sort_key);
}

# ---------------------------------------------------------------- walkers

walker:priv SetGoal {
    """Get-or-create Me; create (or reactivate, if identical text exists) a
    Goal under Me via HasGoal; deactivate every other goal. Reports [Goal]."""
    has text: str;
    has reports: list[Goal] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if existing {
            me = existing[0];
        } else {
            me = (root ++> Me(name="me"))[0];
        }

        goals = [me ->:HasGoal:->];
        matches = [g for g in goals if g.text == self.text];

        if matches {
            target = matches[0];
            target.active = True;
        } else {
            target = (me +>:HasGoal:+> Goal(text=self.text, created_at=datetime.now().isoformat()))[0];
        }

        for g in goals {
            if jid(g) != jid(target) {
                g.active = False;
            }
        }

        report target;
    }
}

walker:priv CloseGoal {
    """Deactivate the goal and delete its RelevantTo edges. Never deletes
    the node. Reports ["closed"] or ["not_found"]."""
    has goal_id: str;
    has reports: list[str] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report "not_found";
            disengage;
        }
        me = existing[0];

        matches = [g for g in [me ->:HasGoal:->] if jid(g) == self.goal_id];
        if not matches {
            report "not_found";
            disengage;
        }
        goal = matches[0];

        goal.active = False;
        for e in [edge goal <-:RelevantTo:<-] {
            del e;
        }
        report "closed";
    }
}

walker:priv GoalRank {
    """Rebuild the goal's RelevantTo edges and report, ordered best-first,
    one entry per candidate. One batched `by llm` call for the whole run;
    falls back to deterministic ranking on failure. Goal not found -> [].

    `refresh=False` (default): if the goal already has at least one incoming
    `RelevantTo` edge, serve the ranking straight off those edges via
    `serve_cached` — no LLM call, entries carry `cached: true`. `refresh=True`,
    or no edges exist yet, takes the full rebuild path below; those entries
    carry `cached: false`. `CloseGoal` deletes the edges, so a reopened goal
    always re-ranks fresh next time."""
    has goal_id: str;
    has refresh: bool = False;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            disengage;
        }
        me = existing[0];

        matches = [g for g in [me ->:HasGoal:->] if jid(g) == self.goal_id];
        if not matches {
            disengage;
        }
        goal = matches[0];

        if not self.refresh {
            cached = serve_cached(goal, me);
            if cached {
                # SOH-212: never auto-refresh; tell the client whether notes
                # arrived after this ranking and whether the cap cut people.
                notes: list[Note] = [root --> [?:Note]];
                stale = ranking_is_stale(goal.ranked_at, notes);
                annotate_ranking(cached, stale, goal.ranked_at, count_candidate_people(me));
                for item in cached {
                    report item;
                }
                disengage;
            }
        }

        now = datetime.now();
        all_candidates = collect_all_candidates(me, now);
        total_people = len(all_candidates);
        candidates = all_candidates[:RANK_CAP] if total_people > RANK_CAP else all_candidates;

        ranked: list[RankedItem] = [];
        if candidates {
            candidates_text = build_candidates_text(candidates);
            try {
                result = rank_candidates(goal.text, candidates_text);
                ranked = result.items;
            } except Exception {
                # byLLM already retried internally 3x fast; wait out a 503
                # burst and try exactly once more before falling back.
                time.sleep(4);
                try {
                    result = rank_candidates(goal.text, candidates_text);
                    ranked = result.items;
                } except Exception {
                    ranked = fallback_rank(candidates);
                }
            }
        }

        results = materialize(goal, ranked, candidates);
        goal.ranked_at = now.isoformat();
        annotate_ranking(results, False, goal.ranked_at, total_people);
        for item in results {
            report item;
        }
    }
}
