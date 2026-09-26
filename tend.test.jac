"""Tests for tend.sv.jac (SOH-196).

Annex to tend.sv.jac — run with `jac test tend.sv.jac`. Deterministic only:
no LLM (this module never calls one), no server.

`jac test tend.sv.jac` also runs `goals.test.jac` (tend imports from
`goals.sv.jac`, per AGENTS.md's `jac test X.sv.jac also runs the test files
of modules X imports` gotcha) and shares ONE persisted `root` across every
test in the run (jac-testing). Per AGENTS.md's Tend-specific gotcha ("never
take `[root --> [?:Me]][0]` in helpers tests call"), every test here builds
its OWN fresh `Me` + people and calls `tend_for(me, now, limit)` directly —
never `root spawn Tend(...)`, which would resolve "the" `Me` ambiguously off
the shared root. Because `tend_for`'s every traversal starts from a node
reference (`me`, then each `Person`, never `[root --> ...]`), one test's
fixtures can never leak into another's result, so names don't need a random
per-run suffix the way root-wide-scan modules (`capture.test.jac`) do — but
every person is still asserted by name, never by raw list length against the
whole root.
"""

import from tend { tend_for }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal,
    Knows, PromiseTo, AssertsPromise, FactAbout, IntentAbout, AssertsIntent,
    RelevantTo, HasGoal
}
import from datetime { datetime, timedelta }

def _person_names(result: list[dict[str, any]]) -> list[str] {
    names: list[str] = [];
    for item in result {
        p = item["person"] as Person;
        names.append(p.name);
    }
    return names;
}

def _by_kind(result: list[dict[str, any]], kind: str) -> list[dict[str, any]] {
    return [item for item in result if item["kind"] == kind];
}

