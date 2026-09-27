"""Tests for goals.sv.jac (SOH-169).

Annex to goals.sv.jac — run with `jac test goals.sv.jac`.

Covers the deterministic parts only (no LLM, per AGENTS.md — never hit a real
model in tests): candidate collection + labels (known/route/cold, including
the SOH-169 amendment that a person reachable by a Reported hop from a known
person is "route" even if they also carry their own proposed Knows edge, and
that per-person Knows-edge lookup never swaps one person's last_contact for
another's), evidence assembly (facts/intents/notes, the 8-item cap,
expired-intent skipping), days_since_contact parsing, and `materialize`'s
edge rebuild/delete, one-entry-per-candidate report shape, index dedup, and
evidence-gated strength (cross-family review fixes, SOH-169 round 2).

Each test builds its own nodes fresh and only ever traverses from the node(s)
it just created (its own `me`, `p`, or `goal`), so it stays correct even
though `jac test` runs against one shared, persisted root (jac-testing) and
earlier tests' nodes are still hanging around.
"""

import from goals { Candidate, EvidenceItem, RankedItem, compute_days_since_contact, gather_evidence, collect_candidates, materialize, fallback_rank, serve_cached, evidence_item_from_jid, collect_all_candidates, count_candidate_people, ranking_is_stale, annotate_ranking, RANK_CAP, goal_texts_match, set_goal_for, goal_noun_phrase, newest_evidence_at, existing_relevant_to, stale_trigger, candidate_is_stale, change_reason_text, compute_stale_indices, prune_stale_relevantto, materialize_stable }
import from schema { Me, Person, Goal, Fact, Intent, Promise, Note, Knows, Reported, FactAbout, IntentAbout, PromiseTo, AssertsPromise, Mentions, AssertsIntent, RelevantTo, HasGoal }
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

test "candidate collection: last_contact is never swapped between two known people" {
    # Regression for review fix #1: collect_candidates must never zip
    # [me ->:Knows:->] against [edge me ->:Knows:->] by index (no order
    # guarantee across two separate traversals). Two known people with
    # clearly different last_contact values catch a swap immediately.
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="align-test-me"))[0];

    old_contact = datetime(2026, 8, 1, 12, 0, 0).isoformat();      # 56 days before `now`
    recent_contact = datetime(2026, 9, 20, 12, 0, 0).isoformat();  # 6 days before `now`

    _old_p = (me +>:Knows(status="confirmed", last_contact=old_contact):+> Person(name="Old Contact P", status="confirmed"))[0];
    _recent_p = (me +>:Knows(status="confirmed", last_contact=recent_contact):+> Person(name="Recent Contact P", status="confirmed"))[0];

    result = collect_candidates(me, now);
    by_name: dict[str, Candidate] = {};
    for c in result {
        by_name[c.person.name] = c;
    }

    assert by_name["Old Contact P"].days_since_contact == 56, f"got {by_name['Old Contact P'].days_since_contact}";
    assert by_name["Recent Contact P"].days_since_contact == 6, f"got {by_name['Recent Contact P'].days_since_contact}";
}

