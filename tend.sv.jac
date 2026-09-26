"""Tend — reason-based nudges, no timers, no decay (SOH-196, PRD J6).

OWNER: Person A. See contracts/walkers.md for the exact report shape and
ordering. AGENTS.md rules this file must obey:
  - A nudge exists only for a REASON grounded in the graph: an open promise,
    an intent about to expire, a person newly relevant to the active goal, or
    a stale fact. "You haven't talked in N days" is NEVER a reason on its own
    — `Knows.last_contact` surfaces only as `days_since_contact` (display),
    it is never read to decide whether a person is included or to rank
    anything except the `newly_relevant` block's own display order.
  - `:priv`, own-root only, no `by llm` anywhere in this module.

Deterministic gathering is scoped from the caller's own `Me` via typed
traversals (`me ->:Knows:-> Person`, then reverse `PromiseTo`/`IntentAbout`/
`FactAbout`/`RelevantTo` off each known Person) rather than a root-wide scan
(`[root --> [?:Note]]`, the idiom `reads.sv.jac`'s `list_promises_raw` uses).
This is the "or equivalent" reads.sv.jac allows: every traversal here starts
from a node reference (`me`, then each `Person`) so a test can build one
isolated `me` + its own people/promises/intents/facts and call `tend_for`
directly without the shared-persisted-test-root ambiguity `[root -->
[?:Me]][0]` would have inside a helper (AGENTS.md gotcha) — the walker itself
still does that one lookup, since at real runtime (`:priv`, own root) there
is exactly one `Me`.

`_parse_naive_utc` / `compute_days_since_contact` / `evidence_item_from_jid`
are imported from `goals.sv.jac` rather than re-implemented (same idiom
`drafts.sv.jac` and `recall.sv.jac` already use for `_parse_naive_utc`).
"""

import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal,
    Knows, PromiseTo, AssertsPromise, FactAbout, IntentAbout, AssertsIntent,
    RelevantTo, HasGoal
}
import from goals { _parse_naive_utc, compute_days_since_contact, evidence_item_from_jid }

# ---------------------------------------------------------------- helpers

"""Every Person reachable via `me ->:Knows:->`, deduped by jid. Order is the
traversal order (insertion order of the Knows edges), not otherwise sorted —
each nudge kind below sorts its own block."""
def _known_people(me: Me) -> list[Person] {
    people: list[Person] = [];
    seen: list[str] = [];
    for p in [me ->:Knows:->] {
        pid = jid(p);
        if pid in seen {
            continue;
        }
        seen.append(pid);
        people.append(p);
    }
    return people;
}

"""The caller's active goal, or None. Mirrors GraphView's `graph_view_for`
(reads.sv.jac): keeps the LAST goal found with `active == True` rather than
asserting exactly one exists — SetGoal already guarantees at most one, this
just never crashes if that invariant is ever violated."""
def _active_goal(me: Me) -> Goal | None {
    goal: Goal | None = None;
    for g in [me ->:HasGoal:->] {
        if g.active {
            goal = g;
        }
    }
    return goal;
}

"""`me`'s own Knows edge to `p`'s `last_contact`, or "" if none (should not
happen for a `p` drawn from `_known_people(me)`, but never raises either
way). Display only — see module docstring."""
def _knows_last_contact(me: Me, p: Person) -> str {
    matched = [edge me ->:Knows:-> p];
    if matched {
        return matched[0].last_contact;
    }
    return "";
}

"""Strip every gathering function's private bookkeeping keys (`_due`,
`_days_until`, `_sort_days`, `_observed_at`) down to the exact contract
shape: `{ kind, person, reason, evidence, suggested_action,
days_since_contact }`."""
def _strip(item: dict[str, any]) -> dict[str, any] {
    return {
        "kind": item["kind"],
        "person": item["person"],
        "reason": item["reason"],
        "evidence": item["evidence"],
        "suggested_action": item["suggested_action"],
        "days_since_contact": item["days_since_contact"]
    };
}

# ---------------------------------------------------------------- gather: open promises

