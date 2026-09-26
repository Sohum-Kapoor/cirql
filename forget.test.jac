"""Tests for forget.sv.jac (SOH-188) — delete and retract.

Annex to forget.sv.jac — run with `jac test forget.sv.jac`. Deterministic,
no LLM. Per `jac-testing`, tests share one persisted root across runs, so
every name below carries a random per-test suffix (`_uid()`), same idiom as
`imports.test.jac`.

`Forget`'s ownership check (`_my_node`) needs the resolved node's owner root
to differ from the caller's own to prove the negative case — same
architectural limit `reads.test.jac` documents for `Receipt`/`GraphView`:
one shared, persisted root inside a single `jac test` process. That negative
case is proven at the server layer instead (gate.test.jac's pattern, real
two-account harness) and is out of scope for this annex.
"""

import from forget { Forget }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Introduction,
    Knows, Reported, Asserts, AssertsPromise, AssertsIntent, FactAbout, IntentAbout, PromiseTo,
    HasGoal, RelevantTo, Proposes
}
import from datetime { datetime }
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

test "Forget(person): deletes the solely-about fact and the promise, keeps the shared fact, removes Knows/Reported edges and the RelevantTo edge, cancels the Introduction; B and the Note survive" {
    suffix = _uid();
    now = datetime.now().isoformat();

    me = (root ++> Me(name=f"Forget-test Me {suffix}"))[0];
    a = (me +>:Knows(how_met="test", status="confirmed"):+> Person(name=f"Forget-test A {suffix}", status="confirmed"))[0];
    b = (me +>:Knows(how_met="test", status="confirmed"):+> Person(name=f"Forget-test B {suffix}", status="confirmed"))[0];

    note = (root ++> Note(text=f"Forget-test note {suffix}", kind="debrief", captured_at=now))[0];

    fact_solely_a = (note +>:Asserts(span="solely about A"):+> Fact(
        text=f"Forget-test solely about A {suffix}", observed_at=now
    ))[0];
    fact_solely_a +>:FactAbout:+> a;

    fact_shared = (note +>:Asserts(span="about A and B"):+> Fact(
        text=f"Forget-test shared fact {suffix}", observed_at=now
    ))[0];
    fact_shared +>:FactAbout:+> a;
    fact_shared +>:FactAbout:+> b;

    promise = (note +>:AssertsPromise(span="promise to A"):+> Promise(
        text=f"Forget-test promise to A {suffix}"
    ))[0];
    promise +>:PromiseTo:+> a;

    a +>:Reported(source_note=jid(note), span="A knows B"):+> b;

    goal = (me +>:HasGoal:+> Goal(text=f"Forget-test goal {suffix}", created_at=now))[0];
    a +>:RelevantTo(reason="test", strength="weak", evidence=[jid(fact_solely_a)], label="known"):+> goal;

    intro = (root ++> Introduction(state="proposed"))[0];
    intro +>:Proposes:+> a;
    intro +>:Proposes:+> b;

    result = root spawn Forget(id=jid(a));
    assert len(result.reports) == 1;
    out = result.reports[0] as dict[str, any];
    assert out["deleted"] == "person";
    assert out["id"] == jid(a);

    retracted = out["retracted"] as dict[str, any];
    assert retracted["facts"] == 1, f"expected exactly the solely-about fact retracted, got {retracted['facts']}";
    assert retracted["intents"] == 0;
    assert retracted["promises"] == 1;
    assert retracted["introductions_canceled"] == 1;
    assert retracted["relevant_to"] == 1;
    assert (retracted["edges"] as int) >= 2, "at least the Knows and Reported edges";

    # A is gone from Me's Knows list; B survives.
    remaining_people = [me ->:Knows:->];
    remaining_ids = [jid(p) for p in remaining_people];
    assert jid(a) not in remaining_ids, "A must be deleted";
    assert jid(b) in remaining_ids, "B must survive";

    # The solely-about fact and the promise are gone; the shared fact survives,
    # now pointing only at B.
    remaining_facts = [note ->:Asserts:->];
    remaining_fact_ids = [jid(f) for f in remaining_facts];
    assert jid(fact_solely_a) not in remaining_fact_ids, "the solely-about-A fact must be deleted";
    assert jid(fact_shared) in remaining_fact_ids, "the fact shared with B must survive";

    shared_targets = [fact_shared ->:FactAbout:->];
    shared_target_ids = [jid(p) for p in shared_targets];
    assert jid(a) not in shared_target_ids;
    assert jid(b) in shared_target_ids;

    remaining_promises = [note ->:AssertsPromise:->];
    assert jid(promise) not in [jid(pr) for pr in remaining_promises], "the promise to A must be deleted";

    # The Note (the receipt) is never touched.
    reloaded_note = jobj(jid(note));
    assert isinstance(reloaded_note, Note);
    assert (reloaded_note as Note).text == f"Forget-test note {suffix}";

    # The Introduction is canceled, never deleted.
    assert intro.state == "canceled";

    # SOH-211: A's RelevantTo edge went with A (node delete cascades).
    assert jid(a) not in [jid(x) for x in [goal <-:RelevantTo:<-]], "A's RelevantTo edge must be gone";
    assert len([edge goal <-:RelevantTo:<-]) == 0;
}

