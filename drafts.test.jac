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
    build_evidence_text, map_evidence_indices, DraftFollowUp, first_name,
    promise_noun_phrase
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
    # SOH-212: rendered as a noun phrase ("the demo I said I'd send"), never
    # the old verb-form clash ("following up on send the demo").
    assert "the demo" in draft and "I said I'd send" in draft, f"fallback draft must mention the promise as a noun phrase, got: {draft}";
    assert "following up on send" not in draft, f"must not read as a verb-form clash, got: {draft}";
    assert len(based_on) == 1;
    assert based_on[0]["kind"] == "promise";
    assert based_on[0]["id"] == jid(promise);
}

test "SOH-212 fallback_draft: promise noun-phrase template, no verb-form clash, no doubled period, first-name greeting, untrusted fact dropped (judge repro)" {
    p = (root ++> Person(name="Sarah Kim", status="confirmed"))[0];
    note = (root ++> Note(
        text="Drafts-test: told Sarah Kim I'd send company's intern posting.",
        kind="debrief", captured_at="2026-09-20T10:00:00"
    ))[0];
    promise = (note +>:AssertsPromise(span="send company's intern posting"):+> Promise(
        text="send company's intern posting", done=False
    ))[0];
    promise +>:PromiseTo:+> p;

    # judge3: a fact whose text does NOT start with a trusted lowercase noun
    # phrase pattern must never be spliced after "with" (it read as a broken
    # sentence: "with Leads team Graphwalk, who built...").
    fact = (root ++> Fact(
        text="Leads team Graphwalk, who built the winning bot after the hackathon.",
        observed_at="2026-09-18"
    ))[0];
    fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert draft.startswith("Hi Sarah,"), f"greeting must use the first name only, got: {draft}";
    assert "following up on send" not in draft, f"verb-form clash must be gone, got: {draft}";
    assert "I said I'd send" in draft and "company's intern posting" in draft, f"got: {draft}";
    assert "sending it over now." in draft, f"singular deliverable ('posting') must use 'it', got: {draft}";
    assert ".." not in draft, f"must never emit a doubled period, got: {draft}";
    assert "Leads team Graphwalk" not in draft, f"a fact that doesn't open with a trusted noun phrase must never be spliced after 'with', got: {draft}";
    assert draft.endswith("Hope things are going well."), f"got: {draft}";
    based_on = fb["based_on"] as list[dict[str, str]];
    assert len(based_on) == 1 and based_on[0]["kind"] == "promise", f"the untrusted fact must not be cited, got: {based_on}";
}

test "SOH-212 fallback_draft: a fact that opens with a trusted noun phrase ('the ...') is still spliced after 'with'" {
    p = (root ++> Person(name="Trusted Fact P", status="confirmed"))[0];
    note = (root ++> Note(text="Drafts-test filler note 3", kind="debrief", captured_at="2026-09-20T10:00:00"))[0];
    promise = (note +>:AssertsPromise(span="send the deck"):+> Promise(text="send the deck", done=False))[0];
    promise +>:PromiseTo:+> p;

    fact = (root ++> Fact(
        text="the team behind Graphwalk, which built the winning bot after the hackathon.",
        observed_at="2026-09-18"
    ))[0];
    fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert "Hope things are going well with the team behind Graphwalk" in draft, f"a trusted noun-phrase fact must still be spliced, got: {draft}";
    based_on = fb["based_on"] as list[dict[str, str]];
    assert len(based_on) == 2, f"a short (<80 char), trusted-pattern fact is used as the context clause, got: {based_on}";
}

test "SOH-212 (judge3) fallback_draft: exact judge repro — plural deliverable, first name, fact splice dropped" {
    p = (root ++> Person(name="Sarah Lin", status="confirmed"))[0];
    note = (root ++> Note(
        text="Drafts-test: told Sarah Lin I'd send the notes on the Jac teams.",
        kind="debrief", captured_at="2026-09-20T10:00:00"
    ))[0];
    promise = (note +>:AssertsPromise(span="send the notes on the Jac teams"):+> Promise(
        text="send the notes on the Jac teams", done=False
    ))[0];
    promise +>:PromiseTo:+> p;

    fact = (root ++> Fact(
        text="Works in ML at Google and is a fellow judge this weekend.",
        observed_at="2026-09-18"
    ))[0];
    fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert draft == (
        "Hi Sarah, About the notes on the Jac teams I said I'd send: "
        "sending them over now. Hope things are going well."
    ), f"got: {draft}";
}

test "SOH-212 (judge3) promise_noun_phrase: singular deliverable ('the ROI deck') closes with 'sending it over now.'" {
    p = (root ++> Person(name="Singular P", status="confirmed"))[0];
    note = (root ++> Note(text="Drafts-test filler note 4", kind="debrief", captured_at="2026-09-20T10:00:00"))[0];
    promise = (note +>:AssertsPromise(span="send the ROI deck"):+> Promise(text="send the ROI deck", done=False))[0];
    promise +>:PromiseTo:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;
    assert "About the ROI deck I said I'd send: sending it over now." in draft, f"got: {draft}";
    assert "sending them over now." not in draft, f"got: {draft}";
}

