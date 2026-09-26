"""Forget — delete and retract (SOH-188).

OWNER: Person A. See contracts/walkers.md `Forget(id: str)` for the exact
report shape and AGENTS.md for the working rules this file must obey:
  - Deleting a person or fact retracts what depended SOLELY on it. A Fact
    whose only `FactAbout` target is the deleted Person is deleted along
    with it; a Fact about that person AND someone else survives (only the
    dangling `FactAbout` edge to the deleted Person disappears, via the
    normal node-delete cascade — `jac guide jac-node-edge-patterns`:
    "Delete a node — cascades to ALL its edges"). Same pattern for
    Intent/IntentAbout and Promise/PromiseTo.
  - The Note (the receipt) is never deleted, never touched.
  - `Introduction`s are never deleted — one proposing a person being
    forgotten moves to `state = "canceled"`.
  - Users can correct the system: this is the one walker that actually
    deletes graph data (everything else — FreshnessSweep, CloseGoal — only
    flags or deactivates).
  - Every walker here is `:priv` (own-root only, JWT required). No `by llm`.
"""

import from jaclang { JacRuntime as Jac }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Introduction,
    Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, Knows, Reported, RelevantTo,
    HasGoal, Proposes
}

# ---------------------------------------------------------------- ownership idiom
# Mirrored from `reads.sv.jac` (`load`/`owner_root`/`readable`/`my_node`)
# rather than imported, so this module's only cross-file dependency is
# `schema` (see AGENTS.md import-cycle note in freshness.sv.jac).

def _load(some_id: str) -> object {
    try {
        return jobj(some_id);
    } except Exception {
        return None;
    }
}

def _owner_root(n: object) -> str {
    return str(getattr(n, "__jac__").root).replace("-", "");
}

def _readable(n: object) -> bool {
    return bool(Jac.check_read_access(getattr(n, "__jac__")));  # jac:ignore[E1053]
}

def _my_node(some_id: str) -> object {
    n = _load(some_id);
    if n is None {
        return None;
    }
    if not _readable(n) {
        return None;
    }
    if _owner_root(n) != jid(root) {
        return None;
    }
    return n;
}

def _not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

# ---------------------------------------------------------------- shared helper

"""Every RelevantTo edge (Person -> Goal) reachable from ANY Goal under the
caller's own root, whose `evidence` list contains `target_id`: prune the id
out in place, and DELETE the edge when its evidence becomes empty (SOH-211).
Returns the number of edges touched. Walks every `Me ->
HasGoal -> Goal` under `root` rather than "the one Me" (`[root --> [?:Me]]
[0]`) deliberately: `:priv` walkers only ever run on the caller's own root,
so in real (single-tenant) use there is exactly one Me anyway, and this form
sidesteps the "the one Me" ambiguity `reads.test.jac` documents for a shared,
persisted test root (`jac-testing`)."""
def _prune_relevant_to_evidence(target_id: str) -> int {
    count = 0;
    for g in [root --> [?:Me] ->:HasGoal:->] {
        for p in [g <-:RelevantTo:<-] {
            matched = [edge p ->:RelevantTo:-> g];
            if not matched {
                continue;
            }
            e = matched[0];
            if target_id in e.evidence {
                e.evidence = [x for x in e.evidence if x != target_id];
                count += 1;
                if not e.evidence {
                    # SOH-211: a ranking with no evidence left is unsupported;
                    # delete it so a cached GoalRank cannot serve its strength.
                    del e;
                }
            }
        }
    }
    return count;
}

# ---------------------------------------------------------------- Forget(Person)

