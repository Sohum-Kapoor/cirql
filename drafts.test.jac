"""Tests for drafts.sv.jac (SOH-191).

Annex to drafts.sv.jac — run with `jac test drafts.sv.jac`. Deterministic
only: the Gemini quota is exhausted today, so no test may reach `by llm` —
`gather_follow_up_evidence` and `fallback_draft` are exercised directly as
plain defs on hand-built nodes, never through `root spawn DraftFollowUp(...)`
for the success path (the walker resolves "the" `Me` via
`[root --> [?:Me]][0]`, ambiguous once more than one test in this file — or
an earlier `jac test` run against this persisted root — has created a `Me`;
same reasoning `reads.test.jac` documents for `GraphView`). The one walker
test here (`person_id` unresolvable) doesn't depend on which `Me` gets
picked, so it's safe through `root spawn`.
"""

import from drafts {
    EvidenceItem, gather_follow_up_evidence, fallback_draft,
    build_evidence_text, map_evidence_indices, DraftFollowUp
}
import from schema {
    Person, Note, Fact, Intent, Promise,
    FactAbout, IntentAbout, PromiseTo, Mentions, AssertsIntent, AssertsPromise
}
import from datetime { datetime }

test "gather_follow_up_evidence + fallback_draft: an open promise is the top evidence and drives the fallback draft" {
    p = (root ++> Person(name="Drafts-test Promise P", status="confirmed", org="Acme"))[0];
    note = (root ++> Note(
        text="Drafts-test: told Promise P I'd send the demo by Friday.",
        kind="debrief", captured_at="2026-09-20T10:00:00"
    ))[0];
    promise = (note +>:AssertsPromise(span="send the demo by Friday"):+> Promise(
        text="send the demo", due="2026-09-27", done=False
    ))[0];
    promise +>:PromiseTo:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    assert len(evidence) == 1, f"expected exactly the one open promise, got {[e.kind for e in evidence]}";
    assert evidence[0].kind == "promise";
    assert evidence[0].id == jid(promise);

    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;
    based_on = fb["based_on"] as list[dict[str, str]];
    assert "send the demo" in draft, f"fallback draft must mention the promise text, got: {draft}";
    assert len(based_on) == 1;
    assert based_on[0]["kind"] == "promise";
    assert based_on[0]["id"] == jid(promise);
}

test "gather_follow_up_evidence + fallback_draft: a done promise is excluded, an unrelated fact wins instead" {
    p = (root ++> Person(name="Drafts-test Done Promise P", status="confirmed"))[0];
    note = (root ++> Note(text="Drafts-test filler note", kind="debrief", captured_at="2026-09-01T10:00:00"))[0];
    done_promise = (note +>:AssertsPromise(span="already sent"):+> Promise(text="already sent thing", done=True))[0];
    done_promise +>:PromiseTo:+> p;

    fact = (root ++> Fact(text="Drafts-test: works on accessible robotics", observed_at="2026-09-18"))[0];
    fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    kinds = [e.kind for e in evidence];
    assert "promise" not in kinds, f"a done promise must never surface as follow-up evidence, got {kinds}";
    assert "fact" in kinds;

    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;
    assert "works on accessible robotics" in draft;
    based_on = fb["based_on"] as list[dict[str, str]];
    assert len(based_on) == 1;
    assert based_on[0]["kind"] == "fact";
    assert based_on[0]["id"] == jid(fact);
}

test "gather_follow_up_evidence + fallback_draft: a person with nothing gets the generic opener" {
    p = (root ++> Person(name="Drafts-test Nothing P", status="confirmed"))[0];
    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    assert evidence == [], "a person with no facts/intents/promises/notes has no evidence at all";

    fb = fallback_draft(p, evidence);
    assert fb["draft"] == "Hi Drafts-test Nothing P, it was good meeting you. Would love to stay in touch.";
    assert fb["based_on"] == [];
}

test "gather_follow_up_evidence: expired intent skipped, live intent's observed_at comes from its Note, note text truncated to 120" {
    p = (root ++> Person(name="Drafts-test Evidence P", status="confirmed"))[0];

    live_intent = (root ++> Intent(kind="need", text="wants feedback from wheelchair users", expires_at=""))[0];
    live_intent +>:IntentAbout:+> p;
    note_for_intent = (root ++> Note(text="Drafts-test intent note", kind="debrief", captured_at="2026-09-22T09:00:00"))[0];
    note_for_intent +>:AssertsIntent:+> live_intent;

    expired_intent = (root ++> Intent(kind="need", text="expired need", expires_at="2020-01-01T00:00:00"))[0];
    expired_intent +>:IntentAbout:+> p;

    long_text = "x" * 200;
    mention_note = (root ++> Note(text=long_text, kind="paste", captured_at="2026-09-23T09:00:00"))[0];
    mention_note +>:Mentions:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);

    kinds = [e.kind for e in evidence];
    assert "intent" in kinds, f"the live intent must survive, got {kinds}";
    texts = [e.span for e in evidence if e.kind == "intent"];
    assert "wants feedback from wheelchair users" in texts;
    assert "expired need" not in texts, "an expired intent must never surface as evidence";

    intent_item = [e for e in evidence if e.kind == "intent"][0];
    assert intent_item.observed_at == "2026-09-22T09:00:00", "an intent's observed_at is its asserting Note's captured_at";

    note_item = [e for e in evidence if e.kind == "note"][0];
    assert len(note_item.span) == 120, "note span is capped at 120 chars";
}

test "gather_follow_up_evidence: capped at 8, newest first" {
    p = (root ++> Person(name="Drafts-test Cap P", status="confirmed"))[0];

    for i in range(10) {
        f = (root ++> Fact(text=f"drafts-cap fact {i}", observed_at=f"2026-01-{i + 1:02d}"))[0];
        f +>:FactAbout:+> p;
    }

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    assert len(evidence) == 8, f"expected the cap to hold at 8, got {len(evidence)}";
    dropped = ["drafts-cap fact 0", "drafts-cap fact 1"];
    for e in evidence {
        assert e.span not in dropped, f"newest-first: the two oldest facts must be dropped by the 8-cap, got {e.span}";
    }
}

test "build_evidence_text + map_evidence_indices: numbering round-trips, out-of-range and duplicate indices are dropped" {
    ev = [
        EvidenceItem(id="ev-a", kind="fact", observed_at="2026-09-01", span="fact span"),
        EvidenceItem(id="ev-b", kind="promise", observed_at="2026-09-02", span="promise span")
    ];
    text = build_evidence_text(ev);
    assert "[0] fact: fact span" in text;
    assert "[1] promise: promise span" in text;

    mapped = map_evidence_indices(ev, [1, 1, 0, 99, -1]);
    assert len(mapped) == 2, "dedupe by index (first wins) and drop out-of-range";
    assert mapped[0]["id"] == "ev-b";
    assert mapped[1]["id"] == "ev-a";
}

test "DraftFollowUp: an unresolvable person_id reports not_found" {
    result = root spawn DraftFollowUp(person_id="not-a-real-person-id-at-all");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}
