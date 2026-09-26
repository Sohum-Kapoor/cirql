"""Tests for gate.sv.jac (SOH-204, the 9 PM gate).

Annex to gate.sv.jac — run with `jac test gate.sv.jac`.

Same harness approach as walkers.test.jac (read its docstring for why):
JacTestClient cannot target a dotted `*.sv.jac` file, so each test copies the
live gate.sv.jac + schema.sv.jac into a fresh temp dir next to a dot-free
`app.jac` that imports the gate walkers, and gives the client its own
base_path. No `jac clean` anywhere.

Every test registers REAL accounts (A, B, and where needed C) through
/user/register and switches between them with set_auth_token, so every
walker call runs on that user's own root.
"""

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

glob GATE_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _gate_harness(tmp_dir: str) -> str {
    for name in ["gate.sv.jac", "schema.sv.jac"] {
        shutil.copyfile(os.path.join(GATE_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from gate { GateMyRoot, GatePostShared, GateListShared, GateMakeCard, GateReadCard }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"gate-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

"""Register a real account; returns (token, root_id from the register response)."""
def _register(client: JacTestClient, email: str) -> tuple[str, str] {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return (str((reg.data or {})["token"]), str((reg.data or {}).get("root_id")));
}

"""Call a walker as the given user; returns its reports list."""
def _call(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "gate a: root.shared post visible to B; A's private Card invisible to B" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_gate_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        (a, _) = _register(cl, "gate_a1@example.com");
        (b, _) = _register(cl, "gate_b1@example.com");

        # A: a private Card (no grant) and a shared IntroRequest.
        private_id = str(_call(cl, a, "GateMakeCard", {"handle": "a-private"})[0]);
        req_id = str(_call(cl, a, "GatePostShared", {"text": "need a climate VC", "from_handle": "a"})[0]);

        # B, on B's own root, lists the commons.
        listed = _call(cl, b, "GateListShared", {});
        print(f"[gate a] B GateListShared -> {listed}");
        ids = [str(r["id"]) for r in listed];
        assert req_id in ids, f"B cannot see A's shared IntroRequest {req_id}: {listed}";
        assert private_id not in ids, "A's private Card leaked into B's shared listing";
        mine = [r for r in listed if str(r["id"]) == req_id][0];
        assert str(mine["need"]) == "need a climate VC";

        # B posts too; A sees both (the Exchange container is ConnectPerm).
        b_req = str(_call(cl, b, "GatePostShared", {"text": "need a designer", "from_handle": "b"})[0]);
        a_ids = [str(r["id"]) for r in _call(cl, a, "GateListShared", {})];
        assert req_id in a_ids and b_req in a_ids, f"A should see both requests: {a_ids}";

        # And B cannot read A's private Card by id.
        read = _call(cl, b, "GateReadCard", {"card_id": private_id});
        print(f"[gate a] B GateReadCard(private) -> {read}");
        assert read == ["denied"], f"B read A's private Card: {read}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "gate b: allow_root to B's root (learned from B's shared request); B reads, C denied" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_gate_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        (a, _) = _register(cl, "gate_a2@example.com");
        (b, b_root_reg) = _register(cl, "gate_b2@example.com");
        (c, _) = _register(cl, "gate_c2@example.com");

        # How A learns B's root id: B posts a request to the commons; A reads its owner_root.
        b_root = str(_call(cl, b, "GateMyRoot", {})[0]);
        _call(cl, b, "GatePostShared", {"text": "need an intro to a PI", "from_handle": "b"});
        seen = _call(cl, a, "GateListShared", {});
        owner_root = str([r for r in seen if str(r["from_handle"]) == "b"][0]["owner_root"]);
        print(f"[gate b] jid(root) as B={b_root} register root_id={b_root_reg} owner_root seen by A={owner_root}");
        assert owner_root == b_root, f"owner_root {owner_root} != B's jid(root) {b_root}";

        card_id = str(_call(cl, a, "GateMakeCard", {"handle": "a-for-b", "to_root": owner_root})[0]);

        b_read = _call(cl, b, "GateReadCard", {"card_id": card_id});
        c_read = _call(cl, c, "GateReadCard", {"card_id": card_id});
        a_read = _call(cl, a, "GateReadCard", {"card_id": card_id});
        print(f"[gate b] B -> {b_read}  C -> {c_read}  A(owner) -> {a_read}");
        assert b_read == ["a-for-b"], f"B (allowed) could not read: {b_read}";
        assert c_read == ["denied"], f"C (not allowed) was not denied: {c_read}";
        assert a_read == ["a-for-b"], f"owner could not read own card: {a_read}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "gate c: grant public; B and C both read" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_gate_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        (a, _) = _register(cl, "gate_a3@example.com");
        (b, _) = _register(cl, "gate_b3@example.com");
        (c, _) = _register(cl, "gate_c3@example.com");

        card_id = str(_call(cl, a, "GateMakeCard", {"handle": "a-public", "public": True})[0]);
        b_read = _call(cl, b, "GateReadCard", {"card_id": card_id});
        c_read = _call(cl, c, "GateReadCard", {"card_id": card_id});
        print(f"[gate c] B -> {b_read}  C -> {c_read}");
        assert b_read == ["a-public"], f"B could not read public card: {b_read}";
        assert c_read == ["a-public"], f"C could not read public card: {c_read}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "gate d: ungranted Card id read by B is denied" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_gate_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        (a, _) = _register(cl, "gate_a4@example.com");
        (b, _) = _register(cl, "gate_b4@example.com");

        card_id = str(_call(cl, a, "GateMakeCard", {"handle": "a-ungranted"})[0]);
        # jobj(id) resolves ANY node regardless of grants (verified in SOH-204:
        # an unchecked field read by B returned A's ungranted handle). The
        # "denied" below comes only from GateReadCard's Jac.check_read_access.
        enforced = _call(cl, b, "GateReadCard", {"card_id": card_id});
        print(f"[gate d] B -> {enforced}");
        assert enforced == ["denied"], f"ungranted card not denied: {enforced}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
