"""ScoreAgainstNeed — the one need/offer scorer, run over the caller's own root.

OWNER: Person A. See contracts/walkers.md `ScoreAgainstNeed(need, exclude_handles)`
for the exact report shape. `score_against_need` is kept as a plain def (not a
walker method) so the future Exchange walker (SOH-205) can `import from scoring
{ score_against_need }` and call it directly on its owner's root.

Deterministic exclusions run first (proposed people, excluded card handles,
expired intents); ONE `by llm` call scores the survivors; on any failure a
deterministic fallback takes over. Nothing here reads `Knows.last_contact`.
"""

import from byllm.lib { Model }
import from datetime { datetime }
import from schema {
    Me, Person, Knows, Fact, FactAbout, Intent, IntentAbout, Card, FromCard
}

glob llm: Model = Model(model_name="gemini/gemini-3.8-flash");

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

sem NeedMatch.strength = "strong only when a listed offer/open_to intent or a fact shows this person can directly provide what the need asks for; medium when their role or a fact makes it plausible; weak otherwise. Sharing an employer, school, or job title with the need's domain is never more than weak on its own.";
sem NeedMatch.why = "One sentence citing the specific evidence number(s); never mention names of other people.";
sem NeedMatch.evidence_indices = "The evidence numbers relied on; empty if none.";
sem NeedMatches.items = "One item per candidate; omit none.";

def score_need(need: str, candidates_text: str) -> NeedMatches by llm(temperature=0.2);
sem score_need = "Score each numbered candidate against the need using only their listed evidence.";
sem score_need.need = "What the caller is looking for.";
sem score_need.candidates_text = "Numbered candidates, each with its numbered evidence items (facts and offers/open_to intents).";

# ---------------------------------------------------------------- deterministic helpers

# Deterministic exclusions first: proposed people, excluded card handles,
# proposed Knows ties, expired intents, need intents. Cap 40 candidates, 6
# evidence items each. Skip candidates with zero evidence.
# Each candidate: {"person": Person, "evidence": list[dict[str, str]]}
# Each evidence item: {"kind": str, "text": str, "jid": str}
def collect_candidates(me: Me, exclude_handles: list[str]) -> list[dict[str, any]] {
    now = datetime.now().isoformat();
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
            if i.expires_at and i.expires_at < now {
                continue;
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

# Numbered candidate/evidence text for the LLM call, plus the flat
# evidence-number -> jid table used to map its answer back.
def build_prompt(candidates: list[dict[str, any]]) -> dict[str, any] {
    lines: list[str] = [];
    evidence_jids: list[str] = [];
    idx = 0;
    for c in candidates {
        p = c["person"] as Person;
        lines.append(f"Candidate {idx}: {p.name} ({p.org}, {p.title})");
        evidence = c["evidence"] as list[dict[str, str]];
        for e in evidence {
            evidence_jids.append(e["jid"]);
            n = len(evidence_jids);
            lines.append(f"  [{n}] {e['kind']}: {e['text']}");
        }
        idx += 1;
    }
    return {"text": "\n".join(lines), "evidence_jids": evidence_jids};
}

def normalize_strength(s: str) -> str {
    if s == "strong" or s == "medium" or s == "weak" {
        return s;
    }
    return "weak";
}

# Deterministic fallback (no LLM): medium if any offer/open_to intent
# exists in this candidate's evidence, else weak.
def fallback_strength(evidence: list[dict[str, str]]) -> str {
    for e in evidence {
        if e["kind"] == "offer" or e["kind"] == "open_to" {
            return "medium";
        }
    }
    return "weak";
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

# Normalize strength to the enum, map evidence indices -> jids (dropping
# out-of-range), order strong > medium > weak, stable.
def post_process(candidates: list[dict[str, any]], matches: NeedMatches, evidence_jids: list[str]) -> list[dict[str, any]] {
    items: list[dict[str, any]] = [];
    for m in matches.items {
        if m.index < 0 or m.index >= len(candidates) {
            continue;
        }
        c = candidates[m.index];
        evidence_ids: list[str] = [];
        for i in m.evidence_indices {
            if i >= 1 and i <= len(evidence_jids) {
                evidence_ids.append(evidence_jids[i - 1]);
            }
        }
        items.append({
            "person_id": jid(c["person"]),
            "strength": normalize_strength(m.strength),
            "why": m.why,
            "evidence_ids": evidence_ids
        });
    }
    return order_by_strength(items);
}

def fallback_results(candidates: list[dict[str, any]]) -> list[dict[str, any]] {
    items: list[dict[str, any]] = [];
    for c in candidates {
        evidence = c["evidence"] as list[dict[str, str]];
        evidence_ids: list[str] = [e["jid"] for e in evidence];
        items.append({
            "person_id": jid(c["person"]),
            "strength": fallback_strength(evidence),
            "why": "Scored from available evidence.",
            "evidence_ids": evidence_ids
        });
    }
    return order_by_strength(items);
}

# The one need/offer scorer. Kept separate from the walker so the Exchange
# walker (SOH-205) can import and call it directly later.
def score_against_need(me: Me, need: str, exclude_handles: list[str]) -> list[dict[str, any]] {
    candidates = collect_candidates(me, exclude_handles);
    if len(candidates) == 0 {
        return [];
    }
    prompt = build_prompt(candidates);
    try {
        text = prompt["text"] as str;
        matches = score_need(need, text);
        evidence_jids = prompt["evidence_jids"] as list[str];
        return post_process(candidates, matches, evidence_jids);
    } except Exception {
        return fallback_results(candidates);
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
