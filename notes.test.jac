"""Tests for notes.sv.jac (SOH-219) — timeline, deletion, confirmation, digest.

Annex to notes.sv.jac — run with `jac test notes.sv.jac`. Deterministic
only: no LLM, no network (`digest_for` calls `tend_for`/`upcoming_dates_for`,
neither of which ever calls a model).

`jac test notes.sv.jac` also runs the test files of every module notes.sv.jac
imports (`forget`, `dates`, `goals`, `tend` — AGENTS.md's "jac test X.sv.jac
also runs the test files of modules X imports" gotcha) against the same
shared, persisted root (`jac-testing`). `list_notes_for`/`_delete_note_for`/
`digest_for` are exercised directly on hand-built `notes`/`me` (never through
`root spawn ListNotes(...)`/`Digest(...)`), same reason `tend.test.jac`
documents: the walkers' own `[root --> [?:Me]][0]` pick is ambiguous once
more than one test has created a `Me` on the shared root. The two walker
tests that DO go through `root spawn` (`ConfirmFact`/`DeleteNote`'s
`not_found` path) don't depend on which `Me` gets picked.

The cross-root isolation negative for `DeleteNote`/`ConfirmFact` needs two
real, separate roots, so it runs through a `JacTestClient` harness — same
approach `edits.test.jac`/`gate.test.jac` use: `JacTestClient.from_file`
can't target a dotted `*.sv.jac` module directly, so the harness copies
notes.sv.jac's whole import chain (`schema`, `llm`, `goals`, `tend`,
`forget`, `dates`, `notes`) into a fresh temp dir next to a dot-free
`app.jac`, and gives the client its own `base_path`. No `jac clean`
anywhere.
"""

import from notes { ListNotes, DeleteNote, ConfirmFact, Digest, list_notes_for, _delete_note_for, digest_for }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal,
    Knows, Asserts, AssertsIntent, AssertsPromise, Mentions, FactAbout, IntentAbout, PromiseTo, HasGoal
}
import from datetime { datetime, timedelta }
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

# ---------------------------------------------------------------- ListNotes / list_notes_for

test "list_notes_for: newest first, kind filter, before cursor, limit, and item shape" {
    suffix = _uid();
    now = datetime(2026, 9, 26, 12, 0, 0);

    n1 = (root ++> Note(text=f"Notes-test note one {suffix}", kind="debrief", captured_at=(now - timedelta(days=2)).isoformat()))[0];
    n2 = (root ++> Note(text=f"Notes-test note two {suffix}", kind="paste", captured_at=(now - timedelta(days=1)).isoformat()))[0];
    n3 = (root ++> Note(text=f"Notes-test note three {suffix}", kind="debrief", captured_at=now.isoformat()))[0];

    me = (root ++> Me(name=f"Notes-test List Me {suffix}"))[0];
    p = (me +>:Knows(status="confirmed"):+> Person(name=f"Notes-test List Person {suffix}", status="confirmed"))[0];
    n3 +>:Mentions(span="mentioned"):+> p;
    f = (root ++> Fact(text=f"Notes-test list fact {suffix}", observed_at=now.isoformat()))[0];
    n3 +>:Asserts(span="a fact"):+> f;

    notes = [n1, n2, n3];

    ordered = list_notes_for(notes, 50, "", "");
    ids_in_order = [(it["note"] as Note).text for it in ordered if (it["note"] as Note) in notes];
    assert ids_in_order == [n3.text, n2.text, n1.text], "newest captured_at first";

    only_debrief = list_notes_for(notes, 50, "", "debrief");
    debrief_ids = [jid(it["note"] as Note) for it in only_debrief];
    assert jid(n3) in debrief_ids and jid(n1) in debrief_ids;
    assert jid(n2) not in debrief_ids;

    before_n3 = list_notes_for(notes, 50, n3.captured_at, "");
    before_ids = [jid(it["note"] as Note) for it in before_n3];
    assert jid(n3) not in before_ids, "cursor excludes the note captured exactly at the cursor";
    assert jid(n2) in before_ids and jid(n1) in before_ids;

    limited = list_notes_for(notes, 1, "", "");
    assert len(limited) == 1;
    assert (limited[0]["note"] as Note) == n3;

    n3_item = ordered[0];
    assert n3_item["counts"] == {"facts": 1, "intents": 0, "promises": 0};
    people = n3_item["people"] as list[dict[str, str]];
    assert len(people) == 1 and people[0]["name"] == p.name;
    assert n3_item["text_preview"] == n3.text, "short text is returned as-is";
}

