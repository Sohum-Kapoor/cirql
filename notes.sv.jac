"""notes.sv.jac — timeline, deletion, confirmation, weekly digest (SOH-219).

OWNER: Person A. See contracts/walkers.md for the exact report shapes.
AGENTS.md rules this file must obey:
  - Every walker here is `:priv` (own-root only, JWT required). No `by llm`
    anywhere in this module.
  - `DeleteNote` never deletes the Note's asserted people — only a
    Fact/Intent/Promise whose ONLY asserting Note is the one being deleted.
    A claim asserted by another Note too survives; only the dangling
    `Asserts*` edge to the deleted Note disappears (node-delete cascade).
  - `ConfirmFact` only ever flips `status` on a Fact the caller owns.
  - Ownership idiom (`_my_node`, `_forget_fact`/`_forget_intent`/
    `_forget_promise`, `_not_found`) is imported from `forget.sv.jac`
    rather than reimplemented — same reason `edits.sv.jac` imports
    `reads.sv.jac`'s `my_node`.
"""

import from datetime { datetime, timedelta }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal,
    Knows, Asserts, AssertsIntent, AssertsPromise, Mentions, FactAbout, HasGoal
}
import from forget { _my_node, _not_found, _forget_fact, _forget_intent, _forget_promise }
import from dates { upcoming_dates_for }
import from goals { _parse_naive_utc, ranking_is_stale }
import from tend { tend_for }

# ---------------------------------------------------------------- helpers: ListNotes

"""Cut `text` to at most `max_len` chars on a word boundary, appending "…"
when truncated. Mirrors `capture.sv.jac`'s default `how_met` trim."""
def word_trim(text: str, max_len: int) -> str {
    t = text.strip();
    if len(t) <= max_len {
        return t;
    }
    cut = t[:max_len];
    last_space = cut.rfind(" ");
    if last_space > 0 {
        cut = cut[:last_space];
    }
    return cut + "…";
}

"""Every Person a Note `Mentions`, deduped by jid, in traversal order."""
def _note_people(note: Note) -> list[dict[str, str]] {
    out: list[dict[str, str]] = [];
    seen: list[str] = [];
    for p in [note ->:Mentions:->] {
        pid = jid(p);
        if pid in seen {
            continue;
        }
        seen.append(pid);
        out.append({"id": pid, "name": p.name});
    }
    return out;
}

def _note_counts(note: Note) -> dict[str, int] {
    return {
        "facts": len([note ->:Asserts:->]),
        "intents": len([note ->:AssertsIntent:->]),
        "promises": len([note ->:AssertsPromise:->])
    };
}

def _note_item(note: Note) -> dict[str, any] {
    return {
        "note": note,
        "people": _note_people(note),
        "counts": _note_counts(note),
        "text_preview": word_trim(note.text, 140)
    };
}

def _note_sort_key(note: Note) -> str {
    return note.captured_at;
}

"""Deterministic, testable directly on a hand-built `notes` list (see
notes.test.jac): optional `kind` filter, optional `before` ISO cursor
(strictly earlier `captured_at`), newest first, capped at `limit`."""
def list_notes_for(notes: list[Note], limit: int, before: str, kind: str) -> list[dict[str, any]] {
    filtered: list[Note] = [];
    for n in notes {
        if kind and n.kind != kind {
            continue;
        }
        if before and not (n.captured_at < before) {
            continue;
        }
        filtered.append(n);
    }
    ordered = sorted(filtered, key=_note_sort_key, reverse=True);
    if len(ordered) > limit {
        ordered = ordered[:limit];
    }
    return [_note_item(n) for n in ordered];
}

walker:priv ListNotes {
    """Own root only, no LLM. `limit` clamped to [0, 200] (SOH-211 bounded
    budgets idiom)."""
    has limit: int = 50;
    has before: str = "";
    has kind: str = "";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        notes: list[Note] = [root --> [?:Note]];
        items = list_notes_for(notes, min(max(self.limit, 0), 200), self.before, self.kind);
        for it in items {
            report it;
        }
    }
}

# ---------------------------------------------------------------- DeleteNote

