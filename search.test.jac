"""Tests for search.sv.jac (SOH-216, Search).

Annex to search.sv.jac — run with `jac test search.sv.jac`. Deterministic
only: no LLM (this module never calls one), no network for the first block.

Every test below builds its own fresh `Me` and calls `search_for(me, ...)`
directly (never `root spawn Search(...)`) for the same reason
`edits.test.jac`/`export.test.jac` do: `search_for` only ever reads
`[me ->:Knows:->]` and what hangs off THOSE people, so a hand-built `me`
with its own freshly-created `Person`s is naturally isolated from every
other test's leftovers on the shared, persisted `jac-testing` root — no
id-filtering needed, unlike walkers that resolve "the" `Me` internally.

The final block is the required two-account isolation negative: two real
accounts registered through `/user/register` via `JacTestClient`, seeded
through `DevAddPerson` (`walkers.sv.jac`, already used by other suites'
harnesses) and `Capture`-free manual graph writes are not available over
HTTP, so this harness seeds a person straight through `DevAddPerson` and
asserts B's `Search` never finds A's person by name. Same throwaway-harness
approach `edits.test.jac`/`export.test.jac` use: `JacTestClient.from_file`
can't target a dotted `*.sv.jac` module directly, so a fresh temp dir gets
copies of `search.sv.jac`'s import chain (`schema`, `goals`) plus
`walkers.sv.jac` (for `DevAddPerson`) next to a dot-free `app.jac`.
"""

import from search { Search, search_for }
import from schema {
    Me, Person, Note, Fact, Intent, Promise,
    Knows, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo
}

# ---------------------------------------------------------------- helpers

def _kinds_ids(out: dict[str, any]) -> list[tuple[str, str]] {
    results = out["results"] as list[dict[str, any]];
    return [((r["kind"] as str), (r["id"] as str)) for r in results];
}

# ---------------------------------------------------------------- seed one graph, exercise every rule