test "tend_for: open promises (due ascending, empty due last), expiring intents (14-day window), strong-only RelevantTo, stale-only facts, and a no-reason person produces nothing" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Tend-test Me"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Tend-test goal", created_at=now.isoformat(), active=True))[0];

    # --- open promises: due tomorrow, due later, no due at all
    p_due_soon = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Promise Soon", status="confirmed"))[0];
    p_due_later = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Promise Later", status="confirmed"))[0];
    p_due_none = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Promise NoDue", status="confirmed"))[0];

    note_p = (root ++> Note(text="Tend-test promise note", kind="debrief", captured_at=now.isoformat()))[0];

    promise_soon = (root ++> Promise(text="send our demo", due="2026-09-27", done=False))[0];
    note_p +>:AssertsPromise(span="send our demo"):+> promise_soon;
    promise_soon +>:PromiseTo:+> p_due_soon;

    promise_later = (root ++> Promise(text="send the deck", due="2026-10-15", done=False))[0];
    note_p +>:AssertsPromise(span="send the deck"):+> promise_later;
    promise_later +>:PromiseTo:+> p_due_later;

    promise_none = (root ++> Promise(text="intro to Sam", due="", done=False))[0];
    note_p +>:AssertsPromise(span="intro to Sam"):+> promise_none;
    promise_none +>:PromiseTo:+> p_due_none;

    # a DONE promise must never surface
    p_done = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Promise Done", status="confirmed"))[0];
    promise_done = (root ++> Promise(text="already sent", due="2026-09-27", done=True))[0];
    promise_done +>:PromiseTo:+> p_done;

    # --- expiring intents: 5 days out (in), 60 days out (excluded), already expired (excluded)
    p_intent_soon = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Intent Soon", status="confirmed"))[0];
    p_intent_far = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Intent Far", status="confirmed"))[0];
    p_intent_expired = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Intent Expired", status="confirmed"))[0];

    note_i = (root ++> Note(text="Tend-test intent note", kind="debrief", captured_at=now.isoformat()))[0];

    intent_soon = (root ++> Intent(kind="offer", text="intros to climate-tech founders", expires_at=(now + timedelta(days=5)).isoformat()))[0];
    note_i +>:AssertsIntent(span="intros to climate-tech founders"):+> intent_soon;
    intent_soon +>:IntentAbout:+> p_intent_soon;

    intent_far = (root ++> Intent(kind="offer", text="far offer", expires_at=(now + timedelta(days=60)).isoformat()))[0];
    note_i +>:AssertsIntent(span="far offer"):+> intent_far;
    intent_far +>:IntentAbout:+> p_intent_far;

    intent_expired = (root ++> Intent(kind="need", text="already lapsed need", expires_at=(now - timedelta(days=1)).isoformat()))[0];
    note_i +>:AssertsIntent(span="already lapsed need"):+> intent_expired;
    intent_expired +>:IntentAbout:+> p_intent_expired;

    # --- RelevantTo: one strong (in), one weak (excluded)
    p_strong = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Strong Match", status="confirmed"))[0];
    p_weak = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Weak Match", status="confirmed"))[0];

    strong_fact = (root ++> Fact(text="wants a VC intro", observed_at=now.isoformat(), status="reported"))[0];
    strong_fact +>:FactAbout:+> p_strong;
    p_strong +>:RelevantTo(reason="wants a VC intro", strength="strong", label="known", evidence=[jid(strong_fact)], opener=""):+> goal;
    p_weak +>:RelevantTo(reason="similar title", strength="weak", label="cold", evidence=[], opener=""):+> goal;

    # --- stale facts: one stale (in), one fresh (excluded)
    p_stale = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Stale Fact", status="confirmed"))[0];
    p_fresh = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-test Fresh Fact", status="confirmed"))[0];

    stale_fact = (root ++> Fact(text="works at the lab", observed_at="2026-03-01", status="stale"))[0];
    stale_fact +>:FactAbout:+> p_stale;
    fresh_fact = (root ++> Fact(text="still works at the lab", observed_at="2026-09-20", status="reported"))[0];
    fresh_fact +>:FactAbout:+> p_fresh;

    # --- a person with ONLY an old last_contact and no other reason: no nudge, ever
    p_old_contact_only = (me +>:Knows(status="confirmed", last_contact=(now - timedelta(days=400)).isoformat()):+> Person(name="Tend-test Old Contact Only", status="confirmed"))[0];

    result = tend_for(me, now, 8);
    names = _person_names(result);

    # ---- kinds present, in contract order
    kinds_in_order = [item["kind"] for item in result];
    assert kinds_in_order == [
        "open_promise", "open_promise", "open_promise",
        "expiring_intent",
        "newly_relevant",
        "stale_fact"
    ], f"got {kinds_in_order}";

    # ---- open promises: due ascending, empty due last; done promise excluded
    promises = _by_kind(result, "open_promise");
    assert len(promises) == 3;
    assert [(pr["person"] as Person).name for pr in promises] == [
        "Tend-test Promise Soon", "Tend-test Promise Later", "Tend-test Promise NoDue"
    ];
    assert promises[0]["reason"] == "You promised Tend-test Promise Soon: send our demo (due 2026-09-27)";
    assert promises[2]["reason"] == "You promised Tend-test Promise NoDue: intro to Sam", "no-due promise reason must not append a '(due ...)' suffix";
    assert promises[0]["evidence"]["kind"] == "promise";
    assert promises[0]["evidence"]["id"] == jid(promise_soon);
    assert promises[0]["evidence"]["span"] == "send our demo";
    assert promises[0]["suggested_action"] == "Send it";
    assert "Tend-test Promise Done" not in names, "a done promise must never surface as a nudge";

    # ---- expiring intents: only the 5-day one; 60-day and already-expired excluded
    intents = _by_kind(result, "expiring_intent");
    assert len(intents) == 1;
    intent_person = intents[0]["person"] as Person;
    assert intent_person.name == "Tend-test Intent Soon";
    assert intents[0]["reason"] == "Tend-test Intent Soon's offer 'intros to climate-tech founders' expires in 5 days";
    assert intents[0]["evidence"]["kind"] == "intent";
    assert intents[0]["evidence"]["id"] == jid(intent_soon);
    assert intents[0]["suggested_action"] == "Reconfirm or let it lapse";
    assert "Tend-test Intent Far" not in names, "an intent expiring in 60 days must be excluded (14-day window)";
    assert "Tend-test Intent Expired" not in names, "an already-expired intent is FreshnessSweep's concern, not a Tend nudge";

    # ---- newly_relevant: only the strong match
    relevant = _by_kind(result, "newly_relevant");
    assert len(relevant) == 1;
    relevant_person = relevant[0]["person"] as Person;
    assert relevant_person.name == "Tend-test Strong Match";
    assert relevant[0]["reason"] == "Tend-test Strong Match is a strong match for your goal 'Tend-test goal'";
    assert relevant[0]["evidence"]["id"] == jid(strong_fact);
    assert relevant[0]["suggested_action"] == "Reach out (use the drafted opener)";
    assert "Tend-test Weak Match" not in names, "a weak RelevantTo match must never surface";

    # ---- stale facts: only the stale one
    stale = _by_kind(result, "stale_fact");
    assert len(stale) == 1;
    stale_person = stale[0]["person"] as Person;
    assert stale_person.name == "Tend-test Stale Fact";
    assert stale[0]["reason"] == "A fact about Tend-test Stale Fact is stale: 'works at the lab' (observed 2026-03-01)";
    assert stale[0]["evidence"]["id"] == jid(stale_fact);
    assert stale[0]["suggested_action"] == "Reconfirm or forget";
    assert "Tend-test Fresh Fact" not in names, "a fresh (non-stale) fact must never surface";

    # ---- the "old last_contact only" person never appears, in any kind
    assert "Tend-test Old Contact Only" not in names, "a stale last_contact is display-only and is never itself a reason";
}

