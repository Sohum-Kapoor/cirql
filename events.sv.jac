"""Events — where-we-met, per user (SOH-217).

OWNER: Person A. See contracts/walkers.md for the exact report shapes and
AGENTS.md for the working rules this file must obey:
  - `Event` and `HasEvent` (Me -> Event) / `MetAt` (Person -> Event,
    `source_note`) already exist in schema.sv.jac (SOH-215), all optional,
    all own-root — no schema change here.
  - Every walker is `:priv` (own-root only, JWT required). No `by llm`.
  - `event_id`/`person_id` are resolved directly among the caller's own
    `[me ->:HasEvent:->]` / `[me ->:Knows:->]` — isolated by construction,
    no `jobj` lookup of a foreign id, no grant ever given.
  - `MetAt.source_note` carries the provenance (the Note that placed a
    person at an event) when known; empty when the pairing was made by
    hand (`AddToEvent` with no `source_note`), same as `Knows.how_met`.
  - The lookup+mutate logic for every walker below lives in a plain
    `..._for(me, ...)` def so `events.test.jac` can call it directly on a
    hand-built `me`/`Event`/`Person` — same idiom `edits.sv.jac`'s
    `update_person_for` uses (AGENTS.md Gotcha: a shared, persisted test
    root can carry more than one `Me` across `jac test` runs, so
    `[root --> [?:Me]][0]` is an unreliable pick inside a test). Each
    walker just resolves `me` and delegates.
"""

import from schema { Me, Person, Event, Knows, HasEvent, MetAt }
import from datetime { datetime }

# ---------------------------------------------------------------- Me resolution

def _get_or_create_me() -> Me {
    existing = [root --> [?:Me]];
    if existing {
        return existing[0];
    }
    return (root ++> Me(name="me"))[0];
}

def _find_me() -> Me | None {
    existing = [root --> [?:Me]];
    if existing {
        return existing[0];
    }
    return None;
}

# ---------------------------------------------------------------- lookups

def find_event(me: Me, event_id: str) -> Event | None {
    for e in [me ->:HasEvent:->] {
        if jid(e) == event_id {
            return e;
        }
    }
    return None;
}

def find_known_person(me: Me, person_id: str) -> Person | None {
    for p in [me ->:Knows:->] {
        if jid(p) == person_id {
            return p;
        }
    }
    return None;
}

def _not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

"""Newest date first; an event with no `date` sorts last (empty string is
the lexicographically smallest ISO date, so it ends up last once the list
is reversed)."""
def _event_date_key(item: dict[str, any]) -> str {
    e = item["event"] as Event;
    return e.date;
}

# ---------------------------------------------------------------- deterministic ops (testable directly)

def create_event_for(me: Me, name: str, date: str = "", location: str = "") -> Event {
    return (me +>:HasEvent:+> Event(
        name=name, date=date, location=location,
        created_at=datetime.now().isoformat()
    ))[0];
}

def list_events_for(me: Me) -> list[dict[str, any]] {
    items: list[dict[str, any]] = [];
    for e in [me ->:HasEvent:->] {
        count = len([e <-:MetAt:<-]);
        items.append({"event": e, "count": count});
    }
    return sorted(items, key=_event_date_key, reverse=True);
}

def add_to_event_for(me: Me, person_id: str, event_id: str, source_note: str = "") -> object {
    person = find_known_person(me, person_id);
    event = find_event(me, event_id);
    if person is None or event is None {
        return _not_found();
    }
    p = person as Person;
    ev = event as Event;
    already: list[Event] = [p ->:MetAt:->];
    attached = False;
    for existing_e in already {
        if jid(existing_e) == jid(ev) {
            attached = True;
        }
    }
    if not attached {
        p +>:MetAt(source_note=source_note):+> ev;
    }
    return {"ok": True};
}

def remove_from_event_for(me: Me, person_id: str, event_id: str) -> object {
    person = find_known_person(me, person_id);
    event = find_event(me, event_id);
    if person is None or event is None {
        return _not_found();
    }
    p = person as Person;
    ev = event as Event;
    for e in [edge p ->:MetAt:-> ev] {
        del e;
    }
    return {"ok": True};
}

def event_people_for(me: Me, event_id: str) -> object {
    event = find_event(me, event_id);
    if event is None {
        return _not_found();
    }
    return [p for p in [(event as Event) <-:MetAt:<-]];
}

"""Only NON-EMPTY (stripped) args overwrite a field; an omitted/blank arg
leaves the existing value alone (same idiom `edits.sv.jac`'s
`update_person_for` uses)."""
def update_event_for(me: Me, event_id: str, name: str = "", date: str = "", location: str = "") -> object {
    target = find_event(me, event_id);
    if target is None {
        return _not_found();
    }
    e = target as Event;
    if len(name.strip()) > 0 {
        e.name = name;
    }
    if len(date.strip()) > 0 {
        e.date = date;
    }
    if len(location.strip()) > 0 {
        e.location = location;
    }
    return e;
}

# ---------------------------------------------------------------- walkers

walker:priv CreateEvent {
    """Get-or-create Me; create an Event under it via HasEvent. Reports
    `[Event]`."""
    has name: str;
    has date: str = "";
    has location: str = "";
    has reports: list[Event] = [];

    can run with Root entry {
        me = _get_or_create_me();
        report create_event_for(me, self.name, date=self.date, location=self.location);
    }
}

walker:priv ListEvents {
    """Reports `[{ event: Event, count: int }]`, newest `date` first;
    `count` = how many people `MetAt` this event. Empty list when there's
    no `Me` yet."""
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            disengage;
        }
        for item in list_events_for(me as Me) {
            report item;
        }
    }
}

walker:priv AddToEvent {
    """Attaches `MetAt` (Person -> Event) with `source_note` if it doesn't
    already exist. Reports `[{ ok: true }]`, or `[{ error: "not_found" }]`
    when `person_id`/`event_id` don't resolve to the caller's own graph."""
    has person_id: str;
    has event_id: str;
    has source_note: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report add_to_event_for(me as Me, self.person_id, self.event_id, source_note=self.source_note);
    }
}

walker:priv RemoveFromEvent {
    """Deletes the `MetAt` edge (Person -> Event), if any. Reports
    `[{ ok: true }]`, or `[{ error: "not_found" }]` when `person_id`/
    `event_id` don't resolve to the caller's own graph."""
    has person_id: str;
    has event_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report remove_from_event_for(me as Me, self.person_id, self.event_id);
    }
}

walker:priv EventPeople {
    """Reports `[Person]`, every person `MetAt` this event, or
    `[{ error: "not_found" }]` when `event_id` isn't one of the caller's
    own events."""
    has event_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        result = event_people_for(me as Me, self.event_id);
        if isinstance(result, dict) {
            report result as dict[str, any];
            disengage;
        }
        for p in result as list[Person] {
            report p;
        }
    }
}

walker:priv UpdateEvent {
    """Only NON-EMPTY (stripped) args overwrite a field; an omitted/blank
    arg leaves the existing value alone (same idiom `edits.sv.jac`'s
    `UpdatePerson` uses). Reports `[Event]`, or `[{ error: "not_found" }]`."""
    has event_id: str;
    has name: str = "";
    has date: str = "";
    has location: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report update_event_for(me as Me, self.event_id, name=self.name, date=self.date, location=self.location);
    }
}
