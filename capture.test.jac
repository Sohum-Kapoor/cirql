"""Tests for capture.sv.jac — the deterministic parts only (no LLM call).

Annex of capture.sv.jac; run with `jac test capture.sv.jac`. Per `jac-testing`,
all tests here share one persisted root across runs, so every Person name below
carries a random per-call suffix (`_uid()`) — this guarantees a name is always
genuinely new, whether this is the first run ever or the hundredth.
"""

import from capture { CaptureExtraction, XPerson, XFact, XIntent, XPromise, XTie, safe_span, resolve_person, apply_extraction }
import from schema { Fact, Intent, Knows, Me, Mentions, Note, Person, Promise, Reported }
import uuid;
import from datetime { datetime }

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

def _fresh_me() -> Me {
    return (root ++> Me(name="me-" + _uid()))[0];
}

def _fresh_note(text: str, kind: str = "debrief") -> Note {
    return (root ++> Note(text=text, kind=kind, captured_at=datetime.now().isoformat()))[0];
}

test "get-or-create Person by name: new, then found on a fresh call" {
    me = _fresh_me();
    note = _fresh_note("Met Priya at the meetup.");
    name = "Priya" + _uid();

    r1: dict[str, any] = {};
    entry1 = resolve_person(name, me, note, r1, org="Acme", title="Eng");
    p1 = entry1["person"] as Person;
    assert entry1["is_new"];
    assert len(entry1["ambiguous_with"] as list[str]) == 0;
    assert p1.status == "confirmed";
    assert p1.org == "Acme";
    assert p1.title == "Eng";

    # A fresh `resolved` dict simulates a brand-new Capture call reusing the
    # same Me — this is the path a second debrief note takes in production.
    r2: dict[str, any] = {};
    entry2 = resolve_person(name.upper(), me, note, r2);   # case-insensitive match
    p2 = entry2["person"] as Person;
    assert not entry2["is_new"];
    assert jid(p2) == jid(p1);
    assert len(entry2["ambiguous_with"] as list[str]) == 0;
}

test "ambiguity: two known people share a first token, never guessed" {
    me = _fresh_me();
    note = _fresh_note("Ran into Sam at the conference.");
    first_name = "Sam" + _uid();

    r0: dict[str, any] = {};
    e_a = resolve_person(first_name + " Lee", me, note, r0);
    e_b = resolve_person(first_name + " Patel", me, note, r0);
    a = e_a["person"] as Person;
    b = e_b["person"] as Person;

    # Fresh dict: simulate a later Capture call that only saw the first name.
    r1: dict[str, any] = {};
    entry = resolve_person(first_name, me, note, r1);
    p = entry["person"] as Person;
    ambiguous_with = entry["ambiguous_with"] as list[str];

    assert entry["is_new"];
    assert p.status == "proposed";
    assert len(ambiguous_with) == 2;
    assert jid(a) in ambiguous_with;
    assert jid(b) in ambiguous_with;
    assert jid(p) != jid(a);
    assert jid(p) != jid(b);
}

test "single-token name matching exactly ONE known person resolves to them" {
    me = _fresh_me();
    note = _fresh_note("Ran into Maya at the cafe.");
    suffix = _uid();
    full_name = "Maya" + suffix + " Chen";
    first_name = "Maya" + suffix;

    r0: dict[str, any] = {};
    known_entry = resolve_person(full_name, me, note, r0);
    known = known_entry["person"] as Person;

    # Fresh dict: simulate a later Capture call that only saw the first name,
    # and exactly one known person shares that first token.
    r1: dict[str, any] = {};
    entry = resolve_person(first_name, me, note, r1);
    p = entry["person"] as Person;

    assert not entry["is_new"];
    assert jid(p) == jid(known);
    assert len(entry["ambiguous_with"] as list[str]) == 0;
}

test "span lookup: verbatim substring wins, else fallback, else 80-char note prefix" {
    note = _fresh_note("She works on accessible robotics and knows Arjun.");
    assert safe_span("accessible robotics", note, "fallback") == "accessible robotics";
    assert safe_span("not anywhere in the note", note, "the fallback text") == "the fallback text";
    assert safe_span("also not in note", note, "") == note.text[:80];
}