"""Every OPEN Promise (`done == False`) made to a known person, via the
reverse `PromiseTo` edge (scoped to `p`, so cross-test-root leakage never
happens even on the shared jac-testing root). `reason` cites the promise's
own text and, when set, its `due`; the asserting Note (via reverse
`AssertsPromise`) supplies the evidence `observed_at`."""
def _gather_open_promises(me: Me, people: list[Person], now: datetime) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for p in people {
        for pr in [p <-:PromiseTo:<-] {
            if pr.done {
                continue;
            }
            observed_at = "";
            notes: list[Note] = [pr <-:AssertsPromise:<-];
            if notes {
                observed_at = notes[0].captured_at;
            }
            reason = f"You promised {p.name}: {pr.text}";
            if pr.due {
                reason = reason + f" (due {pr.due})";
            }
            days = compute_days_since_contact(_knows_last_contact(me, p), now);
            out.append({
                "kind": "open_promise",
                "person": p,
                "reason": reason,
                "evidence": {"id": jid(pr), "kind": "promise", "span": pr.text, "observed_at": observed_at},
                "suggested_action": "Send it",
                "days_since_contact": days,
                "_due": pr.due
            });
        }
    }
    return out;
}

"""Open promises first ordered by `due` ascending, `""` due last (ties keep
traversal order — `sorted` is stable)."""
def _promise_sort_key(item: dict[str, any]) -> tuple[int, str] {
    due = item["_due"] as str;
    rank = 1 if not due else 0;
    return (rank, due);
}

# ---------------------------------------------------------------- gather: expiring intents

"""Every Intent about a known person, via the reverse `IntentAbout` edge,
whose `expires_at` is set, parseable, and within the next 14 days
(`0 <= days_until <= 14`) — already-expired intents are FreshnessSweep's
concern (surfaced there, reconfirmed there), not a Tend nudge; an unparsable
`expires_at` is skipped, never flagged, same idiom as `freshness.sv.jac`."""
def _gather_expiring_intents(people: list[Person], now: datetime) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for p in people {
        for it in [p <-:IntentAbout:<-] {
            if not it.expires_at {
                continue;
            }
            exp_dt = _parse_naive_utc(it.expires_at);
            if exp_dt is None {
                continue;
            }
            days_until = (exp_dt - now).days;
            if days_until < 0 or days_until > 14 {
                continue;
            }
            kind_word = "need";
            if it.kind == "offer" {
                kind_word = "offer";
            } elif it.kind == "open_to" {
                kind_word = "interest";
            }
            observed_at = "";
            notes: list[Note] = [it <-:AssertsIntent:<-];
            if notes {
                observed_at = notes[0].captured_at;
            }
            reason = f"{p.name}'s {kind_word} '{it.text}' expires in {days_until} days";
            out.append({
                "kind": "expiring_intent",
                "person": p,
                "reason": reason,
                "evidence": {"id": jid(it), "kind": "intent", "span": it.text, "observed_at": observed_at},
                "suggested_action": "Reconfirm or let it lapse",
                "days_since_contact": None,
                "_days_until": days_until
            });
        }
    }
    return out;
}

"""Soonest-to-expire first."""
def _intent_sort_key(item: dict[str, any]) -> int {
    return item["_days_until"] as int;
}

# ---------------------------------------------------------------- gather: newly relevant

