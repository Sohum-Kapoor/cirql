"""Tests for serendipity.sv.jac (SOH-201).

Annex to serendipity.sv.jac — run with `jac test serendipity.sv.jac`.
Deterministic only: this module never calls a model, so nothing here can hit
one (`_tokenize`'s reused stopword-based, lowercase/alnum/length>=4 token
overlap rule decides everything).

Per AGENTS.md's `tend.sv.jac`-established gotcha (never take `[root -->
[?:Me]][0]` inside a helper tests call), every test builds its OWN fresh
`Me` + people and calls `serendipity_for` directly — never `root spawn
Serendipity(...)`, which would resolve "the" `Me` ambiguously off the
shared, persisted `jac test` root. Because `serendipity_for`'s every
traversal starts from a node reference (`me`, then each `Person`), one
test's fixtures can never leak into another's result — names don't need a
random per-run suffix, but every person is still asserted by name, never by
raw list length against the whole root.
"""

import from serendipity {
    serendipity_for, pick_top_evidence, _confirmed_known_people,
    _match_person, _qualifies, _topic_phrase, _why_fragment,
    _newest_observed_at
}
import from goals { EvidenceItem, gather_evidence }
import from schema {
    Me, Person, Note, Fact, Intent, Knows,
    FactAbout, IntentAbout, Mentions, AssertsIntent
}
import from datetime { datetime }

def _names(rows: list[dict[str, any]]) -> list[str] {
    out: list[str] = [];
    for r in rows {
        p = r["person"] as Person;
        out.append(p.name);
    }
    return out;
}

def _evidence_kinds(row: dict[str, any]) -> list[str] {
    ev = row["evidence"] as list[dict[str, str]];
    out: list[str] = [];
    for e in ev {
        out.append(e["kind"]);
    }
    return out;
}

# ---------------------------------------------------------------- the PRD scenario: Maya / Priya / Dan

test "serendipity_for: Maya (fact + intent) qualifies on the accessible-robotics piece; Priya and Dan do not" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me"))[0];

    maya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Maya Serendipity", status="confirmed"))[0];
    maya_fact = (root ++> Fact(text="works on accessible robotics", observed_at="2026-09-01T00:00:00"))[0];
    maya_fact +>:FactAbout():+> maya;
    maya_intent = (root ++> Intent(kind="need", text="feedback from wheelchair users", expires_at=""))[0];
    maya_intent +>:IntentAbout():+> maya;
    maya_note = (root ++> Note(text="Maya wants feedback from wheelchair users", kind="debrief", captured_at="2026-09-20T00:00:00"))[0];
    maya_note +>:AssertsIntent(span="feedback from wheelchair users"):+> maya_intent;

    priya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Priya Serendipity", status="confirmed"))[0];
    priya_fact = (root ++> Fact(text="partner at a climate-tech seed fund", observed_at="2026-09-05T00:00:00"))[0];
    priya_fact +>:FactAbout():+> priya;

    _dan = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Dan Serendipity", status="confirmed"))[0];
    # Dan has no Fact/Intent/Note at all.

    text = "New accessible robotics prototype seeks wheelchair users for feedback";
    result = serendipity_for(me, text, "", 5, now);

    names = _names(result);
    assert names == ["Maya Serendipity"], f"expected only Maya to qualify, got {names}";

    row = result[0];
    matched = row["matched"] as list[str];
    assert len(matched) >= 2, f"Maya must qualify with >=2 matched tokens, got {matched}";
    assert "accessible" in matched;
    assert "robotics" in matched;
    assert "wheelchair" in matched;
    assert "feedback" in matched;

    kinds = _evidence_kinds(row);
    assert "intent" in kinds, f"Maya's evidence must include the intent, got {kinds}";
    assert "fact" in kinds;

    why = row["why"] as str;
    assert why.startswith("Maya Serendipity"), f"why must cite Maya by name, got {why}";

    share_draft = row["share_draft"] as str;
    assert share_draft.startswith("Hi Maya Serendipity, saw this and thought of you: "), share_draft;
    assert share_draft.endswith("No pressure."), share_draft;
    assert text[:80] in share_draft, "no url given: share_draft falls back to the first 80 chars of text";
}

test "serendipity_for: the climate-tech-fund piece matches only Priya" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me 2"))[0];

    maya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Maya Serendipity 2", status="confirmed"))[0];
    maya_fact = (root ++> Fact(text="works on accessible robotics", observed_at="2026-09-01T00:00:00"))[0];
    maya_fact +>:FactAbout():+> maya;

    priya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Priya Serendipity 2", status="confirmed"))[0];
    priya_fact = (root ++> Fact(text="partner at a climate-tech seed fund", observed_at="2026-09-05T00:00:00"))[0];
    priya_fact +>:FactAbout():+> priya;

    _dan = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Dan Serendipity 2", status="confirmed"))[0];

    text = "Climate-tech seed funding round announced";
    result = serendipity_for(me, text, "https://example.com/article", 5, now);

    names = _names(result);
    assert names == ["Priya Serendipity 2"], f"expected only Priya to qualify, got {names}";

    row = result[0];
    matched = row["matched"] as list[str];
    assert "climate" in matched;
    assert "seed" in matched;
    assert len(matched) >= 2;

    share_draft = row["share_draft"] as str;
    assert "https://example.com/article" in share_draft, "a url must be used instead of the text excerpt";
}

