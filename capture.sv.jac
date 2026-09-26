"""Capture — a debrief note becomes people, facts, intents, promises, ties.

OWNER: Person A. See contracts/walkers.md `Capture(text, kind)` for the exact
report shape. Extraction is ONE `by llm` call (free-tier rate limits; never
loop LLM calls); graph-writing is the deterministic `apply_extraction` def,
tested without the LLM in capture.test.jac.
"""

import from schema {
    Me, Person, Note, Fact, Intent, Promise,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo
}
import from llm { llm }
import from datetime { datetime }
import from freshness { default_expiry }
import from names { name_key, match_names, trim_words }


# ---------------------------------------------------------------- LLM shape

obj XPerson {
    has name: str;
    has org: str;
    has title: str;
    has span: str;
    has named: bool = True;
    has distinct_from: str = "";
}

obj XFact {
    has about_name: str;
    has text: str;
    has span: str;
    has source_kind: str = "reported";
}

obj XIntent {
    has about_name: str;
    has kind: str;
    has text: str;
    has span: str;
}

obj XPromise {
    has to_name: str;
    has text: str;
    has due: str;
    has span: str;
}

obj XTie {
    has from_name: str;
    has to_name: str;
    has span: str;
}

obj CaptureExtraction {
    has people: list[XPerson];
    has facts: list[XFact];
    has intents: list[XIntent];
    has promises: list[XPromise];
    has ties: list[XTie];
}

sem XPerson.name = "The person's name exactly as written in the note; the note's author is never a person here.";
sem XPerson.org = "The person's organization or company, if stated; empty string if not mentioned.";
sem XPerson.title = "The person's job title or role, if stated; empty string if not mentioned.";
sem XPerson.span = "The exact substring of the note that introduces or describes this person, copied verbatim.";
sem XPerson.named = "true when the note gives this person's name; false when the person is referred to only by description (then `name` is that description, e.g. 'the young man from the robotics thing who built the wheelchair sensor').";
sem XPerson.distinct_from = "If the note says this is a different person from someone already mentioned or known ('not the X one', 'a different Maya'), that other person's name as written; empty string otherwise.";

sem XFact.about_name = "The name of the person this fact is about.";
sem XFact.text = "A short factual statement about the person. Keep the speaker's uncertainty: if the note hedges a claim ('maybe', '??', 'not sure', 'I think', 'possibly', 'probably'), the fact text must carry the hedge ('Possibly works at Siemens in Detroit - the speaker was unsure') and must never be stated flatly.";
sem XFact.source_kind = "self when the fact is the author's own note-to-self about the relationship (e.g. 'there is a potential conflict of interest I should note', 'keep in mind ...'); reported otherwise.";
sem XFact.span = "The exact substring of the note this fact came from, copied verbatim.";

sem XIntent.about_name = "The name of the person this intent is about.";
sem XIntent.kind = "need if they want something from others in general (not something the author will deliver - that is a Promise), offer if they can give something, open_to otherwise.";
sem XIntent.text = "A short statement of the intent.";
sem XIntent.span = "The exact substring of the note this intent came from, copied verbatim.";

sem XPromise.to_name = "The name of the person the author promised something to (or their description, exactly as used in `people`, when they are not named).";
sem XPromise.text = "What was promised: the concrete deliverable ('send the ROI deck'). Anything the speaker will send, do, or deliver for the person is a Promise even when the note phrases it as what the other person wants ('wants ROI deck by Fri'); a bare 'follow up' is a Promise only when nothing more specific was promised.";
sem XPromise.due = "When the promise is due, if stated; empty string if not mentioned.";
sem XPromise.span = "The exact substring of the note this promise came from, copied verbatim.";

sem XTie.from_name = "The name of the first person in a stated acquaintance.";
sem XTie.to_name = "The name of the second person in a stated acquaintance.";
sem XTie.span = "Verbatim substring of the note that states the two people know each other.";

