"""Tests for dates.sv.jac (SOH-219).

Annex to dates.sv.jac — run with `jac test dates.sv.jac`. Deterministic
only: no LLM, no network (this module never calls one).

`jac test dates.sv.jac` also runs `goals.test.jac` (`dates.sv.jac` imports
`_parse_naive_utc` from `goals.sv.jac`, AGENTS.md's "jac test X.sv.jac also
runs the test files of modules X imports" gotcha).

`parse_due`/`upcoming_dates_for`/`_normalize_promises`/`_normalize_intents`
are exercised directly on hand-built objects, never through `root spawn`,
for the same reason `tend.test.jac` does: `UpcomingDates`/`NormalizeDates`
resolve "the" `Me` via `[root --> [?:Me]][0]`, which is ambiguous once more
than one test has created a `Me` under the shared, persisted `jac-testing`
root.
"""

import from dates {
    parse_due, upcoming_dates_for, _gather_promises_due, _gather_intents_expiring,
    _gather_events, _normalize_promises, _normalize_intents
}
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Event,
    Knows, AssertsPromise, AssertsIntent, PromiseTo, IntentAbout, HasEvent
}
import from datetime { datetime }

# ---------------------------------------------------------------- parse_due
#
# Fixed base: Saturday 2026-09-26 (weekday() == 5). Every case below is
# checked against this one base so the table is easy to eyeball.

glob _BASE: str = "2026-09-26T12:00:00";

test "parse_due: today / tomorrow / next week / end of month" {
    assert parse_due("today", _BASE) == "2026-09-26";
    assert parse_due("Tomorrow", _BASE) == "2026-09-27";
    assert parse_due("next week", _BASE) == "2026-10-03";
    assert parse_due("end of month", _BASE) == "2026-09-30";
}

test "parse_due: in N days / weeks / months (calendar month arithmetic)" {
    assert parse_due("in 3 days", _BASE) == "2026-09-29";
    assert parse_due("in 2 weeks", _BASE) == "2026-10-10";
    assert parse_due("in 1 month", _BASE) == "2026-10-26";
    assert parse_due("in 5 months", _BASE) == "2027-02-26", "Feb 2027 has 28 days; day clamps from 26 -> 26 (no clamp needed here)";
}

test "parse_due: 'in N months' clamps the day to the target month's length" {
    base_jan31 = "2026-01-31T00:00:00";
    assert parse_due("in 1 month", base_jan31) == "2026-02-28", "Jan 31 + 1 month -> Feb 28 (2026 not leap)";
}

test "parse_due: weekday names are always 1-7 days strictly ahead, never the same day" {
    assert parse_due("Friday", _BASE) == "2026-10-02";
    assert parse_due("Sat", _BASE) == "2026-10-03", "base itself is a Saturday -> next Saturday is +7, not +0";
    assert parse_due("Monday", _BASE) == "2026-09-28";
    assert parse_due("thursday", _BASE) == "2026-10-01";
}

test "parse_due: 'in <Month>' -> the 1st of that month, on/after base else next year" {
    assert parse_due("in March", _BASE) == "2027-03-01", "March already passed this year -> next year";
    assert parse_due("in March", "2026-01-15T00:00:00") == "2026-03-01", "March is still ahead this year";
    assert parse_due("in October", _BASE) == "2026-10-01", "October is later this same year";
}

test "parse_due: '<Month> D' / '<Mon> D' / 'M/D' -> next occurrence" {
    assert parse_due("March 3", _BASE) == "2027-03-03";
    assert parse_due("Mar 3", _BASE) == "2027-03-03";
    assert parse_due("3/14", _BASE) == "2027-03-14";
    assert parse_due("October 15", _BASE) == "2026-10-15";
}

test "parse_due: 'YYYY-MM-DD' returned as-is once validated" {
    assert parse_due("2026-10-01", _BASE) == "2026-10-01";
    assert parse_due("2026-02-30", _BASE) == "", "not a real calendar date";
}

test "parse_due: unknown text, empty text, or an unparsable base -> ''" {
    assert parse_due("whenever works", _BASE) == "";
    assert parse_due("", _BASE) == "";
    assert parse_due("   ", _BASE) == "";
    assert parse_due("Friday", "not-a-date") == "";
    assert parse_due("Feb 30", _BASE) == "", "not a real calendar date, in either candidate year";
}

# ---------------------------------------------------------------- upcoming_dates_for

