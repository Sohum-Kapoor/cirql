"""Tests for freshness.sv.jac (SOH-190).

Annex to freshness.sv.jac — run with `jac test freshness.sv.jac`. Deterministic
only: no LLM (this module never calls one), no server.

`jac test` runs every test in this file in declaration order against ONE
shared, persisted `root` (jac-testing) — nodes from earlier tests, and from
earlier `jac test` invocations, are still hanging around, and `FreshnessSweep`
walks the WHOLE caller root (every Note-asserted Fact/Intent, every
`HasIntent`), not just what one test built. So every assertion below filters
`FreshnessSweep`'s report down to the ids this test's own Notes/Facts/Intents
created — never asserts an exact total count over the whole root.
"""

import from freshness { FreshnessSweep, ReconfirmFact, ReconfirmIntent, default_expiry, _parse_naive_utc }
import from schema { Me, Person, Note, Fact, Intent, Asserts, AssertsIntent, HasIntent }
import from datetime { datetime, timedelta }

# ---------------------------------------------------------------- FreshnessSweep

test "FreshnessSweep flags a fact with a past valid_to, a fact stale by age, but not a fresh fact; lists an expired intent but not one with no expiry; is idempotent for facts on a second run" {
    now = datetime.now();
    note = (root ++> Note(
        text="Freshness-test: debrief note for the sweep test.",
        kind="debrief", captured_at=now.isoformat()
    ))[0];

    expired_valid_to = (now - timedelta(days=1)).isoformat();
    old_observed_at = (now - timedelta(days=400)).isoformat();
    fresh_observed_at = now.isoformat();

    fact_expired_valid_to = (note +>:Asserts(span="a"):+> Fact(
        text="Freshness-test fact with an expired valid_to",
        observed_at=fresh_observed_at, valid_to=expired_valid_to, status="reported"
    ))[0];
    fact_old_by_age = (note +>:Asserts(span="b"):+> Fact(
        text="Freshness-test fact stale by age",
        observed_at=old_observed_at, status="reported"
    ))[0];
    fact_fresh = (note +>:Asserts(span="c"):+> Fact(
        text="Freshness-test fresh fact",
        observed_at=fresh_observed_at, status="reported"
    ))[0];

    expired_expires_at = (now - timedelta(days=1)).isoformat();
    intent_expired = (note +>:AssertsIntent(span="d"):+> Intent(
        kind="need", text="Freshness-test expired intent",
        expires_at=expired_expires_at, source_kind="reported"
    ))[0];
    intent_no_expiry = (note +>:AssertsIntent(span="e"):+> Intent(
        kind="need", text="Freshness-test intent with no expiry",
        source_kind="reported"
    ))[0];

    our_fact_ids = [jid(fact_expired_valid_to), jid(fact_old_by_age), jid(fact_fresh)];
    our_intent_ids = [jid(intent_expired), jid(intent_no_expiry)];

    result = root spawn FreshnessSweep(stale_after_days=180);
    assert len(result.reports) == 1;
    out = result.reports[0];

    stale_facts = out["stale_facts"] as list[Fact];
    expired_intents = out["expired_intents"] as list[Intent];

    our_stale_facts = [f for f in stale_facts if jid(f) in our_fact_ids];
    our_expired_intents = [i for i in expired_intents if jid(i) in our_intent_ids];

    assert len(our_stale_facts) == 2, f"expected exactly 2 of this test's facts flagged stale, got {len(our_stale_facts)}";
    stale_ids = [jid(f) for f in our_stale_facts];
    assert jid(fact_expired_valid_to) in stale_ids;
    assert jid(fact_old_by_age) in stale_ids;
    assert jid(fact_fresh) not in stale_ids, "a fresh fact must never be flagged";

    assert len(our_expired_intents) == 1, f"expected exactly 1 of this test's intents listed as expired, got {len(our_expired_intents)}";
    assert jid(intent_expired) == jid(our_expired_intents[0]);

    # Both flagged facts are now status="stale" on the node itself.
    assert fact_expired_valid_to.status == "stale";
    assert fact_old_by_age.status == "stale";
    assert fact_fresh.status != "stale";

    # Second sweep: the two facts are already "stale" -> skipped -> never
    # re-flagged (the idempotence the walker docstring promises). The expired
    # intent carries no such "already told you" state, so it correctly keeps
    # reappearing every sweep until it's reconfirmed or its Fact-equivalent
    # design point doesn't apply to Intent - this is documented behavior, not
    # a bug: GoalRank/scoring already skip an expired intent regardless.
    result2 = root spawn FreshnessSweep(stale_after_days=180);
    out2 = result2.reports[0];
    stale_facts2 = out2["stale_facts"] as list[Fact];
    our_stale_facts2 = [f for f in stale_facts2 if jid(f) in our_fact_ids];
    assert len(our_stale_facts2) == 0, "a second sweep must flag none of this test's facts again";
}

