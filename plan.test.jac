"""Tests for plan.sv.jac (SOH-197 GamePlan).

Annex to plan.sv.jac — run with `jac test plan.sv.jac`. `game_plan_for` takes
`me` explicitly and every traversal starts from that reference (`me
->:Knows:->`, then each `Person`) — same idiom as `tend.sv.jac`/`paths.sv.jac`
— so one test's fixtures never leak into another's assertions via node-
reference confusion, and the walker itself (which resolves "the" Me via
`[root --> [?:Me]]`) is never spawned here. The one root-wide scan in the
reuse chain (`reads.sv.jac`'s `list_promises_raw`, used by `open_promise_for`)
is filtered by `person_id` (a per-node jid) — unique regardless of how many
prior test runs' Notes/Promises are still hanging off this persisted root.
Every Person/Goal NAME below still carries a random per-run suffix (`_uid()`)
per AGENTS.md's testing gotcha, so exact-name / single-token matching is
never confused by a same-named fixture left over from an earlier run.
"""

import from plan { game_plan_for, match_known, find_reported_route, cap_report }
import from schema {
    Me, Person, Note, Fact, Promise, Goal,
    Knows, Reported, AssertsPromise, PromiseTo, FactAbout, HasGoal, RelevantTo
}
import uuid;
import from datetime { datetime }

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

test "GamePlan: known (open promise + cached opener + strong goal match), known via a fact (weak goal match), a first-name ambiguity, a Reported route (hops=2), and an unknown name" {
    suffix = _uid();
    me = (root ++> Me(name="Plan-test Me " + suffix))[0];
    goal = (me +>:HasGoal:+> Goal(text="Plan-test goal " + suffix, created_at=datetime.now().isoformat(), active=True))[0];

    # --- Maya Okafor: confirmed, one open Promise, RelevantTo strong with a cached opener
    maya_first = "Maya" + suffix;
    maya_full = maya_first + " Okafor";
    maya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name=maya_full, status="confirmed"))[0];

    promise_note = (root ++> Note(text="Plan-test promise note " + suffix, kind="debrief", captured_at=datetime.now().isoformat()))[0];
    promise = (root ++> Promise(text="send the deck", due="", done=False))[0];
    promise_note +>:AssertsPromise(span="send the deck"):+> promise;
    promise +>:PromiseTo:+> maya;

    maya +>:RelevantTo(
        reason="wants intros to funders", strength="strong", label="known",
        evidence=[], opener="Cached opener for Maya."
    ):+> goal;

    # --- Arjun Patel: confirmed, no promise, weak RelevantTo, but a Fact exists about him
    arjun_first = "Arjun" + suffix;
    arjun_full = arjun_first + " Patel";
    arjun = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name=arjun_full, status="confirmed"))[0];
    arjun +>:RelevantTo(reason="similar title", strength="weak", label="known", evidence=[], opener=""):+> goal;

    arjun_fact = (root ++> Fact(text="just joined a robotics startup", observed_at=datetime.now().isoformat(), status="reported"))[0];
    arjun_fact +>:FactAbout:+> arjun;

    # --- a proposed person literally named "Maya<suffix>" makes the bare first name ambiguous
    maya_dup = (me +>:Knows(status="proposed", last_contact=""):+> Person(name=maya_first, status="proposed"))[0];

    # --- Priya Rao: reachable only via Reported from Arjun (one hop)
    priya_first = "Priya" + suffix;
    priya_full = priya_first + " Rao";
    priya = (root ++> Person(name=priya_full, status="confirmed"))[0];
    tie_note = (root ++> Note(text="Plan-test tie note " + suffix, kind="debrief", captured_at=datetime.now().isoformat()))[0];
    arjun +>:Reported(source_note=jid(tie_note), span="knows " + priya_full):+> priya;

    nobody = "Nobody Here " + suffix;

    names = [maya_full, arjun_first, maya_first, priya_full, nobody];
    result = game_plan_for(me, names, "Plan-test mixer " + suffix);

    assert result["event"] == "Plan-test mixer " + suffix;

    # ---- known
    known = result["known"] as list[dict[str, any]];
    assert len(known) == 2, f"expected exactly Maya Okafor and Arjun known, got {[k['name'] for k in known]}";

    by_name: dict[str, any] = {};
    for entry in known {
        by_name[entry["name"] as str] = entry;
    }
    assert maya_full in by_name;
    assert arjun_first in by_name;

    maya_entry = by_name[maya_full] as dict[str, any];
    maya_person = maya_entry["person"];
    assert maya_person is not None and jid(maya_person as Person) == jid(maya);
    assert maya_entry["open_promise"] == "send the deck";
    assert maya_entry["opener"] == "Cached opener for Maya.", "must reuse the cached RelevantTo.opener, never rebuild one";
    assert maya_entry["goal_label"] == "known";
    assert maya_entry["goal_strength"] == "strong";
    assert "send the deck" in (maya_entry["why_talk"] as str), "an open promise outranks goal relevance and facts in why_talk";

    arjun_entry = by_name[arjun_first] as dict[str, any];
    arjun_person = arjun_entry["person"];
    assert arjun_person is not None and jid(arjun_person as Person) == jid(arjun);
    assert arjun_entry["open_promise"] == "";
    assert arjun_entry["goal_strength"] == "weak";
    assert "just joined a robotics startup" in (arjun_entry["why_talk"] as str), "no promise, no strong/medium match -> falls to the recent fact";

    # ---- ambiguous
    ambiguous = result["ambiguous"] as list[dict[str, any]];
    assert len(ambiguous) == 1;
    amb = ambiguous[0];
    assert amb["name"] == maya_first;
    amb_candidates = amb["candidates"] as list[Person];
    assert len(amb_candidates) == 2;
    amb_ids = [jid(p) for p in amb_candidates];
    assert jid(maya) in amb_ids;
    assert jid(maya_dup) in amb_ids;

    # ---- routes
    routes = result["routes"] as list[dict[str, any]];
    assert len(routes) == 1;
    route = routes[0];
    assert route["name"] == priya_full;
    route_person = route["person"];
    assert route_person is not None and jid(route_person as Person) == jid(priya);
    assert route["via"] == arjun_full;
    assert route["hops"] == 2;

    # ---- unknown
    assert result["unknown"] == [nobody];

    # ---- suggested_order: promise-holder first, then other known, then routes
    suggested_order = result["suggested_order"] as list[str];
    assert suggested_order == [maya_full, arjun_first, priya_full], f"got {suggested_order}";
}

