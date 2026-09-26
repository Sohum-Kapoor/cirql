"""Tests for handshake.sv.jac (SOH-183, the QR handshake).

Annex to handshake.sv.jac — run with `jac test handshake.sv.jac`.

Same harness as gate.test.jac / exchange.test.jac / cards.test.jac:
JacTestClient cannot target a dotted `*.sv.jac` file, so each test copies the
live server modules into a fresh temp dir next to a dot-free entry file and
gives the client its own base_path. No `jac clean` anywhere.

The entry file is named `hs_entry.jac`, NOT `app.jac`: `handshake.sv.jac`
imports from `exchange`, so `jac test handshake.sv.jac` transitively loads
`exchange.sv.jac` and auto-attaches ITS `exchange.test.jac` annex too (same
mechanism that pairs `handshake.test.jac` with `handshake.sv.jac` — an annex
attaches whenever its base module loads, not only when explicitly targeted).
`exchange.test.jac`'s own harness also builds a dot-free entry file, and if
both used the literal name `app.jac`, Python's module cache (keyed by module
name, not path) would serve whichever harness's `app` module loaded first to
BOTH JacTestClients in the same test process — the second server would then
404 on walkers only the other harness registered. A unique entry name avoids
that collision entirely.

Three REAL registered accounts: A, B (both scan each other's QR), C
(bystander, never scanned by anyone). Every walker call runs on that
account's own root via set_auth_token.
"""

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import signal;
import socket;
import subprocess;
import tempfile;
import time;
import requests;

