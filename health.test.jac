"""Tests for health.sv.jac (SOH-200 NetworkHealth).

Annex to health.sv.jac — run with `jac test health.sv.jac`. Deterministic
only: no LLM (this module never calls one), no server.

`jac test` runs every test in this file in declaration order against ONE
shared, persisted `root` (jac-testing) — nodes from earlier tests, and from
earlier `jac test` invocations, are still hanging around. Following
tend.test.jac's pattern (the newest of this shape in the repo): every test
calls `_build_fixture()`, which builds a BRAND NEW `Me` + people + ties and
returns direct node references, then calls `network_health_for(me)` on that
`me` directly — never `root spawn NetworkHealth()` (which resolves "the" Me
via `[root --> [?:Me]][0]`, ambiguous once more than one test has created a
Me under the shared root) and never a query back onto the shared root by a
fixed name (which would risk resolving a DIFFERENT run's leftover node — the
"per-run id" gotcha in AGENTS.md). Since `network_health_for`'s every
traversal starts from the `me` reference it was given, never `[root --> ...]`,
one test's fixture can never leak into another's result and no random
per-run suffix is needed — each test's fixture is its own isolated graph by
construction, run after run.

One graph, fresh per test:
    A, B, C — confirmed, org "Lab", a Reported triangle (A-B, B-C, C-A)
    D, E    — confirmed, org "Fund", one Reported tie (D-E)
    C - D   — one Reported tie (the only link between the two orgs: C and D
              are both articulation points of the resulting 5-person component)
    F       — confirmed, no org, no Reported tie to anyone (isolated in G)
    G       — proposed (not part of G at all)
"""

import from health { network_health_for, build_graph, find_components, find_bridges, label_for, Graph }
import from schema { Me, Person, Knows, Reported }

def _build_fixture() -> dict[str, object] {
    me = (root ++> Me(name="Health-test Me"))[0];

    a = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name="Health-test A", status="confirmed", org="Lab"
    ))[0];
    b = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name="Health-test B", status="confirmed", org="Lab"
    ))[0];
    c = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name="Health-test C", status="confirmed", org="Lab"
    ))[0];
    d = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name="Health-test D", status="confirmed", org="Fund"
    ))[0];
    e = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name="Health-test E", status="confirmed", org="Fund"
    ))[0];
    f = (me +>:Knows(how_met="test", status="confirmed"):+> Person(
        name="Health-test F", status="confirmed"
    ))[0];
    g = (me +>:Knows(how_met="test", status="proposed"):+> Person(
        name="Health-test G", status="proposed"
    ))[0];

    a +>:Reported(source_note="", span=""):+> b;
    b +>:Reported(source_note="", span=""):+> c;
    c +>:Reported(source_note="", span=""):+> a;
    d +>:Reported(source_note="", span=""):+> e;
    c +>:Reported(source_note="", span=""):+> d;

    return {"me": me, "a": a, "b": b, "c": c, "d": d, "e": e, "f": f, "g": g};
}

test "fixture sanity: confirmed/proposed status and the isolated F are what we think they are" {
    fx = _build_fixture();
    me = fx["me"] as Me;
    a = fx["a"] as Person;
    f = fx["f"] as Person;
    g = fx["g"] as Person;

    assert a.status == "confirmed";
    assert f.status == "confirmed";
    assert not f.org;
    assert g.status == "proposed";
    assert [edge me ->:Knows:-> g][0].status == "proposed";
}

test "network_health_for: people/confirmed/proposed/ties counts" {
    fx = _build_fixture();
    me = fx["me"] as Me;

    result = network_health_for(me);

    assert result["people"] == 7;
    assert result["confirmed"] == 6;
    assert result["proposed"] == 1;
    assert result["ties"] == 5, "A-B, B-C, C-A, D-E, C-D = 5 undirected ties";
}