"""Delete `note` and every Fact/Intent/Promise it asserts whose ONLY
asserting Note is `note` itself (a claim another Note also asserts
survives, only losing its `Asserts*` edge to `note`). People are NEVER
deleted here. Counts the people `note` mentions BEFORE deleting it (the
`Mentions` edges disappear with the Note, the Person nodes do not) as
`kept_people`. Deletion of each doomed Fact/Intent/Promise is delegated to
`forget.sv.jac`'s `_forget_fact`/`_forget_intent`/`_forget_promise` so
`RelevantTo` evidence pruning stays in exactly one place."""
def _delete_note_for(note: Note) -> dict[str, any] {
    facts_deleted = 0;
    for f in [note ->:Asserts:->] {
        asserting = [f <-:Asserts:<-];
        if len(asserting) <= 1 {
            _forget_fact(f);
            facts_deleted += 1;
        }
    }

    intents_deleted = 0;
    for i in [note ->:AssertsIntent:->] {
        asserting = [i <-:AssertsIntent:<-];
        if len(asserting) <= 1 {
            _forget_intent(i);
            intents_deleted += 1;
        }
    }

    promises_deleted = 0;
    for pr in [note ->:AssertsPromise:->] {
        asserting = [pr <-:AssertsPromise:<-];
        if len(asserting) <= 1 {
            _forget_promise(pr);
            promises_deleted += 1;
        }
    }

    kept_people = len(_note_people(note));

    del note;

    return {
        "deleted": {"facts": facts_deleted, "intents": intents_deleted, "promises": promises_deleted},
        "kept_people": kept_people
    };
}

walker:priv DeleteNote {
    """Own root only. `not_found` when `note_id` isn't a Note owned by the
    caller. Reports one dict `{deleted: {facts, intents, promises},
    kept_people}`."""
    has note_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        n = _my_node(self.note_id);
        if n is None or not isinstance(n, Note) {
            report _not_found();
            disengage;
        }
        note = n as Note;
        report _delete_note_for(note);
    }
}

# ---------------------------------------------------------------- ConfirmFact

walker:priv ConfirmFact {
    """Own root only. Sets `status = "confirmed"` on the caller's own Fact.
    Reports `[Fact]`, or `[{error: "not_found"}]` when `fact_id` isn't a
    Fact owned by the caller."""
    has fact_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        n = _my_node(self.fact_id);
        if n is None or not isinstance(n, Fact) {
            report _not_found();
            disengage;
        }
        f = n as Fact;
        f.status = "confirmed";
        report f;
    }
}

# ---------------------------------------------------------------- Digest

"""The ISO date of the Monday starting `now`'s week."""
def _week_of(now: datetime) -> str {
    monday = now - timedelta(days=now.weekday());
    return monday.date().isoformat();
}

def _new_people_sort_key(item: dict[str, any]) -> str {
    return item["_captured"] as str;
}

"""Every Person `me` met (`Knows`) whose `source_note` resolves to one of
`notes` captured in the last 7 days (inclusive), newest first. A `Knows`
edge with no `source_note`, or one that resolves to nothing in `notes`
(should not happen for the caller's own edges, but never raises either
way), is skipped rather than counted as "new"."""
def _new_people(me: Me, notes: list[Note], now: datetime) -> list[dict[str, any]] {
    notes_by_id: dict[str, Note] = {};
    for n in notes {
        notes_by_id[jid(n)] = n;
    }

    out: list[dict[str, any]] = [];
    for p in [me ->:Knows:->] {
        matched = [edge me ->:Knows:-> p];
        if not matched {
            continue;
        }
        ke = matched[0];
        if not ke.source_note or ke.source_note not in notes_by_id {
            continue;
        }
        note = notes_by_id[ke.source_note];
        captured_dt = _parse_naive_utc(note.captured_at);
        if captured_dt is None {
            continue;
        }
        days_since = (now.date() - captured_dt.date()).days;
        if days_since < 0 or days_since > 7 {
            continue;
        }
        out.append({"id": jid(p), "name": p.name, "how_met": ke.how_met, "_captured": note.captured_at});
    }
    ordered = sorted(out, key=_new_people_sort_key, reverse=True);
    return [{"id": it["id"], "name": it["name"], "how_met": it["how_met"]} for it in ordered];
}