test "search_for: name prefix, org, fact text, note text, description-name, archived-excluded, kinds, limit" {
    me = (root ++> Me(name="Search-test Me"))[0];

    # p1: a normal person with org/title/location/email, a fact, and a note
    # that mentions them (both containing the word "priya" too, so a query
    # for "priya" also has to find the fact/note rows through the PERSON
    # context those rows carry, not just their own text).
    p1 = (me +>:Knows(how_met="conference", status="confirmed"):+> Person(
        name="Search-test Priya Patel", org="Acme Climate", title="Founder",
        location="Ann Arbor", email="priya@example.com", status="confirmed"
    ))[0];

    note1 = (root ++> Note(
        text="Search-test note: met Priya, works on climate tech policy.",
        kind="debrief", captured_at="2026-09-20T09:00:00"
    ))[0];
    note1 +>:Mentions(span="met Priya"):+> p1;

    fact1 = (note1 +>:Asserts(span="works on climate tech policy"):+> Fact(
        text="Search-test works on climate tech policy", observed_at="2026-09-20T09:00:00", source_kind="reported"
    ))[0];
    fact1 +>:FactAbout:+> p1;

    # p2: a second person with an intent and a promise, no fact/note overlap
    # with p1's tokens, so kind-filtering can be checked cleanly.
    p2 = (me +>:Knows(how_met="referral", status="confirmed"):+> Person(
        name="Search-test Dana Osei", org="Beta Corp", status="confirmed"
    ))[0];

    note2 = (root ++> Note(
        text="Search-test note: Dana needs a VC intro, promised to send the deck by Friday.",
        kind="debrief", captured_at="2026-09-21T09:00:00"
    ))[0];
    intent2 = (note2 +>:AssertsIntent(span="needs a VC intro"):+> Intent(
        kind="need", text="Search-test needs a VC intro", source_kind="reported"
    ))[0];
    intent2 +>:IntentAbout:+> p2;
    promise2 = (note2 +>:AssertsPromise(span="send the deck by Friday"):+> Promise(
        text="Search-test send the deck by Friday"
    ))[0];
    promise2 +>:PromiseTo:+> p2;

    # p3: archived — must never surface, in any kind, even on an exact name hit.
    p3 = (me +>:Knows(how_met="old contact", status="confirmed"):+> Person(
        name="Search-test Archived Amara", org="Gamma Inc", status="confirmed", archived=True
    ))[0];
    note3 = (root ++> Note(text="Search-test archived note about Amara", kind="debrief", captured_at="2026-09-19T09:00:00"))[0];
    note3 +>:Mentions(span="about Amara"):+> p3;
    fact3 = (note3 +>:Asserts(span="works at Gamma"):+> Fact(text="Search-test works at Gamma Inc", observed_at="2026-09-19T09:00:00"))[0];
    fact3 +>:FactAbout:+> p3;

    # p4: described-only person — the NAME itself is the description, and it
    # must be found by a query matching that description's words.
    p4 = (me +>:Knows(how_met="climbing gym", status="confirmed"):+> Person(
        name="Search-test tall girl from the climbing gym", status="proposed"
    ))[0];

    # ---- name prefix (partial word "pri" -> "Priya") ----
    r_prefix = search_for(me, "pri", 25, ["person"]);
    assert ("person", jid(p1)) in _kinds_ids(r_prefix), f"name-prefix search must find p1: {r_prefix}";

    # ---- org ("acme" doesn't appear in p1's name, only its org) ----
    r_org = search_for(me, "acme", 25, ["person"]);
    assert ("person", jid(p1)) in _kinds_ids(r_org), f"org search must find p1: {r_org}";
    assert ("person", jid(p2)) not in _kinds_ids(r_org);

    # ---- fact text ----
    r_fact = search_for(me, "climate", 25, ["fact"]);
    fact_ids = [rid for (k, rid) in _kinds_ids(r_fact) if k == "fact"];
    assert jid(fact1) in fact_ids, f"fact-text search must find fact1: {r_fact}";

    # ---- note text ----
    r_note = search_for(me, "policy", 25, ["note"]);
    note_ids = [rid for (k, rid) in _kinds_ids(r_note) if k == "note"];
    assert jid(note1) in note_ids, f"note-text search must find note1: {r_note}";

    # ---- description-only person, found by NAME words ----
    r_desc = search_for(me, "tall girl climbing gym", 25, ["person"]);
    assert ("person", jid(p4)) in _kinds_ids(r_desc), f"description-name search must find p4: {r_desc}";

    # ---- archived excluded: p3's own name/org find nothing, in any kind ----
    r_archived_name = search_for(me, "amara", 25, []);
    assert r_archived_name["total"] == 0, f"archived person must never surface: {r_archived_name}";
    r_archived_org = search_for(me, "gamma inc", 25, []);
    assert r_archived_org["total"] == 0, f"archived person's claims must never surface: {r_archived_org}";

    # ---- kinds filter: a query that would match p2 (person) AND its intent
    # ("need"/"needs") only returns intent rows when kinds=["intent"] ----
    r_kind_all = search_for(me, "dana needs", 25, []);
    all_kinds = set([k for (k, _rid) in _kinds_ids(r_kind_all)]);
    assert "person" in all_kinds and "intent" in all_kinds, f"unfiltered search should surface both: {r_kind_all}";

    r_kind_intent_only = search_for(me, "dana needs", 25, ["intent"]);
    only_kinds = set([k for (k, _rid) in _kinds_ids(r_kind_intent_only)]);
    assert only_kinds == {"intent"}, f"kinds=['intent'] must exclude every other kind: {r_kind_intent_only}";
    assert jid(intent2) in [rid for (k, rid) in _kinds_ids(r_kind_intent_only)];

    # ---- promise still reachable through the same person, unfiltered ----
    r_promise = search_for(me, "send the deck", 25, ["promise"]);
    promise_ids = [rid for (k, rid) in _kinds_ids(r_promise) if k == "promise"];
    assert jid(promise2) in promise_ids, f"promise-text search must find promise2: {r_promise}";

    # ---- limit: "search-test" is a token shared by every name/text above,
    # so it matches many rows; total must count them all, results must be
    # clamped to `limit`, and an out-of-range limit is clamped to [0, 100] ----
    r_limited = search_for(me, "search-test", 2, []);
    assert len(r_limited["results"] as list[dict[str, any]]) == 2;
    assert (r_limited["total"] as int) > 2, f"total must count every match, not just the returned page: {r_limited}";

    r_over_cap = search_for(me, "search-test", 500, []);
    assert len(r_over_cap["results"] as list[dict[str, any]]) <= 100;

    r_negative = search_for(me, "search-test", -5, []);
    assert r_negative["results"] == [];
}

# ---------------------------------------------------------------- sort order

