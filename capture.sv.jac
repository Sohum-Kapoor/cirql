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


# ---------------------------------------------------------------- LLM shape

obj XPerson {
    has name: str;
    has org: str;
    has title: str;
    has span: str;
}

obj XFact {
    has about_name: str;
    has text: str;
    has span: str;
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

sem XFact.about_name = "The name of the person this fact is about.";
sem XFact.text = "A short factual statement about the person.";
sem XFact.span = "The exact substring of the note this fact came from, copied verbatim.";

sem XIntent.about_name = "The name of the person this intent is about.";
sem XIntent.kind = "need if they want something from others, offer if they can give something, open_to otherwise.";
sem XIntent.text = "A short statement of the intent.";
sem XIntent.span = "The exact substring of the note this intent came from, copied verbatim.";

sem XPromise.to_name = "The name of the person the author promised something to.";
sem XPromise.text = "What was promised.";
sem XPromise.due = "When the promise is due, if stated; empty string if not mentioned.";
sem XPromise.span = "The exact substring of the note this promise came from, copied verbatim.";

sem XTie.from_name = "The name of the first person in a stated acquaintance.";
sem XTie.to_name = "The name of the second person in a stated acquaintance.";
sem XTie.span = "Verbatim substring of the note that states the two people know each other.";

sem CaptureExtraction.people = "Every person named in the note other than the author (who says 'I'); include people only mentioned as someone's acquaintance.";
sem CaptureExtraction.facts = "Facts stated about any person in the note.";
sem CaptureExtraction.intents = "Needs, offers, or openness stated about any person in the note.";
sem CaptureExtraction.promises = "Promises the author (the note's 'I') made to any person in the note.";
sem CaptureExtraction.ties = "Pairs of people the note says know each other.";

def extract_capture(text: str) -> CaptureExtraction by llm(temperature=0.1);
sem extract_capture = "Extract people, facts, intents, promises, and ties from a personal debrief note.";
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
    mentioned[key] = {"person": p, "is_new": is_new, "ambiguous_with": ambiguous_with};
    order.append(key);
}

"""Get-or-create a Person by name. Memoized per-call via `resolved` (name.lower() -> entry)."""
def resolve_person(
    name: str,
    me: Me,
    note: Note,
    resolved: dict[str, any],
    org: str = "",
    title: str = "",
    confirmed_if_new: bool = True
) -> dict[str, any] {
    key = name.strip().lower();
    if key in resolved {
        return resolved[key] as dict[str, any];
    }

    known: list[Person] = [me ->:Knows:->];
    for p in known {
        if p.name.strip().lower() == key {
            entry = {"person": p, "is_new": False, "ambiguous_with": []};
            resolved[key] = entry;
            return entry;
        }
    }

    ambiguous_with: list[str] = [];
    if " " not in name.strip() {
        matches: list[Person] = [];
        for p in known {
            parts = p.name.strip().split(" ");
            first = parts[0] if len(parts) > 0 else p.name;
            if first.strip().lower() == key {
                matches.append(p);
            }
        }
        if len(matches) == 1 {
            # Exactly one known person shares this first token - not ambiguous,
            # not a guess: resolve straight to them.
            entry = {"person": matches[0], "is_new": False, "ambiguous_with": []};
            resolved[key] = entry;
            return entry;
        }
        if len(matches) >= 2 {
            ambiguous_with = [jid(p) for p in matches];
        }
    }

    now = datetime.now().isoformat();
    how_met = f"{note.kind}: {note.text[:60]}";

    if len(ambiguous_with) > 0 {
        new_p = (me +>:Knows(how_met=how_met, last_contact=now, source_note=jid(note), status="proposed"):+> Person(name=name, status="proposed"))[0];
    } elif confirmed_if_new {
        new_p = (me +>:Knows(how_met=how_met, last_contact=now, source_note=jid(note), status="reported"):+> Person(name=name, org=org, title=title, status="confirmed"))[0];
    } else {
        new_p = (me +>:Knows(how_met=how_met, last_contact=now, source_note=jid(note), status="proposed"):+> Person(name=name, status="proposed"))[0];
    }

    entry = {"person": new_p, "is_new": True, "ambiguous_with": ambiguous_with};
    resolved[key] = entry;
    return entry;
}

"""Deterministic, testable: turns an already-built CaptureExtraction into graph writes.
Returns the Capture contract dict (contracts/walkers.md)."""
def apply_extraction(note: Note, me: Me, x: CaptureExtraction) -> dict[str, any] {
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

    for xp in deduped_people {
        key = xp.name.strip().lower();
        tie_target_only = key in tie_to_names and key not in primary_names;
        entry = resolve_person(xp.name, me, note, resolved, org=xp.org, title=xp.title, confirmed_if_new=not tie_target_only);
        p = entry["person"] as Person;
        span = safe_span(xp.span, note, xp.name);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
    }

    for xf in x.facts {
        if len(xf.about_name.strip()) == 0 {
            continue;
        }
        entry = resolve_person(xf.about_name, me, note, resolved, confirmed_if_new=False);
        p = entry["person"] as Person;
        span = safe_span(xf.span, note, xf.text);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
        f = (note +>:Asserts(span=span):+> Fact(text=xf.text, observed_at=now, source_kind="reported"))[0];
        f +>:FactAbout:+> p;
        facts_report.append({"fact": f, "about": jid(p), "span": span});
    }

    for xi in x.intents {
        if len(xi.about_name.strip()) == 0 {
            continue;
        }
        entry = resolve_person(xi.about_name, me, note, resolved, confirmed_if_new=False);
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
        entry = resolve_person(xpr.to_name, me, note, resolved, confirmed_if_new=False);
        p = entry["person"] as Person;
        span = safe_span(xpr.span, note, xpr.text);
        record_mention(note, p, entry["is_new"] as bool, entry["ambiguous_with"] as list[str], span, mentioned, mention_order);
        pr = (note +>:AssertsPromise(span=span):+> Promise(text=xpr.text, due=xpr.due))[0];
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
        a_entry = resolve_person(xt.from_name, me, note, resolved, confirmed_if_new=False);
        b_entry = resolve_person(xt.to_name, me, note, resolved, confirmed_if_new=False);
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
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        note = (root ++> Note(text=self.text, kind=self.kind, captured_at=datetime.now().isoformat()))[0];

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

        result = apply_extraction(note, me, extraction);
        report result;
    }
}
