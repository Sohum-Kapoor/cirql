"""DraftFollowUp — a follow-up message drafter for one person (SOH-191).

OWNER: Person A. See contracts/walkers.md `DraftFollowUp(person_id, intent)` for
the exact report shape. Rules from AGENTS.md this file must obey:
  - Every Fact/Intent/Promise tie the draft leans on carries its own
    provenance (`based_on` items always resolve back to a real Fact/Intent/
    Promise/Note node's id — never invented).
  - `by llm` returns a plain `obj` (`FollowUp`), never a node — its fields are
    copied into the report dict, nothing is persisted from it.
  - Nothing sends: this only ever produces a draft string. No send button,
    no side effect on the graph.
  - ONE `by llm` call per invocation, wrapped in `try/except`; the
    deterministic `fallback_draft` always produces a usable message.
  - `Knows.last_contact` is never read here (nothing in this module lowers or
    raises anything from it).

`_parse_naive_utc` is imported from `goals.sv.jac` rather than re-implemented
(established pattern in this codebase — `cards.sv.jac` imports from
`onboard.sv.jac`, `exchange.sv.jac` imports from `scoring.sv.jac`).

Ownership: `person_id` is resolved by looking it up directly among
`[me ->:Knows:->]` — a person only ever reaches that traversal if this
account's Capture/Import/Confirm flow created the Knows edge, which is
exactly "belongs to the caller". A person id that isn't found there (unknown,
or belongs to someone else's graph) reports `not_found`; the fuller
`jobj`/`check_read_access`/`owner_root` idiom in `reads.sv.jac` is for
resolving *arbitrary* ids (e.g. `Receipt`), which this walker never needs to
do since it only ever starts from the caller's own `Me`.
"""

import re;
import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise,
    Knows, FactAbout, IntentAbout, PromiseTo, Mentions, AssertsIntent, AssertsPromise
}
import from llm { llm }
import from goals { _parse_naive_utc }

# ---------------------------------------------------------------- LLM shape

obj FollowUp {
    has draft: str;
    has evidence_indices: list[int];
}
sem FollowUp.draft = "A two-to-four sentence message to this person that mentions ONE specific thing from the numbered evidence (a fact, an open promise, or something they wanted), sounds like a real person, no flattery, no subject line, no sign-off placeholder. Never say 'the fact'/'the note'/'the author'/'the user' or narrate where the evidence came from — write the message itself, not a description of it; never quote evidence in parentheses. Never use an em-dash or en-dash; use a period, colon or comma instead.";
sem FollowUp.evidence_indices = "Numbers of the evidence items the draft relies on.";

def draft_follow_up(person_summary: str, evidence_text: str, intent: str) -> FollowUp by llm(temperature=0.5);
sem draft_follow_up = "Draft a short follow-up message to a specific person using only the given numbered evidence. Never use an em-dash or en-dash; use a period, colon or comma instead.";
sem draft_follow_up.person_summary = "The person's name, title, and organization.";
sem draft_follow_up.evidence_text = "Numbered evidence about this person: facts, open promises, and notes that mention them.";
sem draft_follow_up.intent = "What the user wants this message to do, e.g. 'send the demo I promised'; empty string when not given.";

# ---------------------------------------------------------------- plain data

obj EvidenceItem {
    has id: str;
    has kind: str;          # note | fact | intent | promise
    has observed_at: str;
    has span: str;
}

def item_to_dict(it: EvidenceItem) -> dict[str, str] {
    return {"id": it.id, "kind": it.kind, "observed_at": it.observed_at, "span": it.span};
}

# ---------------------------------------------------------------- deterministic helpers
# (no LLM; each is a plain `def` so a test block can call it directly on
# hand-built nodes attached under root.)

def _sortable_dt(ts: str) -> datetime {
    dt = _parse_naive_utc(ts);
    if dt is None {
        return datetime.min;   # empty/unparsable observed_at sorts oldest
    }
    return dt;
}

def _evidence_sort_key(it: EvidenceItem) -> datetime {
    return _sortable_dt(it.observed_at);
}

