"""Tests for merge.sv.jac (SOH-195) — duplicate merge: propose, confirm, undo.

Annex to merge.sv.jac — run with `jac test merge.sv.jac`. Deterministic, no
LLM. Per `jac-testing`, tests share one persisted `root` across runs (and
across every past invocation of `jac test merge.sv.jac` - `.jac/data`
persists), so every name below carries a random per-run suffix (`_uid()`),
same idiom as `imports.test.jac`/`forget.test.jac`.

`ProposeMerges`/`MergePeople`/`UndoMerge` all resolve "the" `Me` via
`[root --> [?:Me]][0]` internally (same pattern `imports.sv.jac`/
`capture.sv.jac` use for real single-tenant use) - ambiguous once more than
one test has created a `Me` under the shared root, per `reads.test.jac`'s
note on `GraphView`. So this file creates its `Me` exactly once, the same
way the walkers do internally (get first, else create), and every test
after the first reuses that same node - never a second `root ++> Me(...)`.
Assertions search for THIS test's own people by their unique suffix rather
than asserting totals on the shared, ever-growing `Knows` list or the
shared `ProposeMerges` report list.
"""

import from merge { ProposeMerges, MergePeople, UndoMerge }
import from schema {
    Me, Person, Note, Fact, Promise, Goal,
    Knows, Reported, Asserts, AssertsPromise, FactAbout, PromiseTo,
    HasGoal, RelevantTo
}
import from datetime { datetime }
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

def _get_or_create_me() -> Me {
    existing = [root --> [?:Me]];
    if existing {
        return existing[0];
    }
    return (root ++> Me(name="merge-test-me"))[0];
}

