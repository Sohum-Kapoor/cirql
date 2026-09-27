"""search.sv.jac — Search (SOH-216).

OWNER: Person A. See contracts/walkers.md for the exact report shape and
AGENTS.md for the working rules this file must obey:
  - `:priv`, own-root only, no `by llm` anywhere in this module.
  - Traversal starts only from the caller's own `Me` (`[me ->:Knows:->]` and
    what hangs off each of those `Person`s) — never `root.shared`, never a
    `jobj(id)` lookup of a foreign id. A person under a different account's
    graph is simply never reached; there is no not_found branch to leak.
  - Archived people, and every Fact/Intent/Promise/Note reached only through
    them, are skipped entirely (never iterated, not just filtered after).
  - Deterministic: tokenize `query` (lowercase, alnum runs of length >= 2,
    stopwords dropped, manual char-scan idiom — same as `scoring.sv.jac`'s
    `fallback_tokens`, no `re` dependency). Per result row:
      score = sum over tokens of
        (3 if the token is a PREFIX of one of the person's name words)
      + (2 if the token appears anywhere in org/title/location/email)
      + (1 * how many times the token occurs in the row's own text)
    then the WHOLE (stripped, lowercased) query, if it appears as a
    substring anywhere across name/org/title/location/email/text, DOUBLES
    the row's score. A row with score 0 is dropped.
  - Sort: score descending; ties broken with `person` rows first, then
    newest first (`_parse_naive_utc`, imported from `goals.sv.jac` rather
    than re-implemented — same reused-helper pattern `person.sv.jac` and
    `export.sv.jac` already follow). A `person` row has no timestamp of its
    own, but the kind tie-break already puts it ahead of same-score
    fact/intent/promise/note rows regardless.
  - `kinds` (`"person"|"fact"|"intent"|"promise"|"note"`) filters which row
    kinds are considered at all; an empty list (the default) means every
    kind. `limit` is clamped to `[0, 100]` (default 25); `total` counts every
    scored row BEFORE that clamp is applied.
  - A description-only person (SOH-215's `Person.name` holding a description
    like "tall girl from the climbing gym" instead of a real name) is found
    the same way any other person is: their `name` IS the searchable text,
    so its own words score the normal 3-points-per-matching-token name path.

`person_id`/`person_name` on every row (including a `person` row, where they
name the row's own person) mirror the shape `person.sv.jac`'s
`PersonDetail` and `export.sv.jac`'s `ExportGraph` already use for
provenance: a `fact`/`intent`/`promise` row's `span` and a `note` row's
`span` are read off the same `Asserts*`/`Mentions` edge idiom those two
modules use (`[x <-:Asserts*:<-]` for the asserting Note, `[edge note
->:Asserts*:-> x]` for its `span`).
"""

import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise,
    Knows, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo
}
import from goals { _parse_naive_utc }

# ---------------------------------------------------------------- tokenizing

glob SEARCH_STOPWORDS: list[str] = [
    "a", "an", "and", "are", "as", "at", "be", "been", "being", "by",
    "can", "could", "did", "do", "does", "for", "from", "has", "have", "he",
    "her", "hers", "him", "his", "i", "if", "in", "is", "it", "its",
    "me", "my", "not", "of", "on", "or", "our", "she", "should", "so",
    "than", "that", "the", "their", "them", "they", "this", "those", "to",
    "too", "very", "was", "we", "were", "what", "which", "who", "whom",
    "will", "with", "would", "you", "your"
];

"""Lowercased alnum runs of length >= 2 that are not stopwords — manual
char-scan tokenizer, same idiom as `scoring.sv.jac`'s `fallback_tokens`
(no `re` dependency, no double-counting concerns)."""
def _tokenize(query: str) -> list[str] {
    out: list[str] = [];
    cur = "";
    for ch in (query.lower() + " ") {
        if ch.isalnum() {
            cur = cur + ch;
        } else {
            if len(cur) >= 2 and cur not in SEARCH_STOPWORDS {
                out.append(cur);
            }
            cur = "";
        }
    }
    return out;
}

# ---------------------------------------------------------------- scoring

"""score = sum over `tokens` of (3 name-word-prefix, 2 org/title/location/
email substring, 1 per occurrence in `text`); doubled once, at the end, if
the whole stripped-lowercased `query_norm` appears as a substring anywhere
across name/org/title/location/email/text."""
def _row_score(
    tokens: list[str], query_norm: str,
    name: str, org: str, title: str, location: str, email: str, text: str
) -> int {
    name_l = name.lower();
    org_l = org.lower();
    title_l = title.lower();
    location_l = location.lower();
    email_l = email.lower();
    text_l = text.lower();
    name_words = name_l.split();

    score = 0;
    for tok in tokens {
        matched_name = False;
        for w in name_words {
            if w.startswith(tok) {
                matched_name = True;
                break;
            }
        }
        if matched_name {
            score += 3;
        }
        if (tok in org_l) or (tok in title_l) or (tok in location_l) or (tok in email_l) {
            score += 2;
        }
        score += text_l.count(tok);
    }

    if query_norm {
        combined = name_l + " " + org_l + " " + title_l + " " + location_l + " " + email_l + " " + text_l;
        if query_norm in combined {
            score = score * 2;
        }
    }

    return score;
}

# ---------------------------------------------------------------- row helper

def _row(
    kind: str, row_id: str, text: str, person_id: str, person_name: str,
    span: str, score: int, observed_at: str
) -> dict[str, any] {
    return {
        "kind": kind, "id": row_id, "text": text,
        "person_id": person_id, "person_name": person_name,
        "span": span, "score": score, "observed_at": observed_at
    };
}

# ---------------------------------------------------------------- sorting

