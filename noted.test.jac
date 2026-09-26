"""Tests for noted.sv.jac (SOH-184 NotedCard + ApplyCorrection).

Annex to noted.sv.jac — run with `jac test noted.sv.jac`. Deterministic
only: no LLM anywhere in this module.

`jac test` runs every test in this file in declaration order against ONE
shared, persisted `root` (jac-testing) — nodes from earlier tests, and from
earlier `jac test` invocations, are still hanging around. Two consequences:
  - `noted_card_for` and `apply_correction_for` are exercised directly on
    hand-built nodes (never via `root spawn NotedCard(...)` /
    `root spawn ApplyCorrection(...)` for the success paths) because the
    walkers resolve "the" Me via `[root --> [?:Me]][0]` — ambiguous once
    more than one test has created a Me under the shared root (same
    reasoning `drafts.test.jac`/`reads.test.jac` document). `ApplyCorrection`
    validates `kind` BEFORE it resolves `person_id`, so the `bad_kind` walker
    test is safe through `root spawn` with a garbage id (no "which Me"
    dependency); the `not_found` walker test is likewise safe (an unmatched
    random id never resolves regardless of which Me gets picked).
  - Every test uses a name/text unique to itself (a per-run random suffix)
    so it stays correct however many times the suite has already run
    against this persisted root.
"""

import from noted {
    NotedCard, ApplyCorrection,
    noted_card_for, apply_correction_for, find_known_person, how_met_for,
    build_share_text, intent_prefix, gather_person_facts,
    gather_person_intents, gather_person_promises,
    fact_to_dict, intent_to_dict, promise_to_dict,
    valid_correction_kinds, not_found, bad_kind
}
import from schema {
    Me, Person, Note, Fact, Intent, Promise,
    Knows, Asserts, AssertsIntent, AssertsPromise, FactAbout, IntentAbout, PromiseTo
}
import from datetime { datetime }
import from uuid { uuid4 }

def rid() -> str {
    return str(uuid4())[:8];
}

# ---------------------------------------------------------------- NotedCard

test "NotedCard: 2 facts (one stale), 1 need intent, 1 promise — the shape and the share_text" {
    tag = rid();
    me = (root ++> Me(name=f"Noted-test Me {tag}"))[0];
    p = (root ++> Person(name=f"Noted-test Priya {tag}", status="confirmed"))[0];
    me +>:Knows(how_met="met at a conference", status="confirmed"):+> p;

    note = (root ++> Note(
        text=f"Noted-test debrief {tag}: Priya works on accessible robotics and is looking for feedback from wheelchair users.",
        kind="debrief", captured_at="2026-09-20T10:00:00"
    ))[0];

    fresh_fact = (note +>:Asserts(span="works on accessible robotics"):+> Fact(
        text=f"works on accessible robotics {tag}", observed_at="2026-09-20T10:00:00", status="confirmed"
    ))[0];
    fresh_fact +>:FactAbout:+> p;

    stale_fact = (note +>:Asserts(span="stale fact"):+> Fact(
        text=f"stale claim {tag}", observed_at="2026-09-01T10:00:00", status="stale"
    ))[0];
    stale_fact +>:FactAbout:+> p;

    intent = (note +>:AssertsIntent(span="feedback from wheelchair users"):+> Intent(
        kind="need", text="feedback from wheelchair users", expires_at=""
    ))[0];
    intent +>:IntentAbout:+> p;

    card = noted_card_for(me, p);

    facts_list = card["facts"] as list;
    intents_list = card["intents"] as list;
    assert card["person"] == p;
    assert len(facts_list) == 2, f"expected 2 facts, got {len(facts_list)}";
    assert len(intents_list) == 1;
    assert card["how_met"] == "met at a conference";

    share = card["share_text"] as str;
    assert p.name in share;
    assert f"works on accessible robotics {tag}" in share;
    assert f"stale claim {tag}" not in share, "a stale fact must not appear in share_text";
    assert "looking for:" in share;
    assert "feedback from wheelchair users" in share;
}

test "NotedCard: promises never appear in share_text (they are mine, not the person's to correct)" {
    tag = rid();
    me = (root ++> Me(name=f"Noted-test Me B {tag}"))[0];
    p = (root ++> Person(name=f"Noted-test Sam {tag}", status="confirmed"))[0];
    me +>:Knows(how_met="", status="confirmed"):+> p;

    note = (root ++> Note(text=f"Noted-test debrief B {tag}", kind="debrief", captured_at="2026-09-20T10:00:00"))[0];
    promise = (note +>:AssertsPromise(span="send the demo"):+> Promise(
        text=f"send the demo {tag}", due="2026-09-27"
    ))[0];
    promise +>:PromiseTo:+> p;

    card = noted_card_for(me, p);
    promises_list = card["promises"] as list;
    assert len(promises_list) == 1;
    first_promise = promises_list[0] as dict;
    assert first_promise["text"] == f"send the demo {tag}";

    share = card["share_text"] as str;
    assert f"send the demo {tag}" not in share, "a promise's text must never appear in share_text";
}

