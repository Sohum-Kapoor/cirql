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
import from schema { Me, Person, Fact, Intent, Goal, Knows, Reported, HasGoal, FactAbout, IntentAbout, Mentions, AssertsIntent, RelevantTo }
import from llm { llm }

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

"""Candidate collection — deterministic, no LLM. See the module docstring
for the known / route / cold rule."""
def collect_candidates(me: Me, now: datetime) -> list[Candidate] {
    known: list[Candidate] = [];
    known_jids: list[str] = [];
    proposed_people: list[Person] = [];
    proposed_edges: list[Knows] = [];

    for p in [me ->:Knows:->] {
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

    if len(result) > 60 {
        result = result[:60];
    }

    return result;
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

"""Deterministic fallback used when the batched `by llm` call fails.
Never reports "medium" with empty evidence: evidence_indices names the
exact fact/intent items that produced the signal, so `materialize`'s
evidence-gate (a candidate with no mapped evidence is always "weak") holds."""
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
        ranked.append(RankedItem(
            index=idx,
            strength="medium" if signal_indices else "weak",
            reason="Extraction unavailable; ranked by available evidence.",
            evidence_indices=signal_indices,
            opener=""
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
            "opener": opener
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
    falls back to deterministic ranking on failure. Goal not found -> []."""
    has goal_id: str;
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

        now = datetime.now();
        candidates = collect_candidates(me, now);

        ranked: list[RankedItem] = [];
        if candidates {
            candidates_text = build_candidates_text(candidates);
            try {
                result = rank_candidates(goal.text, candidates_text);
                ranked = result.items;
            } except Exception {
                ranked = fallback_rank(candidates);
            }
        }

        results = materialize(goal, ranked, candidates);
        for item in results {
            report item;
        }
    }
}