test "candidate collection: a doubly-connected person never appears twice" {
    # Regression for review fix #3 (belt-and-suspenders: the cold loop must
    # also skip known_jids, not just route_jids). A person reachable via two
    # Knows edges from the same Me must still surface exactly once.
    now = datetime.now();
    me = (root ++> Me(name="dup-edge-test-me"))[0];
    shared = Person(name="Dual Edge P", status="confirmed");
    me +>:Knows(status="confirmed", last_contact=""):+> shared;
    me +>:Knows(status="proposed", last_contact=""):+> shared;

    result = collect_candidates(me, now);
    matches = [c for c in result if c.person.name == "Dual Edge P"];
    assert len(matches) == 1, f"expected exactly one candidate for a doubly-connected person, got {len(matches)}";
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

test "materialize: dedupe by index, default entry for a missing index, evidence-gated strength" {
    now = datetime.now();
    goal = (root ++> Goal(text="materialize-review-fixes-goal", created_at=now.isoformat()))[0];

    p0 = (root ++> Person(name="P0 Dup", status="confirmed"))[0];
    p1 = (root ++> Person(name="P1 NoEvidence", status="confirmed"))[0];
    p2 = (root ++> Person(name="P2 Unranked", status="confirmed"))[0];

    fact_ev = EvidenceItem(id="ev-a", kind="fact", observed_at="2026-09-01", span="some fact");

    c0 = Candidate(person=p0, label="known", evidence_items=[fact_ev], days_since_contact=None);
    c1 = Candidate(person=p1, label="known", evidence_items=[fact_ev], days_since_contact=None);
    c2 = Candidate(person=p2, label="cold", evidence_items=[], days_since_contact=None);
    candidates = [c0, c1, c2];

    ranked = [
        RankedItem(index=0, strength="strong", reason="first wins", evidence_indices=[0], opener="o-first"),
        RankedItem(index=0, strength="weak", reason="duplicate, must be ignored", evidence_indices=[], opener="o-dup"),
        RankedItem(index=1, strength="strong", reason="claims strong but the evidence index is out of range", evidence_indices=[99], opener="o1")
        # index 2 (P2 Unranked) is intentionally never mentioned by `ranked`.
    ];

    results = materialize(goal, ranked, candidates);

    assert len(results) == 3, "materialize reports exactly one entry per candidate, never fewer or more";

    by_name: dict[str, dict[str, any]] = {};
    for r in results {
        person = r["person"] as Person;
        by_name[person.name] = r;
    }

    assert by_name["P0 Dup"]["reason"] == "First wins.", "duplicate RankedItems for the same index: the first occurrence wins (SOH-226: materialize polishes reason/opener before storing)";
    assert by_name["P0 Dup"]["strength"] == "strong";

    assert by_name["P1 NoEvidence"]["strength"] == "weak", "an out-of-range evidence index leaves no mapped evidence -> forced weak even though the ranker said strong";
    assert by_name["P1 NoEvidence"]["evidence"] == [];

    assert by_name["P2 Unranked"]["strength"] == "weak", "a candidate `ranked` never mentions still gets a default report entry";
    assert by_name["P2 Unranked"]["reason"] == "No ranking returned for this person.";
    assert by_name["P2 Unranked"]["opener"] == "";
}

test "fallback_rank (SOH-169): reason text, evidence-gated strength, opener names the evidence span" {
    with_evidence = (root ++> Person(name="With Evidence P", status="confirmed"))[0];
    without_evidence = (root ++> Person(name="Without Evidence P", status="confirmed"))[0];

    ev = EvidenceItem(id="ev-fallback", kind="fact", observed_at="2026-09-01", span="wants feedback from wheelchair users");
    c_with = Candidate(person=with_evidence, label="known", evidence_items=[ev], days_since_contact=None);
    c_without = Candidate(person=without_evidence, label="cold", evidence_items=[], days_since_contact=None);

    ranked = fallback_rank([c_with, c_without]);

    assert len(ranked) == 2;
    for item in ranked {
        assert item.reason == "Ranking unavailable right now; ordered by the evidence in your notes.";
    }

    with_item = ranked[0];
    without_item = ranked[1];
    assert with_item.strength == "medium", "evidence-gated: an intent/fact present -> medium";
    assert with_item.evidence_indices == [0];
    assert with_item.opener == "Hi With Evidence P, I was thinking about what you mentioned about wants feedback from wheelchair users.";

    assert without_item.strength == "weak", "no intent/fact evidence -> weak";
    assert without_item.evidence_indices == [];
    assert without_item.opener == "", "no evidence -> no opener";
}

test "serve_cached (SOH-169 cache): serves the materialized ranking off hand-built RelevantTo edges, no LLM" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="cache-test-me"))[0];
    goal = (root ++> Goal(text="cache-test-goal", created_at=now.isoformat()))[0];

    strong_p = (root ++> Person(name="Strong Cached P", status="confirmed"))[0];
    weak_p = (root ++> Person(name="Weak Cached P", status="confirmed"))[0];

    # strong_p is a known contact (Knows edge) 10 days before `now`
    ten_days_ago = datetime(2026, 9, 16, 12, 0, 0).isoformat();
    me +>:Knows(status="confirmed", last_contact=ten_days_ago):+> strong_p;

    fact = (root ++> Fact(text="Cached fact evidence", observed_at="2026-09-20"))[0];
    fact +>:FactAbout():+> strong_p;
    note = (root ++> Note(text="Cached note evidence", kind="debrief", captured_at="2026-09-21T09:00:00"))[0];
    note +>:Mentions():+> strong_p;

    unknown_jid = "not-a-real-jid-0000";

    strong_p +>:RelevantTo(
        reason="strong reason",
        strength="strong",
        label="known",
        evidence=[jid(fact), jid(note), unknown_jid],
        opener="op-strong"
    ):+> goal;
    weak_p +>:RelevantTo(
        reason="weak reason",
        strength="weak",
        label="cold",
        evidence=[],
        opener=""
    ):+> goal;

    results = serve_cached(goal, me);

    assert len(results) == 2, f"expected one entry per RelevantTo edge, got {len(results)}";

    strong_person = results[0]["person"] as Person;
    weak_person = results[1]["person"] as Person;
    assert strong_person.name == "Strong Cached P", "strong ranks first, same ordering as a fresh run";
    assert weak_person.name == "Weak Cached P";

    assert results[0]["cached"], "cached serve must mark every entry cached: true";
    assert results[1]["cached"];
    assert results[0]["strength"] == "strong";
    assert results[0]["label"] == "known";
    assert results[0]["reason"] == "strong reason";
    assert results[0]["opener"] == "op-strong";
    assert results[0]["days_since_contact"] == 10, "days_since_contact recomputed from the Knows edge as of today";
    assert results[1]["days_since_contact"] is None, "no Knows edge from me -> no displayed days";

    ev = results[0]["evidence"] as list[dict[str, any]];
    assert len(ev) == 2, "unknown jid must be dropped, only the real Fact and Note survive";
    kinds = [e["kind"] for e in ev];
    assert "fact" in kinds and "note" in kinds;
    for e in ev {
        if e["kind"] == "fact" {
            assert e["id"] == jid(fact);
            assert e["span"] == "Cached fact evidence";
            assert e["observed_at"] == "2026-09-20";
        } elif e["kind"] == "note" {
            assert e["id"] == jid(note);
            assert e["span"] == "Cached note evidence";
            assert e["observed_at"] == "2026-09-21T09:00:00";
        }
    }
}

