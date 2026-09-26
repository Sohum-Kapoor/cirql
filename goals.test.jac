"""Tests for goals.sv.jac (SOH-169).

Annex to goals.sv.jac — run with `jac test goals.sv.jac`.

Covers the deterministic parts only (no LLM, per AGENTS.md — never hit a real
model in tests): candidate collection + labels (known/route/cold, including
the SOH-169 amendment that a person reachable by a Reported hop from a known
person is "route" even if they also carry their own proposed Knows edge),
evidence assembly (facts/intents/notes, the 8-item cap, expired-intent
skipping), days_since_contact parsing, and `materialize`'s edge
rebuild/delete + report ordering.

Each test builds its own nodes fresh and only ever traverses from the node(s)
it just created (its own `me`, `p`, or `goal`), so it stays correct even
though `jac test` runs against one shared, persisted root (jac-testing) and
earlier tests' nodes are still hanging around.
"""

import from goals { Candidate, EvidenceItem, RankedItem, compute_days_since_contact, gather_evidence, collect_candidates, materialize }
import from schema { Me, Person, Goal, Fact, Intent, Note, Knows, Reported, FactAbout, IntentAbout, Mentions, AssertsIntent, RelevantTo }
import from datetime { datetime }

test "candidate collection: known, route (both sub-cases), cold" {
    now = datetime.now();
    me = (root ++> Me(name="collect-test-me"))[0];

    alice = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Alice CT", status="confirmed"))[0];
    bob = (me +>:Knows(status="reported", last_contact=""):+> Person(name="Bob CT", status="confirmed"))[0];
    # cold: person itself is proposed
    _cara = (me +>:Knows(status="reported", last_contact=""):+> Person(name="Cara CT", status="proposed"))[0];
    # cold: the Knows edge is proposed even though the person node is confirmed
    _dave = (me +>:Knows(status="proposed", last_contact=""):+> Person(name="Dave CT", status="confirmed"))[0];

    # route: reachable via a Reported hop from known Alice, no Knows edge at all
    erin = Person(name="Erin CT", status="confirmed");
    alice +>:Reported():+> erin;

    # route: reachable via a Reported hop from known Bob, AND has its own
    # proposed Knows edge — route must win over cold per the SOH-169 amendment
    fay = Person(name="Fay CT", status="proposed");
    me +>:Knows(status="proposed", last_contact=""):+> fay;
    bob +>:Reported():+> fay;

    result = collect_candidates(me, now);

    by_name: dict[str, Candidate] = {};
    for c in result {
        by_name[c.person.name] = c;
    }

    assert len(result) == 6, f"expected 6 candidates, got {len(result)}: {[c.person.name for c in result]}";
    assert by_name["Alice CT"].label == "known";
    assert by_name["Bob CT"].label == "known";
    assert by_name["Cara CT"].label == "cold";
    assert by_name["Dave CT"].label == "cold";
    assert by_name["Erin CT"].label == "route";
    assert by_name["Erin CT"].via == "Alice CT";
    assert by_name["Fay CT"].label == "route", "person reachable via Reported must be route, not cold, even with a proposed Knows edge";
    assert by_name["Fay CT"].via == "Bob CT";
    assert by_name["Fay CT"].days_since_contact is None, "route candidates never carry a scored/displayed last_contact";
}

test "evidence assembly: facts, then intents (expired skipped), then notes" {
    now = datetime.now();
    p = (root ++> Person(name="Evidence Target", status="confirmed"))[0];

    f1 = (root ++> Fact(text="Works on accessible robotics", observed_at="2026-09-20"))[0];
    f1 +>:FactAbout():+> p;

    i1 = (root ++> Intent(kind="need", text="wants feedback from wheelchair users", expires_at=""))[0];
    i1 +>:IntentAbout():+> p;
    n1 = (root ++> Note(text="Talked about robotics need", kind="debrief", captured_at="2026-09-24T10:00:00"))[0];
    n1 +>:AssertsIntent():+> i1;

    # expired intent must be skipped entirely
    i2 = (root ++> Intent(kind="need", text="expired thing", expires_at="2020-01-01T00:00:00"))[0];
    i2 +>:IntentAbout():+> p;

    n2 = (root ++> Note(text="Some note text about the target person", kind="paste", captured_at="2026-09-25T09:00:00"))[0];
    n2 +>:Mentions():+> p;

    ev = gather_evidence(p, now);

    assert len(ev) == 3, f"expected fact + live intent + note (expired intent skipped), got {[e.kind for e in ev]}";
    assert ev[0].kind == "fact";
    assert ev[0].span == "Works on accessible robotics";
    assert ev[1].kind == "intent";
    assert ev[1].span == "wants feedback from wheelchair users";
    assert ev[1].observed_at == "2026-09-24T10:00:00", "intent observed_at comes from the Note that AssertsIntent it";
    assert ev[2].kind == "note";
    assert ev[2].span == "Some note text about the target person";
}

