"""Tests for imports.sv.jac (SOH-180) — ImportPeople, ConfirmPerson, SkipPerson.

Annex to imports.sv.jac — run with `jac test imports.sv.jac`. Deterministic,
no LLM. Per `jac-testing`, tests share one persisted root across runs, so
every name below carries a random per-test suffix (`_uid()`) — this
guarantees a name is always genuinely new, whether this is the first run
ever or the hundredth, and that two tests never collide on the same
lowercase name.
"""

import from imports { ImportPeople, ConfirmPerson, ConfirmPeople, SkipPerson, SkipPeople, row_str, source_display }
import from schema { Me, Person, Note, Knows, Mentions }
import from datetime { datetime }
import uuid;
import os;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

test "row_str: present, missing, and None-valued keys" {
    row: dict[str, any] = {"name": "Maya", "org": None};
    assert row_str(row, "name") == "Maya";
    assert row_str(row, "org") == "";
    assert row_str(row, "title") == "";
}

test "SOH-232 source_display: known sources get a display form, unknown sources pass through unchanged" {
    assert source_display("csv") == "CSV";
    assert source_display("CSV") == "CSV";
    assert source_display("linkedin") == "LinkedIn";
    assert source_display("LinkedIn") == "LinkedIn";
    assert source_display("paste") == "a pasted list";
    assert source_display("vcard") == "a vCard file";
    assert source_display("something_else") == "something_else";
    assert source_display("") == "";
}

test "SOH-232 ImportPeople: the import Note's text uses the display form of the source, not the raw value" {
    suffix = _uid();
    person_name = f"Source-test {suffix} Nguyen";

    r_csv = (root spawn ImportPeople(rows=[{"name": person_name}], source="csv")).reports[0] as dict[str, any];
    note_csv = jobj(r_csv["note_id"] as str) as Note;
    assert note_csv.text == "Imported 1 people from CSV", f"got: {note_csv.text}";

    person_name2 = f"Source-test {suffix} Osei";
    r_li = (root spawn ImportPeople(rows=[{"name": person_name2}], source="linkedin")).reports[0] as dict[str, any];
    note_li = jobj(r_li["note_id"] as str) as Note;
    assert note_li.text == "Imported 1 people from LinkedIn", f"got: {note_li.text}";
}