test "serve_cached (SOH-169 cache): no RelevantTo edges -> empty, so GoalRank falls through to a fresh rank" {
    now = datetime.now();
    me = (root ++> Me(name="cache-empty-test-me"))[0];
    goal = (root ++> Goal(text="cache-empty-test-goal", created_at=now.isoformat()))[0];

    results = serve_cached(goal, me);
    assert results == [], "no edges yet -> serve_cached must return [] so the walker falls through to the full rebuild";
}

test "evidence_item_from_jid (SOH-169 cache): unknown jid resolves to None" {
    item = evidence_item_from_jid("definitely-not-a-real-jid");
    assert item is None;
}

# ---------------------------------------------------------------- SOH-212 staleness + cap

test "SOH-212 GoalRank cap: 70 people -> 60 ranked, total_people 70, truncated true" {
    now = datetime.now();
    me = (root ++> Me(name="cap-test-me"))[0];
    for i in range(70) {
        me +>:Knows(status="confirmed", last_contact=""):+> Person(name=f"Cap212 P{i}", status="confirmed");
    }
    all_c = collect_all_candidates(me, now);
    assert len(all_c) == 70;
    assert len(collect_candidates(me, now)) == RANK_CAP;
    assert count_candidate_people(me) == 70;
    items: list[dict[str, any]] = [{"person": "x"}];
    annotate_ranking(items, False, "2026-09-26T10:00:00", 70);
    assert items[0]["truncated"] == True and items[0]["total_people"] == 70;
    assert items[0]["stale"] == False and items[0]["ranked_at"] == "2026-09-26T10:00:00";
    few: list[dict[str, any]] = [{"person": "y"}];
    annotate_ranking(few, True, "", 12);
    assert few[0]["truncated"] == False;
}

