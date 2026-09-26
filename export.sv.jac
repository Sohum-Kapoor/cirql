"""ExportGraph — the caller's whole graph as one JSON dict (SOH-210).

OWNER: Person A. See contracts/walkers.md `ExportGraph()` for the exact
report shape. `:priv`, own-root only, no `by llm` anywhere in this module.

Traversal is confined to the caller's own graph, reached only from `root`
and the caller's own `Me` node — never `root.shared`, never a `jobj(id)`
lookup of a foreign id, nothing from the Exchange (requests/replies). Every
node dict uses `jid(n)` for its id, never a node object, so the report is
plain JSON-serialisable. `Knows.last_contact` is copied verbatim (it is the
user's own export of their own data) and never read to compute or rank
anything, per AGENTS.md.

`build_export(me, cap)` is the deterministic, testable core (mirrors
`reads.sv.jac`'s `graph_view_for` / `list_promises_raw` pattern): the
walker resolves "the" caller's `Me` via `[root --> [?:Me]][0]` (ambiguous
across repeated `jac test` runs against one persisted root — the same
reason `reads.test.jac` calls `graph_view_for` directly instead of
`root spawn GraphView(...)`), then delegates. Facts/Intents/Promises are
gathered by walking every Note's own `Asserts*` edges (same idiom
`list_promises_raw` uses for promises) rather than by walking outward from
each Person, so a Promise/Fact/Intent with no target still gets exported
with a source_note and span, and every entry is naturally deduped by jid
across notes. `cap` bounds `people`/`facts`/`intents`/`promises`/`notes`
combined at 5,000 total items (`truncated: true` once hit) — exposed as a
parameter so a test can exercise the truncation path without building 5,000
nodes.
"""

import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, HasGoal, Owns
}

# ---------------------------------------------------------------- node dicts

def me_dict(me: Me) -> dict[str, any] {
    return {"id": jid(me), "name": me.name, "about": me.about};
}

def goal_dict(g: Goal) -> dict[str, any] {
    return {"id": jid(g), "text": g.text, "active": g.active};
}

def card_dict(c: Card) -> dict[str, any] {
    return {
        "id": jid(c), "handle": c.handle, "name": c.name, "headline": c.headline,
        "about": c.about, "looking_for": c.looking_for, "can_offer": c.can_offer,
        "links": c.links, "contact_pref": c.contact_pref, "visibility": c.visibility,
        "updated_at": c.updated_at
    };
}

def person_dict(p: Person) -> dict[str, any] {
    return {"id": jid(p), "name": p.name, "org": p.org, "title": p.title, "status": p.status};
}

def note_dict(n: Note) -> dict[str, any] {
    return {"id": jid(n), "kind": n.kind, "text": n.text, "captured_at": n.captured_at, "audio_ref": n.audio_ref};
}

"""The span of the Mentions edge from the Note named by `source_note_id`
to `p`, or "" when that note doesn't mention `p` (no Mentions edge) or
`source_note_id` is empty. Purely typed-edge traversal — no `jobj`."""
def knows_span(p: Person, source_note_id: str) -> str {
    if not source_note_id {
        return "";
    }
    mention_notes: list[Note] = [p <-:Mentions:<-];
    for note in mention_notes {
        if jid(note) == source_note_id {
            matched = [e.span for e in [edge note ->:Mentions:-> p]];
            if matched {
                return matched[0];
            }
        }
    }
    return "";
}

def knows_dict(me: Me, p: Person, ke: Knows) -> dict[str, any] {
    return {
        "from": jid(me), "to": jid(p), "status": ke.status, "how_met": ke.how_met,
        "source_note": ke.source_note, "span": knows_span(p, ke.source_note),
        "last_contact": ke.last_contact
    };
}

def reported_dict(a: Person, b: Person, re: Reported) -> dict[str, any] {
    return {"from": jid(a), "to": jid(b), "source_note": re.source_note, "span": re.span};
}

def fact_dict(note: Note, f: Fact, about_id: str, span: str) -> dict[str, any] {
    return {
        "id": jid(f), "about": about_id, "text": f.text, "observed_at": f.observed_at,
        "valid_to": f.valid_to, "status": f.status, "source_kind": f.source_kind,
        "source_url": f.source_url, "source_note": jid(note), "span": span
    };
}

