"""ScoreAgainstNeed — the one need/offer scorer, run over the caller's own root.

OWNER: Person A. See contracts/walkers.md `ScoreAgainstNeed(need, exclude_handles)`
for the exact report shape. `score_against_need` is kept as a plain def (not a
walker method) so the future Exchange walker (SOH-205) can `import from scoring
{ score_against_need }` and call it directly on its owner's root.

Deterministic exclusions run first (proposed people, excluded card handles,
expired intents); ONE `by llm` call scores the survivors; on any failure a
deterministic fallback takes over. Nothing here reads `Knows.last_contact`.
Evidence numbering in the prompt and in `NeedMatch.evidence_indices` is
per-candidate (0-based, local to that candidate's own evidence list) — never
a flat/global table — so a match can only ever cite its own evidence. The
prompt never carries a person's name (role + org only): the walker maps the
LLM's answer back to a Person by `index`, and `why` can't name anyone because
the model was never given a name to use.
"""

import from llm { llm }
import from datetime { datetime }
import from schema {
    Me, Person, Knows, Fact, FactAbout, Intent, IntentAbout, Card, FromCard
}


# ---------------------------------------------------------------- LLM shape

obj NeedMatch {
    has index: int;
    has strength: str;
    has why: str;
    has evidence_indices: list[int];
}

obj NeedMatches {
    has items: list[NeedMatch];
}

sem NeedMatch.index = "The candidate's # number from the input, copied exactly.";
sem NeedMatch.strength = "strong only when a listed offer/open_to intent or a fact shows this person can directly provide what the need asks for; medium when their role or a fact makes it plausible; weak otherwise. Sharing an employer, school, or job title with the need's domain is never more than weak on its own.";
sem NeedMatch.why = "One sentence citing the specific evidence number(s) for this candidate. Never invent or mention a person's name — none were given to you.";
sem NeedMatch.evidence_indices = "The 0-based evidence numbers from THIS candidate's own numbered evidence list that you relied on; empty if none. Never a number from another candidate's list.";
sem NeedMatches.items = "One item per candidate; omit none.";

def score_need(need: str, candidates_text: str) -> NeedMatches by llm(temperature=0.2);
sem score_need = "Score each numbered candidate against the need using only their listed evidence.";
sem score_need.need = "What the caller is looking for.";
sem score_need.candidates_text = "Numbered candidates (role + org only, no names), each with its own 0-based numbered evidence items (facts and offers/open_to intents).";

# ---------------------------------------------------------------- deterministic helpers

"""Parse an ISO-8601 timestamp permissively: strips a trailing "Z" and drops
any tzinfo so comparisons against a naive `datetime.now()` never raise.
Returns None on anything unparsable instead of propagating."""
def _parse_naive_utc(ts: str) -> datetime | None {
    if not ts {
        return None;
    }
    cleaned = ts;
    if cleaned.endswith("Z") {
        cleaned = cleaned[:-1];
    }
    try {
        dt = datetime.fromisoformat(cleaned);
    } except (ValueError, TypeError) {
        return None;
    }
    if dt.tzinfo is not None {
        dt = dt.replace(tzinfo=None);
    }
    return dt;
}