test "apply_extraction: J2 example — five kinds, all provenance-linked" {
    me = _fresh_me();
    suffix = _uid();
    maya_name = "Maya" + suffix;
    arjun_name = "Arjun" + suffix;
    note_text = f"Met {maya_name} at JacHacks. She works on accessible robotics, knows {arjun_name} from their lab, wants feedback from wheelchair users, I promised to send our demo.";
    note = _fresh_note(note_text);

    extraction = CaptureExtraction(
        people=[XPerson(name=maya_name, org="", title="", span=f"Met {maya_name} at JacHacks")],
        facts=[XFact(about_name=maya_name, text="works on accessible robotics", span="works on accessible robotics")],
        intents=[XIntent(about_name=maya_name, kind="need", text="feedback from wheelchair users", span="wants feedback from wheelchair users")],
        promises=[XPromise(to_name=maya_name, text="send our demo", due="", span="I promised to send our demo")],
        ties=[XTie(from_name=maya_name, to_name=arjun_name, span=f"knows {arjun_name} from their lab")]
    );

    result = apply_extraction(note, me, extraction);

    assert result["note_id"] == jid(note);

    # Every unique person touched anywhere (Maya via `people`, Arjun via the
    # tie only) shows up exactly once in `people`.
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 2;

    by_name: dict[str, any] = {};
    for entry in people {
        p = entry["person"] as Person;
        by_name[p.name] = entry;
    }

    maya_entry = by_name[maya_name];
    maya = maya_entry["person"] as Person;
    assert maya_entry["is_new"];
    assert len(maya_entry["ambiguous_with"] as list[str]) == 0;
    assert maya.status == "confirmed";
    assert maya_entry["span"] == f"Met {maya_name} at JacHacks";

    arjun_entry = by_name[arjun_name];
    arjun = arjun_entry["person"] as Person;
    assert arjun_entry["is_new"];
    assert arjun.status == "proposed";
    assert arjun_entry["span"] == f"knows {arjun_name} from their lab";

    facts = result["facts"] as list[dict[str, any]];
    assert len(facts) == 1;
    assert facts[0]["about"] == jid(maya);
    assert facts[0]["span"] == "works on accessible robotics";
    fact = facts[0]["fact"] as Fact;
    assert fact.text == "works on accessible robotics";

    intents = result["intents"] as list[dict[str, any]];
    assert len(intents) == 1;
    assert intents[0]["about"] == jid(maya);
    intent = intents[0]["intent"] as Intent;
    assert intent.kind == "need";
    assert intent.text == "feedback from wheelchair users";

    promises = result["promises"] as list[dict[str, any]];
    assert len(promises) == 1;
    assert promises[0]["to"] == jid(maya);
    promise = promises[0]["promise"] as Promise;
    assert promise.text == "send our demo";

    ties = result["ties"] as list[dict[str, any]];
    assert len(ties) == 1;
    tie = ties[0];
    assert tie["from"] == jid(maya);
    assert tie["to"] == jid(arjun);
}

test "tie-only person stays proposed even when the LLM also lists them in people" {
    # Regression: the live LLM does include tie targets in `people` (per the
    # CaptureExtraction.people sem string), so resolution must not treat
    # "is in x.people" as proof the author actually met them.
    me = _fresh_me();
    suffix = _uid();
    maya_name = "Maya" + suffix;
    arjun_name = "Arjun" + suffix;
    note = _fresh_note(f"Met {maya_name}. She knows {arjun_name} from their lab.");

    extraction = CaptureExtraction(
        people=[
            XPerson(name=maya_name, org="", title="", span=f"Met {maya_name}"),
            XPerson(name=arjun_name, org="", title="", span=f"knows {arjun_name} from their lab")
        ],
        facts=[XFact(about_name=maya_name, text="works on accessible robotics", span="works on accessible robotics")],
        intents=[],
        promises=[],
        ties=[XTie(from_name=maya_name, to_name=arjun_name, span=f"knows {arjun_name} from their lab")]
    );

    result = apply_extraction(note, me, extraction);
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 2;

    by_name: dict[str, any] = {};
    for entry in people {
        p = entry["person"] as Person;
        by_name[p.name] = entry;
    }

    maya_entry = by_name[maya_name];
    maya = maya_entry["person"] as Person;
    assert maya.status == "confirmed";

    arjun_entry = by_name[arjun_name];
    arjun = arjun_entry["person"] as Person;
    assert arjun.status == "proposed";
    assert arjun_entry["is_new"];
}

test "one person touched by multiple categories: one people entry, one Mentions edge" {
    me = _fresh_me();
    suffix = _uid();
    name = "Devika" + suffix;
    note = _fresh_note(f"Met {name}. She is a product manager. {name} wants intros to designers. I promised to send her my notes.");

    extraction = CaptureExtraction(
        people=[XPerson(name=name, org="", title="PM", span=f"Met {name}")],
        facts=[XFact(about_name=name, text="is a product manager", span="is a product manager")],
        intents=[XIntent(about_name=name, kind="need", text="intros to designers", span="wants intros to designers")],
        promises=[XPromise(to_name=name, text="send her my notes", due="", span="I promised to send her my notes")],
        ties=[]
    );

    result = apply_extraction(note, me, extraction);
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;

    p = people[0]["person"] as Person;
    # First mention wins: Devika is resolved via the `people` category first
    # (span "Met {name}"), so that span sticks even though facts/intents/
    # promises about her come later with different spans.
    assert people[0]["span"] == f"Met {name}";
    mentions: list[Person] = [note ->:Mentions:->];
    count = 0;
    for m in mentions {
        if jid(m) == jid(p) {
            count += 1;
        }
    }
    assert count == 1;
}

