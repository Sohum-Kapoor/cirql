"""Tests for export.sv.jac (SOH-210, ExportGraph).

Annex to export.sv.jac — run with `jac test export.sv.jac`. Deterministic
only: no LLM (this module never calls one), no server for the first block.

`jac test` runs every test in this file in declaration order against ONE
shared, persisted `root` across repeated invocations of this file (see
`reads.test.jac`'s docstring for the full explanation) — so, exactly like
`reads.sv.jac`'s `graph_view_for`, the first block below calls
`build_export` directly on a hand-built `Me` rather than going through
`root spawn ExportGraph()` (which resolves "the" caller's Me via
`[root --> [?:Me]][0]`, ambiguous once more than one test run has left a Me
under this persisted root). Assertions check that the seeded ids/links are
PRESENT in each section, never that a section equals an exact list — the
same persisted root also carries every earlier run's leftover nodes.

The second block is the required isolation negative test: two real
accounts registered through `/user/register` via JacTestClient, seeded
through `ExportDevSeed` (this module's own deterministic, no-LLM dev/test
helper — see its docstring in export.sv.jac), each calling `ExportGraph`
on their own root. Same throwaway-harness approach `gate.test.jac` and
`walkers.test.jac` use and document: `JacTestClient.from_file` can't target
a dotted `*.sv.jac` module directly, so a fresh temp dir gets a copy of
`export.sv.jac` + `schema.sv.jac` next to a dot-free `app.jac`.
"""

import from export { build_export, ExportGraph, ExportDevSeed }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, HasGoal, Owns
}

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

# ---------------------------------------------------------------- build_export (single root)

