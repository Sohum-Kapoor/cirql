"""Tests for edits.sv.jac (SOH-166, B's "Needs A": UpdatePerson, UpdatePromise).

Annex to edits.sv.jac — run with `jac test edits.sv.jac`. Deterministic only:
no LLM, no network.

`jac test edits.sv.jac` also runs the test files of every module edits.sv.jac
imports (`reads.sv.jac`) against the same shared, persisted root
(`jac-testing`) — same reasoning `person.test.jac`/`reads.test.jac` already
document: every test here uses text/names unique to itself and resolves the
target it just created by id, never by picking "the" `Me`/`Person`/`Promise`
off the shared root.

The true cross-root isolation negative (a person under account A is
`not_found` from account B's `UpdatePerson`) needs two real, separate roots,
so it runs through a `JacTestClient` harness — same approach `gate.test.jac`
and `person.test.jac` use: JacTestClient cannot target a dotted `*.sv.jac`
module directly, so the harness copies every module in edits.sv.jac's import
chain (`schema`, `reads`, `edits`, plus `walkers` for the `DevAddPerson`
test-seeding helper) into a fresh temp dir next to a dot-free `app.jac`, and
gives the client its own `base_path`. No `jac clean` anywhere.
"""

import from edits { UpdatePerson, UpdatePromise, DevAddPromise, update_person_for }
import from schema { Me, Person, Promise, Knows }
import from datetime { datetime, timedelta }

# ---------------------------------------------------------------- UpdatePerson
#
# `update_person_for` is exercised directly on a hand-built `me`/`p` pair
# (never through `root spawn UpdatePerson(...)`) for the same reason
# `person.sv.jac`'s tests call `person_detail_for(me, p)` directly: the
# walker's own `[root --> [?:Me]][0]` pick is ambiguous once more than one
# test (in this file, or an earlier `jac test` run) has created a `Me`
# under the shared, persisted `jac-testing` root. The one walker test below
# (an unresolvable `person_id`) doesn't depend on which `Me` gets picked,
# so it's safe to go through `root spawn`.

test "update_person_for: name+org overwrite, title left unchanged" {
    me = (root ++> Me(name="Edits-test Me 1"))[0];
    p = (me +>:Knows(how_met="conference", status="confirmed"):+> Person(
        name="Edits-test Old Name", org="Old Co", title="Old Title", status="confirmed"
    ))[0];

    result = update_person_for(me, jid(p), "Edits-test New Name", "New Co", "", "");
    out = result as Person;

    assert out.name == "Edits-test New Name";
    assert out.org == "New Co";
    assert out.title == "Old Title", f"title must be left unchanged, got {out.title}";
    assert out.status == "confirmed", "UpdatePerson must never touch status";

    # Re-read straight off the graph, not just the returned reference.
    assert p.name == "Edits-test New Name";
    assert p.org == "New Co";
    assert p.title == "Old Title";
}

test "update_person_for: how_met lands on the caller's own Knows edge" {
    me = (root ++> Me(name="Edits-test Me 2"))[0];
    p = (me +>:Knows(how_met="unknown"):+> Person(name="Edits-test How Met P", status="confirmed"))[0];

    before_edges = [edge me ->:Knows:-> p];
    assert before_edges[0].how_met == "unknown";

    result = update_person_for(me, jid(p), "", "", "", "met at JacHacks");
    out = result as Person;
    assert out.name == "Edits-test How Met P", "person fields with empty args must stay unchanged";

    after_edges = [edge me ->:Knows:-> p];
    assert len(after_edges) == 1, "UpdatePerson must not create a second Knows edge";
    assert after_edges[0].how_met == "met at JacHacks";
}

test "update_person_for: empty args change nothing" {
    me = (root ++> Me(name="Edits-test Me 3"))[0];
    p = (me +>:Knows(how_met="referral", status="confirmed"):+> Person(
        name="Edits-test Untouched", org="Stable Co", title="Stable Title", status="confirmed"
    ))[0];

    result = update_person_for(me, jid(p), "", "", "", "");
    out = result as Person;
    assert out.name == "Edits-test Untouched";
    assert out.org == "Stable Co";
    assert out.title == "Stable Title";

    edges = [edge me ->:Knows:-> p];
    assert edges[0].how_met == "referral";
}