test "match_known: exact full-name match wins even when a first-token collision also exists" {
    suffix = _uid();
    me = (root ++> Me(name="Plan-mk-test Me " + suffix))[0];

    first = "Sam" + suffix;
    full_a = first + " Lee";
    full_b = first;   # exact same string as the bare first name

    a = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name=full_a, status="confirmed"))[0];
    b = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name=full_b, status="confirmed"))[0];

    exact = match_known(me, full_a);
    assert len(exact) == 1;
    assert jid(exact[0]) == jid(a);

    bare = match_known(me, first);
    ids = [jid(p) for p in bare];
    assert len(bare) == 2, "the bare first name matches both by exact equality (b) and by first-token (a)";
    assert jid(a) in ids;
    assert jid(b) in ids;
}

test "find_reported_route: only a direct Reported hop off a known person counts, matched by exact name" {
    suffix = _uid();
    me = (root ++> Me(name="Plan-frr-test Me " + suffix))[0];

    known_name = "Devika" + suffix;
    known = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name=known_name, status="confirmed"))[0];

    target_name = "Farah" + suffix;
    target = (root ++> Person(name=target_name, status="confirmed"))[0];
    note = (root ++> Note(text="Plan-frr-test note " + suffix, kind="debrief", captured_at=datetime.now().isoformat()))[0];
    known +>:Reported(source_note=jid(note), span="knows " + target_name):+> target;

    found = find_reported_route(me, target_name);
    assert found is not None;
    f = found as dict[str, Person];
    assert jid(f["via"]) == jid(known);
    assert jid(f["target"]) == jid(target);

    missing = find_reported_route(me, "Nobody At All " + suffix);
    assert missing is None;
}

test "SOH-212 GamePlan: 70 names against the 60 cap -> 60 processed, 10 in not_processed, nothing silently eaten" {
    me = (root ++> Me(name=f"plan-cap-me-{uuid.uuid4().hex[:6]}"))[0];
    names = [f"Guest212 {i}" for i in range(70)];
    out = game_plan_for(me, names, "gala");
    assert out["total_names"] == 70;
    assert out["processed"] == 60;
    assert out["truncated"] == True;
    rest = out["not_processed"] as list[str];
    assert rest == names[60:];
    assert len(out["unknown"] as list[str]) == 60, "the 60 processed names all land in a bucket";

    small = cap_report(["a", "b"]);
    assert small["truncated"] == False and small["not_processed"] == [] and small["processed"] == 2;
}
