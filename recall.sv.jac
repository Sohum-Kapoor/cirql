"""Recall — ask your own graph a question, answered only from your own notes,
with citations (SOH-189).

OWNER: Person A. See contracts/walkers.md `Recall(question, max_items)` for
the exact report shape. Rules from AGENTS.md this file must obey:
  - "Insufficient evidence" is a valid answer; never invent. The deterministic
    pre-filter decides insufficiency on its own (zero token overlap with the
    question) — the `by llm` call is never even reached in that case, so the
    quota is never spent on a question we already know we can't answer.
  - Every citation carries a `span`/`observed_at` traceable back to a real
    Note/Fact/Intent/Promise id — never invented.
  - `by llm` returns a plain `obj` (`RecallAnswer`), never a node.
  - Nothing sends; this only ever answers a question.
  - ONE `by llm` call per invocation, wrapped in `try/except`; the
    deterministic `fallback_recall` always produces a usable answer.

`_parse_naive_utc` is imported from `goals.sv.jac` rather than
re-implemented (established pattern in this codebase — `cards.sv.jac` imports
from `onboard.sv.jac`, `exchange.sv.jac` imports from `scoring.sv.jac`).
"""

import from datetime { datetime }
import from schema {
    Note, Fact, Intent, Promise,
    FactAbout, IntentAbout, PromiseTo, Mentions, AssertsIntent, AssertsPromise
}
import from llm { llm }
import from goals { _parse_naive_utc }

# ---------------------------------------------------------------- LLM shape

obj RecallAnswer {
    has answer: str;
    has citation_indices: list[int];
    has insufficient: bool;
}
sem RecallAnswer.answer = "Answer ONLY from the numbered evidence in two sentences or fewer, naming the people it comes from; if the evidence does not answer the question, say exactly 'Insufficient evidence in your notes.'";
sem RecallAnswer.citation_indices = "Numbers of the evidence items the answer relies on; empty when insufficient.";
sem RecallAnswer.insufficient = "true when the evidence does not answer the question.";

def recall_answer(question: str, evidence_text: str) -> RecallAnswer by llm(temperature=0.1);
sem recall_answer = "Answer the question using only the numbered evidence drawn from the caller's own notes.";
sem recall_answer.question = "The user's question about their own network.";
sem recall_answer.evidence_text = "Numbered evidence items — notes, facts, intents, and promises — each naming the person it's about.";

# ---------------------------------------------------------------- plain data

obj RecallItem {
    has id: str;
    has kind: str;        # note | fact | intent | promise
    has observed_at: str;
    has span: str;
    has person: str;      # the about-person's name; "" when none
}

