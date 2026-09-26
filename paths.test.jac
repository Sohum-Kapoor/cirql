"""Tests for paths.sv.jac (SOH-194 PathFinder).

Annex to paths.sv.jac — run with `jac test paths.sv.jac`. Deterministic only:
no LLM (this module never calls one), no server.

`jac test` runs every test in this file in declaration order against ONE
shared, persisted `root` (jac-testing) — nodes from earlier tests, and from
earlier `jac test` invocations, are still hanging around. Following
reads.test.jac's pattern: `find_path` is exercised directly on hand-built
nodes (never via `root spawn PathFinder(...)`), because the walker resolves
"the" Me via `[root --> [?:Me]][0]` — ambiguous once more than one test has
created a Me under the shared root. Every node/text used here is unique to
this file's own graph so it stays correct however many times the suite has
already run against this persisted root.

One graph, built once, reused by every test below:
    Me --knows(confirmed)--> A (confirmed)
    Me --knows(proposed)--> B (confirmed)
    Me --knows(confirmed)--> C (confirmed, org=Michigan Robotics)
    A --reported(source_note+span)--> D (confirmed)
    D --reported(source_note+span)--> E (confirmed, org=Michigan Robotics)
    B --reported(source_note+span)--> F (confirmed)
    A --reported(source_note="")--> X (confirmed)   # no provenance
    G (confirmed, no edges to/from anyone)          # unreachable
"""

import from paths { find_path, Candidate }
import from schema { Me, Person, Note, Knows, Reported }

test "PathFinder graph: build once, reused by every test in this file" {
    me = (root ++> Me(name="Paths-test Me"))[0];

    note_a = (root ++> Note(text="Paths-test: met A at the hack night.", kind="debrief", captured_at="2026-09-26T10:00:00"))[0];
    a = (me +>:Knows(how_met="hack night", status="confirmed", source_note=jid(note_a)):+> Person(
        name="Paths-test A", status="confirmed"
    ))[0];

    b = (me +>:Knows(how_met="conference", status="proposed"):+> Person(
        name="Paths-test B", status="confirmed"
    ))[0];

    note_c = (root ++> Note(text="Paths-test: met C, works at Michigan Robotics.", kind="debrief", captured_at="2026-09-26T10:05:00"))[0];
    c = (me +>:Knows(how_met="lab", status="confirmed", source_note=jid(note_c)):+> Person(
        name="Paths-test C", status="confirmed", org="Michigan Robotics"
    ))[0];

    note_ad = (root ++> Note(text="Paths-test: A told me about D from the robotics club.", kind="debrief", captured_at="2026-09-26T11:00:00"))[0];
    d = (root ++> Person(name="Paths-test D", status="confirmed"))[0];
    a +>:Reported(source_note=jid(note_ad), span="knows D from the robotics club"):+> d;

    note_de = (root ++> Note(text="Paths-test: D told me about E, worked together on a project.", kind="debrief", captured_at="2026-09-26T12:00:00"))[0];
    e = (root ++> Person(name="Paths-test E", status="confirmed", org="Michigan Robotics"))[0];
    d +>:Reported(source_note=jid(note_de), span="worked with E on a project"):+> e;

    note_bf = (root ++> Note(text="Paths-test: B mentioned F is a close friend.", kind="debrief", captured_at="2026-09-26T13:00:00"))[0];
    f = (root ++> Person(name="Paths-test F", status="confirmed"))[0];
    b +>:Reported(source_note=jid(note_bf), span="F is a close friend"):+> f;

    x = (root ++> Person(name="Paths-test X", status="confirmed"))[0];
    a +>:Reported(source_note="", span="an unverified tie"):+> x;

    g = (root ++> Person(name="Paths-test G", status="confirmed"))[0];

    # sanity: the fixture graph is what we think it is
    assert a.status == "confirmed";
    assert c.org == "Michigan Robotics";
    assert g.status == "confirmed";
    assert [edge me ->:Knows:-> a][0].status == "confirmed";
    assert [edge me ->:Knows:-> b][0].status == "proposed";
}

"""Re-resolve this file's fixture graph by name off the shared root, rather
than rebuilding it (avoids duplicating nodes across tests)."""
def _by_name(people: list[Person], name: str) -> Person {
    matches = [p for p in people if p.name == name];
    return matches[0];
}