test "SOH-212 ranking_is_stale: a note captured after ranked_at makes it stale; none after -> fresh; no ranked_at -> stale" {
    older = Note(text="old", kind="debrief", captured_at="2026-09-26T09:00:00");
    newer = Note(text="new", kind="debrief", captured_at="2026-09-26T11:00:00");
    assert not ranking_is_stale("2026-09-26T10:00:00", [older]);
    assert ranking_is_stale("2026-09-26T10:00:00", [older, newer]);
    assert ranking_is_stale("", [older]);
}

# ---------------------------------------------------------------- SOH-226 goal_noun_phrase

test "goal_noun_phrase: strips a first-person prefix and lowercases the result" {
    assert goal_noun_phrase("I am looking to find a technical cofounder") == "find a technical cofounder";
    assert goal_noun_phrase("I'm looking to raise a pre-seed round") == "raise a pre-seed round";
    assert goal_noun_phrase("Find a mentor in accessible robotics") == "a mentor in accessible robotics";
    assert goal_noun_phrase("To land a summer internship") == "land a summer internship";
}

test "goal_noun_phrase: keeps a proper-noun/acronym start as-is" {
    assert goal_noun_phrase("AI grants for climate startups") == "AI grants for climate startups";
}

test "goal_noun_phrase: empty-safe and leaves an already-lowercase noun phrase alone" {
    assert goal_noun_phrase("") == "";
    assert goal_noun_phrase("intros to climate-tech investors") == "intros to climate-tech investors";
}

# ---------------------------------------------------------------- SOH-225 SetGoal dedupe

test "set_goal_for: a new goal's text is stored as a noun phrase (SOH-226), never the raw first-person ask" {
    me = (root ++> Me(name="setgoal-noun-phrase-test-me"))[0];
    g = set_goal_for(me, "I am looking to find a technical cofounder", datetime(2026, 9, 26, 9, 0, 0));
    assert g.text == "find a technical cofounder", g.text;
}

test "goal_texts_match: reordered/reworded phrasing of the same ask matches via Jaccard" {
    a = "Land a summer 2027 climate-tech VC internship";
    b = "land a climate-tech VC internship for summer 2027";
    assert goal_texts_match(a, b);
    assert goal_texts_match(b, a);
}

test "goal_texts_match: a genuinely different goal does not match" {
    assert not goal_texts_match(
        "Land a summer 2027 climate-tech VC internship",
        "Find a mentor in accessible robotics"
    );
}

test "goal_texts_match: a longer restatement that contains the shorter text matches" {
    assert goal_texts_match(
        "Raise a pre-seed round",
        "Raise a pre-seed round from climate-tech investors"
    );
}

test "set_goal_for: calling twice with near-duplicate text reuses the same goal, sets it active, creates nothing" {
    me = (root ++> Me(name="setgoal-dedupe-test-me"))[0];

    g1 = set_goal_for(me, "Land a summer 2027 climate-tech VC internship", datetime(2026, 9, 26, 9, 0, 0));
    g2 = set_goal_for(me, "land a climate-tech VC internship for summer 2027", datetime(2026, 9, 26, 9, 5, 0));

    assert jid(g1) == jid(g2), "a near-duplicate SetGoal call must reuse the existing goal, not create a second one";
    assert g2.active;
    goals = [me ->:HasGoal:->];
    assert len(goals) == 1, f"expected exactly one goal, got {len(goals)}";
}