test "network_health_for: one cluster of size 5 labeled 'Lab' (most common org wins over 'Fund')" {
    fx = _build_fixture();
    me = fx["me"] as Me;
    f = fx["f"] as Person;

    result = network_health_for(me);
    clusters = result["clusters"] as list[dict[str, object]];

    assert len(clusters) == 1, "F is isolated (no cluster); A-B-C-D-E is one component";
    cluster = clusters[0];
    assert cluster["size"] == 5;
    assert cluster["label"] == "Lab", "3 Lab vs 2 Fund in the component -> Lab wins";
    sample = cluster["sample"] as list[str];
    assert len(sample) <= 3 and len(sample) > 0;
    assert f.name not in sample, "F is isolated: never part of the 5-person cluster's sample";
}

test "network_health_for: C and D are both bridges (articulation points of the 5-person component)" {
    fx = _build_fixture();
    me = fx["me"] as Me;
    c = fx["c"] as Person;
    d = fx["d"] as Person;

    result = network_health_for(me);
    bridges = result["bridges"] as list[dict[str, object]];
    bridge_ids = [jid(b["person"] as Person) for b in bridges];

    assert jid(c) in bridge_ids, "C must split {A,B} from {D,E} when removed";
    assert jid(d) in bridge_ids, "D must split {A,B,C} from {E} when removed";

    for b in bridges {
        if jid(b["person"] as Person) == jid(c) {
            connects = b["connects"] as list[str];
            assert len(connects) == 2;
            assert "Lab" in connects;
            assert "Fund" in connects;
        }
    }
}

test "network_health_for: weak_tie_share is 0.17 (F is the only isolated confirmed person, 1 of 6)" {
    fx = _build_fixture();
    me = fx["me"] as Me;

    result = network_health_for(me);
    assert result["weak_tie_share"] == 0.17;
}

test "network_health_for: echo_share is 0.5 (3 of 6 confirmed people are 'Lab')" {
    fx = _build_fixture();
    me = fx["me"] as Me;

    result = network_health_for(me);
    assert result["echo_share"] == 0.5;
}

test "network_health_for: notes are non-empty, plain sentences, never a score/strength/rank word" {
    fx = _build_fixture();
    me = fx["me"] as Me;

    result = network_health_for(me);
    notes = result["notes"] as list[str];

    assert len(notes) > 0;
    assert len(notes) <= 3;
    banned = ["score", "strength", "rank", "worth", "strong", "weak"];
    for note in notes {
        lowered = note.lower();
        for word in banned {
            assert word not in lowered, f"note must never rank/score a person: {note!r} contains {word!r}";
        }
    }
}

test "network_health_for: no known people at all reports the all-zero/empty shape" {
    me = (root ++> Me(name="Health-test Empty Me"))[0];
    result = network_health_for(me);

    assert result["people"] == 0;
    assert result["confirmed"] == 0;
    assert result["proposed"] == 0;
    assert result["ties"] == 0;
    assert result["clusters"] == [];
    assert result["bridges"] == [];
    assert result["weak_tie_share"] == 0.0;
    assert result["echo_share"] == 0.0;
    assert result["notes"] == [];
}

# ---------------------------------------------------------------- helper unit tests

test "build_graph / find_components / find_bridges / label_for are consistent on the fixture" {
    fx = _build_fixture();
    a = fx["a"] as Person;
    b = fx["b"] as Person;
    c = fx["c"] as Person;
    d = fx["d"] as Person;
    e = fx["e"] as Person;
    f = fx["f"] as Person;

    confirmed = [a, b, c, d, e, f];
    g = build_graph(confirmed);
    assert g.ties == 5;
    assert g.adj[jid(f)] == [], "F has no ties";

    comps = find_components(g);
    assert len(comps) == 1;
    assert len(comps[0]) == 5;
    assert label_for(comps[0], g) == "Lab";

    bridges = find_bridges(g, comps);
    bridge_ids = [b2["person"] for b2 in bridges];
    assert (a not in bridge_ids) and (b not in bridge_ids), "leaves of the triangle are never cut vertices here";
}
