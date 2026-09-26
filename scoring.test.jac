"""Tests for scoring.sv.jac's deterministic pieces — no LLM calls (rate limits).

Candidate collection (exclusions, tz-safe expiry), prompt building (no names,
per-candidate evidence numbering), and post-processing (per-candidate
evidence mapping, evidence-gated strength, dedupe, omitted-candidate default,
ordering) are exercised directly. The LLM scoring path itself is proven live
via curl (see the SOH-171 deliverable), not by a test.
"""

import from scoring {
    collect_candidates, build_prompt, normalize_strength, fallback_strength,
    order_by_strength, post_process, fallback_results, score_against_need,
    NeedMatch, NeedMatches
}
import from schema {
    Me, Person, Fact, Intent, Card, Knows, FactAbout, IntentAbout, FromCard
}
import from datetime { datetime }

test "collect_candidates: offer intent survives, shared employer survives via fact, proposed person and excluded handle are dropped" {
    me = (root ++> Me(name="Scorer Test Me"))[0];
    now = datetime.now();
    now_iso = now.isoformat();

    # (a) offer intent -> must survive
    p_offer = (me +>:Knows:+> Person(name="Offer Person", org="Acme", status="confirmed"))[0];
    intent_offer = (root ++> Intent(kind="offer", text="can intro climate-tech VCs"))[0];
    intent_offer +>:IntentAbout:+> p_offer;

    # (b) shared employer only, no intents, one fact -> survives with fact evidence only
    p_employer = (me +>:Knows:+> Person(name="Employer Person", org="ClimateCo", status="confirmed"))[0];
    fact_employer = (root ++> Fact(text="Works at ClimateCo as an analyst.", observed_at=now_iso))[0];
    fact_employer +>:FactAbout:+> p_employer;

    # (c) proposed Person -> excluded regardless of evidence
    p_proposed = (me +>:Knows:+> Person(name="Proposed Person", status="proposed"))[0];
    fact_proposed = (root ++> Fact(text="Some fact.", observed_at=now_iso))[0];
    fact_proposed +>:FactAbout:+> p_proposed;

    # (d) FromCard handle in exclude_handles -> excluded
    p_excluded = (me +>:Knows:+> Person(name="Excluded Person", status="confirmed"))[0];
    fact_excluded = (root ++> Fact(text="Some other fact.", observed_at=now_iso))[0];
    fact_excluded +>:FactAbout:+> p_excluded;
    card_excluded = (root ++> Card(handle="excluded-handle"))[0];
    p_excluded +>:FromCard:+> card_excluded;

    # a person with zero evidence -> omitted even though confirmed and not excluded
    _ = (me +>:Knows:+> Person(name="No Evidence Person", status="confirmed"))[0];

    candidates = collect_candidates(me, ["excluded-handle"], now);
    names: list[str] = [];
    for c in candidates {
        p = c["person"] as Person;
        names.append(p.name);
    }

    assert "Offer Person" in names;
    assert "Employer Person" in names;
    assert "Proposed Person" not in names;
    assert "Excluded Person" not in names;
    assert "No Evidence Person" not in names;
}

test "collect_candidates: expired offer intent is skipped (tz-safe), need intents never match, unparsable expires_at is skipped" {
    me = (root ++> Me(name="Scorer Expiry Me"))[0];
    now = datetime.now();
    now_iso = now.isoformat();

    p = (me +>:Knows:+> Person(name="Expiry Person", status="confirmed"))[0];
    expired_offer = (root ++> Intent(kind="offer", text="expired offer", expires_at="2000-01-01T00:00:00"))[0];
    expired_offer +>:IntentAbout:+> p;
    expired_offer_z = (root ++> Intent(kind="offer", text="expired offer with Z", expires_at="2000-01-01T00:00:00Z"))[0];
    expired_offer_z +>:IntentAbout:+> p;
    bad_expiry = (root ++> Intent(kind="offer", text="unparsable expiry", expires_at="not-a-date"))[0];
    bad_expiry +>:IntentAbout:+> p;
    need_intent = (root ++> Intent(kind="need", text="a need, not an offer"))[0];
    need_intent +>:IntentAbout:+> p;

    candidates = collect_candidates(me, [], now);
    names: list[str] = [];
    for c in candidates {
        cp = c["person"] as Person;
        names.append(cp.name);
    }
    assert "Expiry Person" not in names;

    # now give them a fact so they survive, and confirm the expired/unparsable/need
    # intents never rode along as evidence
    fact = (root ++> Fact(text="A fact about them.", observed_at=now_iso))[0];
    fact +>:FactAbout:+> p;
    candidates2 = collect_candidates(me, [], now);
    found: dict[str, any] | None = None;
    for c in candidates2 {
        cp2 = c["person"] as Person;
        if cp2.name == "Expiry Person" {
            found = c;
        }
    }
    assert found is not None;
    matched = found as dict[str, any];
    evidence = matched["evidence"] as list[dict[str, str]];
    assert len(evidence) == 1;
    assert evidence[0]["kind"] == "fact";
}