"""Facts, Intents, open Promises to `p`, and Notes mentioning `p` — merged
newest-first by `observed_at` and capped at 8. Intents whose `expires_at` is
non-empty and already in the past are skipped (freshness/expiry, per
AGENTS.md); Promises already `done` are skipped (only OPEN promises are
follow-up material)."""
def gather_follow_up_evidence(p: Person, now: datetime) -> list[EvidenceItem] {
    items: list[EvidenceItem] = [];

    for f in [p <-:FactAbout:<-] {
        items.append(EvidenceItem(id=jid(f), kind="fact", observed_at=f.observed_at, span=f.text));
    }

    for i in [p <-:IntentAbout:<-] {
        if i.expires_at {
            exp_dt = _parse_naive_utc(i.expires_at);
            if exp_dt is None {
                continue;   # unparsable expires_at -> skip this intent
            }
            if exp_dt < now {
                continue;   # expired -> skip
            }
        }
        observed_at = "";
        notes_for_intent = [i <-:AssertsIntent:<-];
        if notes_for_intent {
            observed_at = notes_for_intent[0].captured_at;
        }
        items.append(EvidenceItem(id=jid(i), kind="intent", observed_at=observed_at, span=i.text));
    }

    for pr in [p <-:PromiseTo:<-] {
        if pr.done {
            continue;   # only open promises are follow-up material
        }
        observed_at = "";
        notes_for_promise = [pr <-:AssertsPromise:<-];
        if notes_for_promise {
            observed_at = notes_for_promise[0].captured_at;
        }
        items.append(EvidenceItem(id=jid(pr), kind="promise", observed_at=observed_at, span=pr.text));
    }

    for n in [p <-:Mentions:<-] {
        items.append(EvidenceItem(id=jid(n), kind="note", observed_at=n.captured_at, span=n.text[:120]));
    }

    items_sorted = sorted(items, key=_evidence_sort_key, reverse=True);
    if len(items_sorted) > 8 {
        items_sorted = items_sorted[:8];
    }
    return items_sorted;
}

def person_summary_text(p: Person) -> str {
    parts: list[str] = [p.name];
    if p.title {
        parts.append(p.title);
    }
    if p.org {
        parts.append(f"at {p.org}");
    }
    return " ".join(parts);
}

"""One numbered line per evidence item for the single `by llm` call."""
def build_evidence_text(evidence: list[EvidenceItem]) -> str {
    lines: list[str] = [];
    idx = 0;
    for it in evidence {
        lines.append(f"[{idx}] {it.kind}: {it.span} ({it.observed_at})");
        idx += 1;
    }
    return "\n".join(lines);
}

"""Map the LLM's `evidence_indices` back to full evidence dicts; out-of-range
indices are dropped, duplicates deduped (first wins) — same idiom as
`goals.sv.jac`'s `materialize` / `scoring.sv.jac`'s `post_process`."""
def map_evidence_indices(evidence: list[EvidenceItem], indices: list[int]) -> list[dict[str, str]] {
    out: list[dict[str, str]] = [];
    seen: list[int] = [];
    for ei in indices {
        if ei < 0 or ei >= len(evidence) {
            continue;
        }
        if ei in seen {
            continue;
        }
        seen.append(ei);
        out.append(item_to_dict(evidence[ei]));
    }
    return out;
}

"""SOH-212 (judge pass): the old template glued the promise's raw, verb-first
text straight after "following up on" ("following up on send company's
intern posting"), which reads as a verb-form clash whenever the stored
Promise text starts with a commitment verb (`capture.sv.jac` stores promises
that way on purpose — see its `XPromise.text` sem, e.g. "send the ROI
deck")."""
glob PROMISE_VERBS: list[str] = ["send", "intro", "introduce", "share", "forward", "connect"];
glob PROMISE_ARTICLE_PREFIXES: list[str] = [
    "the ", "a ", "an ", "your ", "my ", "our ", "his ", "her ", "their ", "its "
];

"""SOH-212 (judge3 pass): plural-vs-singular deliverable check for the
"sending it/them over now" clause. Keep it simple: the noun phrase's last
word ending in 's' means plural ("the intro notes" -> them), except a short
list of nouns that end in 's' but are singular ("news")."""
glob KNOWN_SINGULAR_S_WORDS: list[str] = ["news"];

"""SOH-212 (judge3 pass): a related Fact is only safe to splice straight
after "with" when its own text reads as a lowercase noun phrase (starts with
one of these) — otherwise "Hope things are going well with <fact>." can read
as a broken sentence (the fact text can start mid-clause, e.g. "Works in ML
at Google...")."""
glob FACT_CONTEXT_PREFIXES: list[str] = ["the ", "your ", "her ", "his ", "their "];

