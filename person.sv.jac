"""person.sv.jac — PersonDetail and Brief (SOH-207 / SOH-199).

OWNER: Person A. See contracts/walkers.md for the exact report shapes and
AGENTS.md for the working rules this file must obey:
  - Relationships never decay: `Knows.last_contact` is copied into
    `PersonDetail`'s report for DISPLAY only — nothing here reads it to
    raise or lower anything.
  - Relevance lives on the `RelevantTo` edge (Person -> Goal), never on the
    Person node itself; `PersonDetail`/`Brief` only ever READ that edge,
    never write it (`GoalRank`, goals.sv.jac, is the only writer).
  - Every Fact/Intent/Promise tie carries its own provenance
    (`source_note_id` + `span`, resolved off the `Asserts*`/`Mentions`
    edge that connects it to the Note that said it — same idiom as
    `reads.sv.jac`'s `receipt_for`).
  - `by llm` (`spoken_brief`) returns a plain `obj` (`Recap`), never a node;
    its fields are copied into the report dict, nothing is persisted from
    it. ONE `by llm` call per `Brief` invocation, wrapped in `try/except`,
    with a deterministic fallback that always produces a usable recap.
  - Nothing sends: `Brief` only ever produces a spoken recap string (and,
    optionally, synthesized audio for the user's own earbuds) — no send
    button, no side effect on the graph.
  - Both walkers are `:priv` (own-root only, JWT required).

`person_id` is resolved directly among `[me ->:Knows:->]` — same idiom
`drafts.sv.jac`'s `DraftFollowUp` and `noted.sv.jac`'s `NotedCard` use: a
person only ever reaches that traversal if this account's own Capture/
Import/Confirm flow created the Knows edge, which is exactly "belongs to
the caller". A person id that isn't found there (unknown, or belongs to
someone else's graph) reports `not_found` — the same isolation guarantee
`reads.sv.jac`'s fuller `jobj`/`check_read_access`/`owner_root` idiom gives
for resolving *arbitrary* ids, without needing that idiom here since both
walkers only ever start from the caller's own `Me`.

`gather_follow_up_evidence`, `EvidenceItem`, `item_to_dict`,
`person_summary_text`, `build_evidence_text`, and `map_evidence_indices`
are imported from `drafts.sv.jac` rather than re-implemented (established
pattern in this codebase — `cards.sv.jac` imports from `onboard.sv.jac`,
`person.sv.jac` here does the same for the evidence-assembly helpers
`DraftFollowUp` already built). `_parse_naive_utc` is imported from
`goals.sv.jac` for the same reason.
"""

import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, HasGoal, RelevantTo, FromCard
}
import from goals { _parse_naive_utc }
import from dates { parse_due, due_label }
import from drafts {
    EvidenceItem, gather_follow_up_evidence, item_to_dict,
    person_summary_text, build_evidence_text, map_evidence_indices
}
import from scoring { polish_reason }
import from llm { llm }
import base64;
import os;
import requests;

# ---------------------------------------------------------------- PersonDetail: per-field views

def _fact_view(f: Fact, now: datetime) -> dict[str, any] {
    source_note_id = "";
    span = "";
    notes: list[Note] = [f <-:Asserts:<-];
    if notes {
        note = notes[0];
        source_note_id = jid(note);
        spans = [e.span for e in [edge note ->:Asserts:-> f]];
        if spans {
            span = spans[0];
        }
    }
    dt = _parse_naive_utc(f.observed_at);
    age_days = 0;
    if dt is not None {
        age_days = (now - dt).days;
    }
    return {"fact": f, "age_days": age_days, "source_note_id": source_note_id, "span": span};
}

def _fact_observed_dt(f: Fact) -> datetime {
    dt = _parse_naive_utc(f.observed_at);
    if dt is None {
        return datetime.min;
    }
    return dt;
}

def _intent_view(i: Intent, now: datetime) -> dict[str, any] {
    source_note_id = "";
    span = "";
    notes: list[Note] = [i <-:AssertsIntent:<-];
    if notes {
        note = notes[0];
        source_note_id = jid(note);
        spans = [e.span for e in [edge note ->:AssertsIntent:-> i]];
        if spans {
            span = spans[0];
        }
    }
    expired = False;
    if i.expires_at {
        exp_dt = _parse_naive_utc(i.expires_at);
        if exp_dt is not None and exp_dt < now {
            expired = True;
        }
    }
    return {"intent": i, "expired": expired, "source_note_id": source_note_id, "span": span};
}