test "collect_candidates: a live offer intent with a future expires_at (with trailing Z) survives" {
    me = (root ++> Me(name="Scorer Future Expiry Me"))[0];
    now = datetime.now();
    p = (me +>:Knows:+> Person(name="Future Offer Person", status="confirmed"))[0];
    future_offer = (root ++> Intent(kind="offer", text="still-live offer", expires_at="2999-01-01T00:00:00Z"))[0];
    future_offer +>:IntentAbout:+> p;

    candidates = collect_candidates(me, [], now);
    names: list[str] = [];
    for c in candidates {
        cp = c["person"] as Person;
        names.append(cp.name);
    }
    assert "Future Offer Person" in names;
}

test "normalize_strength maps the enum through and anything else to weak" {
    assert normalize_strength("strong") == "strong";
    assert normalize_strength("medium") == "medium";
    assert normalize_strength("weak") == "weak";
    assert normalize_strength("bogus") == "weak";
    assert normalize_strength("") == "weak";
}

test "fallback_strength: medium when an offer/open_to item exists, weak otherwise (fact-only case)" {
    assert fallback_strength([{"kind": "offer", "text": "x", "jid": "j1"}]) == "medium";
    assert fallback_strength([{"kind": "open_to", "text": "x", "jid": "j1"}]) == "medium";
    assert fallback_strength([{"kind": "fact", "text": "x", "jid": "j1"}]) == "weak";
    assert fallback_strength([]) == "weak";
}

test "order_by_strength is stable: strong, then medium, then weak, preserving input order within a bucket" {
    items = [
        {"person_id": "p1", "strength": "weak", "why": "", "evidence_ids": []},
        {"person_id": "p2", "strength": "strong", "why": "", "evidence_ids": []},
        {"person_id": "p3", "strength": "weak", "why": "", "evidence_ids": []},
        {"person_id": "p4", "strength": "medium", "why": "", "evidence_ids": []}
    ];
    ordered = order_by_strength(items);
    ids: list[str] = [it["person_id"] as str for it in ordered];
    assert ids == ["p2", "p4", "p1", "p3"];
}

test "post_process maps evidence indices PER CANDIDATE, never a flat/global table" {
    person_a = Person(name="A", status="confirmed");
    person_b = Person(name="B", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [
            {"kind": "fact", "text": "a0", "jid": "a-jid-0"},
            {"kind": "offer", "text": "a1", "jid": "a-jid-1"}
        ]},
        {"person": person_b, "evidence": [
            {"kind": "fact", "text": "b0", "jid": "b-jid-0"}
        ]}
    ];
    # both candidates cite local index 0 -> must resolve to THEIR OWN jid, not a shared one
    matches = NeedMatches(items=[
        NeedMatch(index=0, strength="strong", why="cites a1", evidence_indices=[1]),
        NeedMatch(index=1, strength="medium", why="cites b0", evidence_indices=[0])
    ]);
    results = post_process(candidates, matches);
    assert len(results) == 2;
    a_result = [r for r in results if r["person_id"] == jid(person_a)][0];
    b_result = [r for r in results if r["person_id"] == jid(person_b)][0];
    assert a_result["evidence_ids"] == ["a-jid-1"];
    assert b_result["evidence_ids"] == ["b-jid-0"];
}

test "post_process: empty mapped evidence forces strength to weak regardless of the LLM's answer" {
    person_a = Person(name="A", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]}
    ];
    # LLM says "strong" but cites an out-of-range local index -> no evidence maps -> weak
    matches = NeedMatches(items=[
        NeedMatch(index=0, strength="strong", why="unsupported", evidence_indices=[99])
    ]);
    results = post_process(candidates, matches);
    assert len(results) == 1;
    assert results[0]["strength"] == "weak";
    assert results[0]["evidence_ids"] == [];
}

test "post_process: dedupes LLM items by index, first wins" {
    person_a = Person(name="A", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]}
    ];
    matches = NeedMatches(items=[
        NeedMatch(index=0, strength="strong", why="first", evidence_indices=[0]),
        NeedMatch(index=0, strength="weak", why="second, should be ignored", evidence_indices=[])
    ]);
    results = post_process(candidates, matches);
    assert len(results) == 1;
    assert results[0]["strength"] == "strong";
    assert results[0]["why"] == "first";
}