test "list_notes_for: text_preview cuts long text on a word boundary" {
    long_text = "word " * 40;
    note = (root ++> Note(text=long_text, kind="debrief", captured_at=datetime.now().isoformat()))[0];
    ordered = list_notes_for([note], 50, "", "");
    preview = ordered[0]["text_preview"] as str;
    assert len(preview) <= 141;
    assert preview.endswith("…");
}

# ---------------------------------------------------------------- DeleteNote / _delete_note_for

test "_delete_note_for: deletes the solely-asserted fact/intent/promise, keeps a shared fact and every person" {
    suffix = _uid();
    now = datetime.now().isoformat();

    me = (root ++> Me(name=f"Notes-test Delete Me {suffix}"))[0];
    p = (me +>:Knows(status="confirmed"):+> Person(name=f"Notes-test Delete Person {suffix}", status="confirmed"))[0];

    note_keep = (root ++> Note(text=f"Notes-test keep note {suffix}", kind="debrief", captured_at=now))[0];
    note_doomed = (root ++> Note(text=f"Notes-test doomed note {suffix}", kind="debrief", captured_at=now))[0];

    shared_fact = (root ++> Fact(text=f"Notes-test shared fact {suffix}", observed_at=now))[0];
    note_keep +>:Asserts(span="shared"):+> shared_fact;
    note_doomed +>:Asserts(span="shared"):+> shared_fact;
    shared_fact +>:FactAbout:+> p;

    solo_fact = (root ++> Fact(text=f"Notes-test solo fact {suffix}", observed_at=now))[0];
    note_doomed +>:Asserts(span="solo"):+> solo_fact;
    solo_fact +>:FactAbout:+> p;

    solo_intent = (root ++> Intent(kind="need", text=f"Notes-test solo intent {suffix}"))[0];
    note_doomed +>:AssertsIntent(span="solo intent"):+> solo_intent;
    solo_intent +>:IntentAbout:+> p;

    solo_promise = (root ++> Promise(text=f"Notes-test solo promise {suffix}"))[0];
    note_doomed +>:AssertsPromise(span="solo promise"):+> solo_promise;
    solo_promise +>:PromiseTo:+> p;

    note_doomed +>:Mentions(span="mentioned"):+> p;

    doomed_id = jid(note_doomed);
    solo_fact_id = jid(solo_fact);
    solo_intent_id = jid(solo_intent);
    solo_promise_id = jid(solo_promise);
    shared_fact_id = jid(shared_fact);

    result = _delete_note_for(note_doomed);
    assert result["deleted"] == {"facts": 1, "intents": 1, "promises": 1};
    assert result["kept_people"] == 1;

    try {
        _ = jobj(doomed_id);
        assert False, "the deleted Note must be gone";
    } except Exception {
        assert True;
    }
    try {
        _ = jobj(solo_fact_id);
        assert False, "the solely-asserted fact must be gone";
    } except Exception {
        assert True;
    }
    try {
        _ = jobj(solo_intent_id);
        assert False, "the solely-asserted intent must be gone";
    } except Exception {
        assert True;
    }
    try {
        _ = jobj(solo_promise_id);
        assert False, "the solely-asserted promise must be gone";
    } except Exception {
        assert True;
    }

    still_shared = jobj(shared_fact_id);
    assert still_shared is not None, "a fact another note also asserts survives";
    assert isinstance(still_shared, Fact);

    p_id = jid(p);
    still_person = jobj(p_id);
    assert still_person is not None and isinstance(still_person, Person), "the person is never deleted";
    assert p in [me ->:Knows:->], "the Knows edge to the person survives too";
}

test "ConfirmFact: flips status to confirmed" {
    now = datetime.now().isoformat();
    note = (root ++> Note(text="Notes-test confirm note", kind="debrief", captured_at=now))[0];
    f = (root ++> Fact(text="Notes-test confirm fact", observed_at=now, status="reported"))[0];
    note +>:Asserts(span="a fact"):+> f;

    result = root spawn ConfirmFact(fact_id=jid(f));
    out = result.reports[0] as Fact;
    assert out.status == "confirmed";
}

test "ConfirmFact: unknown fact_id reports not_found" {
    result = root spawn ConfirmFact(fact_id="not-a-real-fact-id-at-all");
    assert result.reports == [{"error": "not_found"}];
}

test "DeleteNote: unknown note_id reports not_found" {
    result = root spawn DeleteNote(note_id="not-a-real-note-id-at-all");
    assert result.reports == [{"error": "not_found"}];
}

# ---------------------------------------------------------------- Digest / digest_for

test "digest_for: shape, five lines, and stale_ranking false with no active goal" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Notes-test Digest Me"))[0];

    result = digest_for(me, [], now);
    assert result["week_of"] == "2026-09-21", "Monday of that week";
    assert result["promises_due"] == [];
    assert result["intents_expiring"] == [];
    assert result["new_people"] == [];
    assert not result["stale_ranking"];
    assert result["suggestions"] == [];
    lines = result["lines"] as list[str];
    assert len(lines) == 5;
}