"""Order intents newest-first by their asserting Note's `captured_at` (an
Intent has no `observed_at` of its own); an Intent with no asserting Note
(self-onboarded, via `HasIntent`) sorts oldest."""
def _intent_observed_dt(i: Intent) -> datetime {
    notes_for_intent: list[Note] = [i <-:AssertsIntent:<-];
    if notes_for_intent {
        dt = _parse_naive_utc(notes_for_intent[0].captured_at);
        if dt is not None {
            return dt;
        }
    }
    return datetime.min;
}

"""SOH-232: `due_label` is additive - an "Oct 3" style display label resolved
from `pr.due` (still whatever raw/ISO text `pr.due` itself holds; re-parsed
through `dates.parse_due` the same way `dates._normalize_promises` does, so
an un-normalized raw span like "October 3rd" still resolves) so clients
never need to show the raw captured span. `""` when `pr.due` is empty or
unparsable."""
def _promise_view(pr: Promise, now: datetime) -> dict[str, any] {
    source_note_id = "";
    span = "";
    notes: list[Note] = [pr <-:AssertsPromise:<-];
    if notes {
        note = notes[0];
        source_note_id = jid(note);
        spans = [e.span for e in [edge note ->:AssertsPromise:-> pr]];
        if spans {
            span = spans[0];
        }
    }
    due_lbl = "";
    if pr.due {
        due_iso = parse_due(pr.due, now.isoformat());
        if due_iso {
            due_lbl = due_label(due_iso);
        }
    }
    return {"promise": pr, "source_note_id": source_note_id, "span": span, "due_label": due_lbl};
}

"""Open (`done == False`) first, then done; within each group, `due`
ascending with an empty `due` sorted last — same ordering rule
`reads.sv.jac`'s `_promise_sort_key` uses for `ListPromises`."""
def _promise_sort_key(pr: Promise) -> tuple[int, int, str] {
    done_rank = 1 if pr.done else 0;
    due = pr.due;
    due_empty_rank = 1 if not due else 0;
    return (done_rank, due_empty_rank, due);
}

"""A fresh, unattached `Note` carrying the same fields as `n` except `text`
capped at 400 chars — never mutates the real persisted Note. Not connected
to the graph (no `++>`/`+>:`), so nothing is written; it exists only for
this report."""
def _note_view(n: Note, p: Person) -> dict[str, any] {
    span = "";
    spans = [e.span for e in [edge n ->:Mentions:-> p]];
    if spans {
        span = spans[0];
    }
    text = n.text;
    if len(text) > 400 {
        text = text[:400];
    }
    capped = Note(text=text, kind=n.kind, captured_at=n.captured_at, audio_ref=n.audio_ref);
    return {"note": capped, "span": span};
}

def _note_observed_dt(n: Note) -> datetime {
    dt = _parse_naive_utc(n.captured_at);
    if dt is None {
        return datetime.min;
    }
    return dt;
}

# ---------------------------------------------------------------- PersonDetail assembly