sem CaptureExtraction.people = "Every person in the note other than the author (who says 'I'); include people only mentioned as someone's acquaintance. When a person is referred to only by description, use the description as the name (e.g. 'the young man from the robotics thing who built the wheelchair sensor') and set named=false.";
sem CaptureExtraction.facts = "Facts stated about any person in the note, including the author's notes-to-self about the relationship ('conflict of interest', 'keep in mind'), which are facts about that person with source_kind='self'. Hedged claims keep their hedge.";
sem CaptureExtraction.intents = "Needs, offers, or openness stated about any person in the note.";
sem CaptureExtraction.promises = "Promises the author (the note's 'I') made to any person in the note: anything the author will send, do, or deliver for them, with the concrete deliverable as the text and the due date if stated ('wants ROI deck by Fri' -> text 'send the ROI deck', due 'Fri').";
sem CaptureExtraction.ties = "Pairs of people the note says know each other.";

def extract_capture(text: str) -> CaptureExtraction by llm(temperature=0.1);
sem extract_capture = "Extract people, facts, intents, promises, and ties from a personal debrief note. When a person wants a concrete thing the author can deliver (a deck, a link, a document, an intro), record it as the author's Promise to deliver it ('wants ROI deck by Fri' -> Promise 'send the ROI deck', due 'Fri'), not as that person's need. Keep hedges; never state an uncertain claim flatly.";
sem extract_capture.text = "The debrief note text.";

# ---------------------------------------------------------------- deterministic graph writes

def safe_span(span: str, note: Note, fallback: str) -> str {
    if len(span) > 0 and span in note.text {
        return span;
    }
    if len(fallback) > 0 {
        return fallback;
    }
    return note.text[:80];
}

def normalize_intent_kind(kind: str) -> str {
    k = (kind or "").strip().lower();
    if k in ["need", "needs", "want", "wants", "looking for"] {
        return "need";
    }
    if k in ["offer", "offers", "can offer"] {
        return "offer";
    }
    return "open_to";
}

glob HEDGE_CUES: list[str] = [
    "maybe", "??", "not sure", "i think", "possibly", "probably", "unsure",
    "might be", "i guess", "vielleicht", "glaube"
];
glob HEDGE_KEPT: list[str] = [
    "possibly", "maybe", "unsure", "unconfirmed", "not sure", "reportedly", "probably"
];

"""SOH-212 hedge guard: when the span the fact came from hedges ("maybe",
"??", "not sure", ...) and the fact text states it flatly, prefix
"Possibly: " so the uncertainty survives extraction."""
def hedge_fact_text(text: str, span: str) -> str {
    sp = (span or "").lower();
    hedged = False;
    for cue in HEDGE_CUES {
        if cue in sp {
            hedged = True;
            break;
        }
    }
    if not hedged {
        return text;
    }
    tl = (text or "").lower();
    for kept in HEDGE_KEPT {
        if kept in tl {
            return text;
        }
    }
    return "Possibly: " + text;
}

glob SELF_NOTE_CUES: list[str] = ["conflict of interest", "keep in mind", "note to self", "i should note"];

"""`self` for the author's own notes-to-self about a relationship, else `reported`."""
def fact_source_kind(kind: str, span: str) -> str {
    if (kind or "").strip().lower() == "self" {
        return "self";
    }
    sp = (span or "").lower();
    for cue in SELF_NOTE_CUES {
        if cue in sp {
            return "self";
        }
    }
    return "reported";
}

glob BARE_FOLLOW_UPS: list[str] = [
    "follow up", "follow-up", "followup", "follow up with her", "follow up with him",
    "follow up with them", "follow up with her.", "check in", "touch base"
];

"""SOH-212: a bare "follow up" promise to someone who, in the same note,
wants something concrete becomes "Follow up on: <that want>" so the
deliverable is not lost to a generic reminder. Anything else is unchanged."""
def specific_follow_up(text: str, wants: list[str]) -> str {
    t = (text or "").strip().rstrip(".").lower();
    if t not in BARE_FOLLOW_UPS or len(wants) == 0 {
        return text;
    }
    want = wants[0].strip().rstrip(".");
    low = want.lower();
    for lead in ["wants ", "want ", "needs ", "need "] {
        if low.startswith(lead) {
            want = want[len(lead):];
            break;
        }
    }
    return "Follow up on: " + want;
}