test "evidence assembly: capped at 8 total, facts before intents before notes" {
    now = datetime.now();
    p = (root ++> Person(name="Cap Target", status="confirmed"))[0];

    for i in range(5) {
        f = (root ++> Fact(text=f"fact {i}", observed_at="2026-09-01"))[0];
        f +>:FactAbout():+> p;
    }
    for i in range(5) {
        it = (root ++> Intent(kind="need", text=f"intent {i}", expires_at=""))[0];
        it +>:IntentAbout():+> p;
    }
    for i in range(5) {
        n = (root ++> Note(text=f"note {i}", kind="paste", captured_at="2026-09-01"))[0];
        n +>:Mentions():+> p;
    }

    ev = gather_evidence(p, now);

    assert len(ev) == 8, f"expected the cap to hold at 8, got {len(ev)}";
    for i in range(5) {
        assert ev[i].kind == "fact";
    }
    for i in range(5, 8) {
        assert ev[i].kind == "intent";
    }
}

test "days_since_contact: ISO string, empty, and unparsable input" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    ten_days_ago = datetime(2026, 9, 16, 12, 0, 0).isoformat();

    assert compute_days_since_contact(ten_days_ago, now) == 10;
    assert compute_days_since_contact("", now) is None;
    assert compute_days_since_contact("not-a-date", now) is None;
}

test "materialize: strength/label/days ordering, evidence mapping, edge rebuild and delete" {
    now = datetime.now();
    goal = (root ++> Goal(text="materialize-test-goal", created_at=now.isoformat()))[0];

    weak_p = (root ++> Person(name="Weak P", status="confirmed"))[0];
    med_p = (root ++> Person(name="Med P", status="confirmed"))[0];
    strong_p = (root ++> Person(name="Strong P", status="confirmed"))[0];

    ev = EvidenceItem(id="ev-1", kind="intent", observed_at="2026-09-01", span="wants feedback");

    weak_c = Candidate(person=weak_p, label="cold", evidence_items=[], days_since_contact=5);
    med_c = Candidate(person=med_p, label="known", evidence_items=[ev], days_since_contact=None);
    strong_c = Candidate(person=strong_p, label="known", evidence_items=[ev], days_since_contact=2);

    candidates = [weak_c, med_c, strong_c];
    ranked = [
        RankedItem(index=0, strength="weak", reason="r0", evidence_indices=[], opener="o0"),
        RankedItem(index=1, strength="medium", reason="r1", evidence_indices=[0], opener="o1"),
        RankedItem(index=2, strength="strong", reason="r2", evidence_indices=[0], opener="o2")
    ];

    results = materialize(goal, ranked, candidates);

    assert len(results) == 3;
    r0_person = results[0]["person"] as Person;
    r1_person = results[1]["person"] as Person;
    r2_person = results[2]["person"] as Person;
    assert r0_person.name == "Strong P", "strong ranks best regardless of input order";
    assert r1_person.name == "Med P";
    assert r2_person.name == "Weak P";
    assert results[0]["strength"] == "strong";
    r1_evidence = results[1]["evidence"] as list[dict[str, any]];
    assert r1_evidence[0]["id"] == "ev-1";

    edges_after_first = [edge goal <-:RelevantTo:<-];
    assert len(edges_after_first) == 3, "materialize must create one RelevantTo edge per ranked candidate";
    linked_goals = [strong_p ->:RelevantTo:->];
    assert goal in linked_goals;

    # rebuild: a second call with a different (smaller) candidate set must
    # delete every previous edge into this goal before creating new ones,
    # and an out-of-range evidence index / bad strength must be dropped/normalized
    results2 = materialize(
        goal,
        [RankedItem(index=0, strength="bogus", reason="only", evidence_indices=[99], opener="")],
        [weak_c]
    );
    edges_after_second = [edge goal <-:RelevantTo:<-];
    assert len(edges_after_second) == 1, "rebuild must delete the old edges, not accumulate them";
    assert results2[0]["strength"] == "weak", "an unrecognized strength normalizes to weak";
    assert results2[0]["evidence"] == [], "an evidence index out of range must be dropped, not crash";
}
