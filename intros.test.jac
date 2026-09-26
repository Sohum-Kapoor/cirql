"""Tests for intros.sv.jac — the Introduction state machine.

Deterministic, no LLM calls. Exercises both walkers in-process (`root spawn`)
per `jac guide jac-testing`; no server/JacTestClient needed since these
walkers take no auth-dependent branch beyond `:priv`'s own JWT gate (which
in-process spawn bypasses, same as every other `.test.jac` annex in this repo
that isn't specifically testing auth/isolation).
"""

import from intros { AdvanceIntroduction, DevProposeIntroduction, is_valid_transition }
import from schema { Me, Person, Knows, Introduction, Proposes }

test "is_valid_transition: the deterministic forward map, any-state exits, and sent/terminal rejection" {
    assert is_valid_transition("proposed", "reviewed", "");
    assert is_valid_transition("reviewed", "awaiting_permission", "");
    assert is_valid_transition("awaiting_permission", "approved", "in_app");
    assert is_valid_transition("approved", "draft_ready", "");

    # approving without a valid approval_source is rejected
    assert not is_valid_transition("awaiting_permission", "approved", "");
    assert not is_valid_transition("awaiting_permission", "approved", "bogus");

    # any non-terminal state can exit to declined | canceled | expired
    assert is_valid_transition("proposed", "declined", "");
    assert is_valid_transition("reviewed", "canceled", "");
    assert is_valid_transition("draft_ready", "expired", "");

    # sent is unreachable this weekend, from anywhere
    assert not is_valid_transition("draft_ready", "sent", "");
    assert not is_valid_transition("proposed", "sent", "");

    # terminal states accept nothing further
    assert not is_valid_transition("declined", "reviewed", "");
    assert not is_valid_transition("expired", "canceled", "");

    # unknown states are rejected
    assert not is_valid_transition("bogus", "reviewed", "");
    assert not is_valid_transition("proposed", "bogus", "");

    # skipping ahead in the forward map is rejected
    assert not is_valid_transition("proposed", "approved", "in_app");
}

test "AdvanceIntroduction: full happy path, then sent is rejected" {
    intro = (root ++> Introduction(state="proposed"))[0];
    iid = jid(intro);

    r1 = root spawn AdvanceIntroduction(intro_id=iid, to_state="reviewed");
    rep1 = r1.reports[0];
    assert rep1["ok"];
    assert rep1["from"] == "proposed";
    assert rep1["to"] == "reviewed";

    r2 = root spawn AdvanceIntroduction(intro_id=iid, to_state="awaiting_permission");
    assert r2.reports[0]["ok"];

    # approved without approval_source is rejected
    r3 = root spawn AdvanceIntroduction(intro_id=iid, to_state="approved");
    rep3 = r3.reports[0];
    assert not rep3["ok"];
    assert rep3["error"] == "invalid_transition";
    assert rep3["introduction"] is None;

    r4 = root spawn AdvanceIntroduction(intro_id=iid, to_state="approved", approval_source="in_app");
    assert r4.reports[0]["ok"];

    r5 = root spawn AdvanceIntroduction(intro_id=iid, to_state="draft_ready");
    assert r5.reports[0]["ok"];

    r6 = root spawn AdvanceIntroduction(intro_id=iid, to_state="sent");
    rep6 = r6.reports[0];
    assert not rep6["ok"];
    assert rep6["error"] == "invalid_transition";
    assert rep6["from"] == "draft_ready";
    assert rep6["to"] == "sent";

    assert intro.state == "draft_ready";
}

test "AdvanceIntroduction: declined is a terminal state; reviewed after it is rejected" {
    intro = (root ++> Introduction(state="proposed"))[0];
    iid = jid(intro);

    r1 = root spawn AdvanceIntroduction(intro_id=iid, to_state="declined");
    assert r1.reports[0]["ok"];

    r2 = root spawn AdvanceIntroduction(intro_id=iid, to_state="reviewed");
    rep2 = r2.reports[0];
    assert not rep2["ok"];
    assert rep2["error"] == "invalid_transition";
    assert rep2["from"] == "declined";
}

test "AdvanceIntroduction: unknown id reports not_found" {
    r = root spawn AdvanceIntroduction(intro_id="not-a-real-jid", to_state="reviewed");
    rep = r.reports[0];
    assert not rep["ok"];
    assert rep["error"] == "not_found";
    assert rep["introduction"] is None;
}

test "DevProposeIntroduction: creates an Introduction with two Proposes edges when both people are under the caller's Me" {
    me = (root ++> Me(name="Intro Test Me"))[0];
    a = (me +>:Knows:+> Person(name="A Person", status="confirmed"))[0];
    b = (me +>:Knows:+> Person(name="B Person", status="confirmed"))[0];

    r = root spawn DevProposeIntroduction(a_id=jid(a), b_id=jid(b), rationale_a="ra", rationale_b="rb");
    assert len(r.reports) == 1;
    intro = r.reports[0];
    assert intro.state == "proposed";
    assert intro.rationale_a == "ra";
    assert intro.rationale_b == "rb";
    proposed = [intro ->:Proposes:->];
    assert len(proposed) == 2;
    proposed_ids = [jid(p) for p in proposed];
    assert jid(a) in proposed_ids;
    assert jid(b) in proposed_ids;
}

test "DevProposeIntroduction: a missing person id reports nothing" {
    me = (root ++> Me(name="Intro Test Me 2"))[0];
    a = (me +>:Knows:+> Person(name="Only Person", status="confirmed"))[0];

    r = root spawn DevProposeIntroduction(a_id=jid(a), b_id="not-a-real-jid");
    assert len(r.reports) == 0;
}
