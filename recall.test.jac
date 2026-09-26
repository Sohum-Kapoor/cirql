"""Tests for recall.sv.jac (SOH-189).

Annex to recall.sv.jac — run with `jac test recall.sv.jac`. Deterministic
only: the Gemini quota is exhausted today, so no test may reach `by llm`.

`Recall`'s own `gather_recall_items` reads directly off `root -->` with no
per-Me scoping at all (every Note/Fact/Intent/Promise the caller ever wrote,
full stop) — the most exposed function in this codebase to the shared,
persisted-root gotcha (`jac test` keeps everything every earlier run of this
file ever created). So the pre-filter/select/fallback pieces are exercised
on hand-built `RecallItem` lists directly (no graph, no root, no
contamination possible at all) - "three notes about three people" means
three `RecallItem(kind="note", ...)` objects, not three `Note` nodes. The one
test that does read the real graph (`gather_recall_items` itself) filters
its output down to this run's own ids before asserting anything, exactly the
`ListPromises` idiom in `reads.test.jac`. `cap_and_sort_items` (the pure
sort+cap step pulled out of `gather_recall_items`) is used for the
`max_items` test instead, for the same no-contamination reason.
"""

import from recall {
    RecallItem, prefilter_matches, select_recall_evidence, fallback_recall,
    cap_and_sort_items, gather_recall_items, map_recall_indices,
    build_recall_evidence_text, item_to_citation
}
import from schema { Note, Fact }

# ---------------------------------------------------------------- prefilter / select / fallback (hand-built items, no graph)

test "prefilter_matches: a question about one topic keeps only the item(s) that share a content word" {
    items = [
        RecallItem(id="n-1", kind="note", observed_at="2026-09-20T10:00:00", span="Priya works on climate tech and wants a VC intro", person="Priya"),
        RecallItem(id="n-2", kind="note", observed_at="2026-09-21T10:00:00", span="Bob is a patent lawyer downtown", person="Bob"),
        RecallItem(id="n-3", kind="note", observed_at="2026-09-22T10:00:00", span="Carol plays violin on weekends", person="Carol")
    ];

    matched = prefilter_matches(items, "who works on climate tech?");
    names = [m.person for m in matched];
    assert "Priya" in names, f"expected the climate-tech note to survive the pre-filter, got {names}";
    assert "Bob" not in names;
    assert "Carol" not in names;
}

test "select_recall_evidence: >=3 matches use the strict set; 1-2 matches widen to the newest 12; 0 matches is empty" {
    strong_pool = [
        RecallItem(id=f"s-{i}", kind="note", observed_at=f"2026-09-{i + 1:02d}T00:00:00", span="climate robotics accessible project", person=f"Person{i}")
        for i in range(4)
    ];
    strict = select_recall_evidence(strong_pool, "tell me about the robotics project");
    assert len(strict) == 4, "3+ strict matches: use them all, no widening";

    thin_pool = [
        RecallItem(id="t-1", kind="note", observed_at="2026-09-25T00:00:00", span="robotics accessible project", person="Only Match"),
        RecallItem(id="t-2", kind="note", observed_at="2026-09-24T00:00:00", span="unrelated violin hobby", person="Someone Else"),
        RecallItem(id="t-3", kind="note", observed_at="2026-09-23T00:00:00", span="another unrelated topic entirely", person="Third Party")
    ];
    widened = select_recall_evidence(thin_pool, "tell me about the robotics project");
    assert len(widened) == 3, "only 1 strict match: widen to the newest items in the whole pool";

    nothing_pool = [
        RecallItem(id="z-1", kind="note", observed_at="2026-09-20T00:00:00", span="violin hobby weekends", person="X"),
        RecallItem(id="z-2", kind="fact", observed_at="2026-09-19T00:00:00", span="lawyer downtown office", person="Y")
    ];
    empty = select_recall_evidence(nothing_pool, "spaceship rocket telescope");
    assert empty == [], "zero token overlap with the question: no widening, empty selection";
}

test "fallback_recall: nothing selected -> insufficient; otherwise names the right person and cites the top 3" {
    insufficient = fallback_recall([]);
    assert insufficient["answer"] == "Insufficient evidence in your notes.";
    assert insufficient["citations"] == [];
    assert insufficient["insufficient"];
    assert insufficient["fallback"];

    selected = [
        RecallItem(id="r-1", kind="note", observed_at="2026-09-22T00:00:00", span="wants feedback from wheelchair users", person="Priya"),
        RecallItem(id="r-2", kind="fact", observed_at="2026-09-21T00:00:00", span="works at ClimateCo", person="Priya")
    ];
    result = fallback_recall(selected);
    assert "Priya" in (result["answer"] as str), f"fallback answer must name the matched person, got {result['answer']}";
    assert not result["insufficient"];
    assert result["fallback"];
    citations = result["citations"] as list[dict[str, str]];
    assert len(citations) == 2;
    assert citations[0]["id"] == "r-1";
}

test "map_recall_indices + build_recall_evidence_text: numbering round-trips, out-of-range and duplicate indices dropped" {
    items = [
        RecallItem(id="m-1", kind="fact", observed_at="2026-09-01", span="fact span", person="A"),
        RecallItem(id="m-2", kind="promise", observed_at="2026-09-02", span="promise span", person="B")
    ];
    text = build_recall_evidence_text(items);
    assert "about A" in text;
    assert "about B" in text;

    mapped = map_recall_indices(items, [1, 1, 0, 99, -1]);
    assert len(mapped) == 2, "dedupe by index (first wins) and drop out-of-range";
    assert mapped[0]["id"] == "m-2";
    assert mapped[1]["id"] == "m-1";
}

# ---------------------------------------------------------------- cap_and_sort_items (pure, no graph)

test "cap_and_sort_items: newest first, max_items respected" {
    items = [
        RecallItem(id="c-1", kind="note", observed_at="2026-01-01T00:00:00", span="old", person=""),
        RecallItem(id="c-2", kind="note", observed_at="2026-06-01T00:00:00", span="mid", person=""),
        RecallItem(id="c-3", kind="note", observed_at="2026-09-01T00:00:00", span="new", person="")
    ];
    capped = cap_and_sort_items(items, 2);
    assert len(capped) == 2, f"max_items=2 must be respected, got {len(capped)}";
    assert capped[0].id == "c-3", "newest first";
    assert capped[1].id == "c-2";

    uncapped = cap_and_sort_items(items, 0);
    assert len(uncapped) == 3, "max_items <= 0 means uncapped";
}

# ---------------------------------------------------------------- gather_recall_items (real graph, filtered to this run's own ids)

test "gather_recall_items: reads real Note/Fact nodes off root with the right kind/person/span" {
    unique = "Recall-test-unique-marker-9f3a";
    note = (root ++> Note(text=f"{unique} note text about Dana", kind="debrief", captured_at="2026-09-24T10:00:00"))[0];
    fact = (root ++> Fact(text=f"{unique} fact text", observed_at="2026-09-23T10:00:00"))[0];

    pool = gather_recall_items(0);
    mine = [it for it in pool if unique in it.span];
    assert len(mine) == 2, f"expected exactly the note and the fact just created, got {len(mine)}";

    by_kind: dict[str, RecallItem] = {};
    for it in mine {
        by_kind[it.kind] = it;
    }
    assert by_kind["note"].id == jid(note);
    assert by_kind["note"].span == f"{unique} note text about Dana"[:300];
    assert by_kind["fact"].id == jid(fact);
    assert by_kind["fact"].observed_at == "2026-09-23T10:00:00";
}
