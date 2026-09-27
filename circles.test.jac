"""Tests for circles.sv.jac (SOH-217).

Annex of circles.sv.jac; run with `jac test circles.sv.jac`. Per
`jac guide jac-testing`, all tests here share one persisted root across
runs, so every Circle/Person name below carries a random per-call suffix
(`_uid()`) — this guarantees a name is always genuinely new.

Per AGENTS.md's `update_person_for` Gotcha: a shared, persisted test root
can carry more than one `Me` across repeated `jac test` runs, so
`root spawn CreateCircle(...)` (which resolves `me` via
`[root --> [?:Me]][0]`) is NOT safe to assert mutation results through —
it might silently pick a `Me` from an earlier run. Every mutating test below
calls the plain `..._for(me, ...)` defs directly on a hand-built, freshly
created `Me` instead (same idiom `edits.test.jac` uses for
`update_person_for`). The one `root spawn` smoke test (an unresolvable
circle_id) is safe because it doesn't depend on which `Me` gets picked —
a garbage id never matches regardless.

The true cross-root isolation negative (B cannot AddToCircle into A's
circle) needs two real, separate roots, so it runs through a
`JacTestClient` harness — same approach `edits.test.jac`/`person.test.jac`
use: `JacTestClient.from_file` can't target a dotted `*.sv.jac` module
directly, so the harness copies `schema.sv.jac`, `circles.sv.jac`, and
`walkers.sv.jac` (for the `DevAddPerson` test-seeding helper) into a fresh
temp dir next to a dot-free `app.jac`, giving the client its own
`base_path`. No `jac clean` anywhere.
"""

import from circles {
    CreateCircle, RenameCircle,
    create_circle_for, rename_circle_for, delete_circle_for,
    add_to_circle_for, remove_from_circle_for, list_circles_for,
    circle_name_exists, find_circle, find_known_person
}
import from schema { Me, Person, Circle, Knows, HasCircle, InCircle }
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

def _fresh_me() -> Me {
    return (root ++> Me(name="circles-me-" + _uid()))[0];
}

# ---------------------------------------------------------------- CreateCircle + dedupe

test "create_circle_for: creates, then dedupes case-insensitively (stripped)" {
    me = _fresh_me();
    name = "Michigan Robotics " + _uid();

    c1 = create_circle_for(me, name);
    circle1 = c1 as Circle;
    assert circle1.name == name;

    c2 = create_circle_for(me, name.upper());
    assert c2 == {"error": "exists"};

    c3 = create_circle_for(me, "  " + name.lower() + "  ");
    assert c3 == {"error": "exists"};

    # A different Me is a different namespace: same name, no collision.
    other_me = _fresh_me();
    c4 = create_circle_for(other_me, name);
    circle4 = c4 as Circle;
    assert circle4.name == name;
    assert jid(circle4) != jid(circle1);
}

# ---------------------------------------------------------------- RenameCircle

test "rename_circle_for: renames, not_found on unknown id, exists on collision, self-rename is fine" {
    me = _fresh_me();
    suffix = _uid();
    a_name = "Family " + suffix;
    b_name = "Work " + suffix;

    a = create_circle_for(me, a_name) as Circle;
    b = create_circle_for(me, b_name) as Circle;

    new_name = "Close Friends " + suffix;
    renamed = rename_circle_for(me, jid(a), new_name) as Circle;
    assert renamed.name == new_name;
    assert jid(renamed) == jid(a);

    # Renaming A to its OWN current name again is fine (excludes itself from the collision check).
    r_self = rename_circle_for(me, jid(a), new_name) as Circle;
    assert r_self.name == new_name;

    # Renaming A to B's name collides.
    r_collide = rename_circle_for(me, jid(a), b_name);
    assert r_collide == {"error": "exists"};

    r_missing = rename_circle_for(me, "not-a-real-id-" + suffix, "whatever");
    assert r_missing == {"error": "not_found"};
}

test "RenameCircle walker: unknown circle_id -> not_found (Me-agnostic)" {
    r = root spawn RenameCircle(circle_id="definitely-nowhere-" + _uid(), name="whatever");
    assert r.reports == [{"error": "not_found"}];
}

# ---------------------------------------------------------------- DeleteCircle