"""Delete every Fact/Intent/Promise whose ONLY about/to target is `person`
(node deletion, so their Asserts*/FactAbout/IntentAbout/PromiseTo edges go
with them); leave one that's about `person` AND someone else alone (only
its edge to `person` disappears, via cascade, once `person` itself is
deleted below). Cancel (never delete) every Introduction proposing `person`.
Counts are taken BEFORE the final `del person` — that delete cascades away
Mentions/Knows/Reported/RelevantTo edges touching `person`, which is exactly
what the counts below are counting."""
def _forget_person(person: Person) -> dict[str, any] {
    person_id = jid(person);

    facts_to_delete: list[Fact] = [];
    for f in [person <-:FactAbout:<-] {
        targets = [f ->:FactAbout:->];
        if len(targets) <= 1 {
            facts_to_delete.append(f);
        }
    }

    intents_to_delete: list[Intent] = [];
    for i in [person <-:IntentAbout:<-] {
        targets = [i ->:IntentAbout:->];
        if len(targets) <= 1 {
            intents_to_delete.append(i);
        }
    }

    promises_to_delete: list[Promise] = [];
    for pr in [person <-:PromiseTo:<-] {
        targets = [pr ->:PromiseTo:->];
        if len(targets) <= 1 {
            promises_to_delete.append(pr);
        }
    }

    mentions_count = len([edge person <-:Mentions:<-]);
    knows_count = len([edge person <-:Knows:<-]);
    reported_count = len([edge person ->:Reported:->]) + len([edge person <-:Reported:<-]);
    relevant_count = len([edge person ->:RelevantTo:->]);

    intro_count = 0;
    for intro in [root --> [?:Introduction]] {
        proposed = [intro ->:Proposes:->];
        is_match = False;
        for pp in proposed {
            if jid(pp) == person_id {
                is_match = True;
            }
        }
        if is_match {
            intro.state = "canceled";
            intro_count += 1;
        }
    }

    for f in facts_to_delete {
        del f;
    }
    for i in intents_to_delete {
        del i;
    }
    for pr in promises_to_delete {
        del pr;
    }
    del person;

    return {
        "deleted": "person",
        "id": person_id,
        "retracted": {
            "facts": len(facts_to_delete),
            "intents": len(intents_to_delete),
            "promises": len(promises_to_delete),
            "edges": mentions_count + knows_count + reported_count,
            "introductions_canceled": intro_count,
            "relevant_to": relevant_count
        }
    };
}

# ---------------------------------------------------------------- Forget(Fact/Intent/Promise)

def _forget_fact(fact: Fact) -> dict[str, any] {
    fact_id = jid(fact);
    edges_count = len([edge fact <-:Asserts:<-]) + len([edge fact ->:FactAbout:->]);
    relevant_count = _prune_relevant_to_evidence(fact_id);

    del fact;

    return {
        "deleted": "fact",
        "id": fact_id,
        "retracted": {
            "facts": 1, "intents": 0, "promises": 0,
            "edges": edges_count,
            "introductions_canceled": 0,
            "relevant_to": relevant_count
        }
    };
}

def _forget_intent(it: Intent) -> dict[str, any] {
    intent_id = jid(it);
    edges_count = len([edge it <-:AssertsIntent:<-]) + len([edge it ->:IntentAbout:->]);
    relevant_count = _prune_relevant_to_evidence(intent_id);

    del it;

    return {
        "deleted": "intent",
        "id": intent_id,
        "retracted": {
            "facts": 0, "intents": 1, "promises": 0,
            "edges": edges_count,
            "introductions_canceled": 0,
            "relevant_to": relevant_count
        }
    };
}

def _forget_promise(pr: Promise) -> dict[str, any] {
    promise_id = jid(pr);
    edges_count = len([edge pr <-:AssertsPromise:<-]) + len([edge pr ->:PromiseTo:->]);
    relevant_count = _prune_relevant_to_evidence(promise_id);

    del pr;

    return {
        "deleted": "promise",
        "id": promise_id,
        "retracted": {
            "facts": 0, "intents": 0, "promises": 1,
            "edges": edges_count,
            "introductions_canceled": 0,
            "relevant_to": relevant_count
        }
    };
}

# ---------------------------------------------------------------- walker

walker:priv Forget {
    """Resolve `id` to an owned node (same ownership idiom as `Receipt`,
    reads.sv.jac); delete it (Person/Fact/Intent/Promise) with retraction
    of whatever depended solely on it, per the module docstring. Reports
    one dict `{ deleted, id, retracted }`, or `[{error: "not_found"}]` for
    an unknown/unowned id or any other node kind."""
    has id: str;
    has reports: list[object] = [];

    can run with Root entry {
        n = _my_node(self.id);
        if n is None {
            report _not_found();
            disengage;
        }

        if isinstance(n, Person) {
            report _forget_person(n as Person);
            disengage;
        }
        if isinstance(n, Fact) {
            report _forget_fact(n as Fact);
            disengage;
        }
        if isinstance(n, Intent) {
            report _forget_intent(n as Intent);
            disengage;
        }
        if isinstance(n, Promise) {
            report _forget_promise(n as Promise);
            disengage;
        }

        report _not_found();
    }
}
