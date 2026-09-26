"""Tests for scoring.sv.jac's deterministic pieces — no LLM calls (rate limits).

Candidate collection (exclusions) and post-processing (ordering + enum
normalization) are exercised directly. The LLM scoring path itself is proven
live via curl (see the SOH-171 deliverable), not by a test.
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
    now = datetime.now().isoformat();

    # (a) offer intent -> must survive
    p_offer = (me +>:Knows:+> Person(name="Offer Person", org="Acme", status="confirmed"))[0];
    intent_offer = (root ++> Intent(kind="offer", text="can intro climate-tech VCs"))[0];
    intent_offer +>:IntentAbout:+> p_offer;

    # (b) shared employer only, no intents, one fact -> survives with fact evidence only
    p_employer = (me +>:Knows:+> Person(name="Employer Person", org="ClimateCo", status="confirmed"))[0];
    fact_employer = (root ++> Fact(text="Works at ClimateCo as an analyst.", observed_at=now))[0];
    fact_employer +>:FactAbout:+> p_employer;

    # (c) proposed Person -> excluded regardless of evidence
    p_proposed = (me +>:Knows:+> Person(name="Proposed Person", status="proposed"))[0];
    fact_proposed = (root ++> Fact(text="Some fact.", observed_at=now))[0];
    fact_proposed +>:FactAbout:+> p_proposed;

    # (d) FromCard handle in exclude_handles -> excluded
    p_excluded = (me +>:Knows:+> Person(name="Excluded Person", status="confirmed"))[0];
    fact_excluded = (root ++> Fact(text="Some other fact.", observed_at=now))[0];
    fact_excluded +>:FactAbout:+> p_excluded;
    card_excluded = (root ++> Card(handle="excluded-handle"))[0];
    p_excluded +>:FromCard:+> card_excluded;

    # a person with zero evidence -> omitted even though confirmed and not excluded
    _ = (me +>:Knows:+> Person(name="No Evidence Person", status="confirmed"))[0];

    candidates = collect_candidates(me, ["excluded-handle"]);
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

test "collect_candidates: expired offer intent is skipped, need intents never match" {
    me = (root ++> Me(name="Scorer Expiry Me"))[0];
    now = datetime.now().isoformat();

    p = (me +>:Knows:+> Person(name="Expiry Person", status="confirmed"))[0];
    expired_offer = (root ++> Intent(kind="offer", text="expired offer", expires_at="2000-01-01T00:00:00"))[0];
    expired_offer +>:IntentAbout:+> p;
    need_intent = (root ++> Intent(kind="need", text="a need, not an offer"))[0];
    need_intent +>:IntentAbout:+> p;

    candidates = collect_candidates(me, []);
    names: list[str] = [];
    for c in candidates {
        cp = c["person"] as Person;
        names.append(cp.name);
    }
    assert "Expiry Person" not in names;

    # now give them a fact so they survive, and confirm the expired/need intents never rode along as evidence
    fact = (root ++> Fact(text="A fact about them.", observed_at=now))[0];
    fact +>:FactAbout:+> p;
    candidates2 = collect_candidates(me, []);
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

test "post_process normalizes a bogus strength to weak, maps evidence indices to jids, drops out-of-range, and orders the result" {
    person_a = Person(name="A", status="confirmed");
    person_b = Person(name="B", status="confirmed");
    person_c = Person(name="C", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]},
        {"person": person_b, "evidence": [{"kind": "offer", "text": "t2", "jid": "jid-2"}]},
        {"person": person_c, "evidence": [{"kind": "fact", "text": "t3", "jid": "jid-3"}]}
    ];
    matches = NeedMatches(items=[
        NeedMatch(index=0, strength="weak", why="w1", evidence_indices=[1]),
        NeedMatch(index=1, strength="strong", why="w2", evidence_indices=[2]),
        NeedMatch(index=2, strength="bogus", why="w3", evidence_indices=[999])
    ]);
    evidence_jids = ["jid-1", "jid-2", "jid-3"];

    results = post_process(candidates, matches, evidence_jids);
    assert len(results) == 3;
    assert results[0]["strength"] == "strong";
    assert results[0]["person_id"] == jid(person_b);
    assert results[0]["evidence_ids"] == ["jid-2"];
    assert results[1]["strength"] == "weak";
    assert results[1]["person_id"] == jid(person_a);
    assert results[2]["strength"] == "weak";
    assert results[2]["person_id"] == jid(person_c);
    assert results[2]["evidence_ids"] == [];
}

test "post_process drops out-of-range candidate indices" {
    person_a = Person(name="A", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [{"kind": "fact", "text": "t1", "jid": "jid-1"}]}
    ];
    matches = NeedMatches(items=[
        NeedMatch(index=5, strength="strong", why="out of range", evidence_indices=[1])
    ]);
    results = post_process(candidates, matches, ["jid-1"]);
    assert len(results) == 0;
}

test "build_prompt numbers evidence globally and returns a parallel jid table" {
    person_a = Person(name="A", org="Acme", title="Eng", status="confirmed");
    candidates = [
        {"person": person_a, "evidence": [
            {"kind": "fact", "text": "fact one", "jid": "jid-1"},
            {"kind": "offer", "text": "offer one", "jid": "jid-2"}
        ]}
    ];
    prompt = build_prompt(candidates);
    text = prompt["text"] as str;
    evidence_jids = prompt["evidence_jids"] as list[str];
    assert evidence_jids == ["jid-1", "jid-2"];
    assert "[1]" in text;
    assert "[2]" in text;
    assert "fact one" in text;
    assert "offer one" in text;
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
