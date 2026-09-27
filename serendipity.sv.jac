"""Serendipity — paste an article title/summary or an event description;
which of my contacts would care, and why, with the evidence (SOH-201, PRD
Tier 2 #33).

OWNER: Person A. See contracts/walkers.md `Serendipity(text, url, limit)` for
the exact report shape. Rules from AGENTS.md this file must obey:
  - `:priv`, own-root only, NO `by llm` anywhere in this module. Matching is
    deterministic token overlap on purpose (this is a keyword-overlap nudge,
    not a model judgment) — a model pass can be added later behind its own
    `by llm` call without changing this shape.
  - Never ranks a person's worth: the report order is match COUNT only (then
    newest evidence to break ties), never a score on the person themselves.
  - Every evidence item is traceable to a real Fact/Intent/Note id — reuses
    `goals.sv.jac`'s `gather_evidence`/`EvidenceItem` rather than
    re-gathering (same idiom `tend.sv.jac`/`recall.sv.jac` already use for
    `_parse_naive_utc`/`compute_days_since_contact`/`evidence_item_from_jid`).
  - Nothing sends: `share_draft` is a draft string only, never dispatched.
  - Never reads `Knows.last_contact` for anything.

Tokenizer/stopword list reused from `recall.sv.jac` (`_tokenize`, built on
its `STOPWORDS` glob) rather than re-implemented — same lowercase/alnum/
length->=4/non-stopword rule `Recall`'s pre-filter already uses.

Deterministic gathering is scoped from the caller's own `Me` via a typed
traversal (`me ->:Knows:-> Person`), exactly the `tend.sv.jac` idiom: every
test here builds its own fresh `Me` + people and calls `serendipity_for`
directly — never `root spawn Serendipity(...)`, which would resolve "the"
`Me` ambiguously off the shared, persisted `jac test` root (AGENTS.md
gotcha: never take `[root --> [?:Me]][0]` inside a helper tests call). The
walker itself does that one lookup, since at real runtime (`:priv`, own
root) there is exactly one `Me`.
"""

import from datetime { datetime }
import from schema { Me, Person, Knows, IntentAbout }
import from goals { EvidenceItem, gather_evidence, _parse_naive_utc }
import from recall { _tokenize }

# ---------------------------------------------------------------- helpers

"""Every Person reachable via `me ->:Knows:->` that counts as "confirmed
known" — `Person.status == "confirmed"` AND the `Knows` edge itself isn't
`"proposed"` (same "known" rule `goals.sv.jac`'s `collect_candidates` uses).
Looks up each person's own `Knows` edge directly rather than zipping two
separate traversals by index (same review fix `collect_candidates` already
applies)."""
def _confirmed_known_people(me: Me) -> list[Person] {
    people: list[Person] = [];
    seen: list[str] = [];
    for p in [me ->:Knows:->] {
        pid = jid(p);
        if pid in seen {
            continue;
        }
        matched: list[Knows] = [edge me ->:Knows:-> p];
        if not matched {
            continue;
        }
        e = matched[0];
        if p.status != "confirmed" or e.status == "proposed" or p.archived {
            continue;
        }
        seen.append(pid);
        people.append(p);
    }
    return people;
}

"""Distinct tokens shared between `text_tokens` and `candidate_tokens`,
preserving first-seen order out of `candidate_tokens`."""
def _shared_tokens(text_tokens: list[str], candidate_tokens: list[str]) -> list[str] {
    shared: list[str] = [];
    for t in candidate_tokens {
        if t in text_tokens and t not in shared {
            shared.append(t);
        }
    }
    return shared;
}

"""One person's full matched-token set: their gathered evidence spans plus
`org`/`title`. Also reports whether any matched token came from an Intent
specifically (an explicit want beats a keyword — the >=1 threshold)."""
def _match_person(text_tokens: list[str], p: Person, evidence: list[EvidenceItem]) -> dict[str, any] {
    matched: list[str] = [];
    matched_from_intent = False;

    for item in evidence {
        item_tokens = _tokenize(item.span);
        shared = _shared_tokens(text_tokens, item_tokens);
        if shared and item.kind == "intent" {
            matched_from_intent = True;
        }
        for t in shared {
            if t not in matched {
                matched.append(t);
            }
        }
    }

    for t in _shared_tokens(text_tokens, _tokenize(p.org)) {
        if t not in matched {
            matched.append(t);
        }
    }
    for t in _shared_tokens(text_tokens, _tokenize(p.title)) {
        if t not in matched {
            matched.append(t);
        }
    }

    return {"matched": matched, "matched_from_intent": matched_from_intent};
}