def intent_dict(note: Note, i: Intent, about_id: str, span: str) -> dict[str, any] {
    return {
        "id": jid(i), "about": about_id, "kind": i.kind, "text": i.text,
        "expires_at": i.expires_at, "source_kind": i.source_kind,
        "source_note": jid(note), "span": span
    };
}

def promise_dict(note: Note, pr: Promise, to_id: str, span: str) -> dict[str, any] {
    return {
        "id": jid(pr), "to": to_id, "text": pr.text, "due": pr.due, "done": pr.done,
        "source_note": jid(note), "span": span
    };
}

def empty_export(now_iso: str) -> dict[str, any] {
    return {
        "exported_at": now_iso, "me": None, "goals": [], "card": None,
        "people": [], "knows": [], "reported": [],
        "facts": [], "intents": [], "promises": [], "notes": [],
        "counts": {"people": 0, "facts": 0, "intents": 0, "promises": 0, "notes": 0},
        "truncated": False
    };
}

# ---------------------------------------------------------------- core builder

"""Deterministic, testable: the caller's whole graph (from `me` and `root`)
as one plain dict. `cap` bounds people/facts/intents/promises/notes combined
at that many total items (default 5,000); a smaller `cap` lets a test drive
the truncation path directly."""
def build_export(me: Me, cap: int = 5000) -> dict[str, any] {
    total = 0;
    truncated = False;

    goals: list[dict[str, any]] = [];
    for g in [me ->:HasGoal:->] {
        goals.append(goal_dict(g));
    }

    card: dict[str, any] | None = None;
    owned_cards: list[Card] = [me ->:Owns:->];
    if owned_cards {
        card = card_dict(owned_cards[0]);
    }

    people_out: list[dict[str, any]] = [];
    knows_out: list[dict[str, any]] = [];
    people_nodes: list[Person] = [];
    people_jids: list[str] = [];

    for p in [me ->:Knows:->] {
        if total >= cap {
            truncated = True;
            break;
        }
        people_nodes.append(p);
        people_jids.append(jid(p));
        people_out.append(person_dict(p));
        total += 1;
        know_edges = [edge me ->:Knows:-> p];
        if know_edges {
            knows_out.append(knows_dict(me, p, know_edges[0]));
        }
    }

    reported_out: list[dict[str, any]] = [];
    for a in people_nodes {
        for b in [a ->:Reported:->] {
            bid = jid(b);
            if bid not in people_jids {
                continue;
            }
            matched = [edge a ->:Reported:-> b];
            if matched {
                reported_out.append(reported_dict(a, b, matched[0]));
            }
        }
    }

    facts_out: list[dict[str, any]] = [];
    intents_out: list[dict[str, any]] = [];
    promises_out: list[dict[str, any]] = [];
    notes_out: list[dict[str, any]] = [];

    seen_facts: list[str] = [];
    seen_intents: list[str] = [];
    seen_promises: list[str] = [];

    stop = False;
    all_notes: list[Note] = [root --> [?:Note]];
    for note in all_notes {
        if stop {
            break;
        }
        if total >= cap {
            truncated = True;
            break;
        }
        notes_out.append(note_dict(note));
        total += 1;

        for f in [note ->:Asserts:->] {
            fid = jid(f);
            if fid in seen_facts {
                continue;
            }
            if total >= cap {
                truncated = True;
                stop = True;
                break;
            }
            seen_facts.append(fid);
            spans = [e.span for e in [edge note ->:Asserts:-> f]];
            span = spans[0] if spans else "";
            about_people: list[Person] = [f ->:FactAbout:->];
            about_id = jid(about_people[0]) if about_people else "";
            facts_out.append(fact_dict(note, f, about_id, span));
            total += 1;
        }
        if stop {
            break;
        }

        for it in [note ->:AssertsIntent:->] {
            iid = jid(it);
            if iid in seen_intents {
                continue;
            }
            if total >= cap {
                truncated = True;
                stop = True;
                break;
            }
            seen_intents.append(iid);
            spans = [e.span for e in [edge note ->:AssertsIntent:-> it]];
            span = spans[0] if spans else "";
            about_people: list[Person] = [it ->:IntentAbout:->];
            about_id = jid(about_people[0]) if about_people else jid(me);
            intents_out.append(intent_dict(note, it, about_id, span));
            total += 1;
        }
        if stop {
            break;
        }

        for pr in [note ->:AssertsPromise:->] {
            prid = jid(pr);
            if prid in seen_promises {
                continue;
            }
            if total >= cap {
                truncated = True;
                stop = True;
                break;
            }
            seen_promises.append(prid);
            spans = [e.span for e in [edge note ->:AssertsPromise:-> pr]];
            span = spans[0] if spans else "";
            to_people: list[Person] = [pr ->:PromiseTo:->];
            to_id = jid(to_people[0]) if to_people else "";
            promises_out.append(promise_dict(note, pr, to_id, span));
            total += 1;
        }
        if stop {
            break;
        }
    }

    counts = {
        "people": len(people_out), "facts": len(facts_out),
        "intents": len(intents_out), "promises": len(promises_out),
        "notes": len(notes_out)
    };

    return {
        "exported_at": datetime.now().isoformat(),
        "me": me_dict(me),
        "goals": goals,
        "card": card,
        "people": people_out,
        "knows": knows_out,
        "reported": reported_out,
        "facts": facts_out,
        "intents": intents_out,
        "promises": promises_out,
        "notes": notes_out,
        "counts": counts,
        "truncated": truncated
    };
}