test "duplicate people entries in x.people are deduped by normalized name" {
    me = _fresh_me();
    suffix = _uid();
    name = "Farah" + suffix;
    note = _fresh_note(f"Met {name} twice in the note, once as {name.upper()}.");

    extraction = CaptureExtraction(
        people=[
            XPerson(name=name, org="", title="", span=f"Met {name}"),
            XPerson(name=name.upper(), org="", title="", span=f"Met {name}")
        ],
        facts=[],
        intents=[],
        promises=[],
        ties=[]
    );

    result = apply_extraction(note, me, extraction);
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;
}

test "empty about/to/from names are skipped; no Person with an empty name" {
    me = _fresh_me();
    note = _fresh_note("Some vague debrief with no clear names.");

    extraction = CaptureExtraction(
        people=[XPerson(name="", org="", title="", span="")],
        facts=[XFact(about_name="  ", text="some fact", span="some fact")],
        intents=[XIntent(about_name="", kind="need", text="some need", span="some need")],
        promises=[XPromise(to_name="   ", text="some promise", due="", span="some promise")],
        ties=[XTie(from_name="", to_name="Someone", span="knows Someone")]
    );

    result = apply_extraction(note, me, extraction);

    assert result["people"] == [];
    assert result["facts"] == [];
    assert result["intents"] == [];
    assert result["promises"] == [];
    assert result["ties"] == [];

    known: list[Person] = [me ->:Knows:->];
    assert len(known) == 0;
    for p in known {
        assert len(p.name.strip()) > 0;
    }
}

test "reported tie: equal-name self-tie skipped; duplicate ties don't duplicate the edge" {
    me = _fresh_me();
    suffix = _uid();
    a_name = "Priya" + suffix;
    b_name = "Rahul" + suffix;
    note = _fresh_note(f"{a_name} knows {b_name}.");

    extraction = CaptureExtraction(
        people=[],
        facts=[],
        intents=[],
        promises=[],
        ties=[
            XTie(from_name=a_name, to_name=b_name, span=f"{a_name} knows {b_name}"),
            XTie(from_name=a_name, to_name=b_name, span=f"{a_name} knows {b_name}"),
            XTie(from_name=a_name, to_name=a_name, span="self-tie, must be skipped")
        ]
    );

    result = apply_extraction(note, me, extraction);
    ties = result["ties"] as list[dict[str, any]];
    # Both A->B entries are still reported ...
    assert len(ties) == 2;

    a_id = ties[0]["from"] as str;
    b_id = ties[0]["to"] as str;
    a = jobj(a_id) as Person;
    b = jobj(b_id) as Person;

    # ... but only one physical Reported edge was ever created.
    edges: list[Person] = [a ->:Reported:->];
    edge_count = 0;
    for e in edges {
        if jid(e) == jid(b) {
            edge_count += 1;
        }
    }
    assert edge_count == 1;
}

test "intent kind synonyms normalize to need / offer / open_to" {
    me = _fresh_me();
    note = _fresh_note("Various asks and offers.");
    suffix = _uid();
    name = "Kai" + suffix;

    raw_kinds: list[str] = ["need", "needs", "want", "wants", "looking for", "offer", "offers", "can offer", "open_to", "", "weird"];
    expected_kinds: list[str] = ["need", "need", "need", "need", "need", "offer", "offer", "offer", "open_to", "open_to", "open_to"];

    for i = 0 to i < len(raw_kinds) by i += 1 {
        raw = raw_kinds[i];
        expected = expected_kinds[i];
        extraction = CaptureExtraction(
            people=[],
            facts=[],
            intents=[XIntent(about_name=name, kind=raw, text="something", span="something")],
            promises=[],
            ties=[]
        );
        result = apply_extraction(note, me, extraction);
        intents = result["intents"] as list[dict[str, any]];
        intent = intents[0]["intent"] as Intent;
        assert intent.kind == expected, f"kind '{raw}' -> expected '{expected}' got '{intent.kind}'";
    }
}

test "people[].span falls back to the name when the LLM span isn't a substring of the note" {
    me = _fresh_me();
    suffix = _uid();
    name = "Zara" + suffix;
    note = _fresh_note(f"Talked with {name} about robotics.");

    extraction = CaptureExtraction(
        people=[XPerson(name=name, org="", title="", span="this text is not anywhere in the note")],
        facts=[],
        intents=[],
        promises=[],
        ties=[]
    );

    result = apply_extraction(note, me, extraction);
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;
    assert people[0]["span"] == name;
}

test "empty extraction still yields note_id and empty arrays — note never lost" {
    me = _fresh_me();
    note = _fresh_note("Small talk, nothing extractable.");
    extraction = CaptureExtraction(people=[], facts=[], intents=[], promises=[], ties=[]);

    result = apply_extraction(note, me, extraction);

    assert result["note_id"] == jid(note);
    assert result["people"] == [];
    assert result["facts"] == [];
    assert result["intents"] == [];
    assert result["promises"] == [];
    assert result["ties"] == [];
    assert note.text == "Small talk, nothing extractable.";
}
