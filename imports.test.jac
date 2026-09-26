"""Tests for imports.sv.jac (SOH-180) — ImportPeople, ConfirmPerson, SkipPerson.

Annex to imports.sv.jac — run with `jac test imports.sv.jac`. Deterministic,
no LLM. Per `jac-testing`, tests share one persisted root across runs, so
every name below carries a random per-test suffix (`_uid()`) — this
guarantees a name is always genuinely new, whether this is the first run
ever or the hundredth, and that two tests never collide on the same
lowercase name.
"""

import from imports { ImportPeople, ConfirmPerson, SkipPerson, row_str }
import from schema { Me, Person, Note, Knows, Mentions }
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

test "row_str: present, missing, and None-valued keys" {
    row: dict[str, any] = {"name": "Maya", "org": None};
    assert row_str(row, "name") == "Maya";
    assert row_str(row, "org") == "";
    assert row_str(row, "title") == "";
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