test "post_process: a candidate the LLM omitted is still reported, weak, with the default why" {
    person_a = Person(name="A", status="confirmed");
    person_b = Person(name="B", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "offer", "text": "t1", "jid": "jid-1"}]},
        {"person": person_b, "evidence": [{"kind": "fact", "text": "t2", "jid": "jid-2"}]}
    ];
    # only candidate 0 is mentioned; candidate 1 is omitted entirely
    matches = NeedMatches(items=[
        NeedMatch(index=0, strength="strong", why="w1", evidence_indices=[0])
    ]);
    results = post_process(candidates, matches);
    assert len(results) == 2;
    b_result = [r for r in results if r["person_id"] == jid(person_b)][0];
    assert b_result["strength"] == "weak";
    assert b_result["why"] == "No ranking returned.";
    assert b_result["evidence_ids"] == [];
}

test "post_process normalizes a bogus strength to weak and orders the result" {
    person_a = Person(name="A", status="confirmed");
    person_b = Person(name="B", status="confirmed");
    person_c = Person(name="C", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]},
        {"person": person_b, "evidence": [{"kind": "offer", "text": "t2", "jid": "jid-2"}]},
        {"person": person_c, "evidence": [{"kind": "fact", "text": "t3", "jid": "jid-3"}]}
    ];
    matches = NeedMatches(items=[
        NeedMatch(index=0, strength="weak", why="w1", evidence_indices=[0]),
        NeedMatch(index=1, strength="strong", why="w2", evidence_indices=[0]),
        NeedMatch(index=2, strength="bogus", why="w3", evidence_indices=[0])
    ]);

    results = post_process(candidates, matches);
    assert len(results) == 3;
    assert results[0]["strength"] == "strong";
    assert results[0]["person_id"] == jid(person_b);
    assert results[0]["evidence_ids"] == ["jid-2"];
    assert results[1]["strength"] == "weak";
    assert results[1]["person_id"] == jid(person_a);
    assert results[2]["strength"] == "weak";   # bogus -> normalized to weak
    assert results[2]["person_id"] == jid(person_c);
}

test "post_process drops out-of-range candidate indices" {
    person_a = Person(name="A", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]}
    ];
    matches = NeedMatches(items=[
        NeedMatch(index=5, strength="strong", why="out of range", evidence_indices=[0])
    ]);
    results = post_process(candidates, matches);
    # candidate 0 still gets its default entry; the out-of-range item is dropped
    assert len(results) == 1;
    assert results[0]["person_id"] == jid(person_a);
    assert results[0]["strength"] == "weak";
    assert results[0]["why"] == "No ranking returned.";
}

test "build_prompt never includes a person's name, uses role/org, and numbers evidence per-candidate starting at 0" {
    person_a = Person(name="Priya Rao", org="Acme", title="Eng", status="confirmed");
    person_b = Person(name="Dev Patel", org="Acme", title="Analyst", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [
            {"kind": "fact", "text": "fact one", "jid": "jid-1"},
            {"kind": "offer", "text": "offer one", "jid": "jid-2"}
        ]},
        {"person": person_b, "evidence": [
            {"kind": "fact", "text": "fact two", "jid": "jid-3"}
        ]}
    ];
    text = build_prompt(candidates);
    assert "Priya Rao" not in text;
    assert "Dev Patel" not in text;
    assert "Eng" in text;
    assert "Analyst" in text;
    assert "Acme" in text;
    assert "[0]" in text;
    # per-candidate numbering restarts at 0 for the second candidate too
    lines = text.split("\n");
    assert lines[0] == "Candidate 0: role Eng at Acme";
    assert lines[1] == "  [0] fact: fact one";
    assert lines[2] == "  [1] offer: offer one";
    assert lines[3] == "Candidate 1: role Analyst at Acme";
    assert lines[4] == "  [0] fact: fact two";
}

test "fallback_results scores every candidate deterministically and orders the output" {
    person_a = Person(name="A", status="confirmed");
    person_b = Person(name="B", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]},
        {"person": person_b, "evidence": [{"kind": "offer", "text": "t2", "jid": "jid-2"}]}
    ];
    results = fallback_results(candidates);
    assert len(results) == 2;
    assert results[0]["strength"] == "medium";
    assert results[0]["person_id"] == jid(person_b);
    assert results[1]["strength"] == "weak";
    assert results[1]["person_id"] == jid(person_a);
    assert results[1]["why"] == "Scored from available evidence.";
}

test "score_against_need reports [] when the caller has no candidates" {
    me = (root ++> Me(name="No Candidates Me"))[0];
    results = score_against_need(me, "an intro to anyone", []);
    assert results == [];
}