test "search_for: same-score rows sort person-first, then newest-first" {
    me = (root ++> Me(name="Search-test Sort Me"))[0];

    # Same score for the person row and its own fact row (both hit the
    # unique token "zebraq" once via name-prefix / text, then double on the
    # whole-query substring match) -> person must sort first.
    p5 = (me +>:Knows(status="confirmed"):+> Person(name="Search-test Zebraq Quinn", status="confirmed"))[0];
    note5 = (root ++> Note(text="Search-test-sort note", kind="debrief", captured_at="2026-09-22T09:00:00"))[0];
    fact5 = (note5 +>:Asserts(span="zebraq project"):+> Fact(
        text="Search-test zebraq project details", observed_at="2026-09-22T09:00:00"
    ))[0];
    fact5 +>:FactAbout:+> p5;

    out_tie = search_for(me, "zebraq", 25, []);
    rows_tie = out_tie["results"] as list[dict[str, any]];
    assert len(rows_tie) >= 2;
    assert (rows_tie[0]["kind"] as str) == "person", f"a person row must sort first on a score tie: {out_tie}";

    # Two facts on two different, otherwise-unrelated people, same score via
    # the shared token "alphatok", differing only in observed_at -> newer first.
    p6 = (me +>:Knows(status="confirmed"):+> Person(name="Search-test Gamma6", status="confirmed"))[0];
    note6 = (root ++> Note(text="Search-test-sort note 6", kind="debrief", captured_at="2020-01-01T00:00:00"))[0];
    fact6 = (note6 +>:Asserts(span="alphatok"):+> Fact(
        text="Search-test alphatok old evidence", observed_at="2020-01-01T00:00:00"
    ))[0];
    fact6 +>:FactAbout:+> p6;

    p7 = (me +>:Knows(status="confirmed"):+> Person(name="Search-test Gamma7", status="confirmed"))[0];
    note7 = (root ++> Note(text="Search-test-sort note 7", kind="debrief", captured_at="2025-01-01T00:00:00"))[0];
    fact7 = (note7 +>:Asserts(span="alphatok"):+> Fact(
        text="Search-test alphatok new evidence", observed_at="2025-01-01T00:00:00"
    ))[0];
    fact7 +>:FactAbout:+> p7;

    out_date = search_for(me, "alphatok", 25, ["fact"]);
    rows_date = out_date["results"] as list[dict[str, any]];
    ids_in_order = [r["id"] as str for r in rows_date];
    assert jid(fact6) in ids_in_order and jid(fact7) in ids_in_order;
    assert ids_in_order.index(jid(fact7)) < ids_in_order.index(jid(fact6)), f"same-score facts must sort newest observed_at first: {out_date}";
}

# ---------------------------------------------------------------- through the walker

test "Search: no Me yet reports the empty shape" {
    # This persisted root already has Mes from the tests above via the
    # `search_for` calls, so `root spawn Search(...)` resolves to ONE of
    # them rather than the true "brand-new account" case (covered by the
    # isolation test below) - this only checks the report is well-formed.
    result = root spawn Search(query="search-test", limit=5, kinds=[]);
    assert len(result.reports) == 1;
    out = result.reports[0];
    assert "query" in out and "results" in out and "total" in out;
    assert len(out["results"] as list[dict[str, any]]) <= 5;
}

# ---------------------------------------------------------------- two-account isolation

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

glob SEARCH_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

"""Copy search.sv.jac's import chain (schema, goals) plus walkers.sv.jac
(for the `DevAddPerson` test-seeding helper) into a fresh temp dir next to a
dot-free `app.jac` — `JacTestClient.from_file` can't target a dotted
`*.sv.jac` module name directly (AGENTS.md gotcha)."""
def _search_harness(tmp_dir: str) -> str {
    for name in ["schema.sv.jac", "goals.sv.jac", "search.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(SEARCH_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from search { Search }\n"
        "import from walkers { DevAddPerson }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"search-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _search_register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _search_call(client: JacTestClient, token: str, wname: str, body: dict[str, any]) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "isolation: B's Search never finds A's person, A's own Search does" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_search_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _search_register(cl, "search_a@example.com");
        b = _search_register(cl, "search_b@example.com");

        seeded = _search_call(cl, a, "DevAddPerson", {"name": "Search-isolation Unique Person"});
        person_id = str(seeded[0]["_jac_id"]);
        print(f"[search isolation] A seeded person_id={person_id}");

        a_search = _search_call(cl, a, "Search", {"query": "isolation unique", "limit": 25, "kinds": []});
        a_out = a_search[0] as dict[str, any];
        print(f"[search isolation] A's own Search -> {a_out}");
        a_ids = [r["id"] for r in (a_out["results"] as list[dict[str, any]])];
        assert person_id in a_ids, f"A must find its own seeded person: {a_out}";

        b_search = _search_call(cl, b, "Search", {"query": "isolation unique", "limit": 25, "kinds": []});
        b_out = b_search[0] as dict[str, any];
        print(f"[search isolation] B's Search -> {b_out}");
        assert b_out["results"] == [], f"B must never find A's person: {b_out}";
        assert b_out["total"] == 0;
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
