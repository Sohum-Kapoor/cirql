"""Tests for capture.sv.jac — the deterministic parts only (no LLM call).

Annex of capture.sv.jac; run with `jac test capture.sv.jac`. Per `jac-testing`,
all tests here share one persisted root across runs, so every Person name below
carries a random per-call suffix (`_uid()`) — this guarantees a name is always
genuinely new, whether this is the first run ever or the hundredth.
"""

import from capture { CaptureExtraction, XPerson, XFact, XIntent, XPromise, XTie, safe_span, resolve_person, apply_extraction }
import from schema { Fact, Intent, Knows, Me, Note, Person, Promise }
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

test "span lookup: verbatim substring wins, else fallback, never empty" {
    note = _fresh_note("She works on accessible robotics and knows Arjun.");
    assert safe_span("accessible robotics", note, "fallback") == "accessible robotics";
    assert safe_span("not anywhere in the note", note, "the fallback text") == "the fallback text";
    assert safe_span("also not in note", note, "") == "note";
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

    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;
    maya_entry = people[0];
    maya = maya_entry["person"] as Person;
    assert maya.name == maya_name;
    assert maya_entry["is_new"];
    assert len(maya_entry["ambiguous_with"] as list[str]) == 0;
    assert maya.status == "confirmed";

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
    arjun_id = tie["to"] as str;
    assert arjun_id != jid(maya);

    # Arjun was never in `people` — resolved only via the tie, created proposed.
    known: list[Person] = [me ->:Knows:->];
    arjun_matches: list[Person] = [];
    for p in known {
        if jid(p) == arjun_id {
            arjun_matches.append(p);
        }
    }
    assert len(arjun_matches) == 1;
    assert arjun_matches[0].name == arjun_name;
    assert arjun_matches[0].status == "proposed";
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