test "delete_circle_for: removes the circle and its InCircle edges, leaves the Person" {
    me = _fresh_me();
    suffix = _uid();
    person = (me +>:Knows(how_met="test"):+> Person(name="Delete-target " + suffix))[0];
    circle = create_circle_for(me, "Doomed " + suffix) as Circle;
    person +>:InCircle:+> circle;

    assert len([person ->:InCircle:->]) == 1;

    r1 = delete_circle_for(me, jid(circle));
    assert r1 == {"ok": True};

    # Deleting again -> not_found (already gone).
    r2 = delete_circle_for(me, jid(circle));
    assert r2 == {"error": "not_found"};

    # The Person node survives; it just has no InCircle edges left.
    assert len([person ->:InCircle:->]) == 0;
}

# ---------------------------------------------------------------- AddToCircle / RemoveFromCircle

test "add_to_circle_for / remove_from_circle_for: ok, idempotent, not_found on bad ids" {
    me = _fresh_me();
    suffix = _uid();
    person = (me +>:Knows(how_met="test"):+> Person(name="Circle-member " + suffix))[0];
    circle = create_circle_for(me, "Roster " + suffix) as Circle;

    r_add = add_to_circle_for(me, jid(person), jid(circle));
    assert r_add == {"ok": True};

    # Idempotent: adding again doesn't create a second InCircle edge.
    r_add2 = add_to_circle_for(me, jid(person), jid(circle));
    assert r_add2 == {"ok": True};
    assert len([person ->:InCircle:->]) == 1;

    r_bad_person = add_to_circle_for(me, "nope-" + suffix, jid(circle));
    assert r_bad_person == {"error": "not_found"};

    r_bad_circle = add_to_circle_for(me, jid(person), "nope-" + suffix);
    assert r_bad_circle == {"error": "not_found"};

    r_remove = remove_from_circle_for(me, jid(person), jid(circle));
    assert r_remove == {"ok": True};
    assert len([person ->:InCircle:->]) == 0;

    # Removing again is still "ok" (person/circle both resolve, edge just isn't there).
    r_remove2 = remove_from_circle_for(me, jid(person), jid(circle));
    assert r_remove2 == {"ok": True};
}

# ---------------------------------------------------------------- ListCircles

test "list_circles_for: {circle, count} for every circle this Me has" {
    me = _fresh_me();
    suffix = _uid();
    circle = create_circle_for(me, "Counted " + suffix) as Circle;
    p1 = (me +>:Knows(how_met="test"):+> Person(name="Member One " + suffix))[0];
    p2 = (me +>:Knows(how_met="test"):+> Person(name="Member Two " + suffix))[0];
    add_to_circle_for(me, jid(p1), jid(circle));
    add_to_circle_for(me, jid(p2), jid(circle));

    items = list_circles_for(me);
    matches = [it for it in items if jid(it["circle"] as Circle) == jid(circle)];
    assert len(matches) == 1;
    assert (matches[0]["count"] as int) == 2;
}

# ---------------------------------------------------------------- isolation (two real roots)

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

glob CIRCLES_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _circles_harness(tmp_dir: str) -> str {
    for name in ["schema.sv.jac", "circles.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(CIRCLES_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from circles { CreateCircle, AddToCircle }\n"
        "import from walkers { DevAddPerson }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"circles-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _circles_register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _circles_call(client: JacTestClient, token: str, wname: str, body: dict[str, any]) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "isolation: B cannot AddToCircle into A's circle" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_circles_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _circles_register(cl, "circles_a@example.com");
        b = _circles_register(cl, "circles_b@example.com");

        a_circle = _circles_call(cl, a, "CreateCircle", {"name": "A's Circle"});
        circle_id = str((a_circle[0] as dict[str, any])["_jac_id"]);
        print(f"[circles isolation] A's circle_id={circle_id}");

        b_person = _circles_call(cl, b, "DevAddPerson", {"name": "B's Own Person"});
        person_id = str((b_person[0] as dict[str, any])["_jac_id"]);

        a_add = _circles_call(cl, a, "AddToCircle", {"person_id": person_id, "circle_id": circle_id});
        # A's own circle, but B's person: not one of A's own [me ->:Knows:->] people.
        assert a_add == [{"error": "not_found"}], f"A must never add B's person: {a_add}";

        b_add = _circles_call(cl, b, "AddToCircle", {"person_id": person_id, "circle_id": circle_id});
        print(f"[circles isolation] B's AddToCircle into A's circle -> {b_add}");
        assert b_add == [{"error": "not_found"}], f"B must never reach A's circle: {b_add}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