test "propose -> merge -> undo -> already_undone, and same_person" {
    me = _get_or_create_me();
    suffix = _uid();
    now = datetime.now().isoformat();

    first_token = f"Maya{suffix}";
    full_name = f"{first_token} Okafor{suffix}";
    short_name = first_token;

    full = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name=full_name, org=f"Michigan Robotics {suffix}", status="confirmed"
    ))[0];
    short = (me +>:Knows(how_met="test", status="proposed"):+> Person(
        name=short_name, org="", status="proposed"
    ))[0];
    arjun = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name=f"Arjun{suffix} Patel", status="confirmed"
    ))[0];

    note_full = (root ++> Note(text=f"Merge-test note full {suffix}", kind="debrief", captured_at=now))[0];
    fact_full = (note_full +>:Asserts(span="fact about full"):+> Fact(
        text=f"Merge-test fact about full {suffix}", observed_at=now
    ))[0];
    fact_full +>:FactAbout:+> full;

    note_short = (root ++> Note(text=f"Merge-test note short {suffix}", kind="debrief", captured_at=now))[0];
    fact_short = (note_short +>:Asserts(span="fact about short"):+> Fact(
        text=f"Merge-test fact about short {suffix}", observed_at=now
    ))[0];
    fact_short +>:FactAbout:+> short;

    promise = (note_short +>:AssertsPromise(span="promise to short"):+> Promise(
        text=f"Merge-test promise {suffix}"
    ))[0];
    promise +>:PromiseTo:+> short;

    short +>:Reported(source_note=jid(note_short), span="short knows arjun"):+> arjun;

    goal = (me +>:HasGoal:+> Goal(text=f"Merge-test goal {suffix}", created_at=now))[0];
    short +>:RelevantTo(
        reason=f"test reason {suffix}", strength="strong",
        evidence=[jid(fact_short)], opener=f"hi {suffix}", label="known"
    ):+> goal;

    full_id = jid(full);
    short_id = jid(short);

    # ---- ProposeMerges: exactly this pair, first_name_only_vs_full ----
    propose_result = root spawn ProposeMerges();
    pair_entry: dict[str, any] | None = None;
    for entry in propose_result.reports {
        e = entry as dict[str, any];
        a = e["a"] as Person;
        b = e["b"] as Person;
        touched = [jid(a), jid(b)];
        if full_id in touched and short_id in touched {
            pair_entry = e;
        }
    }
    assert pair_entry is not None, "expected the Maya / Maya Okafor pair to be proposed";
    pe = pair_entry as dict[str, any];
    assert pe["reason"] == "first_name_only_vs_full", f"got reason {pe['reason']}";
    assert pe["confidence"] == "medium";

    # ---- MergePeople(full, short) ----
    merge_result = root spawn MergePeople(keep_id=full_id, remove_id=short_id);
    assert len(merge_result.reports) == 1;
    out = merge_result.reports[0] as dict[str, any];
    kept = out["kept"] as Person;
    assert jid(kept) == full_id;
    moved = out["moved"] as dict[str, any];
    assert (moved["facts"] as int) == 1, f"expected the 1 fact solely about short to be moved, got {moved['facts']}";
    assert (moved["intents"] as int) == 0;
    assert (moved["promises"] as int) == 1;
    assert (moved["reported"] as int) == 1;
    assert (moved["relevant_to"] as int) == 1;
    assert (moved["mentions"] as int) == 0;
    assert (moved["introductions"] as int) == 0;
    record_id = out["record_id"] as str;

    kept_facts: list[Fact] = [kept <-:FactAbout:<-];
    assert len(kept_facts) == 2, f"expected kept to have 2 facts, got {len(kept_facts)}";

    kept_promise_targets: list[Person] = [promise ->:PromiseTo:->];
    assert full_id in [jid(p) for p in kept_promise_targets], "the promise must now point at kept";

    kept_reported: list[Person] = [kept ->:Reported:->];
    assert jid(arjun) in [jid(p) for p in kept_reported], "the Reported edge must now come from kept";

    kept_relevant: list[Goal] = [kept ->:RelevantTo:->];
    assert jid(goal) in [jid(g) for g in kept_relevant], "the RelevantTo edge must now come from kept";

    short_gone = True;
    try {
        reloaded = jobj(short_id);
        short_gone = reloaded is None;
    } except Exception {
        short_gone = True;
    }
    assert short_gone, "the short (removed) Person node must be gone";

    reloaded_note_short = jobj(jid(note_short));
    assert reloaded_note_short is not None, "the Note must survive a merge";

    # ---- UndoMerge(record_id) ----
    undo_result = root spawn UndoMerge(record_id=record_id);
    assert len(undo_result.reports) == 1;
    undo_out = undo_result.reports[0] as dict[str, any];
    restored = undo_out["restored"] as Person;
    assert restored.name == short_name;
    assert restored.org == "";
    assert restored.status == "proposed";
    assert (undo_out["record_id"] as str) == record_id;

    restored_facts: list[Fact] = [restored <-:FactAbout:<-];
    assert len(restored_facts) == 1, f"expected restored to have her 1 fact back, got {len(restored_facts)}";
    assert jid(restored_facts[0]) == jid(fact_short);

    restored_promise_targets: list[Person] = [promise ->:PromiseTo:->];
    assert jid(restored) in [jid(p) for p in restored_promise_targets], "the promise must move back to restored";

    restored_reported: list[Person] = [restored ->:Reported:->];
    assert jid(arjun) in [jid(p) for p in restored_reported], "the Reported edge must move back to restored";

    restored_relevant: list[Goal] = [restored ->:RelevantTo:->];
    assert jid(goal) in [jid(g) for g in restored_relevant], "the RelevantTo edge must move back to restored";

    kept_facts_after_undo: list[Fact] = [kept <-:FactAbout:<-];
    assert len(kept_facts_after_undo) == 1, f"expected kept back to 1 fact, got {len(kept_facts_after_undo)}";
    assert jid(kept_facts_after_undo[0]) == jid(fact_full);

    kept_promise_after_undo: list[Person] = [promise ->:PromiseTo:->];
    assert full_id not in [jid(p) for p in kept_promise_after_undo], "the promise must have left kept";

    kept_reported_after_undo: list[Person] = [kept ->:Reported:->];
    assert jid(arjun) not in [jid(p) for p in kept_reported_after_undo], "the Reported edge must have left kept";

    kept_relevant_after_undo: list[Goal] = [kept ->:RelevantTo:->];
    assert jid(goal) not in [jid(g) for g in kept_relevant_after_undo], "the RelevantTo edge must have left kept";

    # ---- UndoMerge again -> already_undone ----
    undo_again = root spawn UndoMerge(record_id=record_id);
    err_again = undo_again.reports[0] as dict[str, any];
    assert err_again["error"] == "already_undone";

    # ---- MergePeople(x, x) -> same_person ----
    same_result = root spawn MergePeople(keep_id=full_id, remove_id=full_id);
    err_same = same_result.reports[0] as dict[str, any];
    assert err_same["error"] == "same_person";
}

test "MergePeople: unknown ids -> not_found; UndoMerge: unknown record -> not_found" {
    r1 = root spawn MergePeople(keep_id="definitely-not-a-jid", remove_id="also-not-a-jid");
    err1 = r1.reports[0] as dict[str, any];
    assert err1["error"] == "not_found";

    me = _get_or_create_me();
    suffix = _uid();
    only = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name=f"Solo{suffix}", status="confirmed"
    ))[0];
    r2 = root spawn MergePeople(keep_id=jid(only), remove_id="definitely-not-a-jid");
    err2 = r2.reports[0] as dict[str, any];
    assert err2["error"] == "not_found";

    r3 = root spawn UndoMerge(record_id="definitely-not-a-jid");
    err3 = r3.reports[0] as dict[str, any];
    assert err3["error"] == "not_found";
}