test "_gather_promises_due: window, done-exclusion, and dedupe" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Dates-test Me 1"))[0];
    p = (me +>:Knows(status="confirmed"):+> Person(name="Dates-test Promise Person", status="confirmed"))[0];

    note = (root ++> Note(text="Dates-test note", kind="debrief", captured_at=now.isoformat()))[0];

    pr_in_window = (root ++> Promise(text="send the deck", due="Friday", done=False))[0];
    note +>:AssertsPromise(span="send the deck"):+> pr_in_window;
    pr_in_window +>:PromiseTo:+> p;

    pr_done = (root ++> Promise(text="already sent", due="tomorrow", done=True))[0];
    note +>:AssertsPromise(span="already sent"):+> pr_done;
    pr_done +>:PromiseTo:+> p;

    pr_far = (root ++> Promise(text="way out", due="in 3 months", done=False))[0];
    note +>:AssertsPromise(span="way out"):+> pr_far;
    pr_far +>:PromiseTo:+> p;

    pr_unparsable = (root ++> Promise(text="no clear due", due="soonish", done=False))[0];
    note +>:AssertsPromise(span="no clear due"):+> pr_unparsable;

    out = _gather_promises_due([note], now, 14);
    ids = [jid(it["promise"] as Promise) for it in out];
    assert jid(pr_in_window) in ids;
    assert jid(pr_done) not in ids, "done promises are excluded";
    assert jid(pr_far) not in ids, "outside the 14-day window";
    assert jid(pr_unparsable) not in ids, "unparsable due is excluded";
    assert len(out) == 1;
    only = out[0];
    assert (only["to"] as Person) == p;
    assert only["due"] == "2026-10-02";
}

test "_gather_intents_expiring: window and 'about' (targeted vs self)" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Dates-test Me 2"))[0];
    p = (me +>:Knows(status="confirmed"):+> Person(name="Dates-test Intent Person", status="confirmed"))[0];

    note = (root ++> Note(text="Dates-test intent note", kind="debrief", captured_at=now.isoformat()))[0];

    it_soon = (root ++> Intent(kind="need", text="needs an intro", expires_at="2026-10-05T00:00:00"))[0];
    note +>:AssertsIntent(span="needs an intro"):+> it_soon;
    it_soon +>:IntentAbout:+> p;

    it_far = (root ++> Intent(kind="need", text="needs funding", expires_at="2027-01-01T00:00:00"))[0];
    note +>:AssertsIntent(span="needs funding"):+> it_far;
    it_far +>:IntentAbout:+> p;

    it_self = (root ++> Intent(kind="offer", text="can mentor", expires_at="2026-10-01T00:00:00"))[0];
    note +>:AssertsIntent(span="can mentor"):+> it_self;

    out = _gather_intents_expiring([note], now, 14);
    ids = [jid(it["intent"] as Intent) for it in out];
    assert jid(it_soon) in ids;
    assert jid(it_self) in ids;
    assert jid(it_far) not in ids, "outside the 14-day window";

    by_id: dict[str, dict[str, any]] = {};
    for it in out {
        by_id[jid(it["intent"] as Intent)] = it;
    }
    assert (by_id[jid(it_soon)]["about"] as Person) == p;
    assert by_id[jid(it_self)]["about"] is None, "no IntentAbout target -> self";
}

test "_gather_events: window via HasEvent" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Dates-test Me 3"))[0];

    ev_soon = (me +>:HasEvent:+> Event(name="Dates-test soon", date="2026-10-01"))[0];
    ev_far = (me +>:HasEvent:+> Event(name="Dates-test far", date="2027-01-01"))[0];
    ev_no_date = (me +>:HasEvent:+> Event(name="Dates-test no date"))[0];

    out = _gather_events(me, now, 14);
    ids = [jid(it["event"] as Event) for it in out];
    assert jid(ev_soon) in ids;
    assert jid(ev_far) not in ids;
    assert jid(ev_no_date) not in ids;
}

test "upcoming_dates_for: shape has all three keys" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Dates-test Me 4"))[0];
    result = upcoming_dates_for(me, [], now, 14);
    assert result["promises"] == [];
    assert result["intents_expiring"] == [];
    assert result["events"] == [];
}

# ---------------------------------------------------------------- NormalizeDates helpers

test "_normalize_promises: parseable raw text is rewritten to ISO; already-ISO is a no-op" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    note = (root ++> Note(text="Dates-test normalize note", kind="debrief", captured_at=now.isoformat()))[0];

    pr_raw = (root ++> Promise(text="send it", due="tomorrow", done=False))[0];
    note +>:AssertsPromise(span="send it"):+> pr_raw;

    pr_iso = (root ++> Promise(text="already normalized", due="2026-12-01", done=False))[0];
    note +>:AssertsPromise(span="already normalized"):+> pr_iso;

    pr_unparsable = (root ++> Promise(text="vague", due="whenever", done=False))[0];
    note +>:AssertsPromise(span="vague"):+> pr_unparsable;

    count = _normalize_promises([note], now);
    assert count == 1;
    assert pr_raw.due == "2026-09-27";
    assert pr_iso.due == "2026-12-01", "already-ISO due is left alone (no-op)";
    assert pr_unparsable.due == "whenever", "unparsable due is left as the raw text";
}

test "_normalize_intents: parseable expires_at is rewritten; empty is untouched" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    note = (root ++> Note(text="Dates-test normalize intent note", kind="debrief", captured_at=now.isoformat()))[0];

    it_raw = (root ++> Intent(kind="need", text="needs X", expires_at="in 1 week"))[0];
    note +>:AssertsIntent(span="needs X"):+> it_raw;

    it_empty = (root ++> Intent(kind="need", text="needs Y", expires_at=""))[0];
    note +>:AssertsIntent(span="needs Y"):+> it_empty;

    count = _normalize_intents([note], now);
    assert count == 1;
    assert it_raw.expires_at == "2026-10-03";
    assert it_empty.expires_at == "";
}
