"""Tests for events.sv.jac (SOH-217).

Annex of events.sv.jac; run with `jac test events.sv.jac`. Per
`jac guide jac-testing`, all tests here share one persisted root across
runs, so every Event/Person name below carries a random per-call suffix
(`_uid()`) — this guarantees a name is always genuinely new.

Per AGENTS.md's `update_person_for` Gotcha: a shared, persisted test root
can carry more than one `Me` across repeated `jac test` runs, so
`root spawn CreateEvent(...)` (which resolves `me` via
`[root --> [?:Me]][0]`) is NOT safe to assert mutation results through — it
might silently pick a `Me` from an earlier run. Every mutating test below
calls the plain `..._for(me, ...)` defs directly on a hand-built, freshly
created `Me` instead (same idiom `edits.test.jac` uses for
`update_person_for`). The one `root spawn` smoke test (an unresolvable
event_id) is safe because it doesn't depend on which `Me` gets picked — a
garbage id never matches regardless.
"""

import from events {
    AddToEvent,
    create_event_for, list_events_for, add_to_event_for,
    remove_from_event_for, event_people_for, update_event_for,
    find_event, find_known_person
}
import from schema { Me, Person, Event, Knows, HasEvent, MetAt }
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

def _fresh_me() -> Me {
    return (root ++> Me(name="events-me-" + _uid()))[0];
}

test "create_event_for: creates with name/date/location" {
    me = _fresh_me();
    suffix = _uid();
    e = create_event_for(me, "JacHacks " + suffix, date="2026-09-26", location="Ann Arbor");
    assert e.name == "JacHacks " + suffix;
    assert e.date == "2026-09-26";
    assert e.location == "Ann Arbor";
    assert e.created_at != "";
}

test "list_events_for: newest date first, no-date events last, count = MetAt people" {
    me = _fresh_me();
    suffix = _uid();

    oldest = create_event_for(me, "Old " + suffix, date="2020-01-01");
    newest = create_event_for(me, "New " + suffix, date="2026-09-26");
    no_date = create_event_for(me, "No Date " + suffix);

    p1 = (me +>:Knows(how_met="test"):+> Person(name="Attendee One " + suffix))[0];
    add_to_event_for(me, jid(p1), jid(newest));

    items = list_events_for(me);
    ids = [jid(it["event"] as Event) for it in items];
    # Restrict to just the three events THIS test created (the shared test
    # root may carry events from other tests/runs).
    mine = [i for i in ids if i in [jid(oldest), jid(newest), jid(no_date)]];
    assert mine == [jid(newest), jid(oldest), jid(no_date)], f"order was {mine}";

    newest_item = [it for it in items if jid(it["event"] as Event) == jid(newest)][0];
    assert (newest_item["count"] as int) == 1;

    old_item = [it for it in items if jid(it["event"] as Event) == jid(oldest)][0];
    assert (old_item["count"] as int) == 0;
}

test "add_to_event_for / remove_from_event_for: ok, idempotent, source_note kept, not_found on bad ids" {
    me = _fresh_me();
    suffix = _uid();
    person = (me +>:Knows(how_met="test"):+> Person(name="Event-goer " + suffix))[0];
    event = create_event_for(me, "Mixer " + suffix);

    r_add = add_to_event_for(me, jid(person), jid(event), source_note="note-123");
    assert r_add == {"ok": True};

    matched = [edge person ->:MetAt:-> event];
    assert len(matched) == 1;
    assert matched[0].source_note == "note-123";

    # Idempotent: adding again doesn't create a second MetAt edge (and doesn't overwrite source_note).
    r_add2 = add_to_event_for(me, jid(person), jid(event), source_note="different-note");
    assert r_add2 == {"ok": True};
    assert len([person ->:MetAt:->]) == 1;
    assert [edge person ->:MetAt:-> event][0].source_note == "note-123";

    r_bad_person = add_to_event_for(me, "nope-" + suffix, jid(event));
    assert r_bad_person == {"error": "not_found"};

    r_bad_event = add_to_event_for(me, jid(person), "nope-" + suffix);
    assert r_bad_event == {"error": "not_found"};

    r_remove = remove_from_event_for(me, jid(person), jid(event));
    assert r_remove == {"ok": True};
    assert len([person ->:MetAt:->]) == 0;

    r_remove2 = remove_from_event_for(me, jid(person), jid(event));
    assert r_remove2 == {"ok": True};
}

test "event_people_for: every person MetAt this event, not_found on bad id" {
    me = _fresh_me();
    suffix = _uid();
    event = create_event_for(me, "Roster Event " + suffix);
    other_event = create_event_for(me, "Other Event " + suffix);
    p1 = (me +>:Knows(how_met="test"):+> Person(name="Event Member One " + suffix))[0];
    p2 = (me +>:Knows(how_met="test"):+> Person(name="Event Member Two " + suffix))[0];
    add_to_event_for(me, jid(p1), jid(event));
    add_to_event_for(me, jid(p2), jid(other_event));

    result = event_people_for(me, jid(event));
    people = result as list[Person];
    ids = [jid(p) for p in people];
    assert ids == [jid(p1)];

    r_missing = event_people_for(me, "nope-" + suffix);
    assert r_missing == {"error": "not_found"};
}

test "update_event_for: only non-empty args overwrite, not_found on bad id" {
    me = _fresh_me();
    suffix = _uid();
    event = create_event_for(me, "Original " + suffix, date="2026-01-01", location="Detroit");

    updated = update_event_for(me, jid(event), name="Renamed " + suffix) as Event;
    assert updated.name == "Renamed " + suffix;
    assert updated.date == "2026-01-01";   # unchanged
    assert updated.location == "Detroit";  # unchanged

    updated2 = update_event_for(me, jid(event), date="2026-02-02", location="  ") as Event;
    assert updated2.date == "2026-02-02";
    assert updated2.location == "Detroit"; # blank arg leaves it alone

    r_missing = update_event_for(me, "nope-" + suffix, name="whatever");
    assert r_missing == {"error": "not_found"};
}

test "AddToEvent walker: unknown event_id -> not_found (Me-agnostic)" {
    r = root spawn AddToEvent(person_id="nope", event_id="definitely-nowhere-" + _uid());
    assert r.reports == [{"error": "not_found"}];
}