glob TITLE_HONORIFICS: list[str] = ["dr", "prof", "professor", "rev", "reverend"];

"""Dedupe by jid(p): the first call for a given person creates the Mentions
edge and records them; later calls for the same person (from a different
category - fact, tie, ...) are no-ops."""
def record_mention(
    note: Note,
    p: Person,
    is_new: bool,
    ambiguous_with: list[str],
    span: str,
    mentioned: dict[str, any],
    order: list[str]
) {
    key = jid(p);
    if key in mentioned {
        return;
    }
    note +>:Mentions(span=span):+> p;
    mentioned[key] = {"person": p, "is_new": is_new, "ambiguous_with": ambiguous_with, "span": span};
    order.append(key);
}

"""Get-or-create a Person by name. Memoized per-call via `resolved` (clean
name lower-cased -> entry). SOH-212 rule (names.sv.jac `match_names`):
exact clean match (honorifics and parentheticals stripped) -> that person,
unless both orgs are set and differ; a first-name match whose last names do
not contradict ("Helen" vs "Dr. Helen Marsh-Whitcombe", "Maya O." vs
"Maya Okafor") -> a NEW proposed Person with `ambiguous_with` filled, never a
silent merge; `distinct_from` (the note said "not the X one") forces a new
proposed Person ambiguous with X; a person known only by description
(`named=False`) is created proposed."""
def resolve_person(
    name: str,
    me: Me,
    note: Note,
    resolved: dict[str, any],
    org: str = "",
    title: str = "",
    confirmed_if_new: bool = True,
    distinct_from: str = "",
    named: bool = True,
    how_met: str = ""
) -> dict[str, any] {
    nk = name_key(name);
    clean = nk["clean"];
    key = " ".join(clean.lower().split());
    if key in resolved {
        return resolved[key] as dict[str, any];
    }

    known: list[Person] = [me ->:Knows:->];
    same: list[Person] = [];
    ambiguous: list[Person] = [];
    org_l = org.strip().lower();
    for p in known {
        verdict = match_names(clean, p.name) if named else ("same" if " ".join(p.name.lower().split()) == key else "distinct");
        if verdict == "same" {
            p_org = p.org.strip().lower();
            if len(org_l) > 0 and len(p_org) > 0 and org_l != p_org {
                ambiguous.append(p);
            } else {
                same.append(p);
            }
        } elif verdict == "ambiguous" {
            ambiguous.append(p);
        }
    }

    forced = False;
    if len(distinct_from.strip()) > 0 {
        for p in known {
            if match_names(distinct_from, p.name) != "distinct" {
                forced = True;
                if p not in ambiguous {
                    ambiguous.append(p);
                }
            }
        }
        if forced {
            for p in same {
                if p not in ambiguous {
                    ambiguous.append(p);
                }
            }
        }
    }

    if not forced and len(same) > 0 {
        entry = {"person": same[0], "is_new": False, "ambiguous_with": []};
        resolved[key] = entry;
        return entry;
    }

    ambiguous_with: list[str] = [jid(p) for p in ambiguous];
    now = datetime.now().isoformat();
    # SOH-166: an explicit how_met (from the Capture call) wins for NEW edges.
    edge_how_met = how_met.strip() if len(how_met.strip()) > 0 else f"{note.kind}: {trim_words(note.text, 60)}";
    new_title = title;
    if len(new_title) == 0 and nk["honorific"].rstrip(".").lower() in TITLE_HONORIFICS {
        new_title = nk["honorific"];
    }

    if len(ambiguous_with) > 0 or forced or not named or not confirmed_if_new {
        new_p = (me +>:Knows(how_met=edge_how_met, last_contact=now, source_note=jid(note), status="proposed"):+> Person(name=clean, org=org, title=new_title, status="proposed"))[0];
    } else {
        new_p = (me +>:Knows(how_met=edge_how_met, last_contact=now, source_note=jid(note), status="reported"):+> Person(name=clean, org=org, title=new_title, status="confirmed"))[0];
    }

    entry = {"person": new_p, "is_new": True, "ambiguous_with": ambiguous_with};
    resolved[key] = entry;
    return entry;
}