test "serendipity_for: unrelated text (quarterly earnings) matches nobody" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me 3"))[0];

    maya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Maya Serendipity 3", status="confirmed"))[0];
    maya_fact = (root ++> Fact(text="works on accessible robotics", observed_at="2026-09-01T00:00:00"))[0];
    maya_fact +>:FactAbout():+> maya;

    priya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Priya Serendipity 3", status="confirmed"))[0];
    priya_fact = (root ++> Fact(text="partner at a climate-tech seed fund", observed_at="2026-09-05T00:00:00"))[0];
    priya_fact +>:FactAbout():+> priya;

    result = serendipity_for(me, "quarterly earnings", "", 5, now);
    assert result == [], f"expected no matches at all, got {_names(result)}";
}

test "serendipity_for: an empty/all-stopword paste never spends a traversal on a fake match" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me 4"))[0];
    maya = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Maya Serendipity 4", status="confirmed"))[0];
    maya_fact = (root ++> Fact(text="works on accessible robotics", observed_at="2026-09-01T00:00:00"))[0];
    maya_fact +>:FactAbout():+> maya;

    assert serendipity_for(me, "", "", 5, now) == [];
    assert serendipity_for(me, "a to it is", "", 5, now) == [];
}

# ---------------------------------------------------------------- the >=1-if-intent threshold

test "serendipity_for: a single matched token qualifies only when it came from an Intent" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me 5"))[0];

    epsilon = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Epsilon Serendipity", status="confirmed"))[0];
    epsilon_intent = (root ++> Intent(kind="open_to", text="wheelchair", expires_at=""))[0];
    epsilon_intent +>:IntentAbout():+> epsilon;

    zeta = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Zeta Serendipity", status="confirmed"))[0];
    zeta_fact = (root ++> Fact(text="wheelchair mechanic", observed_at="2026-09-01T00:00:00"))[0];
    zeta_fact +>:FactAbout():+> zeta;

    result = serendipity_for(me, "A wheelchair review", "", 5, now);
    names = _names(result);
    assert names == ["Epsilon Serendipity"], f"only the Intent-sourced single-token match should qualify, got {names}";
    assert result[0]["matched"] as list[str] == ["wheelchair"];
}

# ---------------------------------------------------------------- ordering: matched-count desc, then newest evidence

test "serendipity_for: ordered by matched-token count desc" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me 6"))[0];

    gamma = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Gamma Serendipity", status="confirmed"))[0];
    gamma_fact = (root ++> Fact(text="prototype about accessible robotics chair design", observed_at="2026-09-10T00:00:00"))[0];
    gamma_fact +>:FactAbout():+> gamma;

    delta = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Delta Serendipity", status="confirmed"))[0];
    delta_fact = (root ++> Fact(text="robotics chair fan", observed_at="2026-09-15T00:00:00"))[0];
    delta_fact +>:FactAbout():+> delta;

    text = "wheelchair accessible robotics chair prototype design showcase";
    result = serendipity_for(me, text, "", 5, now);

    assert _names(result) == ["Gamma Serendipity", "Delta Serendipity"], f"higher matched-count must come first regardless of evidence date, got {_names(result)}";
    assert len(result[0]["matched"] as list[str]) > len(result[1]["matched"] as list[str]);
}

test "serendipity_for: tied matched-token count breaks by newest evidence; limit caps the report" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    me = (root ++> Me(name="Serendipity-test Me 7"))[0];

    alpha = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Alpha Serendipity", status="confirmed"))[0];
    alpha_fact = (root ++> Fact(text="loves accessible robotics research", observed_at="2026-09-01T00:00:00"))[0];
    alpha_fact +>:FactAbout():+> alpha;

    beta = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Beta Serendipity", status="confirmed"))[0];
    beta_fact = (root ++> Fact(text="builds accessible tools for robotics teams", observed_at="2026-09-20T00:00:00"))[0];
    beta_fact +>:FactAbout():+> beta;

    text = "New accessible robotics update for research teams";

    uncapped = serendipity_for(me, text, "", 5, now);
    assert len(uncapped[0]["matched"] as list[str]) == len(uncapped[1]["matched"] as list[str]), "this fixture is designed to tie on matched count";
    assert _names(uncapped) == ["Beta Serendipity", "Alpha Serendipity"], f"tie must break toward the newer evidence, got {_names(uncapped)}";

    capped = serendipity_for(me, text, "", 1, now);
    assert len(capped) == 1, f"limit=1 must cap the report to one entry, got {len(capped)}";
    assert capped[0]["person"].name == "Beta Serendipity";
}

# ---------------------------------------------------------------- deterministic helpers directly