test "ImportPeople -> ConfirmPerson -> SkipPerson: the full swipe flow" {
    suffix = _uid();
    maya_name = f"Maya {suffix} Chen";
    arjun_name = f"Arjun {suffix} Patel";

    r1 = root spawn ImportPeople(
        rows=[
            {"name": maya_name},
            {"name": maya_name.upper()},
            {"name": ""},
            {"name": arjun_name}
        ],
        source="csv"
    );
    result1 = r1.reports[0] as dict[str, any];

    imported1 = result1["imported"] as list[dict[str, any]];
    skipped1 = result1["skipped"] as list[dict[str, any]];

    assert len(imported1) == 2, f"expected 2 imported new, got {len(imported1)}";
    assert len(skipped1) == 2, f"expected 2 skipped, got {skipped1}";

    reasons = [s["reason"] for s in skipped1];
    assert "empty_name" in reasons;
    assert "duplicate_in_batch" in reasons;

    by_name: dict[str, dict[str, any]] = {};
    for entry in imported1 {
        p = entry["person"] as Person;
        by_name[p.name] = entry;
    }

    assert maya_name in by_name;
    assert arjun_name in by_name;
    assert by_name[maya_name]["is_new"];
    assert by_name[arjun_name]["is_new"];

    maya = by_name[maya_name]["person"] as Person;
    arjun = by_name[arjun_name]["person"] as Person;

    assert maya.status == "proposed";
    assert arjun.status == "proposed";

    note_id = result1["note_id"] as str;
    note = jobj(note_id) as Note;
    mentions: list[Person] = [note ->:Mentions:->];
    mention_ids = [jid(m) for m in mentions];
    assert jid(maya) in mention_ids;
    assert jid(arjun) in mention_ids;

    existing_me = [root --> [?:Me]];
    assert existing_me;
    me = existing_me[0];

    maya_edge = ([edge me ->:Knows:-> maya])[0];
    arjun_edge = ([edge me ->:Knows:-> arjun])[0];
    assert maya_edge.status == "proposed";
    assert arjun_edge.status == "proposed";
    assert maya_edge.source_note == note_id;

    # Re-import "Maya ... Chen" with an org: reused, not duplicated; org gets
    # filled in because it was previously empty; still exactly 2 known people.
    r2 = root spawn ImportPeople(rows=[{"name": maya_name, "org": "Acme Robotics"}], source="csv");
    result2 = r2.reports[0] as dict[str, any];
    imported2 = result2["imported"] as list[dict[str, any]];
    assert len(imported2) == 1;
    assert not imported2[0]["is_new"], "re-importing an existing name must reuse, not duplicate";
    maya_again = imported2[0]["person"] as Person;
    assert jid(maya_again) == jid(maya);
    assert maya_again.org == "Acme Robotics";

    # Per jac-testing: root is shared and persists across runs, so count only
    # this test's own two people, not everyone ever known to the shared Me.
    known_after_reimport: list[Person] = [me ->:Knows:->];
    mine_after_reimport = [p for p in known_after_reimport if p.name in [maya_name, arjun_name]];
    assert len(mine_after_reimport) == 2, "reusing an existing name must not grow the known-people count";

    # ConfirmPerson(maya) -> confirmed on both node and edge.
    r3 = root spawn ConfirmPerson(person_id=jid(maya), how_met="met at JacHacks");
    confirmed = r3.reports[0] as Person;
    assert confirmed.status == "confirmed";
    maya_edge_after = ([edge me ->:Knows:-> maya])[0];
    assert maya_edge_after.status == "confirmed";
    assert maya_edge_after.how_met == "met at JacHacks";

    # SkipPerson(maya) now fails: maya is confirmed, not proposed.
    r4 = root spawn SkipPerson(person_id=jid(maya));
    err4 = r4.reports[0] as dict[str, any];
    assert err4["error"] == "not_proposed";

    # SkipPerson(arjun) succeeds: arjun is still proposed.
    arjun_id = jid(arjun);
    r5 = root spawn SkipPerson(person_id=arjun_id);
    assert r5.reports[0] == "skipped";

    known_after_skip: list[Person] = [me ->:Knows:->];
    remaining_names = [p.name for p in known_after_skip if p.name in [maya_name, arjun_name]];
    assert remaining_names == [maya_name], f"expected only Maya left among this test's people, got {remaining_names}";

    # The skipped Person node and its Mentions edge are gone.
    arjun_still_resolves = True;
    try {
        gone = jobj(arjun_id);
        arjun_still_resolves = gone is not None;
    } except Exception {
        arjun_still_resolves = False;
    }
    assert not arjun_still_resolves, "SkipPerson must delete the Person node";
    mentions_after_skip: list[Person] = [note ->:Mentions:->];
    mention_ids_after_skip = [jid(m) for m in mentions_after_skip];
    assert arjun_id not in mention_ids_after_skip;
    assert jid(maya) in mention_ids_after_skip;

    # ConfirmPerson(random id) -> not_found.
    r6 = root spawn ConfirmPerson(person_id="not-a-real-jid");
    err6 = r6.reports[0] as dict[str, any];
    assert err6["error"] == "not_found";
}

test "ImportPeople: email/phone/location (SOH-216) kept on a new person, filled-when-blank on reuse" {
    suffix = _uid();
    name = f"Priya {suffix} Sundaram";

    r1 = root spawn ImportPeople(
        rows=[{"name": name, "email": "priya@example.com", "phone": "555-0100", "location": "Ann Arbor"}],
        source="csv"
    );
    result1 = r1.reports[0] as dict[str, any];
    imported1 = result1["imported"] as list[dict[str, any]];
    assert len(imported1) == 1;
    p = imported1[0]["person"] as Person;
    assert p.email == "priya@example.com";
    assert p.phone == "555-0100";
    assert p.location == "Ann Arbor";

    # Re-import the same name with a location only: email/phone (already
    # set) are left alone; location (already set) is ALSO left alone -
    # fill-blank-only, same rule org/title already use.
    r2 = root spawn ImportPeople(
        rows=[{"name": name, "location": "Detroit"}],
        source="csv"
    );
    result2 = r2.reports[0] as dict[str, any];
    imported2 = result2["imported"] as list[dict[str, any]];
    assert len(imported2) == 1;
    p_again = imported2[0]["person"] as Person;
    assert jid(p_again) == jid(p);
    assert p_again.email == "priya@example.com", "reuse must never overwrite an existing non-blank field";
    assert p_again.location == "Ann Arbor", "reuse must never overwrite an existing non-blank field";

    # A second, previously-blank person: reuse fills email from the row.
    suffix2 = _uid();
    name2 = f"Dana {suffix2} Osei";
    seed = root spawn ImportPeople(rows=[{"name": name2}], source="csv");
    seed_result = seed.reports[0] as dict[str, any];
    seeded_person = (seed_result["imported"] as list[dict[str, any]])[0]["person"] as Person;
    assert seeded_person.email == "";

    fill = root spawn ImportPeople(rows=[{"name": name2, "phone": "555-0200"}], source="csv");
    fill_result = fill.reports[0] as dict[str, any];
    filled_person = (fill_result["imported"] as list[dict[str, any]])[0]["person"] as Person;
    assert jid(filled_person) == jid(seeded_person);
    assert filled_person.phone == "555-0200";
}