"""Deterministic, testable directly on hand-built nodes (no jobj/ownership
involved) — see person.test.jac. Bounds every list at 50."""
def person_detail_for(me: Me, person: Person) -> dict[str, any] {
    now = datetime.now();

    how_met = "";
    knows_status = "";
    last_contact = "";
    know_edges = [edge me ->:Knows:-> person];
    if know_edges {
        ke = know_edges[0];
        how_met = ke.how_met;
        knows_status = ke.status;
        last_contact = ke.last_contact;   # display only; nothing reads it to lower anything
    }

    relevance: dict[str, any] | None = None;
    goals: list[Goal] = [me ->:HasGoal:->];
    active_goal: Goal | None = None;
    for g in goals {
        if g.active {
            active_goal = g;
        }
    }
    if active_goal is not None {
        ag = active_goal as Goal;
        rel_edges = [edge person ->:RelevantTo:-> ag];
        if rel_edges {
            re = rel_edges[0];
            relevance = {
                "goal_id": jid(ag), "goal_text": ag.text, "label": re.label,
                "strength": re.strength, "reason": re.reason, "opener": re.opener
            };
        }
    }

    facts_raw: list[Fact] = [person <-:FactAbout:<-];
    facts_raw = sorted(facts_raw, key=_fact_observed_dt, reverse=True);
    facts_views = [_fact_view(f, now) for f in facts_raw];
    if len(facts_views) > 50 {
        facts_views = facts_views[:50];
    }

    intents_raw: list[Intent] = [person <-:IntentAbout:<-];
    intents_raw = sorted(intents_raw, key=_intent_observed_dt, reverse=True);
    intents_views = [_intent_view(i, now) for i in intents_raw];
    if len(intents_views) > 50 {
        intents_views = intents_views[:50];
    }

    promises_raw: list[Promise] = [person <-:PromiseTo:<-];
    promises_raw = sorted(promises_raw, key=_promise_sort_key);
    promises_views = [_promise_view(pr, now) for pr in promises_raw];
    if len(promises_views) > 50 {
        promises_views = promises_views[:50];
    }

    notes_raw: list[Note] = [person <-:Mentions:<-];
    notes_raw = sorted(notes_raw, key=_note_observed_dt, reverse=True);
    notes_views = [_note_view(n, person) for n in notes_raw];
    if len(notes_views) > 50 {
        notes_views = notes_views[:50];
    }

    reported_raw: list[Person] = [person <-:Reported:<-];
    reported_by: list[dict[str, str]] = [];
    for rp in reported_raw {
        span = "";
        matched = [edge rp ->:Reported:-> person];
        if matched {
            span = matched[0].span;
        }
        reported_by.append({"person_id": jid(rp), "name": rp.name, "span": span});
    }
    if len(reported_by) > 50 {
        reported_by = reported_by[:50];
    }

    card_handle = "";
    cards: list[Card] = [person ->:FromCard:->];
    if cards {
        card_handle = cards[0].handle;
    }

    return {
        "person": person, "how_met": how_met, "knows_status": knows_status,
        "last_contact": last_contact, "relevance": relevance,
        "facts": facts_views, "intents": intents_views, "promises": promises_views,
        "notes": notes_views, "reported_by": reported_by, "card_handle": card_handle
    };
}

def _not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

# ---------------------------------------------------------------- PersonDetail walker

walker:priv PersonDetail {
    """Everything the person sheet needs, in one call. Reports one entry
    (see `person_detail_for`), or `{ error: "not_found" }` when `person_id`
    isn't one of the caller's own `[me ->:Knows:->]` people."""
    has person_id: str;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report _not_found();
            disengage;
        }
        me = existing[0];

        matches = [p for p in [me ->:Knows:->] if jid(p) == self.person_id];
        if not matches {
            report _not_found();
            disengage;
        }
        person = matches[0];

        report person_detail_for(me, person);
    }
}

# ---------------------------------------------------------------- Brief: LLM shape

obj Recap {
    has text: str;
    has evidence_indices: list[int];
}
sem Recap.text = "A spoken 20-second recap (45-70 words) for the user's earbuds before meeting this person: who they are, the one thing from the last conversation, any open promise, what they wanted. Plain spoken sentences, second person ('you promised'), no bullet points, no greeting, no sign-off. Speak like a person talking to the user, never like a system describing its input: never say 'the fact', 'the note', 'the author', or 'the user'; never quote evidence in parentheses. Never use an em-dash or en-dash; use a period, colon or comma instead.";
sem Recap.evidence_indices = "Numbers of the evidence items the recap relies on.";

def spoken_brief(person_summary: str, evidence_text: str) -> Recap by llm(temperature=0.4);
sem spoken_brief = "Write a short spoken recap of this person for the user's earbuds, right before meeting them, using only the given numbered evidence. Never use an em-dash or en-dash; use a period, colon or comma instead.";
sem spoken_brief.person_summary = "The person's name, title, and organization.";
sem spoken_brief.evidence_text = "Numbered evidence about this person: facts, open promises, current intents, and notes that mention them; may end with an unnumbered line about why they're relevant to the user's current goal.";