test "_confirmed_known_people: excludes proposed people and proposed edges, dedupes" {
    me = (root ++> Me(name="Serendipity-test Me 8"))[0];
    _confirmed = (me +>:Knows(status="confirmed", last_contact=""):+> Person(name="Confirmed Helper P", status="confirmed"))[0];
    _proposed_person = (me +>:Knows(status="reported", last_contact=""):+> Person(name="Proposed Person Helper P", status="proposed"))[0];
    _proposed_edge = (me +>:Knows(status="proposed", last_contact=""):+> Person(name="Proposed Edge Helper P", status="confirmed"))[0];

    people = _confirmed_known_people(me);
    names = [p.name for p in people];
    assert names == ["Confirmed Helper P"], f"expected only the confirmed person/edge pair, got {names}";
}

test "_match_person + _qualifies: org/title tokens count, and matched_from_intent gates the >=1 threshold" {
    now = datetime(2026, 9, 26, 12, 0, 0);
    p = (root ++> Person(name="Match Helper P", org="Robotics Labs", title="Wheelchair Engineer", status="confirmed"))[0];
    evidence = gather_evidence(p, now);   # no Fact/Intent/Note attached: org/title only

    m = _match_person(["wheelchair", "engineer"], p, evidence);
    matched = m["matched"] as list[str];
    assert "wheelchair" in matched, f"a title token must count, got {matched}";
    assert "engineer" in matched;
    assert not (m["matched_from_intent"] as bool);
    assert _qualifies(matched, False), "2 org/title-sourced tokens must qualify without any intent";
    assert not _qualifies(["wheelchair"], False), "a single non-intent-sourced token must not qualify";
    assert _qualifies(["wheelchair"], True), "a single intent-sourced token must qualify";
}

test "pick_top_evidence: prefers an Intent over a Fact, breaks ties by newest observed_at, None when nothing overlaps" {
    fact = EvidenceItem(id="f-1", kind="fact", observed_at="2026-09-20T00:00:00", span="accessible robotics fact");
    intent = EvidenceItem(id="i-1", kind="intent", observed_at="2026-09-01T00:00:00", span="accessible robotics intent");
    note = EvidenceItem(id="n-1", kind="note", observed_at="2026-09-25T00:00:00", span="accessible robotics note");

    top = pick_top_evidence(["accessible", "robotics"], [fact, intent, note]);
    assert top is not None and top.id == "i-1", "an Intent must win over a Fact/Note even when older";

    older_fact = EvidenceItem(id="f-old", kind="fact", observed_at="2026-01-01T00:00:00", span="accessible robotics old");
    newer_fact = EvidenceItem(id="f-new", kind="fact", observed_at="2026-09-01T00:00:00", span="accessible robotics new");
    top2 = pick_top_evidence(["accessible", "robotics"], [older_fact, newer_fact]);
    assert top2 is not None and top2.id == "f-new", "same kind: the newer evidence item must win the tie";

    unrelated = EvidenceItem(id="u-1", kind="fact", observed_at="2026-09-01T00:00:00", span="totally unrelated span");
    assert pick_top_evidence(["accessible", "robotics"], [unrelated]) is None;
}

test "_topic_phrase and _why_fragment: text-order topic, Intent/Fact/org-title clauses" {
    topic = _topic_phrase(["wheelchair", "accessible", "robotics", "chair"], ["accessible", "robotics"]);
    assert topic == "accessible robotics", f"topic must follow text order, capped at two tokens, got {topic}";

    assert _topic_phrase(["quarterly", "earnings"], []) == "this";

    p = (root ++> Person(name="Fragment Helper P", org="ClimateCo", title="Partner", status="confirmed"))[0];
    intent_ev = EvidenceItem(id="i-2", kind="intent", observed_at="2026-09-01", span="feedback from wheelchair users");
    frag = _why_fragment(p, intent_ev, "accessible robotics");
    assert frag == "wants feedback from wheelchair users; this piece is about accessible robotics", frag;

    fact_ev = EvidenceItem(id="f-2", kind="fact", observed_at="2026-09-01", span="partner at a climate-tech seed fund");
    frag2 = _why_fragment(p, fact_ev, "climate tech");
    assert frag2 == "is known for partner at a climate-tech seed fund; this piece is about climate tech", frag2;

    frag3 = _why_fragment(p, None, "climate tech");
    assert frag3 == "works as Partner at ClimateCo; this piece is about climate tech", frag3;
}

test "_newest_observed_at: newest wins, unparsable/empty ignored" {
    items = [
        EvidenceItem(id="a", kind="fact", observed_at="2026-01-01T00:00:00", span="x"),
        EvidenceItem(id="b", kind="fact", observed_at="2026-09-01T00:00:00", span="y"),
        EvidenceItem(id="c", kind="fact", observed_at="not-a-date", span="z"),
        EvidenceItem(id="d", kind="fact", observed_at="", span="w")
    ];
    assert _newest_observed_at(items) == "2026-09-01T00:00:00";
    assert _newest_observed_at([]) == "";
}
