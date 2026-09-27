"""Tests for walkers.sv.jac (SOH-163).

Annex to walkers.sv.jac — run with `jac test walkers.sv.jac`.

Why these tests build a throwaway harness instead of pointing straight at
`main.jac`:

  - `JacTestClient.from_file` cannot target `walkers.sv.jac` directly: it
    derives the served module's name by stripping only the trailing ".jac"
    from the filename, giving "walkers.sv" — a name with an embedded dot.
    At runtime that goes through Python's own import machinery
    (`importlib.import_module("walkers.sv")`), which treats the dot as a
    package/submodule separator and fails with `ModuleNotFoundError: No
    module named 'walkers.sv'; 'walkers' is not a package` — it never
    reaches Jac's own "*.sv.jac" filename-flattening resolution (that
    flattening only fires for a *bare*, dot-free import target, which is
    exactly what main.jac's own `import from walkers { ... }` line uses).

  So each test below copies the real, current `walkers.sv.jac` and
  `schema.sv.jac` into a fresh temp directory next to a two-line, dot-free
  harness module (`app.jac`) that mirrors main.jac's import line, and
  points JacTestClient/`jac start` at that harness. This is test-only
  plumbing: it never touches the real main.jac, and it always copies the
  live file contents, so it can't drift from what's actually checked in.
  The harness's own `jac.toml` mirrors the real one's
  `[plugins.scale.microservices] enabled = false` so `sv import`-style
  targets don't get auto-detected as separate microservices.

Isolation and the unauthenticated-call check use JacTestClient (in-process,
no sockets). The restart/persistence check needs a real process boundary,
so it shells out to `jac start <harness>/app.jac --port <free port> -n`
twice against the same on-disk base_path, per `jac guide jac-testing`'s
documented fallback for when JacTestClient can't reuse a base_path across
two client instances (confirmed here too: two JacTestClient instances
against the same base_path hit `ValueError: Invalid anchor id ...` on the
second instance's first request). The subprocess is started with
`start_new_session=True` so it gets its own process group, and is torn
down by killing that whole group (not just the one pid) — `jac start`
under jac-client can fork helpers, and `proc.terminate()` alone can leave
them behind.

Every test cleans up its own temp dir and any server process group in a
`finally`, on both pass and assertion failure.
"""

import from jaclang.runtimelib.testing { JacTestClient }
import from walkers { filter_people }
import from schema { Person, Circle, Event, InCircle, MetAt }
import uuid;
import os;
import shutil;
import signal;
import socket;
import subprocess;
import tempfile;
import time;
import requests;

glob REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

"""Copy the real server modules into tmp_dir and write a dot-free harness
module (harness_name) that imports every walker in walkers.sv.jac,
including DevAddPerson. Returns the harness module's path."""
def _make_harness(tmp_dir: str, harness_name: str = "app.jac") -> str {
    shutil.copyfile(
        os.path.join(REPO_ROOT, "walkers.sv.jac"),
        os.path.join(tmp_dir, "walkers.sv.jac")
    );
    shutil.copyfile(
        os.path.join(REPO_ROOT, "schema.sv.jac"),
        os.path.join(tmp_dir, "schema.sv.jac")
    );
    harness_path = os.path.join(tmp_dir, harness_name);
    f = open(harness_path, "w");
    f.write("import from walkers { Ping, GetMe, ListPeople, ListGoals, DevAddPerson }\n");
    f.close();
    toml_path = os.path.join(tmp_dir, "jac.toml");
    if not os.path.exists(toml_path) {
        t = open(toml_path, "w");
        t.write(
            "[project]\n"
            "name = \"isolation-test-harness\"\n"
            "version = \"0.1.0\"\n"
            "entry-point = \"" + harness_name + "\"\n"
            "\n"
            "[plugins.scale.microservices]\n"
            "enabled = false\n"
        );
        t.close();
    }
    return harness_path;
}