test "digest_for: new_people counts a Knows created in the last 7 days, not older ones" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Notes-test Digest Me 2"))[0];

    note_recent = (root ++> Note(text="Notes-test digest recent", kind="debrief", captured_at=(now - timedelta(days=2)).isoformat()))[0];
    p_recent = (me +>:Knows(status="confirmed", how_met="from a debrief", source_note=jid(note_recent)):+> Person(name="Notes-test Digest Recent Person", status="confirmed"))[0];

    note_old = (root ++> Note(text="Notes-test digest old", kind="debrief", captured_at=(now - timedelta(days=30)).isoformat()))[0];
    p_old = (me +>:Knows(status="confirmed", how_met="from a debrief", source_note=jid(note_old)):+> Person(name="Notes-test Digest Old Person", status="confirmed"))[0];

    result = digest_for(me, [note_recent, note_old], now);
    new_people = result["new_people"] as list[dict[str, any]];
    names = [it["name"] for it in new_people];
    assert p_recent.name in names;
    assert p_old.name not in names;
}

test "digest_for: stale_ranking true when the active Goal's ranked_at predates the newest note" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Notes-test Digest Me 3"))[0];
    _ = (me +>:HasGoal:+> Goal(text="Notes-test digest goal", created_at=(now - timedelta(days=10)).isoformat(), active=True, ranked_at=(now - timedelta(days=5)).isoformat()))[0];
    note = (root ++> Note(text="Notes-test digest goal note", kind="debrief", captured_at=now.isoformat()))[0];

    result = digest_for(me, [note], now);
    assert result["stale_ranking"];
}

# ---------------------------------------------------------------- isolation (two real roots)

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

glob NOTES_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

"""Copy notes.sv.jac's whole import chain into a fresh temp dir next to a
dot-free `app.jac` — `JacTestClient.from_file` can't target a dotted
`*.sv.jac` module name directly (AGENTS.md gotcha)."""
def _notes_harness(tmp_dir: str) -> str {
    for name in ["schema.sv.jac", "llm.sv.jac", "goals.sv.jac", "tend.sv.jac", "forget.sv.jac", "dates.sv.jac", "notes.sv.jac"] {
        shutil.copyfile(os.path.join(NOTES_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from notes { ListNotes, DeleteNote, ConfirmFact, Digest, DevSeedNote }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"notes-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _notes_register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _notes_call(client: JacTestClient, token: str, wname: str, body: dict[str, any]) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "isolation: A's note is not_found from B's DeleteNote, deletable from A's own" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_notes_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _notes_register(cl, "notes_a@example.com");
        b = _notes_register(cl, "notes_b@example.com");

        seeded = _notes_call(cl, a, "DevSeedNote", {"text": "Notes-test isolation delete seed"});
        note_id = str(seeded[0]["note_id"]);
        print(f"[notes isolation] A seeded note_id={note_id}");

        b_delete = _notes_call(cl, b, "DeleteNote", {"note_id": note_id});
        print(f"[notes isolation] B's DeleteNote on A's note -> {b_delete}");
        assert b_delete == [{"error": "not_found"}], f"B must never delete A's note: {b_delete}";

        a_delete = _notes_call(cl, a, "DeleteNote", {"note_id": note_id});
        print(f"[notes isolation] A's own DeleteNote -> {a_delete}");
        a_entry = a_delete[0] as dict[str, any];
        assert "error" not in a_entry, f"A must be able to delete its own note: {a_delete}";
        assert a_entry["kept_people"] == 1;
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "isolation: A's fact is not_found from B's ConfirmFact, confirmable from A's own" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_notes_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _notes_register(cl, "notes_a2@example.com");
        b = _notes_register(cl, "notes_b2@example.com");

        seeded = _notes_call(cl, a, "DevSeedNote", {"text": "Notes-test isolation confirm seed"});
        fact_id = str(seeded[0]["fact_id"]);
        print(f"[notes isolation] A seeded fact_id={fact_id}");

        b_confirm = _notes_call(cl, b, "ConfirmFact", {"fact_id": fact_id});
        print(f"[notes isolation] B's ConfirmFact on A's fact -> {b_confirm}");
        assert b_confirm == [{"error": "not_found"}], f"B must never confirm A's fact: {b_confirm}";

        a_confirm = _notes_call(cl, a, "ConfirmFact", {"fact_id": fact_id});
        print(f"[notes isolation] A's own ConfirmFact -> {a_confirm}");
        a_entry = a_confirm[0] as dict[str, any];
        assert str(a_entry["status"]) == "confirmed", f"A must be able to confirm its own fact: {a_confirm}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
