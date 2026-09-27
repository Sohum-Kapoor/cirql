"""Circles — named groups a user puts people into (SOH-217).

OWNER: Person A. See contracts/walkers.md for the exact report shapes and
AGENTS.md for the working rules this file must obey:
  - `Circle` and `HasCircle` (Me -> Circle) / `InCircle` (Person -> Circle)
    already exist in schema.sv.jac (SOH-215), all optional, all own-root —
    no schema change here.
  - A Circle is never a score; it is just a name the user gave a group.
  - Every walker is `:priv` (own-root only, JWT required). No `by llm`.
  - Names are deduped case-insensitively PER USER: creating or renaming a
    circle to a name that (case-insensitively) matches another circle this
    same user already has reports `{ error: "exists" }` instead of writing.
  - `circle_id`/`person_id` are resolved directly among the caller's own
    `[me ->:HasCircle:->]` / `[me ->:Knows:->]` — same "belongs to the
    caller" idiom `person.sv.jac`'s `PersonDetail` uses for `person_id`.
    Nothing here ever calls `jobj` on an arbitrary id, so a foreign
    circle_id/person_id simply never turns up in that traversal — isolated
    by construction, no grant ever given.
  - The lookup+mutate logic for every walker below lives in a plain
    `..._for(me, ...)` def so `circles.test.jac` can call it directly on a
    hand-built `me`/`Circle`/`Person` — same idiom `edits.sv.jac`'s
    `update_person_for` uses, needed because a shared, persisted test root
    can carry more than one `Me` across repeated `jac test` runs, making
    `[root --> [?:Me]][0]` an unreliable pick inside a test (AGENTS.md
    Gotchas). Each walker just resolves `me` and delegates.
"""

import from schema { Me, Person, Circle, Knows, HasCircle, InCircle }
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

"""True when `name` (case-insensitively, stripped) matches another circle
this user already has. `exclude_id` lets RenameCircle compare against every
OTHER circle without tripping on itself."""
def circle_name_exists(me: Me, name: str, exclude_id: str = "") -> bool {
    key = " ".join(name.strip().lower().split());
    for c in [me ->:HasCircle:->] {
        if len(exclude_id) > 0 and jid(c) == exclude_id {
            continue;
        }
        if " ".join(c.name.strip().lower().split()) == key {
            return True;
        }
    }
    return False;
}

def find_circle(me: Me, circle_id: str) -> Circle | None {
    for c in [me ->:HasCircle:->] {
        if jid(c) == circle_id {
            return c;
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

def _exists() -> dict[str, str] {
    return {"error": "exists"};
}

# ---------------------------------------------------------------- deterministic ops (testable directly)

"""Get-or-create-style create: reports the new Circle, or `{error:"exists"}`
when the name (case-insensitively) matches one this user already has."""
def create_circle_for(me: Me, name: str) -> object {
    if circle_name_exists(me, name) {
        return _exists();
    }
    return (me +>:HasCircle:+> Circle(name=name, created_at=datetime.now().isoformat()))[0];
}

def rename_circle_for(me: Me, circle_id: str, name: str) -> object {
    target = find_circle(me, circle_id);
    if target is None {
        return _not_found();
    }
    if circle_name_exists(me, name, exclude_id=circle_id) {
        return _exists();
    }
    c = target as Circle;
    c.name = name;
    return c;
}

"""Deletes the `Circle` node. Node-delete cascade removes its `HasCircle`
edge from Me and every `InCircle` edge from a Person; the Person nodes
themselves are untouched."""
def delete_circle_for(me: Me, circle_id: str) -> object {
    target = find_circle(me, circle_id);
    if target is None {
        return _not_found();
    }
    c = target as Circle;
    del c;
    return {"ok": True};
}

def add_to_circle_for(me: Me, person_id: str, circle_id: str) -> object {
    person = find_known_person(me, person_id);
    circle = find_circle(me, circle_id);
    if person is None or circle is None {
        return _not_found();
    }
    p = person as Person;
    c = circle as Circle;
    already: list[Circle] = [p ->:InCircle:->];
    attached = False;
    for existing_c in already {
        if jid(existing_c) == jid(c) {
            attached = True;
        }
    }
    if not attached {
        p +>:InCircle:+> c;
    }
    return {"ok": True};
}

def remove_from_circle_for(me: Me, person_id: str, circle_id: str) -> object {
    person = find_known_person(me, person_id);
    circle = find_circle(me, circle_id);
    if person is None or circle is None {
        return _not_found();
    }
    p = person as Person;
    c = circle as Circle;
    for e in [edge p ->:InCircle:-> c] {
        del e;
    }
    return {"ok": True};
}

def list_circles_for(me: Me) -> list[dict[str, any]] {
    items: list[dict[str, any]] = [];
    for c in [me ->:HasCircle:->] {
        count = len([c <-:InCircle:<-]);
        items.append({"circle": c, "count": count});
    }
    return items;
}

# ---------------------------------------------------------------- walkers

walker:priv CreateCircle {
    """Get-or-create Me; create a named Circle under it via HasCircle.
    Reports `[Circle]`, or `[{ error: "exists" }]` when the name matches
    (case-insensitively) a circle this user already has."""
    has name: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _get_or_create_me();
        report create_circle_for(me, self.name);
    }
}

walker:priv RenameCircle {
    """Reports `[Circle]` (the renamed node), `[{ error: "not_found" }]`
    when `circle_id` isn't one of the caller's own circles, or
    `[{ error: "exists" }]` when the new name collides with another circle
    this user already has."""
    has circle_id: str;
    has name: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report rename_circle_for(me as Me, self.circle_id, self.name);
    }
}

walker:priv DeleteCircle {
    """Removes the circle and its `InCircle` edges only (node-delete
    cascade; Person nodes untouched). Reports `[{ ok: true }]`, or
    `[{ error: "not_found" }]`."""
    has circle_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report delete_circle_for(me as Me, self.circle_id);
    }
}

walker:priv AddToCircle {
    """Attaches `InCircle` (Person -> Circle) if it doesn't already exist.
    Reports `[{ ok: true }]`, or `[{ error: "not_found" }]` when
    `person_id`/`circle_id` don't resolve to the caller's own graph."""
    has person_id: str;
    has circle_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report add_to_circle_for(me as Me, self.person_id, self.circle_id);
    }
}

walker:priv RemoveFromCircle {
    """Deletes the `InCircle` edge (Person -> Circle), if any. Reports
    `[{ ok: true }]`, or `[{ error: "not_found" }]` when `person_id`/
    `circle_id` don't resolve to the caller's own graph."""
    has person_id: str;
    has circle_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            report _not_found();
            disengage;
        }
        report remove_from_circle_for(me as Me, self.person_id, self.circle_id);
    }
}

walker:priv ListCircles {
    """Reports `[{ circle: Circle, count: int }]` for every circle the
    caller has, `count` = how many people are `InCircle` it. Empty list
    when there's no `Me` yet."""
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        me = _find_me();
        if me is None {
            disengage;
        }
        for item in list_circles_for(me as Me) {
            report item;
        }
    }
}