test "set_goal_for: a genuinely different goal creates a second goal and deactivates the first" {
    me = (root ++> Me(name="setgoal-distinct-test-me"))[0];

    g1 = set_goal_for(me, "Land a summer 2027 climate-tech VC internship", datetime(2026, 9, 26, 9, 0, 0));
    g2 = set_goal_for(me, "Find a mentor in accessible robotics", datetime(2026, 9, 26, 9, 5, 0));

    assert jid(g1) != jid(g2);
    assert not g1.active;
    assert g2.active;
    goals = [me ->:HasGoal:->];
    assert len(goals) == 2, f"expected two distinct goals, got {len(goals)}";
}

# ---------------------------------------------------------------- SOH-226 ranking stability
# "Maya Chen went strong -> medium after one capture that had nothing to do
# with her" (POLISH-PLAN #10 / FEEL-AUDIT #3). A candidate's RelevantTo edge
# is only re-sent to the model when a Fact/Intent/Promise/Note about THAT
# person is newer than the edge's own `ranked_at`, the goal's text changed,
# or `force` — never on an unrelated capture.

test "newest_evidence_at: picks the max across facts, intents (via their note), promises (via their note), and notes" {
    p = (root ++> Person(name="Evidence Timing P", status="confirmed"))[0];
    assert newest_evidence_at(p) == "", "no evidence at all -> empty";

    f = (root ++> Fact(text="early fact", observed_at="2026-09-01T00:00:00"))[0];
    f +>:FactAbout():+> p;
    assert newest_evidence_at(p) == "2026-09-01T00:00:00";

    n_later = (root ++> Note(text="later note", kind="paste", captured_at="2026-09-20T00:00:00"))[0];
    n_later +>:Mentions():+> p;
    assert newest_evidence_at(p) == "2026-09-20T00:00:00", "a later Note mentioning p wins";

    i = (root ++> Intent(kind="need", text="wants X", expires_at=""))[0];
    i +>:IntentAbout():+> p;
    n_for_intent = (root ++> Note(text="intent note", kind="debrief", captured_at="2026-09-25T00:00:00"))[0];
    n_for_intent +>:AssertsIntent():+> i;
    assert newest_evidence_at(p) == "2026-09-25T00:00:00", "an even later Intent (via its Note) wins";

    pr = (root ++> Promise(text="send deck", due=""))[0];
    pr +>:PromiseTo():+> p;
    n_for_promise = (root ++> Note(text="promise note", kind="debrief", captured_at="2026-09-27T00:00:00"))[0];
    n_for_promise +>:AssertsPromise():+> pr;
    assert newest_evidence_at(p) == "2026-09-27T00:00:00", "the latest Promise (via its Note) wins over everything earlier";
}

test "stale_trigger: new, goal-edited, evidence-newer, force, and not-stale" {
    never_ranked = {"exists": False};
    assert stale_trigger(never_ranked, "goal text", "", False) == "new";
    assert candidate_is_stale(never_ranked, "goal text", "", False);

    goal_edited = {
        "exists": True, "ranked_at": "2026-09-26T10:00:00", "ranked_goal_text": "old goal text",
        "strength": "weak", "label": "cold", "reason": "", "opener": "", "evidence": [],
        "prev_strength": "", "change_reason": ""
    };
    assert stale_trigger(goal_edited, "new goal text", "", False) == "goal";

    fresh = {
        "exists": True, "ranked_at": "2026-09-26T10:00:00", "ranked_goal_text": "same goal text",
        "strength": "strong", "label": "known", "reason": "r", "opener": "o", "evidence": [],
        "prev_strength": "", "change_reason": ""
    };
    assert stale_trigger(fresh, "same goal text", "", False) == "", "no newer evidence, same goal, no force -> not stale";
    assert not candidate_is_stale(fresh, "same goal text", "", False);

    assert stale_trigger(fresh, "same goal text", "2026-09-27T09:00:00", False) == "evidence", "evidence newer than ranked_at -> stale";
    assert stale_trigger(fresh, "same goal text", "2026-09-25T09:00:00", False) == "", "evidence OLDER than ranked_at -> still not stale";
    assert stale_trigger(fresh, "same goal text", "", True) == "force", "force wins even with nothing else stale";
}