"""Strip one trailing run of '.'/'!'/'?'/whitespace - never anything in the
middle - so composing this text into a new sentence never produces a
doubled ".."."""
def _strip_trailing_stop(text: str) -> str {
    t = (text or "").strip();
    while len(t) > 0 and t[-1] in ".!? \t\r\n" {
        t = t[:-1];
    }
    return t;
}

def _needs_article(rest: str) -> bool {
    low = rest.lower();
    for pfx in PROMISE_ARTICLE_PREFIXES {
        if low.startswith(pfx) {
            return False;
        }
    }
    return True;
}

"""The caller's first name only ("Sarah Lin" -> "Sarah") — a full name in a
greeting reads as a form letter. Whitespace-only/empty names pass through
unchanged."""
def first_name(name: str) -> str {
    n = (name or "").strip();
    if not n {
        return n;
    }
    return n.split()[0];
}

"""True when the noun phrase's head (last) word looks plural: ends in 's'
and is not one of the short known-singular exceptions."""
def _looks_plural(rest: str) -> bool {
    words = rest.split();
    if not words {
        return False;
    }
    last = words[-1].lower().strip(".,!?;:\"'");
    if last in KNOWN_SINGULAR_S_WORDS {
        return False;
    }
    return last.endswith("s");
}

"""True only when `fact_text` opens with a lowercase noun-phrase pattern we
trust to read naturally after "Hope things are going well with " — never a
capitalized clause fragment like "Works in ML at Google...", which is what
produced the judge3 splice bug."""
def _fact_is_spliceable(fact_text: str) -> bool {
    low = fact_text.lower();
    for pfx in FACT_CONTEXT_PREFIXES {
        if low.startswith(pfx) {
            return True;
        }
    }
    return False;
}

"""SOH-232 (audit I-4): a stored Promise span like "send Maya our deck" or
"intro Dev to Priya" carries the RECIPIENT's own name (or a pronoun standing
in for them) inside its object, because `capture.sv.jac` stores the span
verbatim from the conversation. Spliced into a message already addressed to
that same person ("Hi Maya, ... the Maya our deck ...") it reads as a
name-splice bug. Strips, at most once, the first token that is either the
recipient's own first name (case-insensitive) or a third-person object
pronoun standing in for them ("her"/"him"/"them") -- never a name read off
anyone else's graph, just the one name this function is explicitly given.

Once that token is gone, a self-referential possessive determiner ("my" /
"our" / "your") that is now the leading word no longer has a clear referent
(it was disambiguated by standing next to the recipient's name/pronoun) and
reads oddly addressed back to the same person -- normalized to "the"
("Maya our deck" -> "our deck" -> "the deck"). A determiner that already
reads fine as-is ("the"/"a"/"an"/"his"/"her"/"their"/"its") is left alone
("her the intro deck" -> "the intro deck", untouched)."""
glob RECIPIENT_OBJECT_PRONOUNS: list[str] = ["her", "him", "them"];
glob RECIPIENT_AMBIGUOUS_DETERMINERS: list[str] = ["my", "our", "your"];

def _strip_recipient_tokens(words: list[str], recipient_name: str) -> list[str] {
    rn = first_name(recipient_name).lower().strip();
    out: list[str] = [];
    removed = False;
    for w in words {
        bare = w.lower().strip(".,!?;:\"'");
        if not removed and ((rn and bare == rn) or bare in RECIPIENT_OBJECT_PRONOUNS) {
            removed = True;
            continue;
        }
        out.append(w);
    }
    if removed and out and out[0].lower() in RECIPIENT_AMBIGUOUS_DETERMINERS {
        out[0] = "the";
    }
    return out;
}

