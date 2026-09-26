"""Tests for reads.sv.jac (SOH-186 Receipt, SOH-187 promise ledger, SOH-185
GraphView).

Annex to reads.sv.jac — run with `jac test reads.sv.jac`. Deterministic only:
no LLM (this module never calls one), no server.

`jac test` runs every test in this file in declaration order against ONE
shared, persisted `root` (jac-testing) — nodes from earlier tests, and from
earlier `jac test` invocations, are still hanging around. Two consequences
for this file specifically:
  - `receipt_for` and `graph_view_for` are exercised directly on hand-built
    nodes (never via `root spawn Receipt(...)` / `root spawn GraphView(...)`)
    because `jobj`/`Jac.check_read_access` ownership needs a second, isolated
    root to prove the negative case, and `GraphView`'s walker body resolves
    "the" Me via `[root --> [?:Me]][0]` — ambiguous once more than one test
    has created a Me under the shared root. `ListPromises`/`CompletePromise`
    have no such ambiguity (id-keyed / root-wide, no "the one Me" lookup), so
    they run through `root spawn` for real, filtered by a unique promise
    text so earlier tests' leftover Promises never leak into an assertion.
  - Every test uses a name/text unique to itself so it stays correct however
    many times the suite has already run against this persisted root.
"""

import from reads { receipt_for, graph_view_for, Receipt, ListPromises, CompletePromise }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card,
    Knows, Reported, Asserts, AssertsPromise, Mentions,
    FactAbout, PromiseTo, HasGoal, RelevantTo
}

# ---------------------------------------------------------------- receipt_for

test "receipt_for: fact carries the asserting note's span, text, and source_kind" {
    note = (root ++> Note(
        text="Reads-test: Priya works on climate tech and needs a VC intro.",
        kind="debrief", captured_at="2026-09-26T10:00:00"
    ))[0];
    p1 = (root ++> Person(name="Reads-test Priya", status="confirmed"))[0];
    fact = (note +>:Asserts(span="works on climate tech"):+> Fact(
        text="Works on climate tech", observed_at="2026-09-26T10:00:00", source_kind="reported"
    ))[0];
    fact +>:FactAbout:+> p1;

    view = receipt_for(fact);

    assert view["kind"] == "fact";
    assert view["id"] == jid(fact);
    assert view["text"] == "Works on climate tech";
    assert view["span"] == "works on climate tech";
    assert view["note_text"] == note.text;
    assert view["source_note_id"] == jid(note);
    assert view["captured_at"] == "2026-09-26T10:00:00";
    assert view["source_kind"] == "reported";
    assert view["source_url"] == "";
}

test "receipt_for: person prefers the Mentions span over the Knows source_note" {
    note = (root ++> Note(
        text="Reads-test: met Reads-test Bob at the conference, robotics engineer.",
        kind="debrief", captured_at="2026-09-26T11:00:00"
    ))[0];
    me = (root ++> Me(name="Reads-test Me A"))[0];
    p1 = (me +>:Knows(how_met="conference", last_contact="", source_note=jid(note), status="reported"):+> Person(
        name="Reads-test Bob", status="confirmed"
    ))[0];
    note +>:Mentions(span="met Reads-test Bob at the conference"):+> p1;

    view = receipt_for(p1);

    assert view["kind"] == "person";
    assert view["text"] == "Reads-test Bob";
    assert view["span"] == "met Reads-test Bob at the conference";
    assert view["note_text"] == note.text;
    assert view["source_note_id"] == jid(note);
    assert view["captured_at"] == "2026-09-26T11:00:00";
}