"""`True` when the caller's active Goal's ranking predates one of `notes`
(`goals.sv.jac`'s own staleness rule, reused verbatim); `False` when there
is no active Goal."""
def _stale_ranking(me: Me, notes: list[Note]) -> bool {
    goal: Goal | None = None;
    for g in [me ->:HasGoal:->] {
        if g.active {
            goal = g;
        }
    }
    if goal is None {
        return False;
    }
    gg = goal as Goal;
    return ranking_is_stale(gg.ranked_at, notes);
}

"""Deterministic, testable directly on a hand-built `me` + `notes` (see
notes.test.jac). No `by llm` — every field is gathered from the graph or
computed from it."""
def digest_for(me: Me, notes: list[Note], now: datetime) -> dict[str, any] {
    week_of = _week_of(now);
    upcoming = upcoming_dates_for(me, notes, now, 14);
    promises_due = upcoming["promises"] as list[dict[str, any]];
    intents_expiring = upcoming["intents_expiring"] as list[dict[str, any]];
    new_people = _new_people(me, notes, now);
    stale = _stale_ranking(me, notes);
    suggestions = tend_for(me, now, 3);

    lines: list[str] = [f"Week of {week_of}."];

    if promises_due {
        lines.append(f"{len(promises_due)} promise(s) due in the next two weeks.");
    } else {
        lines.append("No promises due in the next two weeks.");
    }

    if intents_expiring {
        lines.append(f"{len(intents_expiring)} intent(s) expiring soon.");
    } else {
        lines.append("No intents expiring soon.");
    }

    if new_people {
        noun = "person" if len(new_people) == 1 else "people";
        lines.append(f"{len(new_people)} new {noun} this week.");
    } else {
        lines.append("No new people this week.");
    }

    if stale {
        lines.append("Your goal ranking is stale — refresh it.");
    } else {
        lines.append("Your goal ranking is current.");
    }

    return {
        "week_of": week_of,
        "promises_due": promises_due,
        "intents_expiring": intents_expiring,
        "new_people": new_people,
        "stale_ranking": stale,
        "suggestions": suggestions,
        "lines": lines
    };
}

walker:priv Digest {
    """Own root only, no LLM. `[]`-shaped defaults when the caller has no
    Me yet."""
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report {
                "week_of": "", "promises_due": [], "intents_expiring": [],
                "new_people": [], "stale_ranking": False, "suggestions": [], "lines": []
            };
            disengage;
        }
        me = existing[0];
        notes: list[Note] = [root --> [?:Note]];
        report digest_for(me, notes, datetime.now());
    }
}

# ---------------------------------------------------------------- DevSeedNote (test seeding)

walker:priv DevSeedNote {
    """Dev/test helper: one Note asserting one Fact about one Person (via
    `Mentions`/`Asserts`/`FactAbout`), no LLM, no full Capture flow —
    `notes.test.jac`'s isolation tests need a real cross-root Note/Fact
    pair to call `DeleteNote`/`ConfirmFact` on. Reuses the caller's `Me` if
    one already exists, else creates one. Never used outside
    `notes.test.jac`."""
    has text: str = "Notes-test seed";
    has kind: str = "debrief";
    has reports: list[dict[str, str]] = [];

    can run with Root entry {
        now = datetime.now().isoformat();
        note = (root ++> Note(text=self.text, kind=self.kind, captured_at=now))[0];

        existing = [root --> [?:Me]];
        me: Me | None = None;
        if existing {
            me = existing[0];
        } else {
            me = (root ++> Me(name="Notes-test seed Me"))[0];
        }
        mm = me as Me;

        p = (mm +>:Knows(status="confirmed", source_note=jid(note)):+> Person(name="Notes-test seed Person", status="confirmed"))[0];
        note +>:Mentions(span=""):+> p;

        f = (root ++> Fact(text="Notes-test seed fact", observed_at=now))[0];
        note +>:Asserts(span=""):+> f;
        f +>:FactAbout:+> p;

        report {"note_id": jid(note), "fact_id": jid(f), "person_id": jid(p)};
    }
}