test "tend_for: 14-day window is inclusive at the boundary and excludes 15 days out" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Tend-window-test Me"))[0];

    p14 = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-window-test 14d", status="confirmed"))[0];
    p15 = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-window-test 15d", status="confirmed"))[0];
    p0 = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-window-test 0d", status="confirmed"))[0];

    note = (root ++> Note(text="Tend-window-test note", kind="debrief", captured_at=now.isoformat()))[0];

    intent14 = (root ++> Intent(kind="need", text="exactly 14 days out", expires_at=(now + timedelta(days=14)).isoformat()))[0];
    note +>:AssertsIntent(span="exactly 14 days out"):+> intent14;
    intent14 +>:IntentAbout:+> p14;

    intent15 = (root ++> Intent(kind="need", text="exactly 15 days out", expires_at=(now + timedelta(days=15)).isoformat()))[0];
    note +>:AssertsIntent(span="exactly 15 days out"):+> intent15;
    intent15 +>:IntentAbout:+> p15;

    intent0 = (root ++> Intent(kind="need", text="expires today", expires_at=now.isoformat()))[0];
    note +>:AssertsIntent(span="expires today"):+> intent0;
    intent0 +>:IntentAbout:+> p0;

    result = tend_for(me, now, 8);
    names = _person_names(result);

    assert "Tend-window-test 14d" in names, "exactly 14 days out must be included";
    assert "Tend-window-test 0d" in names, "expiring today (0 days out) must be included";
    assert "Tend-window-test 15d" not in names, "15 days out is past the 14-day window";
}

