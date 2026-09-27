"""Mocks for the search box (SOH-222 A5) and "Ask your graph" (Recall).
OWNER: Person B.

Exact contract shapes (contracts/walkers.md):
  `Search(query, limit=25, kinds=[])` ->
    `{ query, results: [{kind,id,text,person_id,person_name,span,score,observed_at}], total }`
  `Recall(question, max_items=40)` ->
    `{ answer, citations: [{id,kind,observed_at,span,person}], insufficient, fallback }`

`search.sv.jac` (SOH-216) lives on a parallel branch, not yet on main — this
mock is the only way to render the search box until it merges. `recall.sv.jac`
(SOH-189) IS live on main; its mock is kept anyway so `?mock=1` demos don't
spend the Gemini budget and stay reachable offline, same as every other
walker in `components/api.cl.jac`.

Deterministic substring/token scoring over a small fixed dataset — same shape
as the real walker's scoring, simplified (no name-prefix vs. body-text
distinction), so score ordering and grouping look plausible in a demo.

The people/facts/promises below are the SAME pseudonymous fixtures
`components/mocks/person.cl.jac`/`goalrank.cl.jac` already use (Maya Chen,
Dev Okafor, Lena Park, Sam Ruiz) - so clicking a result's person link, or a
Recall citation chip, opens a person sheet that actually has data, instead of
a `not_found` from two mocks disagreeing on ids.
"""

glob _ROWS: list[dict[str, any]] = [
    {"kind": "person", "id": "mock-person-maya", "text": "Maya Chen",
     "person_id": "mock-person-maya", "person_name": "Maya Chen", "span": "", "observed_at": ""},
    {"kind": "fact", "id": "mock-fact-maya-2", "text": "Leads carbon removal purchasing at Stripe Climate",
     "person_id": "mock-person-maya", "person_name": "Maya Chen",
     "span": "Carbon removal lead, Stripe Climate", "observed_at": "2026-09-23T18:40:00Z"},
    {"kind": "fact", "id": "mock-fact-maya-1", "text": "Worked together at Stripe",
     "person_id": "mock-person-maya", "person_name": "Maya Chen",
     "span": "Maya Chen — worked together at Stripe.", "observed_at": "2026-07-12T16:10:00Z"},
    {"kind": "intent", "id": "mock-intent-maya", "text": "Intros to climate hardware funds",
     "person_id": "mock-person-maya", "person_name": "Maya Chen",
     "span": "Maya said she'd happily intro founders to the climate hardware funds she buys alongside.",
     "observed_at": "2026-09-20T12:00:00Z"},
    {"kind": "intent", "id": "mock-intent-maya-old", "text": "A summer intern for MRV analysis",
     "person_id": "mock-person-maya", "person_name": "Maya Chen",
     "span": "She was hunting for a summer intern to help with MRV.", "observed_at": "2026-08-01T00:00:00Z"},
    {"kind": "promise", "id": "mock-promise-maya", "text": "Send Maya the Kiln Labs one-pager",
     "person_id": "mock-person-maya", "person_name": "Maya Chen",
     "span": "I said I'd send Maya the one-pager this weekend.", "observed_at": "2026-09-21T00:00:00Z"},
    {"kind": "note", "id": "mock-note-maya", "text": "Coffee with Maya Chen after the panel.",
     "person_id": "mock-person-maya", "person_name": "Maya Chen", "span": "", "observed_at": "2026-09-23T18:40:00Z"},

    {"kind": "person", "id": "mock-person-dev", "text": "Dev Okafor",
     "person_id": "mock-person-dev", "person_name": "Dev Okafor", "span": "", "observed_at": ""},
    {"kind": "fact", "id": "mock-fact-dev", "text": "Works at Great Lakes Angels",
     "person_id": "mock-person-dev", "person_name": "Dev Okafor",
     "span": "Works at Great Lakes Angels.", "observed_at": "2026-09-12T19:00:00Z"},
    {"kind": "promise", "id": "mock-promise-dev", "text": "Intro Dev to the Rivian battery team",
     "person_id": "mock-person-dev", "person_name": "Dev Okafor",
     "span": "Told Dev I'd intro him to the Rivian battery folks.", "observed_at": "2026-09-16T00:00:00Z"},
    {"kind": "note", "id": "mock-note-dev", "text": "Coffee with Dev Okafor after the panel.",
     "person_id": "mock-person-dev", "person_name": "Dev Okafor", "span": "", "observed_at": "2026-09-12T19:00:00Z"},

    {"kind": "person", "id": "mock-person-lena", "text": "Lena Park",
     "person_id": "mock-person-lena", "person_name": "Lena Park", "span": "", "observed_at": ""},
    {"kind": "fact", "id": "mock-fact-lena", "text": "Works at Campus Energy Club",
     "person_id": "mock-person-lena", "person_name": "Lena Park",
     "span": "Works at Campus Energy Club.", "observed_at": "2026-09-12T19:00:00Z"},
    {"kind": "promise", "id": "mock-promise-lena", "text": "Speak at the club's October meetup",
     "person_id": "mock-person-lena", "person_name": "Lena Park",
     "span": "Agreed to speak at Lena's October meetup.", "observed_at": "2026-09-17T00:00:00Z"},

    {"kind": "person", "id": "mock-person-sam", "text": "Sam Ruiz",
     "person_id": "mock-person-sam", "person_name": "Sam Ruiz", "span": "", "observed_at": ""},
    {"kind": "fact", "id": "mock-fact-sam", "text": "Works at Ruiz Castings",
     "person_id": "mock-person-sam", "person_name": "Sam Ruiz",
     "span": "Works at Ruiz Castings.", "observed_at": "2026-09-12T19:00:00Z"}
];