test "change_reason_text: product-copy strings per trigger" {
    assert change_reason_text("force", "") == "re-ranked on request";
    assert change_reason_text("goal", "") == "goal edited";
    assert change_reason_text("evidence", "2026-09-27T00:00:00") == "new note on Sep 27";
    assert change_reason_text("evidence", "not-a-date") == "new evidence";
    assert change_reason_text("new", "") == "updated";
}

test "SOH-226 stability: an unrelated capture leaves the untouched candidate's stale_trigger empty (model never asked about them)" {
    now0 = datetime(2026, 9, 26, 9, 0, 0);
    goal = (root ++> Goal(text="stability-test-goal", created_at=now0.isoformat()))[0];
    maya = (root ++> Person(name="Maya Stability", status="confirmed"))[0];
    other = (root ++> Person(name="Other Stability", status="confirmed"))[0];
    ev = EvidenceItem(id="ev-stability", kind="fact", observed_at="2026-09-01", span="some evidence");
    candidates = [
        Candidate(person=maya, label="known", evidence_items=[ev], days_since_contact=None),
        Candidate(person=other, label="known", evidence_items=[ev], days_since_contact=None)
    ];

    # First rank: both are new -> both stale.
    first_indices = compute_stale_indices(candidates, goal, goal.text, False);
    assert first_indices == [0, 1], f"both candidates are new -> both stale, got {first_indices}";

    ranked1 = [
        RankedItem(index=0, strength="strong", reason="Maya reason one.", evidence_indices=[0], opener="Hi Maya"),
        RankedItem(index=1, strength="weak", reason="Other reason one.", evidence_indices=[0], opener="Hi Other")
    ];
    results1 = materialize_stable(goal, candidates, first_indices, ranked1, now0.isoformat(), goal.text, False);
    by_name1: dict[str, dict[str, any]] = {};
    for r in results1 {
        person = r["person"] as Person;
        by_name1[person.name] = r;
    }
    assert by_name1["Maya Stability"]["strength"] == "strong";
    assert by_name1["Maya Stability"]["cached"] == False, "first materialization is a genuine (fallback/model) result, not a carry-over";
    maya_opener_after_first_rank = by_name1["Maya Stability"]["opener"] as str;

    # A capture happens about `other`, NOT about Maya at all.
    later_note = (root ++> Note(text="unrelated capture", kind="debrief", captured_at="2026-09-27T09:00:00"))[0];
    later_note +>:Mentions():+> other;

    second_indices = compute_stale_indices(candidates, goal, goal.text, False);
    assert 0 not in second_indices, "Maya's own evidence never changed -> the model must not be asked about her again";
    assert 1 in second_indices, "other's evidence changed -> other is stale";

    # Second rebuild: only `other` (subset position 0, since Maya isn't in
    # the stale subset at all) gets a fresh ranked item.
    ranked2 = [RankedItem(index=0, strength="medium", reason="Other reason two.", evidence_indices=[0], opener="Hi Other again")];
    results2 = materialize_stable(goal, candidates, second_indices, ranked2, "2026-09-27T09:05:00", goal.text, False);
    by_name2: dict[str, dict[str, any]] = {};
    for r in results2 {
        person = r["person"] as Person;
        by_name2[person.name] = r;
    }

    assert by_name2["Maya Stability"]["strength"] == "strong", "Maya's strength must be identical to the first rank";
    assert by_name2["Maya Stability"]["reason"] == "Maya reason one.", "Maya's reason must be identical to the first rank";
    assert by_name2["Maya Stability"]["opener"] == maya_opener_after_first_rank, "Maya's opener must be identical to the first rank";
    assert by_name2["Maya Stability"]["cached"] == True, "Maya was carried over verbatim, never re-sent to the model";
    assert by_name2["Maya Stability"]["prev_strength"] == "", "nothing changed for Maya -> no prev_strength recorded";
    assert by_name2["Maya Stability"]["change_reason"] == "", "nothing changed for Maya -> no change_reason recorded";

    assert by_name2["Other Stability"]["strength"] == "medium", "other WAS re-evaluated and its strength changed";
    assert by_name2["Other Stability"]["cached"] == False;
    assert by_name2["Other Stability"]["prev_strength"] == "weak", "other's previous strength must be recorded on change";
    assert by_name2["Other Stability"]["change_reason"] == "new note on Sep 27", "other's change is attributed to the new note";
}