test "receipt_for: person falls back to the Knows edge's source_note when no Mentions edge exists" {
    note = (root ++> Note(
        text="Reads-test: Carol is a patent lawyer.", kind="debrief", captured_at="2026-09-26T12:00:00"
    ))[0];
    me = (root ++> Me(name="Reads-test Me B"))[0];
    p1 = (me +>:Knows(how_met="referral", last_contact="", source_note=jid(note), status="reported"):+> Person(
        name="Reads-test Carol", status="confirmed"
    ))[0];

    view = receipt_for(p1);

    assert view["kind"] == "person";
    assert view["span"] == "", "no Mentions edge: span stays empty even though a note was found via Knows";
    assert view["note_text"] == note.text;
    assert view["source_note_id"] == jid(note);
}

test "receipt_for: note, card, goal dispatch to their own text/handle field, empty elsewhere" {
    note = (root ++> Note(text="Reads-test raw note text", kind="paste", captured_at="2026-09-26T13:00:00"))[0];
    note_view = receipt_for(note);
    assert note_view["kind"] == "note";
    assert note_view["text"] == "Reads-test raw note text";
    assert note_view["note_text"] == "Reads-test raw note text";
    assert note_view["span"] == "";
    assert note_view["source_note_id"] == "";

    card = (root ++> Card(handle="reads-test-handle", name="Reads-test Card Name"))[0];
    card_view = receipt_for(card);
    assert card_view["kind"] == "card";
    assert card_view["text"] == "reads-test-handle";
    assert card_view["source_kind"] == "self";
    assert card_view["note_text"] == "";

    goal = (root ++> Goal(text="Reads-test goal text", created_at="2026-09-26T13:05:00"))[0];
    goal_view = receipt_for(goal);
    assert goal_view["kind"] == "goal";
    assert goal_view["text"] == "Reads-test goal text";
    assert goal_view["note_text"] == "";
    assert goal_view["source_note_id"] == "";
}