# ---------------------------------------------------------------- Brief: deterministic helpers

"""First evidence item of a given kind, else None."""
def _first_of_kind(evidence: list[EvidenceItem], kind: str) -> EvidenceItem | None {
    for it in evidence {
        if it.kind == kind {
            return it;
        }
    }
    return None;
}

"""SOH-232: the Brief's "Last time" line must describe an actual captured
conversation - never an ImportPeople/OnboardMe housekeeping note (the
audit's "Last time: Imported 3 people from linkedin." bug). `evidence`'s
"note" items are already newest-first (`gather_follow_up_evidence`); this
walks them and returns the first whose underlying Note is a real
conversation kind, else None."""
glob CONVERSATION_NOTE_KINDS: list[str] = ["debrief", "paste", "voice"];

def _last_conversation_note_item(evidence: list[EvidenceItem]) -> EvidenceItem | None {
    for it in evidence {
        if it.kind != "note" {
            continue;
        }
        try {
            n = jobj(it.id);
        } except Exception {
            continue;   # not a real node id (e.g. a hand-built test fixture)
        }
        if n is None {
            continue;
        }
        note = n as Note;
        if note.kind in CONVERSATION_NOTE_KINDS {
            return it;
        }
    }
    return None;
}

"""SOH-232: the label for the newest intent evidence item depends on the
underlying Intent's own kind - 'They wanted:' for a need (or anything not
recognized as an offer), 'They offered:' for an offer (the audit's
"They wanted: Offered to review your pitch deck" template mismatch)."""
def _intent_label(it: EvidenceItem) -> str {
    try {
        n = jobj(it.id);
    } except Exception {
        return "They wanted:";   # not a real node id (e.g. a hand-built test fixture)
    }
    if n is None {
        return "They wanted:";
    }
    intent = n as Intent;
    if intent.kind == "offer" {
        return "They offered:";
    }
    return "They wanted:";
}

"""Deterministic fallback recap: `"{name}, {title} at {org}. Last time: ...
You promised: ... They wanted: ..."` with any empty clause dropped cleanly
(no dangling "at" / "Last time: ." etc)."""
def deterministic_brief(person: Person, evidence: list[EvidenceItem]) -> str {
    parts: list[str] = [];

    role = "";
    if person.title and person.org {
        role = f"{person.title} at {person.org}";
    } elif person.title {
        role = person.title;
    } elif person.org {
        role = f"at {person.org}";
    }
    if role {
        parts.append(f"{person.name}, {role}.");
    } else {
        parts.append(f"{person.name}.");
    }

    last_item = _last_conversation_note_item(evidence);
    if last_item is not None {
        li = last_item as EvidenceItem;
        parts.append(f"Last time: {li.span}.");
    } else {
        parts.append("You haven't captured a conversation with them yet.");
    }

    promise_item = _first_of_kind(evidence, "promise");
    if promise_item is not None {
        pi = promise_item as EvidenceItem;
        parts.append(f"You promised: {pi.span}.");
    } else {
        parts.append("You promised: nothing open.");
    }

    intent_item = _first_of_kind(evidence, "intent");
    if intent_item is not None {
        ii = intent_item as EvidenceItem;
        label = _intent_label(ii);
        parts.append(f"{label} {ii.span}.");
    } else {
        parts.append("They wanted: nothing on record.");
    }

    return " ".join(parts);
}

"""Fallback recap: the deterministic text plus every evidence item as
`based_on` (there's no LLM-picked subset to narrow to). Used both when
there's no evidence at all and when the one `by llm` call fails — same
"always produces a usable result" shape as `drafts.sv.jac`'s
`fallback_draft`."""
def fallback_recap(person: Person, evidence: list[EvidenceItem]) -> dict[str, any] {
    return {
        "text": deterministic_brief(person, evidence),
        "based_on": [item_to_dict(it) for it in evidence]
    };
}

"""Relevance reason for `person` against the caller's ACTIVE goal, else ""."""
def _relevance_reason(me: Me, person: Person) -> str {
    goals: list[Goal] = [me ->:HasGoal:->];
    for g in goals {
        if g.active {
            rel_edges = [edge person ->:RelevantTo:-> g];
            if rel_edges {
                return rel_edges[0].reason;
            }
        }
    }
    return "";
}