# Deterministic exclusions first: proposed people, excluded card handles,
# proposed Knows ties, expired/unparsable-expiry intents, need intents. Cap
# 40 candidates, 6 evidence items each. Skip candidates with zero evidence.
# Each candidate: {"person": Person, "evidence": list[dict[str, str]]}
# Each evidence item: {"kind": str, "text": str, "jid": str}
def collect_candidates(me: Me, exclude_handles: list[str], now: datetime) -> list[dict[str, any]] {
    candidates: list[dict[str, any]] = [];
    for p in [me ->:Knows:->] {
        if len(candidates) >= 40 {
            break;
        }
        if p.status != "confirmed" {
            continue;
        }
        edges = [edge me ->:Knows:-> p];
        if len(edges) == 0 {
            continue;
        }
        if edges[0].status == "proposed" {
            continue;
        }
        excluded = False;
        for c in [p ->:FromCard:->] {
            if c.handle in exclude_handles {
                excluded = True;
            }
        }
        if excluded {
            continue;
        }
        evidence: list[dict[str, str]] = [];
        for f in [p <-:FactAbout:<-] {
            if len(evidence) >= 6 {
                break;
            }
            evidence.append({"kind": "fact", "text": f.text, "jid": jid(f)});
        }
        for i in [p <-:IntentAbout:<-] {
            if len(evidence) >= 6 {
                break;
            }
            if i.kind != "offer" and i.kind != "open_to" {
                continue;
            }
            if i.expires_at {
                exp_dt = _parse_naive_utc(i.expires_at);
                if exp_dt is None {
                    continue;   # unparsable expires_at -> skip this intent
                }
                if exp_dt < now {
                    continue;   # expired -> skip
                }
            }
            evidence.append({"kind": i.kind, "text": i.text, "jid": jid(i)});
        }
        if len(evidence) == 0 {
            continue;
        }
        candidates.append({"person": p, "evidence": evidence});
    }
    return candidates;
}

# Numbered candidate/evidence text for the LLM call. Role + org only — never
# a name — and evidence is numbered 0-based PER CANDIDATE so an
# evidence_indices answer can only ever point into its own candidate's list.
def build_prompt(candidates: list[dict[str, any]]) -> str {
    lines: list[str] = [];
    idx = 0;
    for c in candidates {
        p = c["person"] as Person;
        lines.append(f"Candidate {idx}: role {p.title} at {p.org}");
        evidence = c["evidence"] as list[dict[str, str]];
        ei = 0;
        for e in evidence {
            lines.append(f"  [{ei}] {e['kind']}: {e['text']}");
            ei += 1;
        }
        idx += 1;
    }
    return "\n".join(lines);
}

def normalize_strength(s: str) -> str {
    if s == "strong" or s == "medium" or s == "weak" {
        return s;
    }
    return "weak";
}

# SOH-211: the fallback (no LLM) never claims more than it can show. Only a
# deterministic token overlap earns `weak`; no overlap excludes the
# candidate; the fallback never assigns `medium` or `strong`.
glob FALLBACK_STOPWORDS: list[str] = [
    "about", "after", "also", "been", "being", "from", "have", "into", "just",
    "like", "looking", "more", "most", "need", "needs", "only", "other", "some",
    "someone", "that", "their", "them", "then", "there", "these", "they",
    "this", "those", "very", "want", "wants", "were", "what", "when", "where",
    "which", "while", "with", "would", "your", "intro", "intros"
];

"""Lowercased alphanumeric tokens of length >= 4 that are not stopwords."""
def fallback_tokens(text: str) -> list[str] {
    out: list[str] = [];
    cur = "";
    for ch in (text.lower() + " ") {
        if ch.isalnum() {
            cur = cur + ch;
        } else {
            if len(cur) >= 4 and cur not in FALLBACK_STOPWORDS and cur not in out {
                out.append(cur);
            }
            cur = "";
        }
    }
    return out;
}

"""The evidence items sharing at least one fallback token with the need."""
def fallback_overlap(need: str, evidence: list[dict[str, str]]) -> list[dict[str, str]] {
    need_tokens = fallback_tokens(need);
    hits: list[dict[str, str]] = [];
    for e in evidence {
        for t in fallback_tokens(e["text"]) {
            if t in need_tokens {
                hits.append(e);
                break;
            }
        }
    }
    return hits;
}

"""`weak` when any evidence item shares a token with the need, else "" (exclude).
Never `medium`/`strong`, whatever the evidence kind."""
def fallback_strength(need: str, evidence: list[dict[str, str]]) -> str {
    if fallback_overlap(need, evidence) {
        return "weak";
    }
    return "";
}