# ---------------------------------------------------------------- walker

walker:priv ExportGraph {
    """Resolves the caller's own Me, then delegates to `build_export`.
    Reports one dict (contracts/walkers.md). No Me yet -> the empty shape,
    `me: null`, `card: null`, everything else empty, `truncated: false`."""
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report empty_export(datetime.now().isoformat());
            return;
        }
        me = existing[0];
        report build_export(me);
    }
}

walker:priv ExportDevSeed {
    """Dev/test helper only (not in the client contract, not called by any
    other walker): deterministically builds one Me + one Goal + two Person
    (one via Knows with a `how_met`, one Reported from the first, both also
    reached via the caller's own Knows edges per schema) + one Note that
    Asserts a Fact/Intent/Promise and Mentions the first Person. Exists so
    `export.test.jac`'s two-account isolation test can seed account A's
    graph over the real HTTP API without a `by llm` call (`Capture` needs
    the model; this doesn't). No `main.jac` import — never reachable from
    the real client."""
    has reports: list[dict[str, str]] = [];

    can go with Root entry {
        me = (root ++> Me(name="Export-seed Me", about="dev seed"))[0];
        goal = (me +>:HasGoal:+> Goal(text="Export-seed goal", created_at=datetime.now().isoformat()))[0];

        note = (root ++> Note(
            text="Export-seed note: met Priya at the conference, works on climate tech, needs a VC intro, promised to send the deck by Friday.",
            kind="debrief", captured_at=datetime.now().isoformat()
        ))[0];

        p1 = (me +>:Knows(how_met="conference", status="confirmed", source_note=jid(note)):+> Person(
            name="Export-seed Priya", org="Acme Climate", title="Founder", status="confirmed"
        ))[0];
        note +>:Mentions(span="met Priya at the conference"):+> p1;

        p2 = (me +>:Knows(how_met="reported by Priya"):+> Person(
            name="Export-seed Dana", status="confirmed"
        ))[0];
        p1 +>:Reported(source_note=jid(note), span="Priya knows Dana"):+> p2;

        fact = (note +>:Asserts(span="works on climate tech"):+> Fact(
            text="Works on climate tech", observed_at=datetime.now().isoformat(), source_kind="reported"
        ))[0];
        fact +>:FactAbout:+> p1;

        intent = (note +>:AssertsIntent(span="needs a VC intro"):+> Intent(
            kind="need", text="Needs a VC intro", source_kind="reported"
        ))[0];
        intent +>:IntentAbout:+> p1;

        promise = (note +>:AssertsPromise(span="send the deck by Friday"):+> Promise(
            text="Send the deck", due="2026-10-03"
        ))[0];
        promise +>:PromiseTo:+> p1;

        report {
            "me": jid(me), "goal": jid(goal), "note": jid(note),
            "p1": jid(p1), "p2": jid(p2),
            "fact": jid(fact), "intent": jid(intent), "promise": jid(promise)
        };
    }
}