# ---------------------------------------------------------------- Brief: voice

"""POST the recap text to ElevenLabs TTS; base64-encode the audio on
success. Never logs the key, even on a non-2xx response. No key ->
`voice_error: "no_key"`; any other failure -> `voice_error` is the status
code or exception, capped at 120 chars."""
def synthesize_voice(text: str) -> dict[str, str] {
    api_key = os.environ.get("ELEVENLABS_API_KEY", "");
    if not api_key {
        return {"audio_b64": "", "mime": "", "voice_error": "no_key"};
    }
    voice_id = os.environ.get("ELEVENLABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM");

    try {
        resp = requests.post(
            f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}?output_format=mp3_44100_64",
            headers={"xi-api-key": api_key, "Content-Type": "application/json"},
            json={"text": text, "model_id": "eleven_turbo_v2_5"},
            timeout=30
        );
    } except Exception as e {
        msg = str(e);
        if len(msg) > 120 {
            msg = msg[:120];
        }
        return {"audio_b64": "", "mime": "", "voice_error": msg};
    }

    if resp.status_code == 200 {
        b64 = base64.b64encode(resp.content).decode("ascii");
        return {"audio_b64": b64, "mime": "audio/mpeg", "voice_error": ""};
    }

    err = str(resp.status_code);
    if len(err) > 120 {
        err = err[:120];
    }
    return {"audio_b64": "", "mime": "", "voice_error": err};
}

# ---------------------------------------------------------------- Brief walker

walker:priv Brief {
    """Spoken recap for one of the caller's own people, evidence assembled
    the same way `DraftFollowUp` does (`gather_follow_up_evidence`), plus
    the relevance reason against the caller's active goal when there is
    one. ONE `by llm` call, wrapped in `try/except`; deterministic fallback
    on any failure or when there's no evidence at all. `voice=True` (and a
    non-empty `ELEVENLABS_API_KEY`) additionally synthesizes audio."""
    has person_id: str;
    has voice: bool = True;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report _not_found();
            disengage;
        }
        me = existing[0];

        matches = [p for p in [me ->:Knows:->] if jid(p) == self.person_id];
        if not matches {
            report _not_found();
            disengage;
        }
        person = matches[0];

        now = datetime.now();
        evidence = gather_follow_up_evidence(person, now);
        relevance_reason = _relevance_reason(me, person);

        text = "";
        based_on: list[dict[str, str]] = [];
        fallback = False;

        if not evidence {
            fb = fallback_recap(person, evidence);
            text = fb["text"] as str;
            based_on = fb["based_on"] as list[dict[str, str]];
            fallback = True;
        } else {
            try {
                summary = person_summary_text(person);
                evidence_text = build_evidence_text(evidence);
                if relevance_reason {
                    evidence_text = evidence_text + f"\nAlso relevant to your current goal: {relevance_reason}";
                }
                result = spoken_brief(summary, evidence_text);
                mapped = map_evidence_indices(evidence, result.evidence_indices);
                if not result.text or not mapped {
                    raise Exception("empty recap or no evidence cited");
                }
                text = result.text;
                based_on = mapped;
            } except Exception {
                fb = fallback_recap(person, evidence);
                text = fb["text"] as str;
                based_on = fb["based_on"] as list[dict[str, str]];
                fallback = True;
            }
        }
        # SOH-226: product copy, not model narration - applied once, at the
        # walker boundary, so `deterministic_brief`'s own unit test keeps
        # asserting its plain (already-conformant) text unpolished.
        text = polish_reason(text);

        voice_error = "";
        audio_b64 = "";
        mime = "";
        if self.voice {
            voiced = synthesize_voice(text);
            audio_b64 = voiced["audio_b64"];
            mime = voiced["mime"];
            voice_error = voiced["voice_error"];
        } else {
            voice_error = "voice_disabled";
        }

        report {
            "person_id": jid(person), "text": text, "audio_b64": audio_b64, "mime": mime,
            "based_on": based_on, "fallback": fallback, "voice_error": voice_error
        };
    }
}
