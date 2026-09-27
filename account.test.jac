"""Tests for account.sv.jac (SOH-226). Deterministic: no model, no network.

HTTP harness only (DeleteAccount mutates the auth store, not just the
graph) — never run on the shared persisted test root. Own temp dir + own
`base_path`, torn down after.
"""

import from account { DeleteAccount, _account_db_path, _disable_identity }
import from lifecycle { ArchivePerson, DeleteMyData }

import from uuid { uuid4 }
import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;
import sqlite3;

glob AC_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _ac_harness(tmp_dir: str) -> str {
    for name in ["account.sv.jac", "lifecycle.sv.jac", "schema.sv.jac", "reads.sv.jac", "export.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(AC_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "accountapp.jac");
    f = open(harness_path, "w");
    f.write(
        "import from account { DeleteAccount }\n"
        "import from lifecycle { ArchivePerson, DeleteMyData }\n"
        "import from walkers { ListPeople, ListGoals }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"account-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"accountapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _reg(client: JacTestClient, username: str) -> dict[str, str] {
    reg = client.register_user(username, "password123");
    assert reg.ok, f"register {username} failed: {reg.status_code} {reg.text}";
    d = reg.data or {};
    return {"token": str(d["token"]), "root_id": str(d["root_id"]).replace("-", "")};
}

def _call(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "DeleteAccount: wrong confirm is a no-op" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    run = str(uuid4())[:8];
    try {
        cl = JacTestClient.from_file(_ac_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, f"ac_noop_{run}");
        noop = _call(cl, a["token"], "DeleteAccount", {"confirm": "delete"})[0] as dict[str, any];
        assert noop["ok"] == False;
        assert noop["identity_removed"] == False;
        assert noop["identity_disabled"] == False;

        # account still fully usable: same token, same login
        assert _call(cl, a["token"], "ListPeople", {}) == [];
        again = cl.login(f"ac_noop_{run}", "password123");
        assert again.ok, f"login should still work: {again.status_code} {again.text}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "DeleteAccount(confirm='DELETE'): graph wiped, identity disabled, old token dead, old login dead, new username free" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    run = str(uuid4())[:8];
    username_a = f"ac_del_{run}";
    username_b = f"ac_keep_{run}";
    try {
        cl = JacTestClient.from_file(_ac_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, username_a);
        b = _reg(cl, username_b);
        old_token = a["token"];

        gone = _call(cl, old_token, "DeleteAccount", {"confirm": "DELETE"})[0] as dict[str, any];
        print(f"[account] DeleteAccount -> {gone}");
        assert gone["ok"] == True;
        assert gone["identity_removed"] == False;
        assert gone["identity_disabled"] == True;
        deleted = gone["deleted"] as dict[str, any];
        assert isinstance(deleted, dict);

        # old bearer token is dead: an authenticated call now fails
        cl.set_auth_token(old_token);
        resp = cl.post("/walker/ListPeople", json={});
        assert (not resp.ok) or resp.status_code == 401, f"old token should be rejected, got {resp.status_code} {resp.text}";

        # login with the OLD username/password now fails (row was renamed + repassworded)
        relogin = cl.login(username_a, "password123");
        assert not relogin.ok, "login with old identity should fail after DeleteAccount";

        # the old username is free again: re-registering it succeeds
        again = cl.register_user(username_a, "password456");
        assert again.ok, f"old username should be free to re-register: {again.status_code} {again.text}";
        d2 = again.data or {};
        assert str(d2["root_id"]).replace("-", "") != a["root_id"], "re-registration must be a brand-new root, not the deleted one";

        # B untouched throughout
        cl.set_auth_token(b["token"]);
        b_people = _call(cl, b["token"], "ListPeople", {});
        assert b_people == [];
        still_b = cl.login(username_b, "password123");
        assert still_b.ok;
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "_account_db_path and _disable_identity: no db file yet is a clean false, not a crash" {
    tmp_dir = tempfile.mkdtemp();
    old_cwd = os.getcwd();
    try {
        os.chdir(tmp_dir);
        path = _account_db_path();
        assert path.endswith(os.path.join(".jac", "data", "main.db"));
        assert _disable_identity("nonexistent-root-id") == False;
    } finally {
        os.chdir(old_cwd);
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
