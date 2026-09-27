"""Mocks for Circles + Events (SOH-222 A4) — server on a parallel branch.

Exact contract shapes (contracts/walkers.md, appended this pass): `CreateCircle`,
`RenameCircle`, `DeleteCircle`, `AddToCircle`, `RemoveFromCircle`, `ListCircles`,
`CreateEvent`, `ListEvents`, `AddToEvent`, `RemoveFromEvent`, `EventPeople`,
`UpdateEvent`, and the scoped `ListPeople(circle_id, event_id, include_archived)`.
Each returns the walker's report LIST. Same pseudonymous roster as the GoalRank /
PersonSheet mocks (mock-person-maya, -dev, -lena, -sam) so tapping a member here
opens the same PersonSheet under `?mock=1`. State lives in module globs so
creates/renames/deletes/membership survive across calls for the session.
"""

glob MOCK_ROSTER: list[dict] = [
         {"_jac_id": "mock-person-maya", "name": "Maya Chen", "org": "Stripe Climate", "title": "Carbon removal lead", "status": "confirmed", "archived": False},
         {"_jac_id": "mock-person-dev", "name": "Dev Okafor", "org": "Great Lakes Angels", "title": "Associate", "status": "confirmed", "archived": False},
         {"_jac_id": "mock-person-lena", "name": "Lena Park", "org": "Campus Energy Club", "title": "President", "status": "confirmed", "archived": False},
         {"_jac_id": "mock-person-sam", "name": "Sam Ruiz", "org": "Ruiz Castings", "title": "Plant manager", "status": "confirmed", "archived": False}
     ];

glob MOCK_CIRCLES: dict[str, any] = {
         "circles": [
             {"_jac_id": "mock-circle-lab", "name": "Robotics lab", "created_at": "2026-09-01T10:00:00Z"},
             {"_jac_id": "mock-circle-family", "name": "Family", "created_at": "2026-09-02T10:00:00Z"}
         ],
         "members": {"mock-circle-lab": ["mock-person-maya", "mock-person-dev"], "mock-circle-family": []},
         "next": 1
     };

glob MOCK_EVENTS: dict[str, any] = {
         "events": [
             {"_jac_id": "mock-event-jachacks", "name": "JacHacks 2026", "date": "2026-09-26", "location": "Ann Arbor"},
             {"_jac_id": "mock-event-pitch", "name": "Spring pitch night", "date": "2026-03-14", "location": ""}
         ],
         "members": {"mock-event-jachacks": ["mock-person-maya", "mock-person-lena"], "mock-event-pitch": ["mock-person-dev"]},
         "next": 1
     };

def _by_id(ids: list[str]) -> list[dict] {
    out: list[dict] = [];
    for p in MOCK_ROSTER {
        if (p["_jac_id"] as str) in ids {
            out.append(p);
        }
    }
    return out;
}

# ---------------------------------------------------------------- Circles

def:pub mock_create_circle(name: str) -> list[dict] {
    clean: str = name.strip();
    for c in (MOCK_CIRCLES["circles"] as list[dict]) {
        if (c["name"] as str).lower() == clean.lower() {
            return [{"error": "exists"}];
        }
    }
    n: int = MOCK_CIRCLES["next"] as int;
    MOCK_CIRCLES["next"] = n + 1;
    cid: str = "mock-circle-new-" + str(n);
    circle: dict = {"_jac_id": cid, "name": clean, "created_at": "2026-09-26T20:00:00Z"};
    MOCK_CIRCLES["circles"] = (MOCK_CIRCLES["circles"] as list[dict]) + [circle];
    members: dict = {**(MOCK_CIRCLES["members"] as dict)};
    members[cid] = [];
    MOCK_CIRCLES["members"] = members;
    return [circle];
}

def:pub mock_rename_circle(circle_id: str, name: str) -> list[dict] {
    clean: str = name.strip();
    circles: list[dict] = MOCK_CIRCLES["circles"] as list[dict];
    updated: list[dict] = [];
    found: dict = {};
    found_id: str = "";
    for c in circles {
        if c["_jac_id"] == circle_id {
            nc: dict = {**c};
            nc["name"] = clean;
            found = nc;
            found_id = circle_id;
            updated.append(nc);
        } else {
            updated.append(c);
        }
    }
    if not found_id {
        return [{"error": "not_found"}];
    }
    MOCK_CIRCLES["circles"] = updated;
    return [found];
}

def:pub mock_delete_circle(circle_id: str) -> list[dict] {
    circles: list[dict] = MOCK_CIRCLES["circles"] as list[dict];
    kept: list[dict] = [c for c in circles if c["_jac_id"] != circle_id];
    if len(kept) == len(circles) {
        return [{"error": "not_found"}];
    }
    MOCK_CIRCLES["circles"] = kept;
    return [{"ok": True}];
}