"""Newest first; unparsable/empty timestamps sort oldest (matches the
`_parse_naive_utc is None -> datetime.min` idiom `person.sv.jac`'s
`_fact_observed_dt`/`_intent_observed_dt` use)."""
def _date_rank(observed_at: str) -> float {
    dt = _parse_naive_utc(observed_at);
    if dt is None {
        dt = datetime.min;
    }
    return -((dt - datetime.min).total_seconds());
}

"""Score descending, `person` rows before any other kind on a tie, newest
first within that — same single-tuple `_sort_key` pattern `goals.sv.jac`
uses for `GoalRank`."""
def _sort_key(row: dict[str, any]) -> tuple[int, int, float] {
    score = row["score"] as int;
    kind = row["kind"] as str;
    observed_at = row["observed_at"] as str;
    kind_rank = 0 if kind == "person" else 1;
    return (-score, kind_rank, _date_rank(observed_at));
}

# ---------------------------------------------------------------- core builder

"""Deterministic, testable directly on a hand-built `me` (see
`search.test.jac`) — same reason `edits.sv.jac`'s `update_person_for` and
`person.sv.jac`'s `person_detail_for` take `me` as an argument rather than
resolving "the" `Me` via `[root --> [?:Me]][0]` inside the helper itself:
that resolution is ambiguous once more than one test has created a `Me`
under the shared, persisted test root. `limit` is clamped to `[0, 100]`
here so both the walker and a direct test call get the same behavior."""
def search_for(me: Me, query: str, limit: int, kinds: list[str]) -> dict[str, any] {
    tokens = _tokenize(query);
    query_norm = query.strip().lower();

    allow_person = (not kinds) or ("person" in kinds);
    allow_fact = (not kinds) or ("fact" in kinds);
    allow_intent = (not kinds) or ("intent" in kinds);
    allow_promise = (not kinds) or ("promise" in kinds);
    allow_note = (not kinds) or ("note" in kinds);

    rows: list[dict[str, any]] = [];

    people: list[Person] = [me ->:Knows:->];
    for p in people {
        if p.archived {
            continue;
        }
        name = p.name;
        org = p.org;
        title = p.title;
        location = p.location;
        email = p.email;
        pid = jid(p);

        if allow_person {
            sc = _row_score(tokens, query_norm, name, org, title, location, email, name);
            if sc > 0 {
                rows.append(_row("person", pid, name, pid, name, "", sc, ""));
            }
        }

        if allow_fact {
            for f in [p <-:FactAbout:<-] {
                sc = _row_score(tokens, query_norm, name, org, title, location, email, f.text);
                if sc <= 0 {
                    continue;
                }
                span = "";
                notes: list[Note] = [f <-:Asserts:<-];
                if notes {
                    note = notes[0];
                    spans = [e.span for e in [edge note ->:Asserts:-> f]];
                    if spans {
                        span = spans[0];
                    }
                }
                rows.append(_row("fact", jid(f), f.text, pid, name, span, sc, f.observed_at));
            }
        }

        if allow_intent {
            for it in [p <-:IntentAbout:<-] {
                sc = _row_score(tokens, query_norm, name, org, title, location, email, it.text);
                if sc <= 0 {
                    continue;
                }
                span = "";
                observed_at = "";
                notes: list[Note] = [it <-:AssertsIntent:<-];
                if notes {
                    note = notes[0];
                    observed_at = note.captured_at;
                    spans = [e.span for e in [edge note ->:AssertsIntent:-> it]];
                    if spans {
                        span = spans[0];
                    }
                }
                rows.append(_row("intent", jid(it), it.text, pid, name, span, sc, observed_at));
            }
        }

        if allow_promise {
            for pr in [p <-:PromiseTo:<-] {
                sc = _row_score(tokens, query_norm, name, org, title, location, email, pr.text);
                if sc <= 0 {
                    continue;
                }
                span = "";
                observed_at = "";
                notes: list[Note] = [pr <-:AssertsPromise:<-];
                if notes {
                    note = notes[0];
                    observed_at = note.captured_at;
                    spans = [e.span for e in [edge note ->:AssertsPromise:-> pr]];
                    if spans {
                        span = spans[0];
                    }
                }
                rows.append(_row("promise", jid(pr), pr.text, pid, name, span, sc, observed_at));
            }
        }

        if allow_note {
            for n in [p <-:Mentions:<-] {
                text = n.text;
                if len(text) > 300 {
                    text = text[:300];
                }
                sc = _row_score(tokens, query_norm, name, org, title, location, email, text);
                if sc <= 0 {
                    continue;
                }
                span = "";
                spans = [e.span for e in [edge n ->:Mentions:-> p]];
                if spans {
                    span = spans[0];
                }
                rows.append(_row("note", jid(n), text, pid, name, span, sc, n.captured_at));
            }
        }
    }

    rows = sorted(rows, key=_sort_key);

    total = len(rows);

    eff_limit = limit;
    if eff_limit < 0 {
        eff_limit = 0;
    } elif eff_limit > 100 {
        eff_limit = 100;
    }

    return {"query": query, "results": rows[:eff_limit], "total": total};
}

# ---------------------------------------------------------------- walker

walker:priv Search {
    """Deterministic search across the caller's own people and every Fact/
    Intent/Promise/Note reached from them. Reports one dict:
    `{ query, results: [...], total }` (see module docstring and
    `contracts/walkers.md` for the exact row shape). No `Me` yet -> empty
    results, `total: 0`."""
    has query: str;
    has limit: int = 25;
    has kinds: list[str] = [];
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"query": self.query, "results": [], "total": 0};
            disengage;
        }
        me = existing_me[0];

        report search_for(me, self.query, self.limit, self.kinds);
    }
}
