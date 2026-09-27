"""Tests for lifecycle.sv.jac (SOH-220). Deterministic: no model, no network.

In-process blocks build their own Me on the shared persisted test root and
filter by per-run ids. Everything that deletes goes through a throwaway
JacTestClient harness (own temp dir + base_path), never the shared root:
DeleteMyData on the shared test root would wipe every other suite's data.
"""

import from lifecycle {
    active_people, _upload_path_ok, import_audio_ref, clean_name,
    ArchivePerson, RestorePerson, ListArchived, DeleteMyData, ImportGraph
}
import from schema {
    Me, Person, Note, Fact, Knows, Reported, Asserts, FactAbout
}
import from scoring { collect_candidates }
import from tend { _known_people }
import from plan { match_known }
import from health { network_health_for }

import from datetime { datetime }
import from uuid { uuid4 }
import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

# ---------------------------------------------------------------- archived people are invisible

test "archived person drops out of active_people, Tend, GamePlan, ScoreAgainstNeed and NetworkHealth" {
    run = str(uuid4())[:8];
    me = (root ++> Me(name=f"LC Me {run}"))[0];
    note = (root ++> Note(text=f"LC note {run}", kind="debrief", captured_at="2026-09-26T10:00:00"))[0];
    keep = (me +>:Knows(status="confirmed", source_note=jid(note)):+> Person(name=f"Keep {run}", status="confirmed"))[0];
    gone = (me +>:Knows(status="confirmed", source_note=jid(note)):+> Person(name=f"Gone {run}", status="confirmed"))[0];
    for p in [keep, gone] {
        f = (note +>:Asserts(span="builds robots"):+> Fact(text="Builds robots", observed_at="2026-09-26T10:00:00"))[0];
        f +>:FactAbout:+> p;
    }
    keep +>:Reported(source_note=jid(note), span="knows"):+> gone;

    before = [jid(p) for p in active_people(me)];
    assert jid(keep) in before and jid(gone) in before;

    gone.archived = True;

    assert [jid(p) for p in active_people(me)] == [jid(keep)];
    assert jid(gone) not in [jid(p) for p in _known_people(me)];
    assert match_known(me, f"Gone {run}") == [];
    cands = collect_candidates(me, [], datetime.now());
    cand_ids = [jid(c["person"] as Person) for c in cands];
    assert jid(keep) in cand_ids and jid(gone) not in cand_ids;
    health = network_health_for(me);
    assert health["people"] == 1;

    gone.archived = False;
    assert jid(gone) in [jid(p) for p in active_people(me)];
    assert len(match_known(me, f"Gone {run}")) == 1;
}

# ---------------------------------------------------------------- upload path guard

test "_upload_path_ok: flat uploads file or own root dir only; traversal and other roots refused" {
    assert _upload_path_ok("uploads/abc.jpg", "r1");
    assert _upload_path_ok("uploads/r1/a.webm", "r1");
    assert not _upload_path_ok("uploads/r2/a.webm", "r1");
    assert not _upload_path_ok("uploads/../main.jac", "r1");
    assert not _upload_path_ok("uploads/r1/../../main.jac", "r1");
    assert not _upload_path_ok("/etc/passwd", "r1");
    assert not _upload_path_ok("", "r1");
    assert not _upload_path_ok("uploads", "r1");
    assert import_audio_ref("uploads/r1/a.webm", "r1") == "uploads/r1/a.webm";
    assert import_audio_ref("uploads/abc.jpg", "r1") == "";
    assert import_audio_ref("uploads/r2/a.webm", "r1") == "";
    assert clean_name("  Ada   LOVELACE ") == "ada lovelace";
}

# ---------------------------------------------------------------- HTTP harness