test "ImportPeople: over-limit rows are bounded and reported as skipped" {
    suffix = _uid();
    rows: list[dict[str, any]] = [];
    for i in range(501) {
        rows.append({"name": f"Bulk {suffix} {i}"});
    }

    result = (root spawn ImportPeople(rows=rows, source="csv")).reports[0] as dict[str, any];
    imported = result["imported"] as list[dict[str, any]];
    skipped = result["skipped"] as list[dict[str, any]];

    assert len(imported) == 500, f"expected the 500-row bound to hold, got {len(imported)}";
    over_limit = [s for s in skipped if s["reason"] == "over_limit"];
    assert len(over_limit) == 1, f"expected exactly 1 row past the bound, got {len(over_limit)}";
}

test "SkipPerson / ConfirmPerson: unknown person_id -> not_found" {
    r1 = root spawn SkipPerson(person_id="definitely-not-a-jid");
    err1 = r1.reports[0] as dict[str, any];
    assert err1["error"] == "not_found";

    r2 = root spawn ConfirmPerson(person_id="definitely-not-a-jid");
    err2 = r2.reports[0] as dict[str, any];
    assert err2["error"] == "not_found";
}

test "SOH-226 ImportPeople: last_contact=now on a NEW Knows edge only; a reused edge's last_contact is left untouched" {
    suffix = _uid();
    name = f"Ravi {suffix} Iyer";

    before = datetime.now();
    r1 = root spawn ImportPeople(rows=[{"name": name}], source="csv");
    after = datetime.now();
    result1 = r1.reports[0] as dict[str, any];
    p = (result1["imported"] as list[dict[str, any]])[0]["person"] as Person;

    existing_me = [root --> [?:Me]];
    assert existing_me;
    me = existing_me[0];
    edge1 = ([edge me ->:Knows:-> p])[0];
    assert edge1.last_contact != "", "a NEW Knows edge from ImportPeople must get last_contact=now";
    lc_dt = datetime.fromisoformat(edge1.last_contact);
    assert lc_dt >= before and lc_dt <= after, f"last_contact must be 'now' at import time, got {edge1.last_contact}";

    # Re-import the same person: reused edge's last_contact is untouched (still
    # whatever it was, never forced to "now" again on a plain enrichment pass).
    original_last_contact = edge1.last_contact;
    r2 = root spawn ImportPeople(rows=[{"name": name, "org": "Acme"}], source="csv");
    result2 = r2.reports[0] as dict[str, any];
    p_again = (result2["imported"] as list[dict[str, any]])[0]["person"] as Person;
    assert jid(p_again) == jid(p);
    edge2 = ([edge me ->:Knows:-> p_again])[0];
    assert edge2.last_contact == original_last_contact, "reusing an existing Knows edge must not touch last_contact";
}

test "SOH-212 ImportPeople: 26 genuinely new rows all report is_new=true; the same rows re-imported report false" {
    tag = uuid.uuid4().hex[:8];
    rows: list[dict[str, str]] = [];
    for i in range(26) {
        rows.append({"name": f"Marcus212 Row{i} {tag}", "org": "Acme", "how_met": "linkedin"});
    }
    first = (root spawn ImportPeople(rows=rows, source="linkedin csv")).reports[0] as dict[str, any];
    imported = first["imported"] as list[dict[str, any]];
    assert len(imported) == 26;
    flags = [e["is_new"] as bool for e in imported];
    assert all(flags), f"every genuinely new row must be is_new=true, got {flags}";

    again = (root spawn ImportPeople(rows=rows[:3], source="linkedin csv")).reports[0] as dict[str, any];
    reused = again["imported"] as list[dict[str, any]];
    assert len(reused) == 3;
    assert not any([e["is_new"] as bool for e in reused]), "a reused name is is_new=false";
}