"""Render a promise's concrete-deliverable text as a noun phrase instead of
a raw verb-first clause. When the text starts with one of a short list of
common commitment verbs, everything after the verb reads naturally as "the
X" ("send company's intern posting" -> "the company's intern posting I said
I'd send"; "send the ROI deck" -> already has its own article, so it is not
doubled). The closing clause is "sending it over now." for a singular
deliverable and "sending them over now." when the noun phrase's head word
looks plural (SOH-212 judge3). Anything else (no recognized verb, or nothing
after it) has no clean noun phrase to extract, so the whole text is quoted
plainly instead.

SOH-232 (audit I-4): `recipient_name` (the person the promise is TO, i.e. the
message's own greeting name) is stripped out of the object first via
`_strip_recipient_tokens` -- "send Maya our deck" -> "About the deck I said
I'd send: sending it over now."; "send her the intro deck" -> "About the
intro deck I said I'd send: sending it over now.". `intro`/`introduce` gets
its own phrasing for the "<target> to <third party>" shape ("intro Dev to
Priya", recipient Dev): once the recipient token is gone all that is left is
the trailing "to <third party>" clause, which has no deliverable noun to
call "the X I said I'd intro" (nobody says "I said I'd intro"), so it is
rendered "the intro to Priya I said I'd make" instead -- deterministic, and
the third party's name is correctly kept (they are not who this message is
addressed to)."""
def promise_noun_phrase(text: str, recipient_name: str = "") -> str {
    t = _strip_trailing_stop(text);
    words = t.split();
    if len(words) > 1 {
        verb = words[0].lower();
        if verb in PROMISE_VERBS {
            rest_words = _strip_recipient_tokens(words[1:], recipient_name);
            if not rest_words {
                rest_words = words[1:];
            }
            rest = " ".join(rest_words).strip();
            if (verb == "intro" or verb == "introduce") and rest.lower().startswith("to ") {
                phrase = "the intro " + rest;
                closing = "sending them over now." if _looks_plural(rest) else "sending it over now.";
                return f"About {phrase} I said I'd make: {closing}";
            }
            if _needs_article(rest) {
                rest = "the " + rest;
            }
            closing = "sending them over now." if _looks_plural(rest) else "sending it over now.";
            return f"About {rest} I said I'd {verb}: {closing}";
        }
    }
    return f"About what I said I'd do: {t}.";
}

"""SOH-232: `scoring.polish_reason`'s author->your substitutions, applied
here WITHOUT its capitalize-first-letter/forced-terminal-period side
effects (those are wrong for text about to be spliced mid-sentence, not
written as its own standalone sentence)."""
def _author_to_your(text: str) -> str {
    t = text or "";
    t = re.sub(r"(?i)\bauthor's\b", "your", t);
    t = re.sub(r"(?i)\bthe author\b", "you", t);
    t = re.sub(r"(?i)\bauthor\b", "you", t);
    return t;
}

"""SOH-232: a stored Fact/Intent/Promise clause with its subject elided
often opens with a bare commitment/want verb ("Offered to review...",
"Wanted an intro...", "Needed feedback...") - the shape `capture.sv.jac`'s
XIntent/XPromise sems produce when the speaker (or the person themselves)
is the implied subject. Spliced after "what you said about" these read as
a dangling clause ("what you said about Offered to review..."); detected
here so the fallback can phrase them as a full sentence instead ("what you
mentioned: you offered to review...")."""
glob INTENT_LEAD_VERBS: list[str] = [
    "offered", "offers", "offer",
    "wanted", "wants", "want",
    "needed", "needs", "need",
    "asked", "asks", "ask",
    "promised", "promises", "promise",
    "mentioned", "mentions", "mention",
    "hoped", "hopes", "hoping",
    "looking", "looked", "looks",
];

def _starts_with_lead_verb(text: str) -> bool {
    words = (text or "").split();
    if not words {
        return False;
    }
    first = words[0].lower().strip(".,!?;:\"'");
    return first in INTENT_LEAD_VERBS;
}

"""SOH-232: words that commonly OPEN a Fact/Intent clause about a person
(never a name) - safe to lowercase when the clause is spliced mid-sentence.
Anything else that starts with a capital letter is treated as proper-noun
led (a name, a company, a place) and left alone, e.g. "Stripe is hiring
backend engineers" keeps its capital "S" when spliced after "about"."""
glob LOWERABLE_LEAD_WORDS: list[str] = (
    ["the", "a", "an", "your", "her", "his", "their", "its", "our", "my"]
    + ["just", "still", "also", "recently", "currently", "possibly", "probably", "maybe", "now", "already", "not"]
    + ["she", "he", "they", "it", "is", "was", "has", "had", "will", "would", "can", "could"]
    + ["works", "worked", "working", "moved", "moving", "leads", "leading", "lives", "living", "runs", "running", "met"]
    + INTENT_LEAD_VERBS
);

"""Lowercase `text`'s first letter, unless its first word reads as a proper
noun (not in `LOWERABLE_LEAD_WORDS`) - see module docstring above."""
def _lowercase_unless_proper_noun(text: str) -> str {
    if not text {
        return text;
    }
    words = text.split();
    if not words {
        return text;
    }
    first_bare = words[0].strip(".,!?;:\"'").lower();
    if first_bare in LOWERABLE_LEAD_WORDS {
        return text[0].lower() + text[1:];
    }
    return text;
}