test "Receipt: an id that resolves to nothing reports not_found" {
    result = root spawn Receipt(id="not-a-real-id-at-all");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- ListPromises / CompletePromise

test "ListPromises reports one open promise with the right to/span/source_note_id, then CompletePromise moves it to the end" {
    me = (root ++> Me(name="Reads-test Promise Me"))[0];
    p1 = (me +>:Knows(how_met="test"):+> Person(name="Reads-test Promise P1", status="confirmed"))[0];
    p2 = (me +>:Knows(how_met="test"):+> Person(name="Reads-test Promise P2", status="confirmed"))[0];

    note = (root ++> Note(
        text="Reads-test: I'll send Dana the SOH-186 report by Friday.",
        kind="debrief", captured_at="2026-09-26T14:00:00"
    ))[0];
    fact = (note +>:Asserts(span="Dana"):+> Fact(text="Reads-test filler fact", observed_at="2026-09-26T14:00:00"))[0];
    fact +>:FactAbout:+> p1;
    note +>:Mentions(span="Dana"):+> p1;

    promise = (note +>:AssertsPromise(span="send the SOH-186 report by Friday"):+> Promise(
        text="Reads-test-unique send the SOH-186 report", due="2026-10-03"
    ))[0];
    promise +>:PromiseTo:+> p2;

    result = root spawn ListPromises();
    # Match by this run's own Note id, not promise text: `jac test` shares one
    # persisted root across every run of this suite, so a fixed text string
    # accumulates one Promise node per run (SOH-186 review fix) - the Note
    # created just above is the one thing guaranteed unique to this call.
    matches = [r for r in result.reports if r["source_note_id"] == jid(note)];
    assert len(matches) == 1, f"expected exactly one matching open promise, got {len(matches)}";
    entry = matches[0];
    assert entry["span"] == "send the SOH-186 report by Friday";
    assert entry["source_note_id"] == jid(note);
    to_person = entry["to"];
    assert to_person is not None and (to_person as Person).name == "Reads-test Promise P2";

    completed_result = root spawn CompletePromise(promise_id=jid(promise));
    assert len(completed_result.reports) == 1;
    completed = completed_result.reports[0] as Promise;
    assert completed.done;

    other_note = (root ++> Note(
        text="Reads-test: I'll call Eve about SOH-186 next week.",
        kind="debrief", captured_at="2026-09-26T14:05:00"
    ))[0];
    other_promise = (other_note +>:AssertsPromise(span="call Eve about SOH-186 next week"):+> Promise(
        text="Reads-test-unique call Eve about SOH-186", due=""
    ))[0];
    other_promise +>:PromiseTo:+> p1;

    result2 = root spawn ListPromises();
    note_ids = [r["source_note_id"] for r in result2.reports];
    idx_done = note_ids.index(jid(note));
    idx_open = note_ids.index(jid(other_note));
    assert idx_open < idx_done, f"a done promise must sort after any still-open promise (source_note_id order: {note_ids})";
}

test "CompletePromise on an unknown id reports not_found" {
    result = root spawn CompletePromise(promise_id="not-a-real-promise-id");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- graph_view_for

test "graph_view_for: 3+ nodes, knows/reported/relevant_to edges with the right labels, 300-cap" {
    me = (root ++> Me(name="Reads-test GraphView Me"))[0];
    p1 = (me +>:Knows(how_met="conference", status="confirmed"):+> Person(
        name="Reads-test GraphView P1", status="confirmed", org="Acme", title="Engineer"
    ))[0];
    p2 = (me +>:Knows(how_met="referral", status="confirmed"):+> Person(
        name="Reads-test GraphView P2", status="confirmed"
    ))[0];
    p1 +>:Reported(source_note="", span="they know each other"):+> p2;

    goal = (me +>:HasGoal:+> Goal(text="Reads-test GraphView goal", created_at="2026-09-26T15:00:00", active=True))[0];
    p1 +>:RelevantTo(reason="test", strength="strong", label="known"):+> goal;

    view = graph_view_for(me, jid(goal));
    nodes = view["nodes"] as list[dict[str, str]];
    edges = view["edges"] as list[dict[str, str]];

    assert len(nodes) >= 4, f"expected Me + 2 people + goal, got {len(nodes)}";
    node_ids = [n["id"] for n in nodes];
    assert jid(me) in node_ids;
    assert jid(p1) in node_ids;
    assert jid(p2) in node_ids;
    assert jid(goal) in node_ids;

    knows_to_p1 = [e for e in edges if e["kind"] == "knows" and e["to"] == jid(p1)];
    assert len(knows_to_p1) == 1;
    assert knows_to_p1[0]["label"] == "conference";
    assert knows_to_p1[0]["strength"] == "confirmed";

    reported_edges = [e for e in edges if e["kind"] == "reported" and e["from"] == jid(p1) and e["to"] == jid(p2)];
    assert len(reported_edges) == 1;
    assert reported_edges[0]["label"] == "reported";

    relevant_edges = [e for e in edges if e["kind"] == "relevant_to" and e["from"] == jid(p1) and e["to"] == jid(goal)];
    assert len(relevant_edges) == 1;
    assert relevant_edges[0]["label"] == "known";
    assert relevant_edges[0]["strength"] == "strong";
}

test "graph_view_for: falls back to the active goal when no goal_id is given, and to none when there isn't one" {
    me = (root ++> Me(name="Reads-test GraphView Me 2"))[0];
    inactive_goal = (me +>:HasGoal:+> Goal(text="Reads-test inactive goal", created_at="2026-09-26T15:10:00", active=False))[0];
    active_goal = (me +>:HasGoal:+> Goal(text="Reads-test active goal", created_at="2026-09-26T15:11:00", active=True))[0];

    view = graph_view_for(me, "");
    node_ids = [n["id"] for n in (view["nodes"] as list[dict[str, str]])];
    assert jid(active_goal) in node_ids;
    assert jid(inactive_goal) not in node_ids;

    me2 = (root ++> Me(name="Reads-test GraphView Me 3"))[0];
    view2 = graph_view_for(me2, "");
    node_ids2 = [n["id"] for n in (view2["nodes"] as list[dict[str, str]])];
    assert len(node_ids2) == 1, "no goal at all: only the Me node";
}