# ---------------------------------------------------------------- ConfirmPeople (SOH-235)

test "SOH-235 ConfirmPeople: bulk-confirms three proposed people in one call" {
    suffix = _uid();
    rows: list[dict[str, any]] = [];
    for i in range(3) {
        rows.append({"name": f"Bulk235 {suffix} {i}"});
    }
    imported_result = (root spawn ImportPeople(rows=rows, source="csv")).reports[0] as dict[str, any];
    imported = imported_result["imported"] as list[dict[str, any]];
    assert len(imported) == 3;
    ids = [jid(e["person"] as Person) for e in imported];

    result = (root spawn ConfirmPeople(person_ids=ids, how_met="met at JacHacks")).reports[0] as dict[str, any];
    assert result["count"] == 3, f"expected count 3, got {result}";
    assert result["confirmed"] == ids, "confirmed order must follow person_ids";
    assert result["not_found"] == [];

    for e in imported {
        p = e["person"] as Person;
        assert p.status == "confirmed";
    }

    existing_me = [root --> [?:Me]];
    assert existing_me;
    me = existing_me[0];
    for e in imported {
        p = e["person"] as Person;
        ke = ([edge me ->:Knows:-> p])[0];
        assert ke.status == "confirmed";
        assert ke.how_met == "met at JacHacks";
    }

    # Re-confirming the same batch is idempotent: still counted as confirmed.
    result2 = (root spawn ConfirmPeople(person_ids=ids)).reports[0] as dict[str, any];
    assert result2["count"] == 3;
    assert result2["confirmed"] == ids;
}

test "SOH-235 ConfirmPeople: a bogus id lands in not_found alongside real confirms" {
    suffix = _uid();
    name = f"Bulk235B {suffix} Solo";
    r1 = (root spawn ImportPeople(rows=[{"name": name}], source="csv")).reports[0] as dict[str, any];
    imported = r1["imported"] as list[dict[str, any]];
    assert len(imported) == 1;
    real_id = jid(imported[0]["person"] as Person);
    bogus_id = "not-a-real-jid-at-all";

    result = (root spawn ConfirmPeople(person_ids=[real_id, bogus_id])).reports[0] as dict[str, any];
    assert result["count"] == 1, f"expected count 1, got {result}";
    assert result["confirmed"] == [real_id];
    assert result["not_found"] == [bogus_id];
}

# ---------------------------------------------------------------- SkipPeople (SOH-236)

test "SOH-236 SkipPeople: skips proposed people in one call; a confirmed person lands in not_found" {
    suffix = _uid();
    rows: list[dict[str, any]] = [];
    for i in range(3) {
        rows.append({"name": f"Skip236 {suffix} {i}"});
    }
    imported_result = (root spawn ImportPeople(rows=rows, source="csv")).reports[0] as dict[str, any];
    imported = imported_result["imported"] as list[dict[str, any]];
    assert len(imported) == 3;
    ids = [jid(e["person"] as Person) for e in imported];

    # Confirm the last one so it is no longer "proposed" — SkipPeople must
    # refuse it (same rule SkipPerson already enforces on a single id).
    confirmed_id = ids[2];
    confirm_out = (root spawn ConfirmPerson(person_id=confirmed_id)).reports[0];
    assert isinstance(confirm_out, Person);

    result = (root spawn SkipPeople(person_ids=ids)).reports[0] as dict[str, any];
    assert result["count"] == 2, f"expected count 2, got {result}";
    assert result["skipped"] == [ids[0], ids[1]], "skipped order must follow person_ids";
    assert result["not_found"] == [confirmed_id], "the confirmed person must not be skippable";

    existing_me = [root --> [?:Me]];
    assert existing_me;
    me = existing_me[0];
    known_ids = [jid(p) for p in [me ->:Knows:->]];
    assert ids[0] not in known_ids, "a skipped person's Knows edge/node must be gone";
    assert ids[1] not in known_ids, "a skipped person's Knows edge/node must be gone";
    assert confirmed_id in known_ids, "the confirmed person must be untouched";
}