glob HS_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _hs_harness(tmp_dir: str) -> str {
    for name in [
        "handshake.sv.jac", "schema.sv.jac", "exchange.sv.jac", "onboard.sv.jac",
        "cards.sv.jac", "scoring.sv.jac", "freshness.sv.jac", "walkers.sv.jac",
        "reads.sv.jac"
    ] {
        shutil.copyfile(os.path.join(HS_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "hs_entry.jac");
    f = open(harness_path, "w");
    f.write(
        "import from walkers { ListPeople, DevAddPerson }\n"
        "import from cards { PublishCard, get_card }\n"
        "import from reads { Receipt }\n"
        "import from handshake { OfferHandshake, ListHandshakes, AcceptHandshake, DeclineHandshake }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"handshake-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"hs_entry.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

"""Register a real account with a username identity (an email-shaped value,
same pattern proven in gate.test.jac/exchange.test.jac/cards.test.jac) plus
its own email identity, matching the register contract
(`identity.type 'username' is required` per AGENTS.md gotchas)."""
def _reg(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _run(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

def _publish(client: JacTestClient, token: str, body: dict[str, any]) -> dict[str, any] {
    reports = _run(client, token, "PublishCard", body);
    assert len(reports) == 1, f"PublishCard reported {len(reports)} items: {reports}";
    return dict(reports[0]);
}

def _get_card_anon(client: JacTestClient, handle: str) -> dict[str, any] {
    client.clear_auth();
    resp = client.post("/function/get_card", json={"handle": handle});
    assert resp.ok, f"get_card failed: {resp.status_code} {resp.text}";
    return dict(resp.data["result"]);
}

def _err(reports: list[any]) -> str {
    if len(reports) == 1 and isinstance(reports[0], dict) and "error" in reports[0] {
        return str(reports[0]["error"]);
    }
    return "";
}

test "handshake a/b: offer, incoming/outgoing views, isolation, accept end to end, idempotent" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_hs_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "hs_a1@example.com");
        b = _reg(cl, "hs_b1@example.com");
        c = _reg(cl, "hs_c1@example.com");

        a_card = _publish(cl, a, {"headline": "Robotics", "about": "I build accessible robots.", "visibility": "handshake_only", "name": "Alice"});
        a_handle = str(a_card["handle"]);
        b_card = _publish(cl, b, {"headline": "Design", "about": "I design climate products.", "visibility": "link", "name": "Bob"});
        b_handle = str(b_card["handle"]);
        _publish(cl, c, {"headline": "Bystander", "visibility": "link", "name": "Carol"});
        print(f"[hs ab] a_handle={a_handle} b_handle={b_handle}");

        # (a) A offers B; B sees it incoming; C sees nothing; C cannot accept it.
        offered = _run(cl, a, "OfferHandshake", {"to_handle": b_handle})[0];
        print(f"[hs ab] OfferHandshake -> {offered}");
        assert str(offered["status"]) == "offered" and str(offered["to_handle"]) == b_handle;
        offer_id = str(offered["offer_id"]);

        # Idempotent: a second identical offer returns the same one, no dup.
        again = _run(cl, a, "OfferHandshake", {"to_handle": b_handle})[0];
        assert str(again["offer_id"]) == offer_id, f"duplicate offer created: {again}";

        b_list = _run(cl, b, "ListHandshakes", {});
        print(f"[hs ab] B ListHandshakes (before accept) -> {b_list}");
        b_mine = [x for x in b_list if str(x["offer_id"]) == offer_id];
        assert len(b_mine) == 1, b_list;
        assert str(b_mine[0]["direction"]) == "incoming" and str(b_mine[0]["status"]) == "offered";

        c_list = _run(cl, c, "ListHandshakes", {});
        print(f"[hs ab] C ListHandshakes -> {c_list}");
        assert [x for x in c_list if str(x["offer_id"]) == offer_id] == [], c_list;

        assert _err(_run(cl, c, "AcceptHandshake", {"offer_id": offer_id})) == "not_found";

        # (c) Isolation before accept: A's handshake_only card is not publicly
        # gettable, and a direct read of its id is not_found to a bystander.
        anon_a = _get_card_anon(cl, a_handle);
        print(f"[hs ab] anon get_card(A handshake_only) -> {anon_a}");
        assert not anon_a["found"], anon_a;
        a_card_id = str(a_card["_jac_id"]);
        c_receipt = _run(cl, c, "Receipt", {"id": a_card_id})[0];
        print(f"[hs ab] C Receipt(A's card id) -> {c_receipt}");
        assert dict(c_receipt).get("error") == "not_found", c_receipt;

        # (b) B accepts: person materializes in B's graph right away.
        accepted = _run(cl, b, "AcceptHandshake", {"offer_id": offer_id})[0];
        print(f"[hs ab] B AcceptHandshake -> {accepted}");
        assert str(accepted["person"]["name"]) == "Alice", accepted;
        assert str(accepted["card"]["handle"]) == a_handle, accepted;

        b_people = _run(cl, b, "ListPeople", {});
        print(f"[hs ab] B ListPeople -> {b_people}");
        assert [str(p["name"]) for p in b_people] == ["Alice"], b_people;

        # A's outgoing offer now derives "accepted", with a person_id, and A
        # gained Bob in their own graph with how_met "handshake".
        a_list = _run(cl, a, "ListHandshakes", {});
        print(f"[hs ab] A ListHandshakes (after accept) -> {a_list}");
        a_mine = [x for x in a_list if str(x["offer_id"]) == offer_id];
        assert len(a_mine) == 1, a_list;
        assert str(a_mine[0]["direction"]) == "outgoing" and str(a_mine[0]["status"]) == "accepted", a_mine;
        a_person_id = str(a_mine[0]["person_id"]);
        assert a_person_id, a_mine;

        a_people = _run(cl, a, "ListPeople", {});
        print(f"[hs ab] A ListPeople -> {a_people}");
        assert [str(p["name"]) for p in a_people] == ["Bob"], a_people;
        assert str(a_people[0]["_jac_id"]) == a_person_id;

        # Idempotent materialization: calling again does not duplicate A's Person.
        a_list_again = _run(cl, a, "ListHandshakes", {});
        a_mine_again = [x for x in a_list_again if str(x["offer_id"]) == offer_id];
        assert str(a_mine_again[0]["person_id"]) == a_person_id, a_mine_again;
        a_people_again = _run(cl, a, "ListPeople", {});
        assert len(a_people_again) == len(a_people), (a_people, a_people_again);

        # Isolation: B's ListPeople carries no foreign id from A's root other
        # than (at most) A's Card id — and the FromCard cross-root attach is
        # best-effort (only ReadPerm was granted, not ConnectPerm), so it may
        # carry none at all.
        b_ids = [str(p["_jac_id"]) for p in b_people];
        leaked = [pid for pid in b_ids if pid != a_card_id and pid == a_person_id];
        assert leaked == [], f"A's person id leaked into B's graph: {b_ids}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "handshake SOH-211: offer to a handshake_only card published in the same process is found" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_hs_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "hs_a8@example.com");
        b = _reg(cl, "hs_b8@example.com");
        _publish(cl, a, {"headline": "Batteries", "visibility": "link", "name": "Ann"});
        b_card = _publish(cl, b, {"headline": "Climate fund", "about": "I run a climate fund.", "visibility": "handshake_only", "name": "Ben"});
        b_handle = str(b_card["handle"]);

        offered = _run(cl, a, "OfferHandshake", {"to_handle": b_handle});
        print(f"[hs 211] A OfferHandshake(B handshake_only) -> {offered}");
        assert _err(offered) == "", offered;
        assert str(offered[0]["status"]) == "offered" and str(offered[0]["to_handle"]) == b_handle, offered;
        offer_id = str(offered[0]["offer_id"]);

        # Still not public: finding it for a handshake is not granting it.
        assert not _get_card_anon(cl, b_handle)["found"];

        accepted = _run(cl, b, "AcceptHandshake", {"offer_id": offer_id})[0];
        assert str(accepted["person"]["name"]) == "Ann", accepted;
        a_mine = [x for x in _run(cl, a, "ListHandshakes", {}) if str(x["offer_id"]) == offer_id];
        assert len(a_mine) == 1 and str(a_mine[0]["status"]) == "accepted", a_mine;
        assert [str(p["name"]) for p in _run(cl, a, "ListPeople", {})] == ["Ben"];
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "handshake d: decline hides the pair; the offerer keeps seeing offered" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_hs_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "hs_a2@example.com");
        c = _reg(cl, "hs_c2@example.com");

        _publish(cl, a, {"headline": "A", "visibility": "link", "name": "Alice2"});
        c_card = _publish(cl, c, {"headline": "C", "visibility": "link", "name": "Carol"});
        c_handle = str(c_card["handle"]);

        offered = _run(cl, a, "OfferHandshake", {"to_handle": c_handle})[0];
        offer_id = str(offered["offer_id"]);

        declined = _run(cl, c, "DeclineHandshake", {"offer_id": offer_id});
        assert declined == ["declined"], declined;

        c_list = _run(cl, c, "ListHandshakes", {});
        print(f"[hs d] C ListHandshakes (after decline) -> {c_list}");
        assert [x for x in c_list if str(x["offer_id"]) == offer_id] == [], c_list;

        a_list = _run(cl, a, "ListHandshakes", {});
        print(f"[hs d] A ListHandshakes (after C declined) -> {a_list}");
        a_mine = [x for x in a_list if str(x["offer_id"]) == offer_id];
        assert len(a_mine) == 1, a_list;
        assert str(a_mine[0]["status"]) == "offered", f"decline reason crossed to the offerer: {a_mine}";

        # C cannot accept an offer they already declined.
        assert _err(_run(cl, c, "AcceptHandshake", {"offer_id": offer_id})) == "invalid_state";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "handshake: bad inputs — no card, self, not_found, own outgoing decline" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_hs_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "hs_a3@example.com");
        b = _reg(cl, "hs_b3@example.com");

        # No card yet -> no_card.
        assert _err(_run(cl, a, "OfferHandshake", {"to_handle": "nobody"})) == "no_card";

        a_card = _publish(cl, a, {"visibility": "link", "name": "Alice3"});
        a_handle = str(a_card["handle"]);
        b_card = _publish(cl, b, {"visibility": "link", "name": "Bob3"});
        b_handle = str(b_card["handle"]);

        # Unknown handle -> not_found.
        assert _err(_run(cl, a, "OfferHandshake", {"to_handle": "no-such-handle"})) == "not_found";

        # Offering your own handle -> self.
        assert _err(_run(cl, a, "OfferHandshake", {"to_handle": a_handle})) == "self";

        # A withdraws their own outgoing offer directly (they own it).
        offer_id = str(_run(cl, a, "OfferHandshake", {"to_handle": b_handle})[0]["offer_id"]);
        assert _run(cl, a, "DeclineHandshake", {"offer_id": offer_id}) == ["declined"];
        a_list = _run(cl, a, "ListHandshakes", {});
        mine = [x for x in a_list if str(x["offer_id"]) == offer_id];
        assert len(mine) == 1 and str(mine[0]["status"]) == "declined", mine;

        # B can no longer usefully accept a withdrawn offer.
        assert _err(_run(cl, b, "AcceptHandshake", {"offer_id": offer_id})) == "invalid_state";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

# ---------------------------------------------------------------- restart

"""SOH-183 (per SOH-205's finding): `OfferHandshake`/`ListHandshakes` walk
`root.shared` for `HandshakeOffer` nodes owned by OTHER users than root.shared
itself — exactly the shape that loses cross-owner edges from a TYPED
traversal after a real server restart (the topology index lives with the
origin node's owner, and no caller owns root.shared). `find_card_in_directory`
has the same shape for the shared CardDirectory. Both were fixed to the
UNTYPED-then-isinstance pattern (`[x for x in [n -->] if isinstance(x, T)]`);
this test proves it survives an actual process boundary, not just the
in-process JacTestClient the tests above use (per `jac guide jac-testing`,
JacTestClient can't reuse one base_path across two client instances either,
so a real restart needs two real `jac start` subprocesses against the same
on-disk base_path — copied verbatim from walkers.test.jac's persistence
test). The harness entry file is named `hsapp.jac`, not `app.jac`, for the
same module-cache-collision reason as `_hs_entry.jac` above; every module in
the import chain (down to `llm.sv.jac`, needed transitively by
exchange/onboard/scoring but never actually called here — no `.env` in the
harness dir, so nothing hits the network) is copied into the harness dir
because a subprocess has no access to the real repo's modules the way an
in-process JacTestClient apparently does."""

def _make_restart_harness(tmp_dir: str) -> str {
    for name in [
        "handshake.sv.jac", "schema.sv.jac", "exchange.sv.jac", "onboard.sv.jac",
        "cards.sv.jac", "scoring.sv.jac", "freshness.sv.jac", "walkers.sv.jac",
        "reads.sv.jac", "llm.sv.jac"
    ] {
        shutil.copyfile(os.path.join(HS_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "hsapp.jac");
    f = open(harness_path, "w");
    f.write(
        "import from walkers { ListPeople, DevAddPerson }\n"
        "import from cards { PublishCard, get_card }\n"
        "import from handshake { OfferHandshake, ListHandshakes, AcceptHandshake, DeclineHandshake }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"handshake-restart-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"hsapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _hs_free_port() -> int {
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    s.bind(("127.0.0.1", 0));
    port = s.getsockname()[1];
    s.close();
    return int(port);
}

def _hs_tail(log_path: str, n: int = 4000) -> str {
    try {
        f = open(log_path, "rb");
        data = f.read();
        f.close();
        return data[-n:].decode("utf-8", errors="replace");
    } except OSError {
        return "<no log available>";
    }
}

def _hs_wait_until_ready(proc: subprocess.Popen[bytes], port: int, timeout: float = 15.0) -> bool {
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

def _hs_kill_process_group(proc: (subprocess.Popen[bytes] | None)) {
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

def _hs_start_server(tmp_dir: str, port: int) -> subprocess.Popen[bytes] {
    log_path = os.path.join(tmp_dir, f"server_{port}.log");
    log_file = open(log_path, "wb");
    proc = subprocess.Popen(
        ["jac", "start", "hsapp.jac", "--port", str(port), "-n"],
        cwd=tmp_dir,
        stdin=subprocess.DEVNULL,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True
    );
    log_file.close();
    ok = _hs_wait_until_ready(proc, port);
    if not ok {
        tail = _hs_tail(log_path);
        _hs_kill_process_group(proc);
        assert False, f"harness server on port {port} did not come up in time; log tail:\n{tail}";
    }
    return proc;
}

def _hs_register(base: str, email: str) -> str {
    reg = requests.post(f"{base}/user/register", json={
        "identities": [{"type": "username", "value": email}],
        "credential": {"type": "password", "password": "password123"}
    });
    assert reg.ok, reg.text;
    return str(reg.json()["data"]["token"]);
}

def _hs_login(base: str, email: str) -> str {
    login = requests.post(f"{base}/user/login", json={
        "identity": {"type": "username", "value": email},
        "credential": {"type": "password", "password": "password123"}
    });
    assert login.ok, login.text;
    return str(login.json()["data"]["token"]);
}

def _hs_call(base: str, token: str, wname: str, body: dict[str, any]) -> list[any] {
    resp = requests.post(
        f"{base}/walker/{wname}",
        headers={"Authorization": f"Bearer {token}"},
        json=body
    );
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.json()["data"]["reports"]);
}

test "handshake restart: an offer posted before a real server restart is still visible after it" {
    tmp_dir = tempfile.mkdtemp();
    proc1: (subprocess.Popen[bytes] | None) = None;
    proc2: (subprocess.Popen[bytes] | None) = None;
    try {
        _make_restart_harness(tmp_dir);
        port1 = _hs_free_port();
        base1 = f"http://127.0.0.1:{port1}";
        proc1 = _hs_start_server(tmp_dir, port1);

        a_token = _hs_register(base1, "hs_restart_a@example.com");
        b_token = _hs_register(base1, "hs_restart_b@example.com");

        a_card = _hs_call(base1, a_token, "PublishCard", {"visibility": "link", "name": "AliceR"})[0];
        b_card = _hs_call(base1, b_token, "PublishCard", {"visibility": "link", "name": "BobR"})[0];
        a_handle = str(a_card["handle"]);
        b_handle = str(b_card["handle"]);

        offered = _hs_call(base1, a_token, "OfferHandshake", {"to_handle": b_handle})[0];
        offer_id = str(offered["offer_id"]);
        print(f"[hs restart] OfferHandshake (pre-restart) -> {offered}");

        # Sanity check before restart: B already sees it incoming.
        pre = _hs_call(base1, b_token, "ListHandshakes", {});
        pre_mine = [x for x in pre if str(x["offer_id"]) == offer_id];
        assert len(pre_mine) == 1 and str(pre_mine[0]["status"]) == "offered", pre;

        _hs_kill_process_group(proc1);
        proc1 = None;

        # Same on-disk base_path (tmp_dir/.jac by default), brand new process.
        port2 = _hs_free_port();
        base2 = f"http://127.0.0.1:{port2}";
        proc2 = _hs_start_server(tmp_dir, port2);

        b_token2 = _hs_login(base2, "hs_restart_b@example.com");
        post = _hs_call(base2, b_token2, "ListHandshakes", {});
        print(f"[hs restart] B ListHandshakes (post-restart) -> {post}");
        post_mine = [x for x in post if str(x["offer_id"]) == offer_id];
        assert len(post_mine) == 1, f"offer vanished after restart (untyped-traversal fix regressed?): {post}";
        assert str(post_mine[0]["direction"]) == "incoming" and str(post_mine[0]["status"]) == "offered", post_mine;

        # And AcceptHandshake still finds A's Card via the shared CardDirectory
        # post-restart (find_card_in_directory is the same untyped pattern).
        accepted = _hs_call(base2, b_token2, "AcceptHandshake", {"offer_id": offer_id})[0];
        print(f"[hs restart] B AcceptHandshake (post-restart) -> {accepted}");
        assert str(accepted["card"]["handle"]) == a_handle, accepted;
        assert str(accepted["person"]["name"]) == "AliceR", accepted;
    } finally {
        if proc1 is not None { _hs_kill_process_group(proc1); }
        if proc2 is not None { _hs_kill_process_group(proc2); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