test "NotedCard: fact/intent/promise dict shapes carry id/text/status/kind/due/done" {
    tag = rid();
    p = (root ++> Person(name=f"Noted-test Dict P {tag}", status="confirmed"))[0];

    fact = (root ++> Fact(text=f"fact {tag}", observed_at="2026-09-20T10:00:00", status="confirmed"))[0];
    fact +>:FactAbout:+> p;
    intent = (root ++> Intent(kind="offer", text=f"intent {tag}", expires_at="2027-01-01T00:00:00"))[0];
    intent +>:IntentAbout:+> p;
    promise = (root ++> Promise(text=f"promise {tag}", due="2026-10-01", done=True))[0];
    promise +>:PromiseTo:+> p;

    fd = fact_to_dict(fact);
    assert fd["id"] == jid(fact);
    assert fd["text"] == f"fact {tag}";
    assert fd["status"] == "confirmed";

    idd = intent_to_dict(intent);
    assert idd["kind"] == "offer";
    assert idd["expires_at"] == "2027-01-01T00:00:00";

    pd = promise_to_dict(promise);
    assert pd["due"] == "2026-10-01";
    assert pd["done"];
}

test "NotedCard walker: unknown person_id reports not_found" {
    tag = rid();
    result = root spawn NotedCard(person_id=f"nonexistent-{tag}");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- ApplyCorrection

test "apply_correction_for: replace_fact_id — new fact is self-asserted, old fact goes stale, a correction Note exists" {
    tag = rid();
    p = (root ++> Person(name=f"Noted-test Correction P {tag}", status="confirmed"))[0];
    old_note = (root ++> Note(text=f"Noted-test old note {tag}", kind="debrief", captured_at="2026-09-01T00:00:00"))[0];
    old_fact = (old_note +>:Asserts(span="old span"):+> Fact(
        text=f"old fact text {tag}", observed_at="2026-09-01T00:00:00", status="reported", source_kind="reported"
    ))[0];
    old_fact +>:FactAbout:+> p;

    now_dt = datetime.now();
    result = apply_correction_for(p, f"corrected fact text {tag}", jid(old_fact), "fact", now_dt);

    new_fact = result["fact"] as Fact;
    assert new_fact.text == f"corrected fact text {tag}";
    assert new_fact.status == "confirmed";
    assert new_fact.source_kind == "self";
    about = [new_fact ->:FactAbout:->];
    assert p in about;

    assert old_fact.status == "stale", "the replaced fact must be flagged stale, never deleted";
    still_exists = [f for f in gather_person_facts(p) if jid(f) == jid(old_fact)];
    assert len(still_exists) == 1, "the old fact must still exist (never deleted)";

    corrections = [n for n in [root --> [?:Note]] if n.kind == "correction" and n.text == f"corrected fact text {tag}"];
    assert len(corrections) == 1, "a correction Note must exist";
    assert corrections[0].captured_at == now_dt.isoformat();
}

test "apply_correction_for: kind offer — self-sourced intent with a future expiry" {
    tag = rid();
    p = (root ++> Person(name=f"Noted-test Offer P {tag}", status="confirmed"))[0];
    now_dt = datetime.now();

    result = apply_correction_for(p, f"can mentor juniors {tag}", "", "offer", now_dt);
    intent = result["intent"] as Intent;

    assert intent.kind == "offer";
    assert intent.text == f"can mentor juniors {tag}";
    assert intent.source_kind == "self";
    assert intent.expires_at != "", "an offer correction must get a default expiry";

    exp_dt = datetime.fromisoformat(intent.expires_at);
    assert exp_dt > now_dt, "the expiry must be in the future";

    about = [intent ->:IntentAbout:->];
    assert p in about;
}

test "ApplyCorrection walker: bad kind reports error regardless of person_id" {
    tag = rid();
    result = root spawn ApplyCorrection(person_id=f"whatever-{tag}", text="x", kind="nonsense");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "bad_kind"};
}

test "ApplyCorrection walker: unknown person_id reports not_found" {
    tag = rid();
    result = root spawn ApplyCorrection(person_id=f"nonexistent-{tag}", text="x", kind="fact");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

test "valid_correction_kinds / not_found / bad_kind helpers" {
    kinds = valid_correction_kinds();
    assert "fact" in kinds;
    assert "need" in kinds;
    assert "offer" in kinds;
    assert "open_to" in kinds;
    assert "garbage" not in kinds;
    assert not_found() == {"error": "not_found"};
    assert bad_kind() == {"error": "bad_kind"};
}

test "intent_prefix: need/offer/open_to map to the three share_text prefixes" {
    assert intent_prefix("need") == "looking for:";
    assert intent_prefix("offer") == "can offer:";
    assert intent_prefix("open_to") == "open to:";
}

test "find_known_person: resolves a person under Me's own Knows, None for anyone else" {
    tag = rid();
    me = (root ++> Me(name=f"Noted-test FindKnown Me {tag}"))[0];
    p = (root ++> Person(name=f"Noted-test FindKnown P {tag}", status="confirmed"))[0];
    me +>:Knows(status="confirmed"):+> p;

    stranger = (root ++> Person(name=f"Noted-test Stranger {tag}", status="confirmed"))[0];

    found = find_known_person(me, jid(p));
    assert found is not None and jid(found) == jid(p);

    missing = find_known_person(me, jid(stranger));
    assert missing is None;
}