"""`>= 2` matched tokens qualifies on its own; `>= 1` qualifies when at least
one of those matched tokens came from an Intent's own text (an explicit want
beats a bare keyword overlap)."""
def _qualifies(matched: list[str], matched_from_intent: bool) -> bool {
    if len(matched) >= 2 {
        return True;
    }
    return matched_from_intent and len(matched) >= 1;
}

"""The single evidence item to cite in `why`/`share_draft`: among the
evidence items that themselves share a token with the pasted text, prefer an
Intent (explicit want) over a Fact over a Note; break ties by the newest
`observed_at`. `None` when no individual evidence item overlapped (a match
that only came from `org`/`title`)."""
def _evidence_priority(kind: str) -> int {
    if kind == "intent" {
        return 0;
    }
    if kind == "fact" {
        return 1;
    }
    return 2;
}

def _evidence_priority_key(item: EvidenceItem) -> int {
    return _evidence_priority(item.kind);
}

def _evidence_dt(item: EvidenceItem) -> datetime {
    dt = _parse_naive_utc(item.observed_at);
    if dt is None {
        return datetime.min;
    }
    return dt;
}

def pick_top_evidence(text_tokens: list[str], evidence: list[EvidenceItem]) -> EvidenceItem | None {
    candidates: list[EvidenceItem] = [];
    for item in evidence {
        item_tokens = _tokenize(item.span);
        overlap = False;
        for t in item_tokens {
            if t in text_tokens {
                overlap = True;
                break;
            }
        }
        if overlap {
            candidates.append(item);
        }
    }
    if not candidates {
        return None;
    }
    by_date = sorted(candidates, key=_evidence_dt, reverse=True);
    by_priority = sorted(by_date, key=_evidence_priority_key);
    return by_priority[0];
}

"""The newest `observed_at` across every gathered evidence item, unparsable/
empty ones ignored — used only to break ties in the report ordering, never
to gate or rank a person on its own."""
def _newest_observed_at(evidence: list[EvidenceItem]) -> str {
    best = "";
    best_dt = datetime.min;
    for item in evidence {
        dt = _parse_naive_utc(item.observed_at);
        if dt is None {
            continue;
        }
        if dt > best_dt {
            best_dt = dt;
            best = item.observed_at;
        }
    }
    return best;
}

"""First two matched tokens, in the order they appear in the pasted text
(not in evidence-gathering order) — a short, deterministic stand-in for "the
topic of this piece". `"this"` alone when nothing matched (should not happen
for a person who already qualified, since qualifying requires >=1 matched
token)."""
def _topic_phrase(text_tokens: list[str], matched: list[str]) -> str {
    chosen: list[str] = [];
    for t in text_tokens {
        if t in matched and t not in chosen {
            chosen.append(t);
        }
        if len(chosen) >= 2 {
            break;
        }
    }
    if not chosen {
        return "this";
    }
    return " ".join(chosen);
}

"""One sentence citing the top evidence, e.g. 'Maya wants feedback from
wheelchair users; this piece is about accessible robotics.' Falls back to
`org`/`title` when no single evidence item overlapped (matched only via
org/title)."""
glob INTENT_LEADS: list[str] = [
    "looking for", "wants", "want", "needs", "need", "seeking", "hoping",
    "can ", "is ", "open to", "offers", "would like"
];

"""Quoted evidence text for the middle of a sentence: first letter
lower-cased, trailing period dropped (SOH-212)."""
def _inline(text: str) -> str {
    t = (text or "").strip().rstrip(".").strip();
    if len(t) == 0 {
        return t;
    }
    return t[:1].lower() + t[1:];
}

"""The verb phrase for one intent: its own text when it already leads with a
verb ("Looking for a nurse mentor" -> "looking for a nurse mentor"), else
"wants ..." / "can offer ..." by intent kind."""
def _intent_clause(text: str, kind: str) -> str {
    inline = _inline(text);
    low = inline.lower();
    for lead in INTENT_LEADS {
        if low.startswith(lead) {
            return inline;
        }
    }
    if kind == "offer" {
        return f"can offer {inline}";
    }
    return f"wants {inline}";
}