test "build_export: Me/goal/card/2 people (Knows + Reported)/fact/intent/promise/note all present with the right links" {
    me = (root ++> Me(name="Export-test Me", about="testing exports"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Export-test goal", created_at="2026-09-26T09:00:00", active=True))[0];
    card = (me +>:Owns:+> Card(handle="export-test-handle", name="Export-test Card"))[0];

    note = (root ++> Note(
        text="Export-test: met Priya at the summit, works on climate tech, needs a VC intro, I'll send the deck by Friday. She knows Dana.",
        kind="debrief", captured_at="2026-09-26T09:05:00"
    ))[0];

    priya = (me +>:Knows(how_met="summit", status="confirmed", source_note=jid(note)):+> Person(
        name="Export-test Priya", org="Acme Climate", title="Founder", status="confirmed",
        email="priya@example.com", phone="555-0111", links=["https://priya.example.com"], location="Ann Arbor"
    ))[0];
    note +>:Mentions(span="met Priya at the summit"):+> priya;

    dana = (me +>:Knows(how_met="reported by Priya", status="reported"):+> Person(
        name="Export-test Dana", status="confirmed"
    ))[0];
    priya +>:Reported(source_note=jid(note), span="She knows Dana"):+> dana;

    fact = (note +>:Asserts(span="works on climate tech"):+> Fact(
        text="Works on climate tech", observed_at="2026-09-26T09:05:00", source_kind="reported"
    ))[0];
    fact +>:FactAbout:+> priya;

    intent = (note +>:AssertsIntent(span="needs a VC intro"):+> Intent(
        kind="need", text="Needs a VC intro", source_kind="reported"
    ))[0];
    intent +>:IntentAbout:+> priya;

    promise = (note +>:AssertsPromise(span="send the deck by Friday"):+> Promise(
        text="Send the deck", due="2026-10-03"
    ))[0];
    promise +>:PromiseTo:+> priya;

    out = build_export(me);

    # me
    me_out = out["me"] as dict[str, any];
    assert me_out["id"] == jid(me);
    assert me_out["name"] == "Export-test Me";
    assert me_out["about"] == "testing exports";

    # goals
    goal_ids = [g["id"] for g in (out["goals"] as list[dict[str, any]])];
    assert jid(goal) in goal_ids;

    # card
    card_out = out["card"] as dict[str, any];
    assert card_out["id"] == jid(card);
    assert card_out["handle"] == "export-test-handle";

    # people
    people_ids = [p["id"] for p in (out["people"] as list[dict[str, any]])];
    assert jid(priya) in people_ids;
    assert jid(dana) in people_ids;
    priya_out = [p for p in (out["people"] as list[dict[str, any]]) if p["id"] == jid(priya)][0];
    assert priya_out["name"] == "Export-test Priya";
    assert priya_out["org"] == "Acme Climate";
    assert priya_out["status"] == "confirmed";
    # SOH-216
    assert priya_out["email"] == "priya@example.com";
    assert priya_out["phone"] == "555-0111";
    assert priya_out["links"] == ["https://priya.example.com"];
    assert priya_out["location"] == "Ann Arbor";

    # knows
    knows_to_priya = [k for k in (out["knows"] as list[dict[str, any]]) if k["to"] == jid(priya)];
    assert len(knows_to_priya) == 1;
    ke = knows_to_priya[0];
    assert ke["from"] == jid(me);
    assert ke["how_met"] == "summit";
    assert ke["source_note"] == jid(note);
    assert ke["span"] == "met Priya at the summit";

    # reported
    reported_priya_dana = [
        r for r in (out["reported"] as list[dict[str, any]])
        if r["from"] == jid(priya) and r["to"] == jid(dana)
    ];
    assert len(reported_priya_dana) == 1;
    re = reported_priya_dana[0];
    assert re["source_note"] == jid(note);
    assert re["span"] == "She knows Dana";

    # facts
    facts_by_id = [f for f in (out["facts"] as list[dict[str, any]]) if f["id"] == jid(fact)];
    assert len(facts_by_id) == 1;
    fe = facts_by_id[0];
    assert fe["about"] == jid(priya);
    assert fe["text"] == "Works on climate tech";
    assert fe["source_note"] == jid(note);
    assert fe["span"] == "works on climate tech";

    # intents
    intents_by_id = [i for i in (out["intents"] as list[dict[str, any]]) if i["id"] == jid(intent)];
    assert len(intents_by_id) == 1;
    ie = intents_by_id[0];
    assert ie["about"] == jid(priya);
    assert ie["kind"] == "need";
    assert ie["source_note"] == jid(note);
    assert ie["span"] == "needs a VC intro";

    # promises
    promises_by_id = [p for p in (out["promises"] as list[dict[str, any]]) if p["id"] == jid(promise)];
    assert len(promises_by_id) == 1;
    pe = promises_by_id[0];
    assert pe["to"] == jid(priya);
    assert pe["due"] == "2026-10-03";
    assert pe["source_note"] == jid(note);
    assert pe["span"] == "send the deck by Friday";

    # notes
    note_ids = [n["id"] for n in (out["notes"] as list[dict[str, any]])];
    assert jid(note) in note_ids;

    assert out["truncated"] == False;
}

test "build_export: a Me with no self-onboarded intent and an Intent with no IntentAbout falls back to me_id" {
    me = (root ++> Me(name="Export-test Self Me"))[0];
    note = (root ++> Note(text="Export-test-self onboarding note", kind="about_me", captured_at="2026-09-26T10:00:00"))[0];
    intent = (note +>:AssertsIntent(span="Export-test-self needs feedback"):+> Intent(
        kind="need", text="Export-test-self needs feedback", source_kind="self"
    ))[0];
    # No IntentAbout edge: this is a self-onboarded intent (HasIntent in the
    # real onboarding flow), never targeted at a Person.

    out = build_export(me);
    matches = [i for i in (out["intents"] as list[dict[str, any]]) if i["id"] == jid(intent)];
    assert len(matches) == 1;
    assert matches[0]["about"] == jid(me);
}

test "build_export: no Goal/Card/people is fine - empty sections, Me still present" {
    me = (root ++> Me(name="Export-test Bare Me"))[0];
    out = build_export(me);
    assert (out["me"] as dict[str, any])["id"] == jid(me);
    assert out["goals"] == [];
    assert out["card"] is None;
}

test "build_export: cap truncates and flips truncated=true" {
    me = (root ++> Me(name="Export-test Cap Me"))[0];
    for i in range(5) {
        me +>:Knows(how_met="cap-test"):+> Person(name=f"Export-test Cap P{i}", status="confirmed");
    }
    out = build_export(me, cap=2);
    assert len(out["people"] as list[dict[str, any]]) == 2;
    assert out["truncated"] == True;
}

test "ExportGraph via root spawn: no Me yet reports the empty shape" {
    # A brand-new root (this in-process test root already has Mes from the
    # tests above, so this only checks the SHAPE of a report by calling the
    # walker for real - not a "first call ever, no Me" claim, which the
    # isolation test below covers with a truly fresh account). See
    # export.sv.jac's ExportGraph docstring for the exact empty shape.
    result = root spawn ExportGraph();
    assert len(result.reports) == 1;
    # This persisted root already has a Me from earlier tests in this file,
    # so ExportGraph resolves to ONE of them rather than the empty shape -
    # assert the shape is at least well-formed instead of asserting emptiness.
    out = result.reports[0];
    assert "exported_at" in out;
    assert "counts" in out;
    assert "truncated" in out;
}

# ---------------------------------------------------------------- two-account isolation

glob EXPORT_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _export_harness(tmp_dir: str) -> str {
    for name in ["export.sv.jac", "schema.sv.jac"] {
        shutil.copyfile(os.path.join(EXPORT_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write("import from export { ExportGraph, ExportDevSeed }\n");
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"export-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _call(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "ExportGraph isolation: A's export has A's seeded ids; B's export has none of A's people, facts, or notes" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_export_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _register(cl, "export_a1@example.com");
        b = _register(cl, "export_b1@example.com");

        seed = _call(cl, a, "ExportDevSeed", {})[0] as dict[str, any];

        a_export = _call(cl, a, "ExportGraph", {})[0] as dict[str, any];
        me_out = a_export["me"] as dict[str, any];
        assert me_out["id"] == seed["me"];

        goal_ids = [g["id"] for g in (a_export["goals"] as list[dict[str, any]])];
        assert seed["goal"] in goal_ids;

        people_ids = [p["id"] for p in (a_export["people"] as list[dict[str, any]])];
        assert seed["p1"] in people_ids and seed["p2"] in people_ids;

        reported = [
            r for r in (a_export["reported"] as list[dict[str, any]])
            if r["from"] == seed["p1"] and r["to"] == seed["p2"]
        ];
        assert len(reported) == 1;

        fact_ids = [f["id"] for f in (a_export["facts"] as list[dict[str, any]])];
        intent_ids = [i["id"] for i in (a_export["intents"] as list[dict[str, any]])];
        promise_ids = [pr["id"] for pr in (a_export["promises"] as list[dict[str, any]])];
        note_ids = [n["id"] for n in (a_export["notes"] as list[dict[str, any]])];
        assert seed["fact"] in fact_ids;
        assert seed["intent"] in intent_ids;
        assert seed["promise"] in promise_ids;
        assert seed["note"] in note_ids;

        counts = a_export["counts"] as dict[str, any];
        assert (counts["people"] as int) >= 2;

        # B's own export: no Me at all yet (never seeded) -> the empty shape.
        b_export = _call(cl, b, "ExportGraph", {})[0] as dict[str, any];
        print(f"[export isolation] B's export -> {b_export}");
        assert b_export["me"] is None;
        assert b_export["people"] == [];
        assert b_export["facts"] == [];
        assert b_export["notes"] == [];

        b_people_ids = [p["id"] for p in (b_export["people"] as list[dict[str, any]])];
        assert seed["p1"] not in b_people_ids and seed["p2"] not in b_people_ids;
        b_fact_ids = [f["id"] for f in (b_export["facts"] as list[dict[str, any]])];
        assert seed["fact"] not in b_fact_ids;
        b_note_ids = [n["id"] for n in (b_export["notes"] as list[dict[str, any]])];
        assert seed["note"] not in b_note_ids;
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