# Stable order: strong, then medium, then weak.
def order_by_strength(items: list[dict[str, any]]) -> list[dict[str, any]] {
    strong: list[dict[str, any]] = [];
    medium: list[dict[str, any]] = [];
    weak: list[dict[str, any]] = [];
    for it in items {
        s = it["strength"] as str;
        if s == "strong" {
            strong.append(it);
        } elif s == "medium" {
            medium.append(it);
        } else {
            weak.append(it);
        }
    }
    return strong + medium + weak;
}

# Deterministic post-processing of the LLM's answer against `candidates`:
#   - dedupe by index (first wins);
#   - a candidate the LLM never mentioned still gets an entry: weak,
#     "No ranking returned.", no evidence;
#   - evidence_indices are LOCAL to that candidate's own evidence list —
#     mapped to jids from `candidates[idx]["evidence"]`, never a flat table;
#     out-of-range indices are dropped;
#   - evidence-gated: if the mapped evidence_ids end up empty, strength is
#     forced back to "weak" regardless of what the LLM said;
#   - normalize strength to the enum;
#   - order strong > medium > weak, stable.
def post_process(candidates: list[dict[str, any]], matches: NeedMatches) -> list[dict[str, any]] {
    n = len(candidates);
    by_index: dict[int, NeedMatch] = {};
    for m in matches.items {
        if m.index < 0 or m.index >= n {
            continue;
        }
        if m.index in by_index {
            continue;   # dedupe by index: first wins
        }
        by_index[m.index] = m;
    }

    items: list[dict[str, any]] = [];
    for idx in range(n) {
        c = candidates[idx];
        evidence = c["evidence"] as list[dict[str, str]];

        if idx in by_index {
            m = by_index[idx];
            strength = normalize_strength(m.strength);
            why = m.why;
            evidence_indices = m.evidence_indices;
        } else {
            strength = "weak";
            why = "No ranking returned.";
            evidence_indices = [];
        }

        evidence_ids: list[str] = [];
        for ei in evidence_indices {
            if ei >= 0 and ei < len(evidence) {
                evidence_ids.append(evidence[ei]["jid"]);
            }
        }

        if not evidence_ids {
            strength = "weak";   # evidence-gated: no mapped evidence -> weak
        }

        items.append({
            "person_id": jid(c["person"]),
            "strength": strength,
            "why": why,
            "evidence_ids": evidence_ids
        });
    }

    return order_by_strength(items);
}

def fallback_results(candidates: list[dict[str, any]], need: str) -> list[dict[str, any]] {
    items: list[dict[str, any]] = [];
    for c in candidates {
        evidence = c["evidence"] as list[dict[str, str]];
        hits = fallback_overlap(need, evidence);
        if not hits {
            continue;   # SOH-211: no shared token -> excluded, never guessed
        }
        items.append({
            "person_id": jid(c["person"]),
            "strength": "weak",
            "why": "Shares a keyword with the need (scored without the model).",
            "evidence_ids": [e["jid"] for e in hits]
        });
    }
    return items;
}

# The one need/offer scorer. Kept separate from the walker so the Exchange
# walker (SOH-205) can import and call it directly later.
def score_against_need(me: Me, need: str, exclude_handles: list[str]) -> list[dict[str, any]] {
    now = datetime.now();
    candidates = collect_candidates(me, exclude_handles, now);
    if len(candidates) == 0 {
        return [];
    }
    text = build_prompt(candidates);
    try {
        matches = score_need(need, text);
        return post_process(candidates, matches);
    } except Exception {
        return fallback_results(candidates, need);
    }
}

# ---------------------------------------------------------------- walker

walker:priv ScoreAgainstNeed {
    """Score the caller's own network against a stated need. See
    contracts/walkers.md for the exact report shape."""
    has need: str;
    has exclude_handles: list[str] = [];
    has reports: list[dict] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if existing {
            me = existing[0];
            results = score_against_need(me, self.need, self.exclude_handles);
            for r in results {
                report r;
            }
        }
    }
}