test "update_person_for: whitespace-only args are treated as empty" {
    me = (root ++> Me(name="Edits-test Me 3b"))[0];
    p = (me +>:Knows(how_met="referral", status="confirmed"):+> Person(
        name="Edits-test Whitespace P", org="Keep Co", status="confirmed"
    ))[0];

    result = update_person_for(me, jid(p), "   ", "\t", "", "");
    out = result as Person;
    assert out.name == "Edits-test Whitespace P";
    assert out.org == "Keep Co";
}

test "update_person_for: contact fields (email/phone/location) overwrite non-empty only" {
    me = (root ++> Me(name="Edits-test Me 5"))[0];
    p = (me +>:Knows(how_met="conference", status="confirmed"):+> Person(
        name="Edits-test Contact P", email="", phone="", location="", status="confirmed"
    ))[0];

    result = update_person_for(me, jid(p), "", "", "", "", "old@example.com", "", [], "");
    out = result as Person;
    assert out.email == "old@example.com";
    assert out.phone == "";
    assert out.location == "";

    result2 = update_person_for(me, jid(p), "", "", "", "", "", "555-1234", [], "Ann Arbor");
    out2 = result2 as Person;
    assert out2.email == "old@example.com", "empty email arg must leave the existing value alone";
    assert out2.phone == "555-1234";
    assert out2.location == "Ann Arbor";
}

test "update_person_for: links REPLACES the whole list when non-empty, left alone when empty" {
    me = (root ++> Me(name="Edits-test Me 6"))[0];
    p = (me +>:Knows(status="confirmed"):+> Person(
        name="Edits-test Links P", links=["https://old.example.com"], status="confirmed"
    ))[0];

    unchanged = update_person_for(me, jid(p), "", "", "", "", "", "", [], "");
    out_unchanged = unchanged as Person;
    assert out_unchanged.links == ["https://old.example.com"], "empty links arg must leave the existing list alone";

    replaced = update_person_for(me, jid(p), "", "", "", "", "", "", ["https://new.example.com", "https://second.example.com"], "");
    out_replaced = replaced as Person;
    assert out_replaced.links == ["https://new.example.com", "https://second.example.com"];
}

test "update_person_for: unknown person_id reports not_found" {
    me = (root ++> Me(name="Edits-test Me 4"))[0];
    result = update_person_for(me, "not-a-real-person-id-at-all", "Nope", "", "", "");
    assert result == {"error": "not_found"};
}

