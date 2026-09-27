"""Tests for capture.sv.jac — the deterministic parts only (no LLM call).

Annex of capture.sv.jac; run with `jac test capture.sv.jac`. Per `jac-testing`,
all tests here share one persisted root across runs, so every Person name below
carries a random per-call suffix (`_uid()`) — this guarantees a name is always
genuinely new, whether this is the first run ever or the hundredth.
"""

import from capture { CaptureExtraction, XPerson, XFact, XIntent, XPromise, XTie, safe_span, resolve_person, apply_extraction, hedge_fact_text, fact_source_kind, specific_follow_up, promise_is_only_a_want, default_how_met, second_person, attach_metat_for_new_people }
import from schema { Event, Fact, HasEvent, Intent, Knows, Me, Mentions, MetAt, Note, Person, Promise, Reported, PromiseTo }
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

test "single-token name matching exactly ONE known person is ambiguous, never a silent merge (SOH-212)" {
    me = _fresh_me();
    note = _fresh_note("Ran into Maya at the cafe.");
    suffix = _uid();
    full_name = "Maya" + suffix + " Chen";
    first_name = "Maya" + suffix;

    r0: dict[str, any] = {};
    known_entry = resolve_person(full_name, me, note, r0);
    known = known_entry["person"] as Person;

    # Fresh dict: a later Capture call that only saw the first name.
    r1: dict[str, any] = {};
    entry = resolve_person(first_name, me, note, r1);
    p = entry["person"] as Person;

    assert entry["is_new"];
    assert p.status == "proposed";
    assert jid(p) != jid(known);
    assert entry["ambiguous_with"] == [jid(known)];
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

# ---------------------------------------------------------------- SOH-212 persona fixes

test "names: honorific / initial / bare-first vs known people -> ambiguous; different last names -> distinct" {
    me = _fresh_me();
    note = _fresh_note("Saw Helen and Maya O. again.");
    u = _uid();
    r0: dict[str, any] = {};
    helen = resolve_person(f"Dr. Helen{u} Marsh-Whitcombe", me, note, r0)["person"] as Person;
    maya = resolve_person(f"Maya{u} Okafor", me, note, r0)["person"] as Person;
    assert helen.name == f"Helen{u} Marsh-Whitcombe", "honorific dropped from the display name";
    assert helen.title == "Dr.";

    r1: dict[str, any] = {};
    e_helen = resolve_person(f"Helen{u}", me, note, r1);
    assert e_helen["is_new"] and (e_helen["person"] as Person).status == "proposed";
    assert e_helen["ambiguous_with"] == [jid(helen)];

    e_mo = resolve_person(f"Maya{u} O.", me, note, r1);
    assert e_mo["is_new"] and (e_mo["person"] as Person).status == "proposed";
    assert e_mo["ambiguous_with"] == [jid(maya)];

    e_ml = resolve_person(f"Maya{u} Lindqvist", me, note, r1);
    assert e_ml["is_new"];
    assert (e_ml["person"] as Person).status == "confirmed";
    assert e_ml["ambiguous_with"] == [];

    # Same clean name with a different honorific -> the same person.
    r2: dict[str, any] = {};
    e_same = resolve_person(f"Prof Helen{u} Marsh-Whitcombe", me, note, r2);
    assert not e_same["is_new"];
    assert jid(e_same["person"] as Person) == jid(helen);
}

test "same name, different org -> ambiguous; distinct_from forces a new proposed person" {
    me = _fresh_me();
    note = _fresh_note("Dana (NOT the MidWest Cold Chain one) runs ops at Fleetly.");
    u = _uid();
    r0: dict[str, any] = {};
    dana = resolve_person(f"Dana{u} Whitfield", me, note, r0, org="MidWest Cold Chain")["person"] as Person;

    r1: dict[str, any] = {};
    e_org = resolve_person(f"Dana{u} Whitfield", me, note, r1, org="Fleetly");
    assert e_org["is_new"] and (e_org["person"] as Person).status == "proposed";
    assert e_org["ambiguous_with"] == [jid(dana)];

    x = CaptureExtraction(
        people=[XPerson(name=f"Dana{u}", org="", title="", span="Dana", distinct_from=f"Dana{u} Whitfield")],
        facts=[], intents=[], promises=[], ties=[]
    );
    result = apply_extraction(note, me, x);
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;
    p = people[0]["person"] as Person;
    assert people[0]["is_new"];
    assert p.status == "proposed";
    assert jid(p) != jid(dana);
    assert jid(dana) in (people[0]["ambiguous_with"] as list[str]);
}

test "a person known only by description is created proposed and the promise to them still attaches" {
    me = _fresh_me();
    u = _uid();
    desc = f"the young man from the robotics thing {u}";
    note = _fresh_note(f"{desc}, cannot remember his name, built the wheelchair sensor. I said I would send him the grant form.");
    x = CaptureExtraction(
        people=[XPerson(name=desc, org="", title="", span=desc, named=False)],
        facts=[XFact(about_name=desc, text="built the wheelchair sensor", span="built the wheelchair sensor")],
        intents=[],
        promises=[XPromise(to_name=desc, text="send him the grant form", due="", span="I said I would send him the grant form")],
        ties=[]
    );
    result = apply_extraction(note, me, x);
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;
    p = people[0]["person"] as Person;
    assert p.status == "proposed";
    assert p.name == desc;
    knows = [edge me ->:Knows:-> p];
    assert len(knows) == 1 and knows[0].status == "proposed";
    promises = result["promises"] as list[dict[str, any]];
    assert len(promises) == 1 and promises[0]["to"] == jid(p);
    assert len([p <-:PromiseTo:<-]) == 1;
}

test "hedge guard: a hedged span keeps its hedge; a flat span is untouched; notes-to-self are source_kind=self" {
    assert hedge_fact_text("Works at Siemens in Detroit.", "er arbeitet bei siemens?? in detroit") == "Possibly: Works at Siemens in Detroit.";
    assert hedge_fact_text("Maybe looking for a room.", "maybe a room") == "Maybe looking for a room.";
    assert hedge_fact_text("Possibly works at Siemens.", "I think siemens") == "Possibly works at Siemens.";
    assert hedge_fact_text("Works at Siemens.", "works at Siemens") == "Works at Siemens.";
    assert fact_source_kind("reported", "so there is a potential conflict of interest I should note") == "self";
    assert fact_source_kind("self", "anything") == "self";
    assert fact_source_kind("reported", "runs the youth program") == "reported";

    me = _fresh_me();
    u = _uid();
    note = _fresh_note(f"Klaus{u} - er arbeitet bei siemens?? maybe a room.");
    x = CaptureExtraction(
        people=[XPerson(name=f"Klaus{u}", org="", title="", span=f"Klaus{u}")],
        facts=[XFact(about_name=f"Klaus{u}", text="Works at Siemens in Detroit.", span="er arbeitet bei siemens??")],
        intents=[], promises=[], ties=[]
    );
    result = apply_extraction(note, me, x);
    f = (result["facts"] as list[dict[str, any]])[0]["fact"] as Fact;
    assert f.text.startswith("Possibly: ");
}

test "SOH-166 how_met: an explicit how_met labels NEW Knows edges only; the default is word-trimmed" {
    me = _fresh_me();
    u = _uid();
    r0: dict[str, any] = {};
    seed_note = _fresh_note(f"Met Omar{u} Haddad after the county accessibility panel downtown last night, great chat.");
    omar = resolve_person(f"Omar{u} Haddad", me, seed_note, r0)["person"] as Person;
    old_how = ([edge me ->:Knows:-> omar])[0].how_met;
    assert old_how == f"from a debrief on {seed_note.captured_at[:10]}", f"default how_met is a human line, got {old_how}";

    note = _fresh_note(f"Coffee with Lena{u} Vogel and Omar{u} Haddad.");
    x = CaptureExtraction(
        people=[
            XPerson(name=f"Lena{u} Vogel", org="", title="", span=f"Lena{u} Vogel"),
            XPerson(name=f"Omar{u} Haddad", org="", title="", span=f"Omar{u} Haddad")
        ],
        facts=[], intents=[], promises=[], ties=[]
    );
    result = apply_extraction(note, me, x, how_met="coffee chat — Ross café");
    people = result["people"] as list[dict[str, any]];
    assert len(people) == 2;
    for entry in people {
        p = entry["person"] as Person;
        k = ([edge me ->:Knows:-> p])[0];
        if entry["is_new"] {
            assert k.how_met == "coffee chat — Ross café";
        } else {
            assert jid(p) == jid(omar);
            assert k.how_met == old_how, "an existing person's edge is untouched";
        }
    }
}

test "SOH-212 a bare 'follow up' promise names what the person wanted in the same note" {
    assert specific_follow_up("Follow up", ["wants ROI deck by Fri"]) == "Follow up on: ROI deck by Fri";
    assert specific_follow_up("Follow up.", []) == "Follow up.";
    assert specific_follow_up("send the ROI deck", ["ROI deck"]) == "send the ROI deck";

    me = _fresh_me();
    u = _uid();
    note = _fresh_note(f"Dana{u} W, Fleetly ops. wants ROI deck by Fri. Follow up Thu.");
    x = CaptureExtraction(
        people=[XPerson(name=f"Dana{u} W", org="Fleetly", title="ops", span=f"Dana{u} W")],
        facts=[],
        intents=[XIntent(about_name=f"Dana{u} W", kind="need", text="Wants ROI deck by Fri", span="wants ROI deck by Fri")],
        promises=[XPromise(to_name=f"Dana{u} W", text="Follow up", due="Thu", span="Follow up Thu")],
        ties=[]
    );
    result = apply_extraction(note, me, x);
    pr = (result["promises"] as list[dict[str, any]])[0]["promise"] as Promise;
    assert pr.text == "Follow up on: ROI deck by Fri", pr.text;
    assert pr.due == "Thu";
}

# ---------------------------------------------------------------- SOH-214

test "SOH-214 a 'promise' that is only the person's want becomes their need; the ROI-deck follow-up stays a promise" {
    assert promise_is_only_a_want("She wants intros to founders hiring in Chicago", "Priya Nair, recruiter. She wants intros to founders hiring in Chicago.");
    assert not promise_is_only_a_want("wants ROI deck by Fri", "Dana W, Fleetly ops. wants ROI deck by Fri. Follow up Thu.");
    assert not promise_is_only_a_want("I said I'd send her the deck she wants", "I said I'd send her the deck she wants.");
    assert not promise_is_only_a_want("send the scholarship link", "I will send the scholarship link.");

    me = _fresh_me();
    u = _uid();
    priya = f"Priya{u} Nair";
    note = _fresh_note(f"{priya}, recruiter at Hirewell. She wants intros to founders hiring in Chicago.");
    x = CaptureExtraction(
        people=[XPerson(name=priya, org="Hirewell", title="recruiter", span=priya)],
        facts=[], intents=[],
        promises=[XPromise(to_name=priya, text="intros to founders hiring in Chicago", due="", span="She wants intros to founders hiring in Chicago")],
        ties=[]
    );
    result = apply_extraction(note, me, x);
    assert len(result["promises"] as list[dict[str, any]]) == 0, "no promise without the speaker's commitment";
    intents = result["intents"] as list[dict[str, any]];
    assert len(intents) == 1;
    it = intents[0]["intent"] as Intent;
    assert it.kind == "need" and it.text == "intros to founders hiring in Chicago";
    pid = jid((result["people"] as list[dict[str, any]])[0]["person"] as Person);
    assert intents[0]["about"] == pid;

    note2 = _fresh_note(f"Dana{u} W, Fleetly ops. wants ROI deck by Fri. Follow up Thu.");
    x2 = CaptureExtraction(
        people=[XPerson(name=f"Dana{u} W", org="Fleetly", title="ops", span=f"Dana{u} W")],
        facts=[], intents=[],
        promises=[XPromise(to_name=f"Dana{u} W", text="send the ROI deck", due="Fri", span="wants ROI deck by Fri")],
        ties=[]
    );
    r2 = apply_extraction(note2, me, x2);
    prs = r2["promises"] as list[dict[str, any]];
    assert len(prs) == 1 and (prs[0]["promise"] as Promise).text == "send the ROI deck";
}

test "SOH-214 default how_met is a human line, never the raw note" {
    assert default_how_met("debrief", "2026-09-26T18:00:00") == "from a debrief on 2026-09-26";
    assert default_how_met("paste", "2026-09-26T18:00:00") == "from a pasted note on 2026-09-26";
    assert default_how_met("import", "2026-09-26T18:00:00") == "from an import on 2026-09-26";
    assert default_how_met("about_me", "2026-09-26T18:00:00") == "from your about-me on 2026-09-26";

    me = _fresh_me();
    u = _uid();
    note = _fresh_note(f"Dana{u} Whitfield - VP ops at MidWest Cold Chain. Luis runs sales.", kind="paste");
    x = CaptureExtraction(people=[XPerson(name=f"Dana{u} Whitfield", org="", title="", span=f"Dana{u} Whitfield")], facts=[], intents=[], promises=[], ties=[]);
    r = apply_extraction(note, me, x);
    p = (r["people"] as list[dict[str, any]])[0]["person"] as Person;
    k = ([edge me ->:Knows:-> p])[0];
    assert k.how_met == f"from a pasted note on {note.captured_at[:10]}", k.how_met;
    assert "Whitfield" not in k.how_met;
}

test "SOH-214 second_person: 'the author/speaker/user/writer' becomes 'you' at word boundaries" {
    assert second_person("Gave the author her card.") == "Gave you her card.";
    assert second_person("The Speaker was unsure where she works.") == "You were unsure where she works.";
    assert second_person("Wants THE USER's deck") == "Wants your deck";
    assert second_person("Owes the writer a call; the author is invited") == "Owes you a call; you are invited";
    assert second_person("Works with the authority board") == "Works with the authority board", "whole words only";
    assert second_person("Mentored the users group") == "Mentored the users group";

    me = _fresh_me();
    u = _uid();
    note = _fresh_note(f"Lena{u} Vogel gave me her card.");
    x = CaptureExtraction(
        people=[XPerson(name=f"Lena{u} Vogel", org="", title="", span=f"Lena{u} Vogel")],
        facts=[XFact(about_name=f"Lena{u} Vogel", text="Gave the author her card.", span="gave me her card")],
        intents=[], promises=[], ties=[]
    );
    r = apply_extraction(note, me, x);
    f = (r["facts"] as list[dict[str, any]])[0]["fact"] as Fact;
    assert f.text == "Gave you her card.", f.text;
}

# ---------------------------------------------------------------- SOH-217: Capture(event_id) -> MetAt for new people only

test "attach_metat_for_new_people: only NEW people get a MetAt tie to the event, existing people don't" {
    me = _fresh_me();
    suffix = _uid();
    note = _fresh_note(f"Met Priya{suffix} and caught up with Arjun{suffix}.");
    event = (me +>:HasEvent:+> Event(name="JacHacks " + suffix, created_at=""))[0];

    new_name = f"Priya{suffix}";
    existing_name = f"Arjun{suffix}";

    # `existing` is already known BEFORE this capture (simulates a person from an earlier Capture).
    r0: dict[str, any] = {};
    existing_entry = resolve_person(existing_name, me, note, r0);
    existing = existing_entry["person"] as Person;

    x = CaptureExtraction(
        people=[
            XPerson(name=new_name, org="", title="", span=new_name),
            XPerson(name=existing_name, org="", title="", span=existing_name)
        ],
        facts=[], intents=[], promises=[], ties=[]
    );
    r = apply_extraction(note, me, x);

    attach_metat_for_new_people(note, event, r);

    people_report = r["people"] as list[dict[str, any]];
    new_entry = [e for e in people_report if (e["person"] as Person).name == new_name][0];
    existing_entry2 = [e for e in people_report if jid(e["person"] as Person) == jid(existing)][0];
    assert new_entry["is_new"] as bool;
    assert not (existing_entry2["is_new"] as bool);

    new_person = new_entry["person"] as Person;
    new_metat = [edge new_person ->:MetAt:-> event];
    assert len(new_metat) == 1;
    assert new_metat[0].source_note == jid(note);

    existing_metat = [edge existing ->:MetAt:-> event];
    assert len(existing_metat) == 0, "an already-known person is never auto-attached to the event";
}

test "attach_metat_for_new_people: no-op when result[\"people\"] is empty" {
    me = _fresh_me();
    suffix = _uid();
    note = _fresh_note("Nothing notable happened.");
    event = (me +>:HasEvent:+> Event(name="Empty Event " + suffix, created_at=""))[0];

    empty_result = {"note_id": jid(note), "people": [], "facts": [], "intents": [], "promises": [], "ties": []};
    attach_metat_for_new_people(note, event, empty_result);

    assert len([event <-:MetAt:<-]) == 0;
}