def item_to_citation(it: RecallItem) -> dict[str, str] {
    return {"id": it.id, "kind": it.kind, "observed_at": it.observed_at, "span": it.span, "person": it.person};
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

def _recall_sort_key(it: RecallItem) -> datetime {
    return _sortable_dt(it.observed_at);
}

"""All of the caller's own Notes (text capped at 300 chars), Facts, Intents,
and Promises — each paired with its about-person's name where one applies —
merged newest-first by `observed_at`/`captured_at`/`due`-note and bounded to
`max_items`. This is the "bounded traversal on the caller's root" the
product spec calls for; it runs BEFORE the token pre-filter."""
def gather_recall_items(max_items: int) -> list[RecallItem] {
    items: list[RecallItem] = [];

    for n in [root --> [?:Note]] {
        person_name = "";
        mentioned = [n ->:Mentions:->];
        if mentioned {
            person_name = mentioned[0].name;
        }
        items.append(RecallItem(id=jid(n), kind="note", observed_at=n.captured_at, span=n.text[:300], person=person_name));
    }

    for f in [root --> [?:Fact]] {
        about = [f ->:FactAbout:->];
        person_name = about[0].name if about else "";
        items.append(RecallItem(id=jid(f), kind="fact", observed_at=f.observed_at, span=f.text, person=person_name));
    }

    for i in [root --> [?:Intent]] {
        about = [i ->:IntentAbout:->];
        person_name = about[0].name if about else "";
        observed_at = "";
        notes_for_intent = [i <-:AssertsIntent:<-];
        if notes_for_intent {
            observed_at = notes_for_intent[0].captured_at;
        }
        items.append(RecallItem(id=jid(i), kind="intent", observed_at=observed_at, span=i.text, person=person_name));
    }

    for pr in [root --> [?:Promise]] {
        to_list = [pr ->:PromiseTo:->];
        person_name = to_list[0].name if to_list else "";
        observed_at = "";
        notes_for_promise = [pr <-:AssertsPromise:<-];
        if notes_for_promise {
            observed_at = notes_for_promise[0].captured_at;
        }
        items.append(RecallItem(id=jid(pr), kind="promise", observed_at=observed_at, span=pr.text, person=person_name));
    }

    return cap_and_sort_items(items, max_items);
}

"""Pure sort+cap step, pulled out of `gather_recall_items` so a test can
exercise the `max_items` bound directly on a hand-built list — no graph, no
shared persisted root involved. Newest first by `observed_at`; a non-positive
`max_items` means uncapped."""
def cap_and_sort_items(items: list[RecallItem], max_items: int) -> list[RecallItem] {
    items_sorted = sorted(items, key=_recall_sort_key, reverse=True);
    if max_items > 0 and len(items_sorted) > max_items {
        items_sorted = items_sorted[:max_items];
    }
    return items_sorted;
}

glob STOPWORDS: list[str] = [
    "with", "that", "this", "have", "about", "what", "when", "where", "which",
    "there", "their", "would", "could", "should", "from", "into", "your",
    "been", "does", "doing", "them", "then", "than", "these", "those",
    "were", "will", "just", "some", "such", "each", "more", "most", "only",
    "very", "here", "over", "also", "much", "many", "does", "have", "tell",
    "please"
];

"""Lowercase word tokens, length >= 4, non-stopword. No regex module used
elsewhere in this codebase — a manual char scan keeps this dependency-free."""
def _tokenize(text: str) -> list[str] {
    lowered = text.lower();
    raw: list[str] = [];
    current = "";
    for ch in lowered {
        if ch.isalnum() {
            current = current + ch;
        } else {
            if current {
                raw.append(current);
            }
            current = "";
        }
    }
    if current {
        raw.append(current);
    }
    tokens: list[str] = [];
    for t in raw {
        if len(t) >= 4 and t not in STOPWORDS {
            tokens.append(t);
        }
    }
    return tokens;
}

"""The strict token-overlap pre-filter itself — exposed separately from
`select_recall_evidence` so a test can assert on it directly."""
def prefilter_matches(pool: list[RecallItem], question: str) -> list[RecallItem] {
    q_tokens = _tokenize(question);
    matched: list[RecallItem] = [];
    for it in pool {
        it_tokens = _tokenize(it.span);
        shared = False;
        for t in it_tokens {
            if t in q_tokens {
                shared = True;
                break;
            }
        }
        if shared {
            matched.append(it);
        }
    }
    return matched;
}

"""The evidence set actually used downstream: the strict token-overlap
matches when there are at least 3 of them; the newest 12 items in the pool
(regardless of topic) when 1 or 2 matched — too few to answer from
confidently on their own, but not nothing; empty when literally nothing
matched the question at all. That empty case is the walker's signal to
short-circuit straight to the deterministic "insufficient" answer without
spending the one `by llm` call — see `fallback_recall`."""
def select_recall_evidence(pool: list[RecallItem], question: str) -> list[RecallItem] {
    matched = prefilter_matches(pool, question);
    if not matched {
        return [];
    }
    if len(matched) < 3 {
        if len(pool) > 12 {
            return pool[:12];
        }
        return pool;
    }
    return matched;
}

"""One numbered line per evidence item for the single `by llm` call."""
def build_recall_evidence_text(items: list[RecallItem]) -> str {
    lines: list[str] = [];
    idx = 0;
    for it in items {
        who = it.person if it.person else "unknown";
        lines.append(f"[{idx}] ({it.kind}, about {who}, {it.observed_at}): {it.span}");
        idx += 1;
    }
    return "\n".join(lines);
}

"""Map the LLM's `citation_indices` back to full citation dicts; out-of-range
indices are dropped, duplicates deduped (first wins) — same idiom as
`goals.sv.jac`'s `materialize` / `scoring.sv.jac`'s `post_process`."""
def map_recall_indices(selected: list[RecallItem], indices: list[int]) -> list[dict[str, str]] {
    out: list[dict[str, str]] = [];
    seen: list[int] = [];
    for idx in indices {
        if idx < 0 or idx >= len(selected) {
            continue;
        }
        if idx in seen {
            continue;
        }
        seen.append(idx);
        out.append(item_to_citation(selected[idx]));
    }
    return out;
}

"""Deterministic fallback used when there is no selected evidence at all
(nothing matched the pre-filter -> insufficient), or the `by llm` call
fails. Otherwise: "Your notes mention: " + the top 3 selected items."""
def fallback_recall(selected: list[RecallItem]) -> dict[str, any] {
    if not selected {
        return {"answer": "Insufficient evidence in your notes.", "citations": [], "insufficient": True, "fallback": True};
    }
    top = selected[:3];
    parts: list[str] = [];
    for it in top {
        parts.append(f"{it.person}: {it.span} ({it.observed_at})");
    }
    answer = "Your notes mention: " + "; ".join(parts);
    citations = [item_to_citation(it) for it in top];
    return {"answer": answer, "citations": citations, "insufficient": False, "fallback": True};
}

# ---------------------------------------------------------------- walker

walker:priv Recall {
    """Ask a question of the caller's own graph. See contracts/walkers.md for
    the exact report shape. Reports exactly one dict."""
    has question: str;
    has max_items: int = 40;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        # SOH-211: max_items sizes the one model prompt -> bounded.
        pool = gather_recall_items(min(max(self.max_items, 0), 100));
        selected = select_recall_evidence(pool, self.question);

        if not selected {
            report fallback_recall(selected);
            disengage;
        }

        try {
            evidence_text = build_recall_evidence_text(selected);
            result = recall_answer(self.question, evidence_text);
            citations = map_recall_indices(selected, result.citation_indices);
            insufficient = result.insufficient;
            answer = result.answer;
            if not answer or (not citations and not insufficient) {
                insufficient = True;
                answer = "Insufficient evidence in your notes.";
                citations = [];
            }
            report {"answer": answer, "citations": citations, "insufficient": insufficient, "fallback": False};
        } except Exception {
            report fallback_recall(selected);
        }
    }
}