"""Every person with a `strength == "strong"` `RelevantTo` edge on the ACTIVE
goal — traversed from the GOAL (reverse `RelevantTo`), not from `me`'s own
`Knows` edges, because a "route" or "cold" candidate GoalRank ranked strong
may have no direct `Knows` edge from `me` at all. No active goal, no entries.
`materialize` (goals.sv.jac) only ever writes `strength in
["strong","medium","weak"]` and forces a candidate with no mapped evidence
back down to `"weak"`, so a `"strong"` edge is guaranteed non-empty
`evidence`; the first jid that resolves (via `evidence_item_from_jid`)
becomes this nudge's evidence. Capped at 3 by the caller, ordered by
`days_since_contact` descending with null (no `Knows` edge — a route
candidate) first — display only, per the product rule."""
def _gather_newly_relevant(me: Me, active_goal: Goal | None, now: datetime) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    if active_goal is None {
        return out;
    }
    goal = active_goal as Goal;
    for p in [goal <-:RelevantTo:<-] {
        matched = [edge p ->:RelevantTo:-> goal];
        if not matched {
            continue;
        }
        e = matched[0];
        if e.strength != "strong" {
            continue;
        }
        ev_item: dict[str, any] | None = None;
        for eid in e.evidence {
            candidate = evidence_item_from_jid(eid);
            if candidate is not None {
                ev_item = candidate;
                break;
            }
        }
        if ev_item is None {
            ev_item = {"id": "", "kind": "fact", "span": e.reason, "observed_at": ""};
        }
        days = compute_days_since_contact(_knows_last_contact(me, p), now);
        out.append({
            "kind": "newly_relevant",
            "person": p,
            "reason": f"{p.name} is a strong match for your goal '{goal.text}'",
            "evidence": ev_item,
            "suggested_action": "Reach out (use the drafted opener)",
            "days_since_contact": days,
            "_sort_days": days
        });
    }
    return out;
}

"""Descending `days_since_contact`, `None` first (display only)."""
def _relevant_sort_key(item: dict[str, any]) -> tuple[int, int] {
    d = item["_sort_days"];
    if d is None {
        return (0, 0);
    }
    return (1, -(d as int));
}

# ---------------------------------------------------------------- gather: stale facts

"""Every Fact about a known person, via the reverse `FactAbout` edge, with
`status == "stale"` (set only by `FreshnessSweep`, freshness.sv.jac; never
deleted, only ever flagged). Capped at 2 by the caller, ordered oldest
`observed_at` first."""
def _gather_stale_facts(people: list[Person]) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for p in people {
        for f in [p <-:FactAbout:<-] {
            if f.status != "stale" {
                continue;
            }
            reason = f"A fact about {p.name} is stale: '{f.text}' (observed {f.observed_at})";
            out.append({
                "kind": "stale_fact",
                "person": p,
                "reason": reason,
                "evidence": {"id": jid(f), "kind": "fact", "span": f.text, "observed_at": f.observed_at},
                "suggested_action": "Reconfirm or forget",
                "days_since_contact": None,
                "_observed_at": f.observed_at
            });
        }
    }
    return out;
}

"""Oldest `observed_at` first (a stale fact confirmed longest ago surfaces
first)."""
def _stale_sort_key(item: dict[str, any]) -> str {
    return item["_observed_at"] as str;
}

# ---------------------------------------------------------------- tend_for

"""Deterministic, testable directly on a hand-built `me` (see tend.test.jac):
open promises (due ascending, "" last) -> intents expiring within 14 days
(soonest first) -> at most 3 strong `RelevantTo` matches on the active goal
(days_since_contact descending, null first) -> at most 2 stale facts (oldest
observed_at first). The whole ordered list is then capped at `limit`."""
def tend_for(me: Me, now: datetime, limit: int) -> list[dict[str, any]] {
    people = _known_people(me);
    active_goal = _active_goal(me);

    promises = sorted(_gather_open_promises(me, people, now), key=_promise_sort_key);
    intents = sorted(_gather_expiring_intents(people, now), key=_intent_sort_key);
    relevant = sorted(_gather_newly_relevant(me, active_goal, now), key=_relevant_sort_key);
    if len(relevant) > 3 {
        relevant = relevant[:3];
    }
    stale = sorted(_gather_stale_facts(people), key=_stale_sort_key);
    if len(stale) > 2 {
        stale = stale[:2];
    }

    ordered = promises + intents + relevant + stale;
    result = [_strip(it) for it in ordered];
    if len(result) > limit {
        result = result[:limit];
    }
    return result;
}

# ---------------------------------------------------------------- walker

walker:priv Tend {
    """Own root only, no LLM. Reports `tend_for`'s ordered, capped list; `[]`
    when the caller has no `Me` yet."""
    has limit: int = 8;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            disengage;
        }
        me = existing[0];
        items = tend_for(me, datetime.now(), min(max(self.limit, 0), 50));  # SOH-211 bounded
        for it in items {
            report it;
        }
    }
}