"""Deterministic, testable: turns an already-built CaptureExtraction into graph writes.
Returns the Capture contract dict (contracts/walkers.md)."""
def apply_extraction(note: Note, me: Me, x: CaptureExtraction, how_met: str = "") -> dict[str, any] {
    resolved: dict[str, any] = {};
    now_dt = datetime.now();
    now = now_dt.isoformat();

    # Every unique person resolved anywhere (people/facts/intents/promises/ties)
    # ends up here exactly once, keyed by jid - one Mentions edge, one entry in
    # the `people` report, no matter how many categories reference them.
    mentioned: dict[str, any] = {};
    mention_order: list[str] = [];

    facts_report: list[dict[str, any]] = [];
    intents_report: list[dict[str, any]] = [];
    promises_report: list[dict[str, any]] = [];
    ties_report: list[dict[str, any]] = [];

    # Dedupe x.people by normalized name; never create a Person with an empty name.
    seen_names: list[str] = [];
    deduped_people: list[XPerson] = [];
    for xp in x.people {
        key = xp.name.strip().lower();
        if len(key) == 0 or key in seen_names {
            continue;
        }
        seen_names.append(key);
        deduped_people.append(xp);
    }

    # A person who ONLY shows up as the far end of a reported tie (someone the
    # author never met, only heard about) stays "proposed" even if the LLM also
    # dropped them into `people` (the extraction prompt asks it to list every
    # acquaintance mentioned, tie targets included). "Primary" = the author has
    # independent evidence about them (a fact/intent/promise, or they are the
    # NEAR end of a tie - the person actually introducing someone else).
    tie_to_names: list[str] = [xt.to_name.strip().lower() for xt in x.ties if len(xt.to_name.strip()) > 0];
    primary_names: list[str] = [xf.about_name.strip().lower() for xf in x.facts if len(xf.about_name.strip()) > 0];
    primary_names += [xi.about_name.strip().lower() for xi in x.intents if len(xi.about_name.strip()) > 0];
    primary_names += [xpr.to_name.strip().lower() for xpr in x.promises if len(xpr.to_name.strip()) > 0];
    primary_names += [xt.from_name.strip().lower() for xt in x.ties if len(xt.from_name.strip()) > 0];

    # People known only by description (named=False) stay proposed wherever
    # they are referenced from (a promise to them still attaches).
    unnamed: list[str] = [xp.name.strip().lower() for xp in deduped_people if not xp.named];

    for xp in deduped_people {
        key = xp.name.strip().lower();
        tie_target_only = key in tie_to_names and key not in primary_names;
        entry = resolve_person(
            xp.name, me, note, resolved, org=xp.org, title=xp.title,
            confirmed_if_new=not tie_target_only, distinct_from=xp.distinct_from, named=xp.named,
            how_met=how_met
        );
        p = entry["person"] as Person;
        span = safe_span(xp.span, note, xp.name);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
    }

    for xf in x.facts {
        if len(xf.about_name.strip()) == 0 {
            continue;
        }
        entry = resolve_person(xf.about_name, me, note, resolved, confirmed_if_new=False, named=xf.about_name.strip().lower() not in unnamed, how_met=how_met);
        p = entry["person"] as Person;
        span = safe_span(xf.span, note, xf.text);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
        f = (note +>:Asserts(span=span):+> Fact(
            text=hedge_fact_text(xf.text, span), observed_at=now,
            source_kind=fact_source_kind(xf.source_kind, span)
        ))[0];
        f +>:FactAbout:+> p;
        facts_report.append({"fact": f, "about": jid(p), "span": span});
    }

    for xi in x.intents {
        if len(xi.about_name.strip()) == 0 {
            continue;
        }
        entry = resolve_person(xi.about_name, me, note, resolved, confirmed_if_new=False, named=xi.about_name.strip().lower() not in unnamed, how_met=how_met);
        p = entry["person"] as Person;
        span = safe_span(xi.span, note, xi.text);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
        norm_kind = normalize_intent_kind(xi.kind);
        it = (note +>:AssertsIntent(span=span):+> Intent(
            kind=norm_kind, text=xi.text, source_kind="reported",
            expires_at=default_expiry(norm_kind, now_dt)
        ))[0];
        it +>:IntentAbout:+> p;
        intents_report.append({"intent": it, "about": jid(p), "span": span});
    }

    for xpr in x.promises {
        if len(xpr.to_name.strip()) == 0 {
            continue;
        }
        entry = resolve_person(xpr.to_name, me, note, resolved, confirmed_if_new=False, named=xpr.to_name.strip().lower() not in unnamed, how_met=how_met);
        p = entry["person"] as Person;
        span = safe_span(xpr.span, note, xpr.text);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
        wants: list[str] = [
            xi.text for xi in x.intents
            if normalize_intent_kind(xi.kind) == "need" and xi.about_name.strip().lower() == xpr.to_name.strip().lower()
        ];
        pr = (note +>:AssertsPromise(span=span):+> Promise(text=specific_follow_up(xpr.text, wants), due=xpr.due))[0];
        pr +>:PromiseTo:+> p;
        promises_report.append({"promise": pr, "to": jid(p), "span": span});
    }

    for xt in x.ties {
        if len(xt.from_name.strip()) == 0 or len(xt.to_name.strip()) == 0 {
            continue;
        }
        if xt.from_name.strip().lower() == xt.to_name.strip().lower() {
            continue;
        }
        a_entry = resolve_person(xt.from_name, me, note, resolved, confirmed_if_new=False, how_met=how_met);
        b_entry = resolve_person(xt.to_name, me, note, resolved, confirmed_if_new=False, how_met=how_met);
        a = a_entry["person"] as Person;
        b = b_entry["person"] as Person;
        if jid(a) == jid(b) {
            continue;
        }
        span = safe_span(xt.span, note, "");
        record_mention(note, a, a_entry["is_new"] as bool, a_entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
        record_mention(note, b, b_entry["is_new"] as bool, b_entry["ambiguous_with"] as list[str], span, mentioned, mention_order);

        already: list[Person] = [a ->:Reported:->];
        edge_exists = False;
        for existing_b in already {
            if jid(existing_b) == jid(b) {
                edge_exists = True;
            }
        }
        if not edge_exists {
            a +>:Reported(source_note=jid(note), span=span):+> b;
        }
        ties_report.append({"from": jid(a), "to": jid(b), "span": span});
    }

    people_report: list[dict[str, any]] = [mentioned[k] as dict[str, any] for k in mention_order];

    return {
        "note_id": jid(note),
        "people": people_report,
        "facts": facts_report,
        "intents": intents_report,
        "promises": promises_report,
        "ties": ties_report
    };
}

# ---------------------------------------------------------------- walker

walker:priv Capture {
    has text: str;
    has kind: str = "debrief";
    has audio_ref: str = "";        # from Transcribe; stored on the Note as the receipt to the audio
    has how_met: str = "";          # SOH-166: when set, every NEW Knows edge this capture creates uses it
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        note = (root ++> Note(text=self.text, kind=self.kind, captured_at=datetime.now().isoformat(), audio_ref=self.audio_ref))[0];

        existing_me = [root --> [?:Me]];
        if len(existing_me) > 0 {
            me = existing_me[0];
        } else {
            me = (root ++> Me(name="me"))[0];
        }

        empty_shape = {
            "note_id": jid(note),
            "people": [],
            "facts": [],
            "intents": [],
            "promises": [],
            "ties": []
        };

        try {
            extraction = extract_capture(self.text);
        } except Exception {
            report empty_shape;
            disengage;
        }

        result = apply_extraction(note, me, extraction, how_met=self.how_met);
        report result;
    }
}
