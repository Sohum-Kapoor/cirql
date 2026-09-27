"""Tests for gaps.sv.jac (SOH-203) — deterministic filter only, no LLM.

Annex to gaps.sv.jac — run with `jac test gaps.sv.jac`. Covers only
`compute_gaps`, the non-LLM half of `GapFinder`: given a hand-built
`GapExtraction` and a warm-person count, a kind covered by an existing
warm person is dropped and an uncovered kind is reported.
"""

import from gaps { compute_gaps, GapExtraction, NeededKind, known_people_texts, strip_score_words, candidate_people, graph_newest_evidence_at, gaps_cache_is_fresh, served_from_cache }
import from schema { Me, Goal, Person, HasGoal, Knows, RelevantTo, Fact, FactAbout }
import from datetime { datetime, timedelta }
import json;
import uuid;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

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
        kind_text = g["kind"] as str;
        assert "climate" not in kind_text.lower(), f"covered kind leaked into gaps: {g}";
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

test "compute_gaps drops a kind already covered by an active known person (SOH-212)" {
    # Reproduces the judge finding: the Home gap card said 'No warm path to
    # JacHacks event organizer' while Lena Fischer (title 'organizer', org
    # 'JacHacks') was in the graph. She has no RelevantTo tie to this goal
    # yet (so the LLM's covered_by/warm_count check alone can't see her) -
    # the deterministic post-filter over known_people_texts must catch her.
    me = (root ++> Me(name="Test3"))[0];
    # goal exists (a real gap must be about a goal in the graph) but Lena is
    # deliberately never tied to it via RelevantTo - the post-filter must
    # catch her without needing that tie.
    (me +>:HasGoal:+> Goal(text="Find a warm path to JacHacks", created_at="2026-09-26T00:00:00Z"))[0];
    (me +>:Knows(how_met="test"):+> Person(
        name="Lena Fischer", org="JacHacks", title="organizer"
    ))[0];

    known_people = known_people_texts(me);
    assert len(known_people) == 1;

    proposed = NeededKind(
        kind="JacHacks event organizer",
        why_needed="The goal needs someone organizing JacHacks to open a warm path.",
        suggested_need="an intro to whoever is organizing JacHacks this year",
        covered_by=[]
    );
    extraction = GapExtraction(kinds=[proposed]);

    gaps = compute_gaps(extraction, 0, known_people);

    assert len(gaps) == 0, f"Lena Fischer (organizer at JacHacks) should have covered this gap, got {gaps}";
}

test "compute_gaps never emits the banned word 'score'/'scores'/'scoring'" {
    dirty = NeededKind(
        kind="climate-tech VC",
        why_needed="Scoring your network found no strong match for this Score.",
        suggested_need="someone to boost your scores with climate investors",
        covered_by=[]
    );
    extraction = GapExtraction(kinds=[dirty]);

    gaps = compute_gaps(extraction, 0);

    assert len(gaps) == 1;
    why_text = gaps[0]["why_needed"] as str;
    need_text = gaps[0]["suggested_need"] as str;
    text = (why_text + " " + need_text).lower();
    assert "score" not in text, f"banned word 'score' leaked into gap text: {gaps}";
    assert strip_score_words("Scoring the Score and scores.") == "results the results and results.";
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

test "compute_gaps (SOH-226): why_needed/suggested_need are polished, model narration stripped" {
    dirty = NeededKind(
        kind="climate-tech VC",
        why_needed="The fact confirms the goal needs a climate-tech VC.",
        suggested_need="an intro to a climate-tech VC (evidence: \"raising a seed round\")",
        covered_by=[]
    );
    extraction = GapExtraction(kinds=[dirty]);

    gaps = compute_gaps(extraction, 0);

    assert len(gaps) == 1;
    assert gaps[0]["why_needed"] == "The goal needs a climate-tech VC.";
    assert gaps[0]["suggested_need"] == "An intro to a climate-tech VC.";
}

# ---------------------------------------------------------------- SOH-236 gap cache

test "gaps_cache_is_fresh: a cache stored minutes ago with no newer evidence is fresh" {
    now = datetime.now();
    gaps_at = (now - timedelta(minutes=5)).isoformat();
    fresh = gaps_cache_is_fresh(
        json.dumps([{"kind": "x", "why_needed": "y", "suggested_need": "z"}]),
        gaps_at, "", now
    );
    assert fresh, "a 5-minute-old cache with no newer evidence must be served";
}

test "gaps_cache_is_fresh: empty gaps_json or gaps_at is never fresh" {
    now = datetime.now();
    gaps_at = (now - timedelta(minutes=5)).isoformat();
    assert not gaps_cache_is_fresh("", gaps_at, "", now), "no stored gaps_json -> never fresh";
    assert not gaps_cache_is_fresh(json.dumps([]), "", "", now), "no stored gaps_at -> never fresh";
}

test "gaps_cache_is_fresh: older than 6 hours is stale (the documented fallback rule)" {
    now = datetime.now();
    gaps_at = (now - timedelta(hours=7)).isoformat();
    fresh = gaps_cache_is_fresh(
        json.dumps([{"kind": "x", "why_needed": "y", "suggested_need": "z"}]),
        gaps_at, "", now
    );
    assert not fresh, "a 7-hour-old cache must be treated as stale";
}

test "gaps_cache_is_fresh: newer evidence than gaps_at invalidates the cache" {
    now = datetime.now();
    gaps_at = (now - timedelta(minutes=5)).isoformat();
    newest_evidence = now.isoformat();   # a note captured AFTER gaps_at
    fresh = gaps_cache_is_fresh(
        json.dumps([{"kind": "x", "why_needed": "y", "suggested_need": "z"}]),
        gaps_at, newest_evidence, now
    );
    assert not fresh, "evidence newer than gaps_at must invalidate the cache";
}

test "graph_newest_evidence_at picks up a new Fact about a known person (a new note invalidates)" {
    me = (root ++> Me(name="CacheTest" + _uid()))[0];
    p = (me +>:Knows(how_met="test"):+> Person(name="Cached Person" + _uid()))[0];

    candidates = candidate_people(me);
    assert len(candidates) == 1;
    assert graph_newest_evidence_at(candidates) == "", "no facts yet -> no evidence timestamp";

    now = datetime.now();
    fact_time = now.isoformat();
    fact = (root ++> Fact(text="raising a seed round", observed_at=fact_time))[0];
    fact +>:FactAbout:+> p;

    newest = graph_newest_evidence_at(candidates);
    assert newest == fact_time, f"expected the fact's own observed_at, got {newest}";

    gaps_at = (now - timedelta(minutes=1)).isoformat();
    fresh = gaps_cache_is_fresh(json.dumps([{"kind": "x"}]), gaps_at, newest, now);
    assert not fresh, "a cache from before this new fact must be invalidated";
}

test "served_from_cache marks every stored gap cached:true and round-trips fields" {
    stored = json.dumps([
        {"kind": "climate-tech VC", "why_needed": "a", "suggested_need": "b"},
        {"kind": "robotics mentor", "why_needed": "c", "suggested_need": "d"}
    ]);
    served = served_from_cache(stored);
    assert served is not None;
    out = served as list[dict[str, any]];
    assert len(out) == 2;
    for gap in out {
        cached_flag = gap["cached"] as bool;
        assert cached_flag, f"every served gap must be marked cached, got {gap}";
    }
    assert out[0]["kind"] == "climate-tech VC";
}

test "served_from_cache returns None (not []) on corrupt stored JSON" {
    served = served_from_cache("not json at all {{{");
    assert served is None, "corrupt gaps_json must be reported as None, not an empty list";
}