test "SOH-236 SkipPeople: a bogus id lands in not_found alongside a real skip" {
    suffix = _uid();
    name = f"Skip236B {suffix} Solo";
    r1 = (root spawn ImportPeople(rows=[{"name": name}], source="csv")).reports[0] as dict[str, any];
    imported = r1["imported"] as list[dict[str, any]];
    assert len(imported) == 1;
    real_id = jid(imported[0]["person"] as Person);
    bogus_id = "not-a-real-jid-at-all";

    result = (root spawn SkipPeople(person_ids=[real_id, bogus_id])).reports[0] as dict[str, any];
    assert result["count"] == 1, f"expected count 1, got {result}";
    assert result["skipped"] == [real_id];
    assert result["not_found"] == [bogus_id];
}

# ---------------------------------------------------------------- ConfirmPeople isolation (two real roots)

import from jaclang.runtimelib.testing { JacTestClient }
import shutil;
import tempfile;

glob IMPORTS_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

"""Copy imports.sv.jac's whole import chain (schema, identity, names) plus
walkers.sv.jac (for `ListPeople`, used to check a person's status without
crossing accounts) into a fresh temp dir next to a dot-free `app.jac` —
`JacTestClient.from_file` can't target a dotted `*.sv.jac` module name
directly (AGENTS.md gotcha). Same approach `person.test.jac`/`gate.test.jac`
already use."""
def _confirm_bulk_harness(tmp_dir: str) -> str {
    for name in ["schema.sv.jac", "names.sv.jac", "identity.sv.jac", "imports.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(IMPORTS_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from imports { ImportPeople, ConfirmPeople, SkipPeople }\n"
        "import from walkers { ListPeople }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"imports-bulk-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _confirm_bulk_register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _confirm_bulk_call(client: JacTestClient, token: str, wname: str, body: dict[str, any]) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "SOH-235 isolation: an id from account B is not_found when confirmed via A's root; B's person stays proposed" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_confirm_bulk_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _confirm_bulk_register(cl, "confirm_bulk_a@example.com");
        b = _confirm_bulk_register(cl, "confirm_bulk_b@example.com");

        b_imported = _confirm_bulk_call(cl, b, "ImportPeople", {
            "rows": [{"name": "Bulk235 Isolation Target"}], "source": "csv"
        });
        b_result = b_imported[0] as dict[str, any];
        b_person_id = str(((b_result["imported"] as list[any])[0] as dict[str, any])["person"]["_jac_id"]);
        print(f"[confirm bulk isolation] B seeded person_id={b_person_id}");

        a_confirm = _confirm_bulk_call(cl, a, "ConfirmPeople", {"person_ids": [b_person_id]});
        a_out = a_confirm[0] as dict[str, any];
        print(f"[confirm bulk isolation] A's ConfirmPeople on B's person -> {a_out}");
        assert a_out["count"] == 0, f"A must never confirm B's person: {a_out}";
        assert a_out["confirmed"] == [];
        assert a_out["not_found"] == [b_person_id];

        b_people = _confirm_bulk_call(cl, b, "ListPeople", {});
        b_row = b_people[0] as dict[str, any];
        print(f"[confirm bulk isolation] B's own ListPeople after A's attempt -> {b_row}");
        assert b_row["status"] == "proposed", "B's person must stay proposed after A's failed cross-root confirm";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "SOH-236 isolation: an id from account B is not_found when skipped via A's root; B's person stays proposed" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_confirm_bulk_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _confirm_bulk_register(cl, "skip_bulk_a@example.com");
        b = _confirm_bulk_register(cl, "skip_bulk_b@example.com");

        b_imported = _confirm_bulk_call(cl, b, "ImportPeople", {
            "rows": [{"name": "Skip236 Isolation Target"}], "source": "csv"
        });
        b_result = b_imported[0] as dict[str, any];
        b_person_id = str(((b_result["imported"] as list[any])[0] as dict[str, any])["person"]["_jac_id"]);
        print(f"[skip bulk isolation] B seeded person_id={b_person_id}");

        a_skip = _confirm_bulk_call(cl, a, "SkipPeople", {"person_ids": [b_person_id]});
        a_out = a_skip[0] as dict[str, any];
        print(f"[skip bulk isolation] A's SkipPeople on B's person -> {a_out}");
        assert a_out["count"] == 0, f"A must never skip B's person: {a_out}";
        assert a_out["skipped"] == [];
        assert a_out["not_found"] == [b_person_id];

        b_people = _confirm_bulk_call(cl, b, "ListPeople", {});
        b_row = b_people[0] as dict[str, any];
        print(f"[skip bulk isolation] B's own ListPeople after A's attempt -> {b_row}");
        assert b_row["status"] == "proposed", "B's person must stay proposed (and present) after A's failed cross-root skip";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