def:pub mock_add_to_circle(person_id: str, circle_id: str) -> list[dict] {
    found: bool = False;
    for c in (MOCK_CIRCLES["circles"] as list[dict]) {
        if c["_jac_id"] == circle_id {
            found = True;
        }
    }
    if not found {
        return [{"error": "not_found"}];
    }
    members: dict = {**(MOCK_CIRCLES["members"] as dict)};
    raw: any = members[circle_id];
    current: list[str] = (raw or []) as list[str];
    if person_id not in current {
        members[circle_id] = current + [person_id];
        MOCK_CIRCLES["members"] = members;
    }
    return [{"ok": True}];
}

def:pub mock_remove_from_circle(person_id: str, circle_id: str) -> list[dict] {
    members: dict = {**(MOCK_CIRCLES["members"] as dict)};
    raw: any = members[circle_id];
    current: list[str] = (raw or []) as list[str];
    members[circle_id] = [p for p in current if p != person_id];
    MOCK_CIRCLES["members"] = members;
    return [{"ok": True}];
}

def:pub mock_list_circles() -> list[dict] {
    rows: list[dict] = [];
    members: dict = MOCK_CIRCLES["members"] as dict;
    for c in (MOCK_CIRCLES["circles"] as list[dict]) {
        cid: str = c["_jac_id"] as str;
        raw: any = members[cid];
        count: int = len((raw or []) as list[str]);
        rows.append({"circle": c, "count": count});
    }
    return rows;
}

# ---------------------------------------------------------------- Events

def:pub mock_create_event(name: str, date: str = "", location: str = "") -> list[dict] {
    n: int = MOCK_EVENTS["next"] as int;
    MOCK_EVENTS["next"] = n + 1;
    eid: str = "mock-event-new-" + str(n);
    event: dict = {"_jac_id": eid, "name": name.strip(), "date": date, "location": location};
    MOCK_EVENTS["events"] = (MOCK_EVENTS["events"] as list[dict]) + [event];
    members: dict = {**(MOCK_EVENTS["members"] as dict)};
    members[eid] = [];
    MOCK_EVENTS["members"] = members;
    return [event];
}

def:pub mock_update_event(event_id: str, name: str, date: str, location: str) -> list[dict] {
    events: list[dict] = MOCK_EVENTS["events"] as list[dict];
    updated: list[dict] = [];
    found: dict = {};
    found_id: str = "";
    for e in events {
        if e["_jac_id"] == event_id {
            ne: dict = {**e};
            ne["name"] = name.strip();
            ne["date"] = date;
            ne["location"] = location;
            found = ne;
            found_id = event_id;
            updated.append(ne);
        } else {
            updated.append(e);
        }
    }
    if not found_id {
        return [{"error": "not_found"}];
    }
    MOCK_EVENTS["events"] = updated;
    return [found];
}

def:pub mock_list_events() -> list[dict] {
    rows: list[dict] = [];
    members: dict = MOCK_EVENTS["members"] as dict;
    for e in (MOCK_EVENTS["events"] as list[dict]) {
        eid: str = e["_jac_id"] as str;
        raw: any = members[eid];
        count: int = len((raw or []) as list[str]);
        rows.append({"event": e, "count": count});
    }
    return rows;
}

def:pub mock_add_to_event(person_id: str, event_id: str) -> list[dict] {
    found: bool = False;
    for e in (MOCK_EVENTS["events"] as list[dict]) {
        if e["_jac_id"] == event_id {
            found = True;
        }
    }
    if not found {
        return [{"error": "not_found"}];
    }
    members: dict = {**(MOCK_EVENTS["members"] as dict)};
    raw: any = members[event_id];
    current: list[str] = (raw or []) as list[str];
    if person_id not in current {
        members[event_id] = current + [person_id];
        MOCK_EVENTS["members"] = members;
    }
    return [{"ok": True}];
}

def:pub mock_remove_from_event(person_id: str, event_id: str) -> list[dict] {
    members: dict = {**(MOCK_EVENTS["members"] as dict)};
    raw: any = members[event_id];
    current: list[str] = (raw or []) as list[str];
    members[event_id] = [p for p in current if p != person_id];
    MOCK_EVENTS["members"] = members;
    return [{"ok": True}];
}

def:pub mock_event_people(event_id: str) -> list[dict] {
    members: dict = MOCK_EVENTS["members"] as dict;
    raw: any = members[event_id];
    ids: list[str] = (raw or []) as list[str];
    return _by_id(ids);
}

# ---------------------------------------------------------------- shared scoped ListPeople

def:pub mock_list_people_scoped(circle_id: str = "", event_id: str = "", include_archived: bool = False) -> list[dict] {
    ids: list[str] = [];
    scoped: bool = False;
    if circle_id {
        scoped = True;
        circle_members: dict = MOCK_CIRCLES["members"] as dict;
        raw: any = circle_members[circle_id];
        ids = (raw or []) as list[str];
    } elif event_id {
        scoped = True;
        event_members: dict = MOCK_EVENTS["members"] as dict;
        raw: any = event_members[event_id];
        ids = (raw or []) as list[str];
    }
    rows: list[dict] = [];
    for p in MOCK_ROSTER {
        if not include_archived and bool(p["archived"]) {
            continue;
        }
        if scoped and (p["_jac_id"] as str) not in ids {
            continue;
        }
        rows.append(p);
    }
    return rows;
}