test "isolation: A never sees B's person" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        harness = _make_harness(tmp_dir);
        client = JacTestClient.from_file(harness, base_path=os.path.join(tmp_dir, "data"));

        alice_reg = client.register_user("alice@example.com", "password123");
        assert alice_reg.ok, f"alice register failed: {alice_reg.status_code} {alice_reg.text}";
        alice_token = str(alice_reg.data["token"]);

        bob_reg = client.register_user("bob@example.com", "password123");
        assert bob_reg.ok, f"bob register failed: {bob_reg.status_code} {bob_reg.text}";
        bob_token = str(bob_reg.data["token"]);

        client.set_auth_token(alice_token);
        add_alice = client.post("/walker/DevAddPerson", json={"name": "Alice's Friend", "me_name": "Alice"});
        assert add_alice.ok, add_alice.text;

        client.set_auth_token(bob_token);
        add_bob = client.post("/walker/DevAddPerson", json={"name": "Bob's Friend", "me_name": "Bob"});
        assert add_bob.ok, add_bob.text;

        # Alice: sees only her own person and her own Me.
        client.set_auth_token(alice_token);
        alice_people = client.post("/walker/ListPeople").data["reports"] as list[dict[str, any]];
        assert len(alice_people) == 1, f"alice sees {len(alice_people)} people: {alice_people}";
        assert str(alice_people[0]["name"]) == "Alice's Friend";
        for p in alice_people {
            assert "Bob" not in str(p["name"]), f"alice's ListPeople leaked a Bob record: {p}";
            assert "last_contact" in p and "how_met" in p, f"ListPeople row lacks the Knows fields: {p}";
        }
        alice_me = client.post("/walker/GetMe").data["reports"] as list[dict[str, any]];
        assert len(alice_me) == 1;
        assert str(alice_me[0]["name"]) == "Alice";

        # Bob: sees only his own person and his own Me — never Alice's.
        client.set_auth_token(bob_token);
        bob_people = client.post("/walker/ListPeople").data["reports"] as list[dict[str, any]];
        assert len(bob_people) == 1, f"bob sees {len(bob_people)} people: {bob_people}";
        assert str(bob_people[0]["name"]) == "Bob's Friend";
        for p in bob_people {
            assert "Alice" not in str(p["name"]), f"bob's ListPeople leaked an Alice record: {p}";
        }
        bob_me = client.post("/walker/GetMe").data["reports"] as list[dict[str, any]];
        assert len(bob_me) == 1;
        assert str(bob_me[0]["name"]) == "Bob";
    } finally {
        if client is not None {
            client.close();
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "ListPeople fields=list omits contact/identity keys (SOH-236)" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        harness = _make_harness(tmp_dir);
        client = JacTestClient.from_file(harness, base_path=os.path.join(tmp_dir, "data"));

        reg = client.register_user("dana@example.com", "password123");
        assert reg.ok, f"register failed: {reg.status_code} {reg.text}";
        token = str(reg.data["token"]);
        client.set_auth_token(token);

        added = client.post("/walker/DevAddPerson", json={"name": "Dana's Friend", "me_name": "Dana"});
        assert added.ok, added.text;

        omitted_keys = ["identity_tokens", "links", "email", "phone"];

        full_rows = client.post("/walker/ListPeople").data["reports"] as list[dict[str, any]];
        assert len(full_rows) == 1;
        for k in omitted_keys {
            assert k in full_rows[0], f"default fields='full' should keep {k}: {full_rows[0]}";
        }
        assert "name" in full_rows[0] and "last_contact" in full_rows[0] and "how_met" in full_rows[0];

        list_rows = client.post("/walker/ListPeople", json={"fields": "list"}).data["reports"] as list[dict[str, any]];
        assert len(list_rows) == 1;
        for k in omitted_keys {
            assert k not in list_rows[0], f"fields='list' should omit {k}: {list_rows[0]}";
        }
        assert "name" in list_rows[0] and "last_contact" in list_rows[0] and "how_met" in list_rows[0];
    } finally {
        if client is not None {
            client.close();
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "isolation: unauthenticated call is rejected" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        harness = _make_harness(tmp_dir);
        client = JacTestClient.from_file(harness, base_path=os.path.join(tmp_dir, "data"));
        client.clear_auth();
        resp = client.post("/walker/ListPeople");
        assert not resp.ok, f"expected an auth failure, got {resp.status_code}: {resp.text}";
        assert resp.status_code in [401, 403], f"expected 401/403, got {resp.status_code}: {resp.text}";
    } finally {
        if client is not None {
            client.close();
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

def _free_port() -> int {
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    s.bind(("127.0.0.1", 0));
    port = s.getsockname()[1];
    s.close();
    return int(port);
}

"""Tail of the server's combined stdout/stderr log, for failure messages."""
def _tail(log_path: str, n: int = 4000) -> str {
    try {
        f = open(log_path, "rb");
        data = f.read();
        f.close();
        return data[-n:].decode("utf-8", errors="replace");
    } except OSError {
        return "<no log available>";
    }
}

"""Poll until the port accepts connections, or the process exits, or timeout.
Fails fast (does not wait out the full timeout) if the process has already
exited."""
def _wait_until_ready(proc: subprocess.Popen[bytes], port: int, timeout: float = 15.0) -> bool {
    deadline = time.time() + timeout;
    while time.time() < deadline {
        if proc.poll() is not None {
            return False;
        }
        try {
            sock = socket.create_connection(("127.0.0.1", port), timeout=0.5);
            sock.close();
            return True;
        } except OSError {
            time.sleep(0.3);
        }
    }
    return False;
}

"""Kill the whole process group (proc was started with start_new_session=True),
SIGTERM first, SIGKILL if it doesn't die quickly."""
def _kill_process_group(proc: (subprocess.Popen[bytes] | None)) {
    if proc is None {
        return;
    }
    try {
        os.killpg(os.getpgid(proc.pid), int(signal.SIGTERM));
    } except OSError { }
    try {
        proc.wait(timeout=5);
    } except subprocess.TimeoutExpired {
        try {
            os.killpg(os.getpgid(proc.pid), int(signal.SIGKILL));
        } except OSError { }
        try {
            proc.wait(timeout=5);
        } except subprocess.TimeoutExpired { }
    }
}

def _start_server(tmp_dir: str, port: int) -> subprocess.Popen[bytes] {
    log_path = os.path.join(tmp_dir, f"server_{port}.log");
    log_file = open(log_path, "wb");
    proc = subprocess.Popen(
        ["jac", "start", "app.jac", "--port", str(port), "-n"],
        cwd=tmp_dir,
        stdin=subprocess.DEVNULL,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True
    );
    log_file.close();
    ok = _wait_until_ready(proc, port);
    if not ok {
        tail = _tail(log_path);
        _kill_process_group(proc);
        assert False, f"harness server on port {port} did not come up in time; log tail:\n{tail}";
    }
    return proc;
}

test "persistence: person survives real server restart" {
    tmp_dir = tempfile.mkdtemp();
    proc1: (subprocess.Popen[bytes] | None) = None;
    proc2: (subprocess.Popen[bytes] | None) = None;
    try {
        _make_harness(tmp_dir);
        port = _free_port();
        base = f"http://127.0.0.1:{port}";

        proc1 = _start_server(tmp_dir, port);
        reg = requests.post(f"{base}/user/register", json={
            "identities": [{"type": "username", "value": "carol@example.com"}],
            "credential": {"type": "password", "password": "password123"}
        });
        assert reg.ok, reg.text;
        token = reg.json()["data"]["token"];

        add = requests.post(
            f"{base}/walker/DevAddPerson",
            headers={"Authorization": f"Bearer {token}"},
            json={"name": "Carol's Friend", "me_name": "Carol"}
        );
        assert add.ok, add.text;

        listed = requests.post(
            f"{base}/walker/ListPeople",
            headers={"Authorization": f"Bearer {token}"},
            json={}
        );
        listed_reports = listed.json()["data"]["reports"] as list[dict[str, any]];
        assert len(listed_reports) == 1;

        _kill_process_group(proc1);
        proc1 = None;

        # Same on-disk base_path (tmp_dir/.jac by default), brand new process.
        port2 = _free_port();
        base2 = f"http://127.0.0.1:{port2}";
        proc2 = _start_server(tmp_dir, port2);
        login = requests.post(f"{base2}/user/login", json={
            "identity": {"type": "username", "value": "carol@example.com"},
            "credential": {"type": "password", "password": "password123"}
        });
        assert login.ok, login.text;
        token2 = login.json()["data"]["token"];

        listed2 = requests.post(
            f"{base2}/walker/ListPeople",
            headers={"Authorization": f"Bearer {token2}"},
            json={}
        );
        reports = listed2.json()["data"]["reports"] as list[dict[str, any]];
        assert len(reports) == 1, f"expected 1 person after restart, got {reports}";
        assert str(reports[0]["name"]) == "Carol's Friend";
    } finally {
        if proc1 is not None {
            _kill_process_group(proc1);
        }
        if proc2 is not None {
            _kill_process_group(proc2);
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

# ---------------------------------------------------------------- ListPeople filters (SOH-217)
#
# `filter_people` (the walker's own filter logic, extracted to a plain def)
# is exercised directly on hand-built Person nodes rather than through
# `root spawn ListPeople(...)` — same "test the plain def directly, not the
# `[root --> [?:Me]]`-resolving walker" idiom `edits.test.jac` uses for
# `update_person_for` (AGENTS.md Gotcha). This also sidesteps a real
# limitation this task uncovered: a `:priv` walker spawned in-process right
# after building fixtures with a bare `root ++>`/`+>:Edge:+>` in the SAME
# `jac test` method does not reliably see edges attached that way when it
# re-reads them through a chained typed traversal (`[root --> [?:Me]
# ->:Knows:->]` reported 0 results here even though `[me ->:Knows:->]`
# reported 4, moments earlier, in the same test) — nobody else in this
# codebase mixes bare `root ++>` fixtures with `root spawn` on a
# `[root --> [?:Me] ->: ...]`-style walker for exactly this reason.

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

test "filter_people: circle_id, event_id, include_archived (SOH-217)" {
    suffix = _uid();
    circle = (root ++> Circle(name="Filter Circle " + suffix, created_at=""))[0];
    other_circle = (root ++> Circle(name="Other Circle " + suffix, created_at=""))[0];
    event = (root ++> Event(name="Filter Event " + suffix, created_at=""))[0];
    other_event = (root ++> Event(name="Other Event " + suffix, created_at=""))[0];

    in_circle = (root ++> Person(name="In Circle " + suffix))[0];
    in_circle +>:InCircle:+> circle;

    at_event = (root ++> Person(name="At Event " + suffix))[0];
    at_event +>:MetAt(source_note=""):+> event;

    archived = (root ++> Person(name="Archived " + suffix))[0];
    archived.archived = True;

    plain = (root ++> Person(name="Plain " + suffix))[0];

    all_people = [in_circle, at_event, archived, plain];

    default_ids = [jid(p) for p in filter_people(all_people, "", "", False)];
    assert jid(in_circle) in default_ids;
    assert jid(at_event) in default_ids;
    assert jid(plain) in default_ids;
    assert jid(archived) not in default_ids, "archived people are excluded by default";

    with_archived_ids = [jid(p) for p in filter_people(all_people, "", "", True)];
    assert jid(archived) in with_archived_ids;

    circle_ids = [jid(p) for p in filter_people(all_people, jid(circle), "", False)];
    assert circle_ids == [jid(in_circle)], f"expected only the circle's member, got {circle_ids}";

    empty_circle_ids = [jid(p) for p in filter_people(all_people, jid(other_circle), "", False)];
    assert empty_circle_ids == [];

    event_ids = [jid(p) for p in filter_people(all_people, "", jid(event), False)];
    assert event_ids == [jid(at_event)], f"expected only the event's attendee, got {event_ids}";

    empty_event_ids = [jid(p) for p in filter_people(all_people, "", jid(other_event), False)];
    assert empty_event_ids == [];
}