def _fixture() -> dict[str, object] {
    me = [p for p in [root --> [?:Me]] if p.name == "Paths-test Me"][0];
    # A/B/C hang off `me` (Knows), D/E/F/X/G hang directly off root (Reported
    # chains only, no Knows edge from Me) - gather both sets.
    all_people = [p for p in [me ->:Knows:->]] + [p for p in [root --> [?:Person]]];

    return {
        "me": me,
        "a": _by_name(all_people, "Paths-test A"),
        "b": _by_name(all_people, "Paths-test B"),
        "c": _by_name(all_people, "Paths-test C"),
        "d": _by_name(all_people, "Paths-test D"),
        "e": _by_name(all_people, "Paths-test E"),
        "f": _by_name(all_people, "Paths-test F"),
        "x": _by_name(all_people, "Paths-test X"),
        "g": _by_name(all_people, "Paths-test G"),
    };
}

test "PathFinder(A): directly known -> found, 1 hop via knows, reason 'Known directly.'" {
    fx = _fixture();
    me = fx["me"] as Me;
    a = fx["a"] as Person;

    result = find_path(me, a, 3);

    assert result["found"];
    target = result["target"];
    assert target is not None and jid(target as Person) == jid(a);
    hops = result["hops"] as list[dict[str, any]];
    assert len(hops) == 1;
    assert hops[0]["via"] == "knows";
    assert jid(hops[0]["person"] as Person) == jid(a);
    assert result["reason"] == "Known directly.";
}

test "PathFinder(D): 2 hops, evidence carries the span, reason mentions A" {
    fx = _fixture();
    me = fx["me"] as Me;
    a = fx["a"] as Person;
    d = fx["d"] as Person;

    result = find_path(me, d, 3);

    assert result["found"];
    hops = result["hops"] as list[dict[str, any]];
    assert len(hops) == 2;
    assert jid(hops[0]["person"] as Person) == jid(a);
    assert jid(hops[1]["person"] as Person) == jid(d);
    assert hops[1]["via"] == "reported";

    ev = hops[1]["evidence"];
    assert ev is not None;
    ev_dict = ev as dict[str, str];
    assert ev_dict["span"] == "knows D from the robotics club";
    assert ev_dict["kind"] == "note";

    reason = result["reason"] as str;
    assert "Paths-test A" in reason;
}

test "PathFinder(E): 3 hops at max_depth 3; no known route at max_depth 2 (still found in-graph)" {
    fx = _fixture();
    me = fx["me"] as Me;
    e = fx["e"] as Person;

    result3 = find_path(me, e, 3);
    assert result3["found"];
    hops3 = result3["hops"] as list[dict[str, any]];
    assert len(hops3) == 3;

    result2 = find_path(me, e, 2);
    assert not result2["found"];
    assert result2["hops"] == [];
    assert result2["reason"] == "No known route. Unknown is not never met.";
    assert result2["target"] is not None, "E is reachable via A->D (broad traversal), just not within max_depth 2";
}

test "PathFinder(F): no known route — B is proposed, cannot be an intermediate hop" {
    fx = _fixture();
    me = fx["me"] as Me;
    f = fx["f"] as Person;

    result = find_path(me, f, 4);

    assert not result["found"];
    assert result["hops"] == [];
    assert result["reason"] == "No known route. Unknown is not never met.";
    assert result["target"] is not None, "F is still reachable via broad traversal through B, just not a valid route";
}

test "PathFinder(E): context contains the same-org line for C" {
    fx = _fixture();
    me = fx["me"] as Me;
    e = fx["e"] as Person;

    result = find_path(me, e, 3);
    context = result["context"] as list[str];
    assert "same org as you: Michigan Robotics" in context;
}

test "PathFinder(G): not reachable by any traversal from Me -> not_found, target null" {
    fx = _fixture();
    me = fx["me"] as Me;
    g = fx["g"] as Person;

    result = find_path(me, g, 4);

    assert not result["found"];
    assert result["target"] is None;
    assert result["hops"] == [];
    assert result["context"] == [];
    assert result["reason"] == "not_found";
}

test "PathFinder(X): a Reported edge with an empty source_note is never a hop" {
    fx = _fixture();
    me = fx["me"] as Me;
    x = fx["x"] as Person;

    result = find_path(me, x, 3);

    assert not result["found"];
    assert result["hops"] == [];
    # X is still reachable by broad (unrestricted) traversal through A, so this
    # is "no known route", not "not_found" — the missing provenance is exactly
    # why there's no route, not why the person is unknown.
    assert result["reason"] == "No known route. Unknown is not never met.";
}