test "SOH-226 stability: force re-evaluates a candidate even when nothing about them changed" {
    now0 = datetime(2026, 9, 26, 9, 0, 0);
    goal = (root ++> Goal(text="stability-force-test-goal", created_at=now0.isoformat()))[0];
    maya = (root ++> Person(name="Maya Force", status="confirmed"))[0];
    ev = EvidenceItem(id="ev-force", kind="fact", observed_at="2026-09-01", span="some evidence");
    candidates = [Candidate(person=maya, label="known", evidence_items=[ev], days_since_contact=None)];

    first_indices = compute_stale_indices(candidates, goal, goal.text, False);
    ranked1 = [RankedItem(index=0, strength="strong", reason="Maya reason one.", evidence_indices=[0], opener="Hi Maya")];
    materialize_stable(goal, candidates, first_indices, ranked1, now0.isoformat(), goal.text, False);

    # Nothing about Maya or the goal changed -> not stale without force.
    assert compute_stale_indices(candidates, goal, goal.text, False) == [], "unforced, unchanged -> nobody stale";

    # An explicit force re-ranks her anyway.
    forced_indices = compute_stale_indices(candidates, goal, goal.text, True);
    assert forced_indices == [0], "force re-evaluates every candidate regardless of individual staleness";

    ranked2 = [RankedItem(index=0, strength="medium", reason="Maya reason two.", evidence_indices=[0], opener="Hi Maya again")];
    results = materialize_stable(goal, candidates, forced_indices, ranked2, "2026-09-27T09:00:00", goal.text, True);
    assert results[0]["strength"] == "medium";
    assert results[0]["cached"] == False;
    assert results[0]["prev_strength"] == "strong";
    assert results[0]["change_reason"] == "re-ranked on request";
}

test "prune_stale_relevantto: a person no longer a candidate loses their RelevantTo edge; a kept candidate keeps theirs" {
    goal = (root ++> Goal(text="prune-test-goal", created_at="2026-09-26T09:00:00"))[0];
    kept = (root ++> Person(name="Kept Prune P", status="confirmed"))[0];
    dropped = (root ++> Person(name="Dropped Prune P", status="confirmed"))[0];

    kept +>:RelevantTo(reason="r", strength="weak", label="known", evidence=[], opener=""):+> goal;
    dropped +>:RelevantTo(reason="r", strength="weak", label="known", evidence=[], opener=""):+> goal;

    prune_stale_relevantto(goal, [Candidate(person=kept, label="known", evidence_items=[], days_since_contact=None)]);

    assert [edge kept ->:RelevantTo:-> goal], "kept candidate's edge must survive pruning";
    assert not [edge dropped ->:RelevantTo:-> goal], "a person no longer in the candidate list must lose their RelevantTo edge";
}