glob _STOPWORDS: list[str] = [
    "a", "an", "and", "are", "as", "at", "for", "from", "has", "have", "in",
    "is", "it", "of", "on", "or", "that", "the", "to", "was", "what", "who",
    "how", "when", "where", "which", "why"
];

glob _ALNUM_CHARS: str = "abcdefghijklmnopqrstuvwxyz0123456789";

"""`str.isalnum()` has no client-runtime polyfill (only `bytes.isalnum` does;
verified by reading `.jac/client/compiled/**` - `_jac.poly.call` raises
AttributeError for a plain string) - membership on a fixed charset instead."""
def _is_alnum_char(ch: str) -> bool {
    return ch in _ALNUM_CHARS;
}

def _tokenize(q: str) -> list[str] {
    out: list[str] = [];
    cur = "";
    for ch in (q.lower() + " ") {
        if _is_alnum_char(ch) {
            cur = cur + ch;
        } else {
            if len(cur) >= 2 and cur not in _STOPWORDS {
                out.append(cur);
            }
            cur = "";
        }
    }
    return out;
}

def _row_score(tokens: list[str], query_norm: str, row: dict[str, any]) -> int {
    text_l: str = (row["text"] as str).lower();
    name_l: str = (row["person_name"] as str).lower();
    score = 0;
    for tok in tokens {
        if tok in name_l {
            score += 3;
        }
        score += text_l.count(tok);
    }
    if query_norm {
        combined = name_l + " " + text_l;
        if query_norm in combined {
            score = score * 2;
        }
    }
    return score;
}

def _kind_rank(kind: str) -> int {
    order: dict[str, int] = {"person": 0, "fact": 1, "intent": 2, "promise": 3, "note": 4};
    if kind in order {
        return order[kind];
    }
    return 5;
}

"""Single scalar key: score descending dominates, kind order breaks ties -
avoids relying on tuple-key sort support in client `.jac`."""
def _sort_key(row: dict[str, any]) -> int {
    score: int = row["score"] as int;
    return (0 - score) * 10 + _kind_rank(row["kind"] as str);
}

def:pub mock_search(query: str, limit: int = 25) -> list[dict[str, any]] {
    tokens = _tokenize(query);
    query_norm = query.strip().lower();
    scored: list[dict[str, any]] = [];
    for row in _ROWS {
        sc = _row_score(tokens, query_norm, row);
        if sc <= 0 {
            continue;
        }
        r2: dict[str, any] = {**row};
        r2["score"] = sc;
        scored.append(r2);
    }
    ranked = sorted(scored, key=_sort_key);
    total: int = len(ranked);
    eff_limit: int = limit if limit > 0 else 0;
    return [{"query": query, "results": ranked[:eff_limit], "total": total}];
}

def:pub mock_recall(question: str) -> list[dict[str, any]] {
    q_l: str = question.lower();
    if ("maya" in q_l) or ("stripe" in q_l) or ("climate" in q_l) {
        return [{
            "answer": "Maya Chen leads carbon removal purchasing at Stripe Climate and can intro you to climate hardware funds; you still owe her the Kiln Labs one-pager.",
            "citations": [
                {"id": "mock-fact-maya-2", "kind": "fact", "observed_at": "2026-09-23T18:40:00Z",
                 "span": "Carbon removal lead, Stripe Climate", "person": "Maya Chen"},
                {"id": "mock-intent-maya", "kind": "intent", "observed_at": "2026-09-20T12:00:00Z",
                 "span": "Maya said she'd happily intro founders to the climate hardware funds she buys alongside.",
                 "person": "Maya Chen"},
                {"id": "mock-promise-maya", "kind": "promise", "observed_at": "2026-09-21T00:00:00Z",
                 "span": "I said I'd send Maya the one-pager this weekend.", "person": "Maya Chen"}
            ],
            "insufficient": False, "fallback": True
        }];
    }
    if ("dev" in q_l) or ("rivian" in q_l) or ("great lakes" in q_l) {
        return [{
            "answer": "Dev Okafor is an associate at Great Lakes Angels; you still owe him an intro to the Rivian battery team.",
            "citations": [
                {"id": "mock-fact-dev", "kind": "fact", "observed_at": "2026-09-12T19:00:00Z",
                 "span": "Works at Great Lakes Angels.", "person": "Dev Okafor"},
                {"id": "mock-promise-dev", "kind": "promise", "observed_at": "2026-09-16T00:00:00Z",
                 "span": "Told Dev I'd intro him to the Rivian battery folks.", "person": "Dev Okafor"}
            ],
            "insufficient": False, "fallback": True
        }];
    }
    return [{
        "answer": "Insufficient evidence in your notes.",
        "citations": [], "insufficient": True, "fallback": True
    }];
}