test "Forget(fact): removes the fact and prunes it from RelevantTo.evidence, leaving other evidence ids alone" {
    suffix = _uid();
    now = datetime.now().isoformat();

    me = (root ++> Me(name=f"Forget-test Me2 {suffix}"))[0];
    p = (me +>:Knows(how_met="test", status="confirmed"):+> Person(name=f"Forget-test P {suffix}", status="confirmed"))[0];

    note = (root ++> Note(text=f"Forget-test note2 {suffix}", kind="debrief", captured_at=now))[0];
    fact = (note +>:Asserts(span="fact to delete"):+> Fact(
        text=f"Forget-test fact to delete {suffix}", observed_at=now
    ))[0];
    fact +>:FactAbout:+> p;

    goal = (me +>:HasGoal:+> Goal(text=f"Forget-test goal2 {suffix}", created_at=now))[0];
    p +>:RelevantTo(reason="test", strength="weak", evidence=[jid(fact), "some-other-evidence-id"], label="known"):+> goal;

    result = root spawn Forget(id=jid(fact));
    assert len(result.reports) == 1;
    out = result.reports[0] as dict[str, any];
    assert out["deleted"] == "fact";
    assert out["id"] == jid(fact);

    retracted = out["retracted"] as dict[str, any];
    assert retracted["facts"] == 1;
    assert retracted["intents"] == 0;
    assert retracted["promises"] == 0;
    assert retracted["relevant_to"] == 1;
    assert (retracted["edges"] as int) >= 1, "at least the Asserts edge from the Note";

    matched = [edge p ->:RelevantTo:-> goal];
    assert len(matched) == 1;
    edge_after = matched[0];
    assert jid(fact) not in edge_after.evidence, "the deleted fact's id must be pruned from evidence";
    assert "some-other-evidence-id" in edge_after.evidence, "an unrelated evidence id must be left alone";

    remaining_facts = [note ->:Asserts:->];
    assert jid(fact) not in [jid(f) for f in remaining_facts];

    # The Note survives.
    reloaded_note = jobj(jid(note));
    assert isinstance(reloaded_note, Note);
}

test "SOH-211 Forget(fact/intent): a RelevantTo edge whose evidence becomes empty is deleted; one with evidence left survives" {
    suffix = _uid();
    now = datetime.now().isoformat();

    me = (root ++> Me(name=f"Forget-test Me3 {suffix}"))[0];
    p = (me +>:Knows(how_met="test", status="confirmed"):+> Person(name=f"Forget-test P3 {suffix}", status="confirmed"))[0];
    q = (me +>:Knows(how_met="test", status="confirmed"):+> Person(name=f"Forget-test Q3 {suffix}", status="confirmed"))[0];
    note = (root ++> Note(text=f"Forget-test note3 {suffix}", kind="debrief", captured_at=now))[0];
    fact = (note +>:Asserts(span="only evidence"):+> Fact(text=f"Forget-test only evidence {suffix}", observed_at=now))[0];
    fact +>:FactAbout:+> p;
    it = (note +>:AssertsIntent(span="offer"):+> Intent(text=f"Forget-test offer {suffix}", kind="offer"))[0];
    it +>:IntentAbout:+> q;

    goal = (me +>:HasGoal:+> Goal(text=f"Forget-test goal3 {suffix}", created_at=now))[0];
    p +>:RelevantTo(reason="test", strength="strong", evidence=[jid(fact)], label="known"):+> goal;
    q +>:RelevantTo(reason="test", strength="medium", evidence=[jid(it)], label="known"):+> goal;

    out = (root spawn Forget(id=jid(fact))).reports[0] as dict[str, any];
    assert (out["retracted"] as dict[str, any])["relevant_to"] == 1;
    assert len([edge p ->:RelevantTo:-> goal]) == 0, "unsupported RelevantTo must be deleted";
    assert len([edge q ->:RelevantTo:-> goal]) == 1, "an unrelated ranking survives";

    out2 = (root spawn Forget(id=jid(it))).reports[0] as dict[str, any];
    assert out2["deleted"] == "intent";
    assert len([edge q ->:RelevantTo:-> goal]) == 0;
    assert len([goal <-:RelevantTo:<-]) == 0;
}

test "Forget on an unknown id reports not_found" {
    result = root spawn Forget(id="not-a-real-id-at-all");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}