test "tend_for: newly_relevant capped at 3, ordered by days_since_contact descending with null first" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Tend-nr-test Me"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Tend-nr-test goal", created_at=now.isoformat(), active=True))[0];

    fact = (root ++> Fact(text="Tend-nr-test evidence fact", observed_at=now.isoformat(), status="reported"))[0];

    # route candidate: no Knows edge from me at all -> days_since_contact is None
    p_route = (root ++> Person(name="Tend-nr-test Route (null)", status="confirmed"))[0];
    fact +>:FactAbout:+> p_route;
    p_route +>:RelevantTo(reason="r", strength="strong", label="route", evidence=[jid(fact)], opener=""):+> goal;

    p_recent = (me +>:Knows(status="confirmed", last_contact=(now - timedelta(days=2)).isoformat()):+> Person(name="Tend-nr-test Recent", status="confirmed"))[0];
    fact +>:FactAbout:+> p_recent;
    p_recent +>:RelevantTo(reason="r", strength="strong", label="known", evidence=[jid(fact)], opener=""):+> goal;

    p_old = (me +>:Knows(status="confirmed", last_contact=(now - timedelta(days=90)).isoformat()):+> Person(name="Tend-nr-test Old", status="confirmed"))[0];
    fact +>:FactAbout:+> p_old;
    p_old +>:RelevantTo(reason="r", strength="strong", label="known", evidence=[jid(fact)], opener=""):+> goal;

    p_middle = (me +>:Knows(status="confirmed", last_contact=(now - timedelta(days=20)).isoformat()):+> Person(name="Tend-nr-test Middle", status="confirmed"))[0];
    fact +>:FactAbout:+> p_middle;
    p_middle +>:RelevantTo(reason="r", strength="strong", label="known", evidence=[jid(fact)], opener=""):+> goal;

    result = tend_for(me, now, 8);
    relevant = _by_kind(result, "newly_relevant");

    assert len(relevant) == 3, f"expected the cap to hold at 3, got {len(relevant)}";
    ordered_names = [(item["person"] as Person).name for item in relevant];
    assert ordered_names == [
        "Tend-nr-test Route (null)", "Tend-nr-test Old", "Tend-nr-test Middle"
    ], f"expected null-first then descending days_since_contact, got {ordered_names}";
    assert relevant[0]["days_since_contact"] is None;
    assert relevant[1]["days_since_contact"] == 90;
    assert relevant[2]["days_since_contact"] == 20;
}

test "tend_for: stale facts capped at 2" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Tend-stale-test Me"))[0];

    p1 = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-stale-test P1", status="confirmed"))[0];
    p2 = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-stale-test P2", status="confirmed"))[0];
    p3 = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Tend-stale-test P3", status="confirmed"))[0];

    f1 = (root ++> Fact(text="stale fact one", observed_at="2026-01-01", status="stale"))[0];
    f1 +>:FactAbout:+> p1;
    f2 = (root ++> Fact(text="stale fact two", observed_at="2026-02-01", status="stale"))[0];
    f2 +>:FactAbout:+> p2;
    f3 = (root ++> Fact(text="stale fact three", observed_at="2026-03-01", status="stale"))[0];
    f3 +>:FactAbout:+> p3;

    result = tend_for(me, now, 8);
    stale = _by_kind(result, "stale_fact");

    assert len(stale) == 2, f"expected the cap to hold at 2, got {len(stale)}";
    ordered_names = [(item["person"] as Person).name for item in stale];
    assert ordered_names == ["Tend-stale-test P1", "Tend-stale-test P2"], "oldest observed_at first, capped at 2";
}

test "tend_for: overall `limit` truncates the final ordered list" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Tend-limit-test Me"))[0];
    note = (root ++> Note(text="Tend-limit-test note", kind="debrief", captured_at=now.isoformat()))[0];

    due_dates = ["2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"];
    for i in range(5) {
        p = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name=f"Tend-limit-test P{i}", status="confirmed"))[0];
        pr = (root ++> Promise(text=f"promise {i}", due=due_dates[i], done=False))[0];
        note +>:AssertsPromise(span=f"promise {i}"):+> pr;
        pr +>:PromiseTo:+> p;
    }

    result = tend_for(me, now, 3);
    assert len(result) == 3, f"expected the overall limit to cap the list at 3, got {len(result)}";
    ordered_names = [(item["person"] as Person).name for item in result];
    assert ordered_names == ["Tend-limit-test P0", "Tend-limit-test P1", "Tend-limit-test P2"];
}