glob LC_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _lc_harness(tmp_dir: str) -> str {
    for name in ["lifecycle.sv.jac", "schema.sv.jac", "reads.sv.jac", "export.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(LC_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "lifecycleapp.jac");
    f = open(harness_path, "w");
    f.write(
        "import from lifecycle { ArchivePerson, RestorePerson, ListArchived, DeleteMyData, ImportGraph }\n"
        "import from export { ExportGraph, ExportDevSeed }\n"
        "import from walkers { ListPeople, ListGoals }\n"
        "import from reads { ListPromises }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"lifecycle-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"lifecycleapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _reg(client: JacTestClient, email: str) -> dict[str, str] {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    d = reg.data or {};
    return {"token": str(d["token"]), "root_id": str(d["root_id"]).replace("-", "")};
}

def _call(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

def _write(path: str) {
    os.makedirs(os.path.dirname(path), exist_ok=True);
    f = open(path, "w");
    f.write("lifecycle test upload");
    f.close();
}

def _pairs(rows: list[dict[str, any]], a: str, b: str) -> list[str] {
    return sorted([str(r[a]) + "|" + str(r[b]) for r in rows]);
}

test "lifecycle over HTTP: archive/restore isolation, DeleteMyData wipes only A, ImportGraph round-trips the export" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    run = str(uuid4())[:8];
    made_dirs: list[str] = [];
    try {
        cl = JacTestClient.from_file(_lc_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, f"lc_a_{run}@example.com");
        b = _reg(cl, f"lc_b_{run}@example.com");
        ta = a["token"];
        tb = b["token"];

        seed = _call(cl, ta, "ExportDevSeed", {})[0] as dict[str, any];
        b_seed = _call(cl, tb, "ExportDevSeed", {})[0] as dict[str, any];

        # ---- archive / restore
        arch = _call(cl, ta, "ArchivePerson", {"person_id": seed["p2"]});
        assert len(arch) == 1 and arch[0]["archived"] == True;
        listed = [str(p["_jac_id"]) for p in _call(cl, ta, "ListArchived", {})];
        assert listed == [seed["p2"]];
        rest = _call(cl, ta, "RestorePerson", {"person_id": seed["p2"]});
        assert rest[0]["archived"] == False;
        assert _call(cl, ta, "ListArchived", {}) == [];

        # isolation: B cannot archive A's person, nor A B's
        assert _call(cl, tb, "ArchivePerson", {"person_id": seed["p1"]}) == [{"error": "not_found"}];
        assert _call(cl, ta, "RestorePerson", {"person_id": b_seed["p1"]}) == [{"error": "not_found"}];
        assert _call(cl, tb, "ListArchived", {}) == [];

        e1 = _call(cl, ta, "ExportGraph", {})[0] as dict[str, any];

        # ---- uploads: one own file, one of B's (A tries to point a note at it)
        own_ref = os.path.join("uploads", a["root_id"], f"lc-{run}.txt");
        b_ref = os.path.join("uploads", b["root_id"], f"lc-{run}.txt");
        made_dirs.append(os.path.join("uploads", a["root_id"]));
        made_dirs.append(os.path.join("uploads", b["root_id"]));
        _write(own_ref);
        _write(b_ref);
        up = _call(cl, ta, "ImportGraph", {"data": {"notes": [
            {"id": "n-own", "text": f"LC voice note {run}", "kind": "debrief", "captured_at": "2026-09-26T11:00:00", "audio_ref": own_ref},
            {"id": "n-evil", "text": f"LC evil note {run}", "kind": "debrief", "captured_at": "2026-09-26T11:00:00", "audio_ref": b_ref}
        ]}})[0] as dict[str, any];
        assert (up["imported"] as dict[str, any])["notes"] == 2;

        # ---- DeleteMyData: wrong confirm does nothing
        noop = _call(cl, ta, "DeleteMyData", {"confirm": "delete"})[0] as dict[str, any];
        assert noop["ok"] == False;
        assert len(_call(cl, ta, "ListPeople", {})) == 2;

        gone = _call(cl, ta, "DeleteMyData", {"confirm": "DELETE"})[0] as dict[str, any];
        print(f"[lifecycle] DeleteMyData -> {gone}");
        assert gone["ok"] == True;
        d = gone["deleted"] as dict[str, any];
        assert d["people"] == 2 and d["facts"] == 1 and d["intents"] == 1 and d["promises"] == 1;
        assert d["notes"] == 3 and d["goals"] == 1;
        assert d["files"] == 1;
        assert not os.path.exists(own_ref);
        assert os.path.exists(b_ref);

        # every list walker is empty for A
        assert _call(cl, ta, "ListPeople", {}) == [];
        assert _call(cl, ta, "ListGoals", {}) == [];
        assert _call(cl, ta, "ListPromises", {}) == [];
        assert _call(cl, ta, "ListArchived", {}) == [];
        empty = _call(cl, ta, "ExportGraph", {})[0] as dict[str, any];
        assert empty["me"] is None and empty["people"] == [] and empty["notes"] == [] and empty["facts"] == [];

        # B untouched
        be = _call(cl, tb, "ExportGraph", {})[0] as dict[str, any];
        assert (be["me"] as dict[str, any])["id"] == b_seed["me"];
        assert b_seed["p1"] in [p["id"] for p in (be["people"] as list[dict[str, any]])];
        assert b_seed["fact"] in [f["id"] for f in (be["facts"] as list[dict[str, any]])];
        assert b_seed["note"] in [n["id"] for n in (be["notes"] as list[dict[str, any]])];

        # ---- ImportGraph round trip
        res = _call(cl, ta, "ImportGraph", {"data": e1})[0] as dict[str, any];
        print(f"[lifecycle] ImportGraph -> {res}");
        imp = res["imported"] as dict[str, any];
        c1 = e1["counts"] as dict[str, any];
        for k in ["people", "facts", "intents", "promises", "notes"] {
            assert imp[k] == c1[k], f"{k}: {imp[k]} != {c1[k]}";
        }
        assert res["skipped"] == 0;

        e2 = _call(cl, ta, "ExportGraph", {})[0] as dict[str, any];
        assert e2["counts"] == e1["counts"];
        assert (e2["me"] as dict[str, any])["name"] == (e1["me"] as dict[str, any])["name"];
        assert _pairs(e2["facts"] as list[dict[str, any]], "text", "span") == _pairs(e1["facts"] as list[dict[str, any]], "text", "span");
        assert _pairs(e2["intents"] as list[dict[str, any]], "text", "span") == _pairs(e1["intents"] as list[dict[str, any]], "text", "span");
        assert _pairs(e2["promises"] as list[dict[str, any]], "text", "span") == _pairs(e1["promises"] as list[dict[str, any]], "text", "span");
        assert _pairs(e2["knows"] as list[dict[str, any]], "how_met", "span") == _pairs(e1["knows"] as list[dict[str, any]], "how_met", "span");
        assert _pairs(e2["reported"] as list[dict[str, any]], "span", "span") == _pairs(e1["reported"] as list[dict[str, any]], "span", "span");
        assert sorted([g["text"] for g in (e2["goals"] as list[dict[str, any]])]) == sorted([g["text"] for g in (e1["goals"] as list[dict[str, any]])]);
        # provenance survived: every fact's source_note is an exported note
        note_ids = [n["id"] for n in (e2["notes"] as list[dict[str, any]])];
        for f in (e2["facts"] as list[dict[str, any]]) {
            assert f["source_note"] in note_ids;
        }

        # merge is idempotent: importing the same export again creates nothing
        again = _call(cl, ta, "ImportGraph", {"data": e1})[0] as dict[str, any];
        ai = again["imported"] as dict[str, any];
        assert ai["people"] == 0 and ai["facts"] == 0 and ai["notes"] == 0 and ai["promises"] == 0;

        # unknown ids are skipped and counted, bad mode refused
        junk = _call(cl, ta, "ImportGraph", {"data": {"facts": [{"id": "x", "source_note": "nope", "text": "orphan"}]}})[0] as dict[str, any];
        assert junk["skipped"] == 1;
        assert _call(cl, ta, "ImportGraph", {"data": {}, "mode": "replace"}) == [{"error": "bad_mode"}];

        # B still untouched after A's import
        be2 = _call(cl, tb, "ExportGraph", {})[0] as dict[str, any];
        assert be2["counts"] == be["counts"];
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
        for dd in made_dirs {
            shutil.rmtree(dd, ignore_errors=True);
        }
    }
}