"""Deterministic fallback used when there is no evidence at all, or the
batched `by llm` call fails / returns nothing usable. Picks the newest open
Promise first, else the newest Fact/Intent, else a generic opener — exactly
the three branches in contracts/walkers.md."""
def fallback_draft(p: Person, evidence: list[EvidenceItem]) -> dict[str, any] {
    promise_item: EvidenceItem | None = None;
    fact_item: EvidenceItem | None = None;
    fact_or_intent_item: EvidenceItem | None = None;

    for it in evidence {
        if it.kind == "promise" and promise_item is None {
            promise_item = it;
        }
        if (it.kind == "fact" or it.kind == "intent") and fact_or_intent_item is None {
            fact_or_intent_item = it;
        }
        if it.kind == "fact" and fact_item is None {
            fact_item = it;
        }
    }

    greeting_name = first_name(p.name);

    if promise_item is not None {
        pi = promise_item as EvidenceItem;
        used: list[EvidenceItem] = [pi];
        promise_sentence = promise_noun_phrase(pi.span, p.name);
        # SOH-212: the context clause is optional and only added for a SHORT
        # fact (< 80 chars) whose own text is a trusted lowercase noun phrase
        # (judge3: NEVER splice a fact after "with" otherwise — it can read
        # as a broken sentence, e.g. "with Works in ML at Google..."); its
        # own trailing stop is stripped first so the sentence we append
        # never produces "..".
        tail = "";
        if fact_item is not None {
            fi = fact_item as EvidenceItem;
            fact_text = _strip_trailing_stop(fi.span);
            if fact_text and len(fact_text) < 80 and _fact_is_spliceable(fact_text) {
                tail = f" Hope things are going well with {fact_text}.";
                used.append(fi);
            } else {
                tail = " Hope things are going well.";
            }
        } elif p.org {
            tail = f" Hope things are going well with {p.org}.";
        }
        draft = f"Hi {greeting_name}, {promise_sentence}{tail}";
        return {"draft": draft, "based_on": [item_to_dict(i) for i in used]};
    }

    if fact_or_intent_item is not None {
        fi2 = fact_or_intent_item as EvidenceItem;
        # SOH-232: apply the author->your replacement first, then strip a
        # trailing period, before deciding how to splice the clause.
        clean = _strip_trailing_stop(_author_to_your(fi2.span));
        if clean and _starts_with_lead_verb(clean) {
            clause = "you " + clean[0].lower() + clean[1:];
            draft = f"Hi {greeting_name}, what you mentioned: {clause}. How is that going?";
        } else {
            polished = _lowercase_unless_proper_noun(clean);
            draft = f"Hi {greeting_name}, I was thinking about what you said about {polished}. How is that going?";
        }
        return {"draft": draft, "based_on": [item_to_dict(fi2)]};
    }

    draft = f"Hi {greeting_name}, it was good meeting you. Would love to stay in touch.";
    return {"draft": draft, "based_on": []};
}

# ---------------------------------------------------------------- walker

walker:priv DraftFollowUp {
    """Draft a follow-up message to one of the caller's own people. See
    contracts/walkers.md for the exact report shape. Reports one entry, or
    `{ error: "not_found" }` when `person_id` isn't the caller's."""
    has person_id: str;
    has intent: str = "";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report {"error": "not_found"};
            disengage;
        }
        me = existing[0];

        matches = [p for p in [me ->:Knows:->] if jid(p) == self.person_id];
        if not matches {
            report {"error": "not_found"};
            disengage;
        }
        person = matches[0];

        now = datetime.now();
        evidence = gather_follow_up_evidence(person, now);

        if not evidence {
            fb = fallback_draft(person, evidence);
            report {"person_id": jid(person), "draft": fb["draft"], "based_on": fb["based_on"], "fallback": True};
            disengage;
        }

        try {
            summary = person_summary_text(person);
            evidence_text = build_evidence_text(evidence);
            result = draft_follow_up(summary, evidence_text, self.intent);
            based_on = map_evidence_indices(evidence, result.evidence_indices);
            if not result.draft or not based_on {
                raise Exception("empty draft or no evidence cited");
            }
            report {"person_id": jid(person), "draft": result.draft, "based_on": based_on, "fallback": False};
        } except Exception {
            fb = fallback_draft(person, evidence);
            report {"person_id": jid(person), "draft": fb["draft"], "based_on": fb["based_on"], "fallback": True};
        }
    }
}