def _why_fragment(p: Person, top: EvidenceItem | None, topic: str, intent_kinds: dict[str, str] = {}) -> str {
    if top is not None {
        t = top as EvidenceItem;
        if t.kind == "intent" {
            kind = "need";
            if t.id in intent_kinds {
                kind = intent_kinds[t.id];
            }
            clause = _intent_clause(t.span, kind);
        } elif t.kind == "fact" {
            clause = f"is known for {_inline(t.span)}";
        } else {
            clause = f"was noted for {_inline(t.span)}";
        }
    } elif p.title and p.org {
        clause = f"works as {p.title} at {p.org}";
    } elif p.title {
        clause = f"works as {p.title}";
    } elif p.org {
        clause = f"works at {p.org}";
    } else {
        clause = "matches this topic";
    }
    return f"{clause}; this piece is about {topic}";
}

"""Descending matched-token count, then newest evidence (both display-only
tie-breaks, never a score on the person). Two-pass stable sort: sort by the
secondary key (newest evidence) descending first, then stable-sort by the
primary key (matched count) descending — same idiom `goals.sv.jac`'s
`_sort_key` tuple achieves with ints; here one key is a string timestamp so
two passes keep every comparison in its own typed helper."""
def _newest_key(item: dict[str, any]) -> str {
    return item["_newest_at"] as str;
}

def _count_key(item: dict[str, any]) -> int {
    return item["_count"] as int;
}

# ---------------------------------------------------------------- serendipity_for

"""Deterministic, testable directly on a hand-built `me` (see
serendipity.test.jac): tokenize `text`; for every confirmed-known person,
gather their OWN Facts/non-expired-Intents (never co-mentioning Notes) via
`goals.sv.jac`'s `gather_evidence`; a person qualifies at >=2 matched tokens
(shared with their evidence spans or their org/title) or >=1 when an Intent
supplied one of those tokens; ordered by matched-token count desc, then
newest evidence desc; capped at `limit`."""
def serendipity_for(me: Me, text: str, url: str, limit: int, now: datetime) -> list[dict[str, any]] {
    text_tokens = _tokenize(text);
    if not text_tokens {
        return [];
    }

    rows: list[dict[str, any]] = [];

    for p in _confirmed_known_people(me) {
        # SOH-212: match only on the person's OWN Facts/Intents (FactAbout /
        # IntentAbout), never on a Note that merely mentions them alongside
        # someone else ("Tom" matched a nursing article via Helen's note).
        evidence: list[EvidenceItem] = [e for e in gather_evidence(p, now) if e.kind != "note"];
        intent_kinds: dict[str, str] = {};
        for it in [p <-:IntentAbout:<-] {
            intent_kinds[jid(it)] = it.kind;
        }
        m = _match_person(text_tokens, p, evidence);
        matched = m["matched"] as list[str];
        matched_from_intent = m["matched_from_intent"] as bool;

        if not _qualifies(matched, matched_from_intent) {
            continue;
        }

        top = pick_top_evidence(text_tokens, evidence);
        topic = _topic_phrase(text_tokens, matched);
        fragment = _why_fragment(p, top, topic, intent_kinds);
        why = f"{p.name} {fragment}.";

        excerpt = url if url else text[:80];
        share_draft = f"Hi {p.name}, saw this and thought of you: {excerpt} — {fragment}. No pressure.";

        evidence_out: list[dict[str, str]] = [];
        for item in evidence {
            evidence_out.append({"id": item.id, "kind": item.kind, "span": item.span, "observed_at": item.observed_at});
        }

        rows.append({
            "person": p,
            "matched": matched,
            "why": why,
            "evidence": evidence_out,
            "share_draft": share_draft,
            "_count": len(matched),
            "_newest_at": _newest_observed_at(evidence)
        });
    }

    by_newest = sorted(rows, key=_newest_key, reverse=True);
    ordered = sorted(by_newest, key=_count_key, reverse=True);

    effective_limit = limit if limit > 0 else 0;
    if len(ordered) > effective_limit {
        ordered = ordered[:effective_limit];
    }

    out: list[dict[str, any]] = [];
    for item in ordered {
        out.append({
            "person": item["person"],
            "matched": item["matched"],
            "why": item["why"],
            "evidence": item["evidence"],
            "share_draft": item["share_draft"]
        });
    }
    return out;
}

# ---------------------------------------------------------------- walker

walker:priv Serendipity {
    """Own root only, no `by llm`. Reports `serendipity_for`'s ordered,
    capped list; `[]` when the caller has no `Me` yet."""
    has text: str;
    has url: str = "";
    has limit: int = 5;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            disengage;
        }
        me = existing[0];
        items = serendipity_for(me, self.text, self.url, min(max(self.limit, 0), 50), datetime.now());  # SOH-211 bounded
        for it in items {
            report it;
        }
    }
}