test "UpdatePerson: unknown person_id reports not_found (through the walker)" {
    result = root spawn UpdatePerson(person_id="not-a-real-person-id-at-all", name="Nope");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- UpdatePromise

test "UpdatePromise: text and due overwrite non-empty args only" {
    seeded = root spawn DevAddPromise(text="Edits-test old promise text", due="2026-10-01");
    pr = seeded.reports[0] as Promise;

    result = root spawn UpdatePromise(promise_id=jid(pr), text="Edits-test new promise text");
    out = result.reports[0] as Promise;
    assert out.text == "Edits-test new promise text";
    assert out.due == "2026-10-01", "due must be left unchanged when the arg is empty";

    result2 = root spawn UpdatePromise(promise_id=jid(pr), due="2026-11-15");
    out2 = result2.reports[0] as Promise;
    assert out2.text == "Edits-test new promise text", "text must be left unchanged when the arg is empty";
    assert out2.due == "2026-11-15";
}

test "UpdatePromise: natural-language due is normalized via dates.sv.jac's parse_due (SOH-219)" {
    seeded = root spawn DevAddPromise(text="Edits-test nl due promise", due="");
    pr = seeded.reports[0] as Promise;

    result = root spawn UpdatePromise(promise_id=jid(pr), due="tomorrow");
    out = result.reports[0] as Promise;
    expected = (datetime.now() + timedelta(days=1)).date().isoformat();
    assert out.due == expected;
}

test "UpdatePromise: a due parse_due can't place on a calendar is stored as the raw text (SOH-219)" {
    seeded = root spawn DevAddPromise(text="Edits-test unparsable due promise", due="");
    pr = seeded.reports[0] as Promise;

    result = root spawn UpdatePromise(promise_id=jid(pr), due="whenever works");
    out = result.reports[0] as Promise;
    assert out.due == "whenever works";
}

test "UpdatePromise: unknown promise_id reports not_found" {
    result = root spawn UpdatePromise(promise_id="not-a-real-promise-id-at-all", text="nope");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- isolation (two real roots)

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

glob EDITS_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

"""Copy edits.sv.jac's whole import chain (schema, reads) plus walkers.sv.jac
(for the `DevAddPerson` test-seeding helper) into a fresh temp dir next to a
dot-free `app.jac` — `JacTestClient.from_file` can't target a dotted
`*.sv.jac` module name directly (AGENTS.md gotcha)."""
def _edits_harness(tmp_dir: str) -> str {
    for name in ["schema.sv.jac", "reads.sv.jac", "edits.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(EDITS_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from edits { UpdatePerson, UpdatePromise, DevAddPromise }\n"
        "import from walkers { DevAddPerson }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"edits-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _edits_register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _edits_call(client: JacTestClient, token: str, wname: str, body: dict[str, any]) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "isolation: A's person is not_found from B's UpdatePerson, found from A's own" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_edits_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _edits_register(cl, "edits_a@example.com");
        b = _edits_register(cl, "edits_b@example.com");

        seeded = _edits_call(cl, a, "DevAddPerson", {"name": "Edits-test Isolation Target"});
        person_id = str(seeded[0]["_jac_id"]);
        print(f"[edits isolation] A seeded person_id={person_id}");

        a_update = _edits_call(cl, a, "UpdatePerson", {
            "person_id": person_id, "org": "A's Co",
            "email": "a@example.com", "phone": "555-0100",
            "links": ["https://a.example.com"], "location": "Ann Arbor"
        });
        print(f"[edits isolation] A's own UpdatePerson -> {a_update}");
        a_entry = a_update[0] as dict[str, any];
        assert len(a_update) == 1 and "error" not in a_entry, f"A must be able to edit its own person: {a_update}";
        assert str(a_entry["org"]) == "A's Co";
        assert str(a_entry["email"]) == "a@example.com";
        assert str(a_entry["phone"]) == "555-0100";
        assert str(a_entry["location"]) == "Ann Arbor";
        assert list(a_entry["links"]) == ["https://a.example.com"];

        b_update = _edits_call(cl, b, "UpdatePerson", {"person_id": person_id, "org": "B's Co"});
        print(f"[edits isolation] B's UpdatePerson on A's person -> {b_update}");
        assert b_update == [{"error": "not_found"}], f"B must never edit A's person: {b_update}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "isolation: A's promise is not_found from B's UpdatePromise, found from A's own" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_edits_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _edits_register(cl, "edits_a2@example.com");
        b = _edits_register(cl, "edits_b2@example.com");

        seeded = _edits_call(cl, a, "DevAddPromise", {"text": "Edits-test isolation promise"});
        promise_id = str(seeded[0]["_jac_id"]);
        print(f"[edits isolation] A seeded promise_id={promise_id}");

        a_update = _edits_call(cl, a, "UpdatePromise", {"promise_id": promise_id, "due": "2026-12-01"});
        print(f"[edits isolation] A's own UpdatePromise -> {a_update}");
        a_entry = a_update[0] as dict[str, any];
        assert len(a_update) == 1 and "error" not in a_entry, f"A must be able to edit its own promise: {a_update}";
        assert str(a_entry["due"]) == "2026-12-01";

        b_update = _edits_call(cl, b, "UpdatePromise", {"promise_id": promise_id, "due": "2026-12-25"});
        print(f"[edits isolation] B's UpdatePromise on A's promise -> {b_update}");
        assert b_update == [{"error": "not_found"}], f"B must never edit A's promise: {b_update}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