test "FreshnessSweep also reaches an unparsable date without ever flagging it, and picks up a self Intent via HasIntent" {
    now = datetime.now();
    note = (root ++> Note(
        text="Freshness-test: unparsable-date note.",
        kind="debrief", captured_at=now.isoformat()
    ))[0];

    fact_bad_date = (note +>:Asserts(span="f"):+> Fact(
        text="Freshness-test fact with an unparsable observed_at",
        observed_at="not-a-real-date", status="reported"
    ))[0];

    me = (root ++> Me(name="Freshness-test HasIntent Me"))[0];
    self_intent_expired = (me +>:HasIntent:+> Intent(
        kind="offer", text="Freshness-test self intent, expired",
        expires_at=(now - timedelta(days=1)).isoformat(), source_kind="self"
    ))[0];

    result = root spawn FreshnessSweep(stale_after_days=180);
    out = result.reports[0];
    stale_facts = out["stale_facts"] as list[Fact];
    expired_intents = out["expired_intents"] as list[Intent];

    stale_ids = [jid(f) for f in stale_facts];
    assert jid(fact_bad_date) not in stale_ids, "an unparsable observed_at must be skipped, never flagged";

    expired_ids = [jid(i) for i in expired_intents];
    assert jid(self_intent_expired) in expired_ids, "an expired self Intent reachable via HasIntent must be listed";
}

# ---------------------------------------------------------------- ReconfirmFact / ReconfirmIntent

test "ReconfirmFact un-stales a fact and bumps observed_at, optionally overwriting valid_to" {
    now = datetime.now();
    note = (root ++> Note(
        text="Freshness-test: reconfirm fact note.",
        kind="debrief", captured_at=now.isoformat()
    ))[0];
    fact = (note +>:Asserts(span="g"):+> Fact(
        text="Freshness-test fact to reconfirm",
        observed_at=(now - timedelta(days=400)).isoformat(), status="stale"
    ))[0];

    new_valid_to = (now + timedelta(days=30)).isoformat();
    result = root spawn ReconfirmFact(fact_id=jid(fact), valid_to=new_valid_to);
    assert len(result.reports) == 1;
    updated = result.reports[0] as Fact;

    assert updated.status == "confirmed";
    assert updated.valid_to == new_valid_to;
    observed_dt = _parse_naive_utc(updated.observed_at);
    assert observed_dt is not None;
    assert (datetime.now() - observed_dt).days <= 1, "observed_at must be bumped to (approximately) now";
}

test "ReconfirmFact on an unknown id reports not_found" {
    result = root spawn ReconfirmFact(fact_id="not-a-real-fact-id");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

test "ReconfirmIntent sets a given future expiry, or falls back to default_expiry by kind" {
    note = (root ++> Note(
        text="Freshness-test: reconfirm intent note.",
        kind="debrief", captured_at=datetime.now().isoformat()
    ))[0];
    intent_need = (note +>:AssertsIntent(span="h"):+> Intent(
        kind="need", text="Freshness-test intent to reconfirm (need)",
        expires_at="2020-01-01T00:00:00", source_kind="reported"
    ))[0];
    intent_offer = (note +>:AssertsIntent(span="i"):+> Intent(
        kind="offer", text="Freshness-test intent to reconfirm (offer)",
        expires_at="2020-01-01T00:00:00", source_kind="reported"
    ))[0];

    explicit_expiry = (datetime.now() + timedelta(days=45)).isoformat();
    result1 = root spawn ReconfirmIntent(intent_id=jid(intent_need), expires_at=explicit_expiry);
    updated1 = result1.reports[0] as Intent;
    assert updated1.expires_at == explicit_expiry;

    result2 = root spawn ReconfirmIntent(intent_id=jid(intent_offer));
    updated2 = result2.reports[0] as Intent;
    new_dt = _parse_naive_utc(updated2.expires_at);
    assert new_dt is not None and new_dt > datetime.now();
    days_out = (new_dt - datetime.now()).days;
    assert 170 <= days_out <= 180, f"offer default_expiry should land ~180 days out, got {days_out}";
}

test "ReconfirmIntent on an unknown id reports not_found" {
    result = root spawn ReconfirmIntent(intent_id="not-a-real-intent-id");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- default_expiry

test "default_expiry: need is ~90 days out, offer/open_to are ~180 days out" {
    now = datetime.now();

    need_expiry = default_expiry("need", now);
    need_dt = _parse_naive_utc(need_expiry);
    assert need_dt is not None;
    need_days = (need_dt - now).days;
    assert 89 <= need_days <= 90, f"expected ~90 days, got {need_days}";

    offer_expiry = default_expiry("offer", now);
    offer_dt = _parse_naive_utc(offer_expiry);
    assert offer_dt is not None;
    offer_days = (offer_dt - now).days;
    assert 179 <= offer_days <= 180, f"expected ~180 days, got {offer_days}";

    open_to_expiry = default_expiry("open_to", now);
    open_to_dt = _parse_naive_utc(open_to_expiry);
    assert open_to_dt is not None;
    open_to_days = (open_to_dt - now).days;
    assert 179 <= open_to_days <= 180, f"expected ~180 days, got {open_to_days}";
}