test "SOH-212 (judge3) promise_noun_phrase: plural deliverable ('the intro notes') closes with 'sending them over now.'" {
    p = (root ++> Person(name="Plural P", status="confirmed"))[0];
    note = (root ++> Note(text="Drafts-test filler note 5", kind="debrief", captured_at="2026-09-20T10:00:00"))[0];
    promise = (note +>:AssertsPromise(span="send the intro notes"):+> Promise(text="send the intro notes", done=False))[0];
    promise +>:PromiseTo:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;
    assert "About the intro notes I said I'd send: sending them over now." in draft, f"got: {draft}";
}

test "SOH-212 (judge3) first_name: splits on the first space, empty/whitespace-only pass through unchanged" {
    assert first_name("Sarah Lin") == "Sarah";
    assert first_name("Cher") == "Cher";
    assert first_name("") == "";
    assert first_name("   ") == "";
}

test "SOH-212 fallback_draft: a long fact (>= 80 chars) is never used as the context clause" {
    p = (root ++> Person(name="Drafts-test Long Fact P", status="confirmed"))[0];
    note = (root ++> Note(text="Drafts-test filler note 2", kind="debrief", captured_at="2026-09-20T10:00:00"))[0];
    promise = (note +>:AssertsPromise(span="send the deck"):+> Promise(text="send the deck", done=False))[0];
    promise +>:PromiseTo:+> p;

    long_fact = (root ++> Fact(
        text="A very long fact indeed, one that runs well past eighty characters in total length here.",
        observed_at="2026-09-18"
    ))[0];
    long_fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert "past eighty characters" not in draft, f"a long fact must not be used as the context clause, got: {draft}";
    assert draft.endswith("Hope things are going well."), f"a dropped fact still gets the plain closer, got: {draft}";
    based_on = fb["based_on"] as list[dict[str, str]];
    assert len(based_on) == 1 and based_on[0]["kind"] == "promise";
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
    assert fb["draft"] == "Hi Drafts-test, it was good meeting you. Would love to stay in touch.";
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

test "SOH-232 fallback_draft: a verb-led intent clause is phrased as 'what you mentioned: you <verb>...', never spliced raw after 'about'; 'author's' -> 'your'" {
    p = (root ++> Person(name="Priya Natarajan", status="confirmed"))[0];
    intent = (root ++> Intent(kind="offer", text="Offered to review author's pitch deck next week.", expires_at=""))[0];
    intent +>:IntentAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert draft == (
        "Hi Priya, what you mentioned: you offered to review your pitch deck next week. "
        "How is that going?"
    ), f"got: {draft}";
    assert "author" not in draft.lower(), f"'author' must never reach the draft, got: {draft}";
    assert "about Offered" not in draft, f"must never splice a capitalized verb-led clause raw, got: {draft}";
}

test "SOH-232 fallback_draft: a non-verb-led fact is lowercased and its trailing period stripped before splicing after 'about'" {
    p = (root ++> Person(name="Drafts-test Lowercase P", status="confirmed"))[0];
    fact = (root ++> Fact(text="Just moved to Detroit.", observed_at="2026-09-18"))[0];
    fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert draft == (
        "Hi Drafts-test, I was thinking about what you said about just moved to Detroit. "
        "How is that going?"
    ), f"got: {draft}";
}

test "SOH-232 fallback_draft: a proper-noun-led fact keeps its leading capital when spliced" {
    p = (root ++> Person(name="Drafts-test ProperNoun P", status="confirmed"))[0];
    fact = (root ++> Fact(text="Stripe is hiring backend engineers.", observed_at="2026-09-18"))[0];
    fact +>:FactAbout:+> p;

    now = datetime.now();
    evidence = gather_follow_up_evidence(p, now);
    fb = fallback_draft(p, evidence);
    draft = fb["draft"] as str;

    assert "about Stripe is hiring backend engineers" in draft, f"a proper-noun-led clause must not be lowercased, got: {draft}";
}

test "DraftFollowUp: an unresolvable person_id reports not_found" {
    result = root spawn DraftFollowUp(person_id="not-a-real-person-id-at-all");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

test "SOH-232 (audit I-4) promise_noun_phrase: recipient's name in the object is stripped, not spliced ('send Maya our deck')" {
    assert promise_noun_phrase("send Maya our deck", "Maya") == "About the deck I said I'd send: sending it over now.";
}

test "SOH-232 (audit I-4) promise_noun_phrase: a bare object pronoun standing in for the recipient is stripped ('send her the intro deck')" {
    assert promise_noun_phrase("send her the intro deck", "Maya") == "About the intro deck I said I'd send: sending it over now.";
}

test "SOH-232 (audit I-4) promise_noun_phrase: 'intro X to Y' strips the recipient (the intro's first party) and keeps the third party's name" {
    assert promise_noun_phrase("intro Dev to Priya", "Dev") == "About the intro to Priya I said I'd make: sending it over now.";
}

test "SOH-232 (audit I-4) promise_noun_phrase: no recipient-name match leaves the object untouched (existing behavior)" {
    assert promise_noun_phrase("send the ROI deck", "Someone Else") == "About the ROI deck I said I'd send: sending it over now.";
}
