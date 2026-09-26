"""Tests for gaps.sv.jac (SOH-203) — deterministic filter only, no LLM.

Annex to gaps.sv.jac — run with `jac test gaps.sv.jac`. Covers only
`compute_gaps`, the non-LLM half of `GapFinder`: given a hand-built
`GapExtraction` and a warm-person count, a kind covered by an existing
warm person is dropped and an uncovered kind is reported.
"""

import from gaps { compute_gaps, GapExtraction, NeededKind }
import from schema { Me, Goal, Person, HasGoal, Knows, RelevantTo }

test "compute_gaps drops the covered kind, keeps the uncovered kind" {
    me = (root ++> Me(name="Test"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Land a summer 2027 climate-tech VC internship", created_at="2026-09-26T00:00:00Z"))[0];

    vc = (me +>:Knows(how_met="test"):+> Person(
        name="VC Contact", org="Climate Ventures", title="Partner at a climate-tech VC fund"
    ))[0];
    vc +>:RelevantTo(label="known", strength="strong", reason="met at demo day"):+> goal;

    barista = (me +>:Knows(how_met="test"):+> Person(
        name="Barista Contact", org="Corner Cafe", title="Barista"
    ))[0];
    barista +>:RelevantTo(label="known", strength="weak", reason="local coffee shop regular"):+> goal;

    # Mirror GapFinder's warm-set filter: label known/route AND strength strong/medium.
    # (weak does not count as a path, so the barista must not be counted.)
    warm_count = 0;
    for p in [me ->:Knows:->] {
        for e in [edge p ->:RelevantTo:-> goal] {
            if e.label in ["known", "route"] and e.strength in ["strong", "medium"] {
                warm_count += 1;
            }
        }
    }
    assert warm_count == 1, f"expected 1 warm person (the VC only), got {warm_count}";

    covered = NeededKind(
        kind="climate-tech VC",
        why_needed="The goal needs a climate-tech VC to sponsor the internship.",
        suggested_need="an intro to a climate-tech VC who takes cold student pitches",
        covered_by=[0]
    );
    uncovered = NeededKind(
        kind="robotics mentor",
        why_needed="The goal needs someone experienced in robotics to mentor the project.",
        suggested_need="an intro to a robotics engineer willing to mentor a student team",
        covered_by=[]
    );
    extraction = GapExtraction(kinds=[covered, uncovered]);

    gaps = compute_gaps(extraction, warm_count);

    assert len(gaps) == 1, f"expected exactly one gap, got {gaps}";
    assert gaps[0]["kind"] == "robotics mentor";
    for g in gaps {
        assert "climate" not in g["kind"].lower(), f"covered kind leaked into gaps: {g}";
    }
}

test "compute_gaps has no warm coverage when only a weak link exists" {
    me = (root ++> Me(name="Test2"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Find wheelchair users to test our robotics prototype", created_at="2026-09-26T00:00:00Z"))[0];

    barista = (me +>:Knows(how_met="test"):+> Person(
        name="Barista Contact 2", org="Corner Cafe", title="Barista"
    ))[0];
    barista +>:RelevantTo(label="known", strength="weak", reason="local coffee shop regular"):+> goal;

    warm_count = 0;
    for p in [me ->:Knows:->] {
        for e in [edge p ->:RelevantTo:-> goal] {
            if e.label in ["known", "route"] and e.strength in ["strong", "medium"] {
                warm_count += 1;
            }
        }
    }
    assert warm_count == 0, f"a weak label=known link must not count as a warm path, got {warm_count}";

    uncovered = NeededKind(
        kind="wheelchair user willing to test a prototype",
        why_needed="The goal needs direct feedback from a wheelchair user.",
        suggested_need="an intro to a wheelchair user willing to test a robotics prototype",
        covered_by=[]
    );
    extraction = GapExtraction(kinds=[uncovered]);

    gaps = compute_gaps(extraction, warm_count);

    assert len(gaps) == 1, f"expected the uncovered kind to be reported, got {gaps}";
    assert gaps[0]["kind"] == "wheelchair user willing to test a prototype";
}

test "compute_gaps dedupes case-insensitively and caps at 4" {
    extraction = GapExtraction(kinds=[
        NeededKind(kind="climate-tech VC", why_needed="a", suggested_need="b", covered_by=[]),
        NeededKind(kind="Climate-Tech VC", why_needed="a", suggested_need="b", covered_by=[]),
        NeededKind(kind="wheelchair user willing to test a prototype", why_needed="c", suggested_need="d", covered_by=[]),
        NeededKind(kind="robotics mentor", why_needed="e", suggested_need="f", covered_by=[]),
        NeededKind(kind="grant writer", why_needed="g", suggested_need="h", covered_by=[]),
        NeededKind(kind="patent lawyer", why_needed="i", suggested_need="j", covered_by=[])
    ]);

    gaps = compute_gaps(extraction, 0);

    assert len(gaps) == 4, f"expected the cap of 4, got {len(gaps)}: {gaps}";
    kinds = [g["kind"].lower() for g in gaps];
    assert kinds.count("climate-tech vc") == 1, f"expected the duplicate kind deduped, got {kinds}";
}

test "compute_gaps drops entries with any empty field" {
    extraction = GapExtraction(kinds=[
        NeededKind(kind="", why_needed="a", suggested_need="b", covered_by=[]),
        NeededKind(kind="valid kind", why_needed="", suggested_need="b", covered_by=[]),
        NeededKind(kind="also valid", why_needed="a", suggested_need="", covered_by=[]),
        NeededKind(kind="fully valid kind", why_needed="a", suggested_need="b", covered_by=[])
    ]);

    gaps = compute_gaps(extraction, 0);

    assert len(gaps) == 1, f"expected only the fully-populated kind, got {gaps}";
    assert gaps[0]["kind"] == "fully valid kind";
}
