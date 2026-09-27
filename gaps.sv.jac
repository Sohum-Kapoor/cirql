"""gaps.sv.jac — GapFinder walker (SOH-203).

OWNER: Person A. See `contracts/walkers.md` (`GapFinder`) for the reported
shape and AGENTS.md for ownership rules. A gap is a statement about the
user's own graph, never about a person: this file's report never names a
person, only a kind of person.
"""

import re;
import json;
import from llm { llm }
import from datetime { datetime }
import from schema { Me, Person, Goal, HasGoal, Knows, Reported, RelevantTo, FactAbout, IntentAbout }
import from scoring { fallback_tokens, polish_reason }
import from goals { _parse_naive_utc, newest_evidence_at }


obj NeededKind {
    has kind: str;
    has why_needed: str;
    has suggested_need: str;
    has covered_by: list[int];
}
sem NeededKind.kind = "A kind of person this goal needs, as a short noun phrase such as 'climate-tech VC' or 'wheelchair user willing to test a prototype'; never a specific person.";
sem NeededKind.why_needed = "One sentence on why the goal needs this kind of person. Never use the words 'score', 'scores', or 'scoring'. Speak as the product talking to the user in second person ('you need...'); never say 'the fact', 'the intent', 'the evidence', 'the profile', 'the note', 'the author', 'the speaker', or 'the user'; never quote evidence in parentheses; one sentence, under 160 characters. Never use an em-dash or en-dash; use a period, colon or comma instead.";
sem NeededKind.suggested_need = "The request a friend's agent could act on, in plain words a non-native English speaker understands: one short sentence, everyday words, no jargon, 14 words or fewer, e.g. 'someone who invests in young climate companies and reads student emails'; no names. Never use the words 'score', 'scores', or 'scoring'. Never 'the fact'/'the note'/'the author'/'the user'; never quote evidence in parentheses. Never use an em-dash or en-dash; use a period, colon or comma instead.";
sem NeededKind.covered_by = "The # numbers of listed warm people who already are this kind of person or can directly provide it; empty if none.";

obj GapExtraction {
    has kinds: list[NeededKind];
}
sem GapExtraction.kinds = "Two to four kinds of people the goal needs, most important first.";

def find_gaps(goal: str, warm_people: str) -> GapExtraction by llm(temperature=0.2);
sem find_gaps = "Given a goal and an anonymized summary of the warm people already available for it, list the kinds of people the goal still needs that none of those warm people already are or provide.";
sem find_gaps.goal = "The user's goal, verbatim.";
sem find_gaps.warm_people = "One line per warm person already available for this goal - role, label, strength, reason, and short evidence snippets, with NO names - or the literal string 'none' if there are no warm people yet. Never use the words 'score', 'scores', or 'scoring' in a suggested need or why_needed.";

# SOH-212 (judge pass): the LLM's own covered_by indices only ever see the
# WARM (known/route, strong/medium) people it was shown - never the rest of
# the user's active network. A person who is already exactly the proposed
# kind (e.g. Lena Fischer, title "organizer" at org "JacHacks", covering a
# proposed "JacHacks event organizer" gap) but who has no strong/medium
# RelevantTo tie to THIS goal yet never appears in `warm_people`, so the
# model has no way to know she covers the gap. `kind_covered_by_person`
# below is a second, deterministic check against every active known person
# in the graph (not just the warm ones), independent of the LLM.
glob SCORE_WORD_RE: str = r"(?i)\bscor(e|es|ing)\b";

"""Replace 'score'/'scores'/'scoring' (any case, word-boundary) with
'results' - the product rule bans the word 'score' from anything shown to
the user, and the LLM is not perfectly reliable about the sem instruction
alone."""
def strip_score_words(text: str) -> str {
    return re.sub(SCORE_WORD_RE, "results", text);
}

"""True when `kind_tokens` (>=4-char, non-stopword tokens of a proposed gap
role, via scoring.fallback_tokens - the same tokenizer/stopword list SOH-211
uses for its own deterministic fallback) meaningfully overlaps a known
person's fields. Rule (deliberately asymmetric): title+org is a short,
on-topic field, so ONE shared token is already a real signal ("organizer"
shared with a role of "JacHacks event organizer"); free-text Facts are
noisier, so we require TWO shared tokens before treating a fact as covering
a role, to avoid a single generic word (e.g. "climate") false-covering a
gap."""
def kind_covered_by_person(kind_tokens: list[str], person_text: dict[str, str]) -> bool {
    role_hits = 0;
    for t in fallback_tokens(person_text["role"]) {
        if t in kind_tokens {
            role_hits += 1;
        }
    }
    if role_hits >= 1 {
        return True;
    }
    fact_hits = 0;
    for t in fallback_tokens(person_text["facts"]) {
        if t in kind_tokens {
            fact_hits += 1;
        }
    }
    return fact_hits >= 2;
}

"""Any active known person (own root; see `known_people_texts`) already
covers this kind."""
def kind_covered_by_any_person(kind: str, known_people: list[dict[str, str]]) -> bool {
    kind_tokens = fallback_tokens(kind);
    if not kind_tokens {
        return False;
    }
    for person_text in known_people {
        if kind_covered_by_person(kind_tokens, person_text) {
            return True;
        }
    }
    return False;
}

"""Active known people (own root only) for the deterministic post-filter:
`role` = "title at org" (or just title), `facts` = that person's own Fact
texts joined with spaces. Same candidate set as `warm_lines_for` (directly
Known + their Reported ties, deduped) but NOT filtered by RelevantTo - the
whole point is to catch a person who covers a gap kind but has no
(yet-scored) tie to this particular goal. 'active' = Person.status
'confirmed' (not still awaiting an import swipe-confirm) and not archived -
the same test `scoring.collect_candidates` uses for SOH-220."""
def known_people_texts(me: Me) -> list[dict[str, str]] {
    known: list[Person] = [me ->:Knows:->];
    candidates: list[Person] = [];
    seen_ids: list[str] = [];
    for p in known {
        pid = jid(p);
        if pid not in seen_ids {
            seen_ids.append(pid);
            candidates.append(p);
        }
    }
    for p in known {
        for rp in [p ->:Reported:->] {
            rid = jid(rp);
            if rid not in seen_ids {
                seen_ids.append(rid);
                candidates.append(rp);
            }
        }
    }

    out: list[dict[str, str]] = [];
    for p in candidates {
        if p.status != "confirmed" or p.archived {
            continue;
        }
        role = f"{p.title} at {p.org}" if p.org else p.title;
        facts: list[str] = [];
        for fact in [p <-:FactAbout:<-] {
            facts.append(fact.text);
        }
        out.append({"role": role, "facts": " ".join(facts)});
    }
    return out;
}

"""Deterministic filter over the LLM's raw extraction: a kind is a gap iff
(a) none of its covered_by indices fall within [0, warm_count) (i.e. no
listed warm person already covers it) AND (b) no active known person's
title/org/facts meaningfully overlaps the kind (`kind_covered_by_any_person`
- SOH-212, catches a person the LLM never saw because they aren't warm YET
for this goal). Cleans strings (also stripping the banned word 'score' /
'scores' / 'scoring' from the free-text fields), drops entries with any
empty field, dedupes by lowercase kind (first occurrence wins), caps at 4.
`known_people` defaults to `[]` so existing callers/tests that only cared
about the covered_by check are unaffected."""
def compute_gaps(x: GapExtraction, warm_count: int, known_people: list[dict[str, str]] | None = None) -> list[dict[str, any]] {
    people: list[dict[str, str]] = known_people if known_people is not None else [];
    out: list[dict[str, any]] = [];
    seen: list[str] = [];
    for k in x.kinds {
        covered = False;
        for idx in k.covered_by {
            if idx >= 0 and idx < warm_count {
                covered = True;
            }
        }
        kind = k.kind.strip();
        if not covered and kind and kind_covered_by_any_person(kind, people) {
            covered = True;
        }
        if covered {
            continue;
        }
        # SOH-226: product copy, not model narration ("The fact confirms...").
        why = polish_reason(strip_score_words(k.why_needed.strip()));
        need = polish_reason(strip_score_words(k.suggested_need.strip()));
        if not kind or not why or not need {
            continue;
        }
        key = kind.lower();
        if key in seen {
            continue;
        }
        seen.append(key);
        out.append({"kind": kind, "why_needed": why, "suggested_need": need});
        if len(out) >= 4 {
            break;
        }
    }
    return out;
}

"""SOH-223: the anonymized warm lines GapFinder sends the model, as a plain
def. One line per (known or reported) person whose RelevantTo edge to
`goal` is known/route and strong/medium. RunAgent treats an empty list as
a deterministic gap (the goal itself has no warm path)."""
def warm_lines_for(me: Me, goal: Goal) -> list[str] {
    known: list[Person] = [me ->:Knows:->];
    candidates: list[Person] = [];
    seen_ids: list[str] = [];
    for p in known {
        pid = jid(p);
        if pid not in seen_ids {
            seen_ids.append(pid);
            candidates.append(p);
        }
    }
    for p in known {
        for rp in [p ->:Reported:->] {
            rid = jid(rp);
            if rid not in seen_ids {
                seen_ids.append(rid);
                candidates.append(rp);
            }
        }
    }

    warm_lines: list[str] = [];
    warm_count = 0;
    for p in candidates {
        for e in [edge p ->:RelevantTo:-> goal] {
            if e.label in ["known", "route"] and e.strength in ["strong", "medium"] {
                role = f"{p.title} at {p.org}" if p.org else p.title;
                line = f"#{warm_count} | role: {role} | {e.label} | {e.strength} | {e.reason}";
                evidence: list[str] = [];
                for fact in [p <-:FactAbout:<-] {
                    if len(evidence) < 3 {
                        evidence.append(fact.text);
                    }
                }
                for intent in [p <-:IntentAbout:<-] {
                    if len(evidence) < 3 {
                        evidence.append(intent.text);
                    }
                }
                if evidence {
                    line = line + " | evidence: " + " / ".join(evidence[:3]);
                }
                warm_lines.append(line);
                warm_count += 1;
            }
        }
    }
    return warm_lines;
}

# ---------------------------------------------------------------- SOH-236 cache

"""Same dedup pattern as `warm_lines_for`/`known_people_texts`: directly
Known people plus their Reported ties, deduped - the candidate set whose
newest evidence timestamp can invalidate the stored gap cache."""
def candidate_people(me: Me) -> list[Person] {
    known: list[Person] = [me ->:Knows:->];
    candidates: list[Person] = [];
    seen_ids: list[str] = [];
    for p in known {
        pid = jid(p);
        if pid not in seen_ids {
            seen_ids.append(pid);
            candidates.append(p);
        }
    }
    for p in known {
        for rp in [p ->:Reported:->] {
            rid = jid(rp);
            if rid not in seen_ids {
                seen_ids.append(rid);
                candidates.append(rp);
            }
        }
    }
    return candidates;
}

"""The newest `goals.newest_evidence_at` timestamp across `candidates` -
"" if nothing parses. A new Fact/Intent/Promise/Note about any of the
caller's known-or-reported people counts as "a new note about the goal"
for cache-invalidation purposes (SOH-236)."""
def graph_newest_evidence_at(candidates: list[Person]) -> str {
    best: str = "";
    best_dt: datetime | None = None;
    for p in candidates {
        ts = newest_evidence_at(p);
        dt = _parse_naive_utc(ts);
        if dt is None {
            continue;
        }
        if best_dt is None or dt > (best_dt as datetime) {
            best_dt = dt;
            best = ts;
        }
    }
    return best;
}

"""SOH-236: true when a stored `Goal.gaps_json`/`gaps_at` is still usable
without re-running `find_gaps`. False when there is nothing stored, when
`gaps_at` doesn't parse, when `newest_evidence` (see
`graph_newest_evidence_at`) postdates `gaps_at` (a new note about one of
the goal's candidate people invalidates the cache), or when the cache is
older than 6 hours (the documented fallback rule for a Goal with no other
freshness signal - AGENTS.md)."""
def gaps_cache_is_fresh(gaps_json: str, gaps_at: str, newest_evidence: str, now: datetime) -> bool {
    if not gaps_json.strip() or not gaps_at.strip() {
        return False;
    }
    gaps_dt = _parse_naive_utc(gaps_at);
    if gaps_dt is None {
        return False;
    }
    evidence_dt = _parse_naive_utc(newest_evidence);
    if evidence_dt is not None and evidence_dt > gaps_dt {
        return False;
    }
    age_seconds = (now - gaps_dt).total_seconds();
    return age_seconds <= 6 * 3600;
}

"""Parse a stored `Goal.gaps_json` and mark every entry `cached: true` -
the shape `GapFinder` serves on a cache hit. Returns `None` (not `[]`) when
the stored JSON fails to parse, so the caller can tell "empty result" from
"corrupt cache" and fall back to recomputing."""
def served_from_cache(gaps_json: str) -> list[dict[str, any]] | None {
    try {
        loaded = json.loads(gaps_json);
    } except Exception {
        return None;
    }
    out: list[dict[str, any]] = [];
    for gap in loaded {
        g = gap as dict[str, any];
        g["cached"] = True;
        out.append(g);
    }
    return out;
}

walker:priv GapFinder {
    """Report the kinds of people a goal needs for which there is no warm
    (known/route, strong/medium) path in the caller's graph. Never names a
    person - only kinds of people. Goal not found (or no Me yet) -> [].

    SOH-236: results are cached on the Goal (`gaps_json`/`gaps_at`). Unless
    `force=True`, a fresh cache (see `gaps_cache_is_fresh`) is served
    straight back (`cached: true`) and `find_gaps` (the `by llm` call) is
    never invoked; otherwise the model runs, the result is stored, and
    every reported entry carries `cached: false`."""
    has goal_id: str;
    has force: bool = False;
    has reports: list[dict[str, any]] = [];

    can find with Root entry {
        me_list = [root --> [?:Me]];
        if not me_list {
            disengage;
        }
        me = me_list[0];

        found_goal: (Goal | None) = None;
        for g in [me ->:HasGoal:->] {
            if jid(g) == self.goal_id {
                found_goal = g;
            }
        }
        if found_goal is None {
            disengage;
        }
        # `is None` narrowing does not cross a walker ability's own scope
        # (verified: it holds inside a plain `def`, not here) - the `disengage`
        # above already made the None case unreachable below, so `as Goal` is
        # a safe, documented cast (`jac guide jac-types`), not a bypass.
        goal: Goal = found_goal as Goal;

        candidates = candidate_people(me);
        newest_at = graph_newest_evidence_at(candidates);

        served: list[dict[str, any]] | None = None;
        if not self.force and gaps_cache_is_fresh(goal.gaps_json, goal.gaps_at, newest_at, datetime.now()) {
            served = served_from_cache(goal.gaps_json);
        }
        if served is not None {
            for gap in (served as list[dict[str, any]]) {
                report gap;
            }
            disengage;
        }

        warm_lines = warm_lines_for(me, goal);
        warm_count = len(warm_lines);
        warm_summary = "\n".join(warm_lines) if warm_lines else "none";

        try {
            extraction = find_gaps(goal.text, warm_summary);
        } except Exception {
            disengage;
        }

        known_people = known_people_texts(me);
        gaps = compute_gaps(extraction, warm_count, known_people);

        goal.gaps_json = json.dumps(gaps);
        goal.gaps_at = datetime.now().isoformat();

        for gap in gaps {
            gap["cached"] = False;
            report gap;
        }
    }
}

walker:priv GapDevSeed {
    """DEV-ONLY: seed helper for exercising GapFinder before SetGoal/GoalRank
    land on main (SOH-203). Get-or-creates the caller's Me, creates a NEW
    Goal, and attaches known People with RelevantTo edges of the requested
    strengths so GapFinder has warm/cold data to reason over. Reports the
    new goal's jid. Never call this from the client."""
    has goal_text: str;
    has with_vc: bool = True;
    has with_barista: bool = True;
    has me_name: str = "me";
    has reports: list[dict[str, str]] = [];

    can seed with Root entry {
        existing = [root --> [?:Me]];
        if existing {
            me = existing[0];
        } else {
            me = (root ++> Me(name=self.me_name))[0];
        }
        goal = (me +>:HasGoal:+> Goal(text=self.goal_text, created_at=datetime.now().isoformat()))[0];

        if self.with_vc {
            vc = (me +>:Knows(how_met="test"):+> Person(
                name="VC Contact", org="Climate Ventures",
                title="Partner at a climate-tech VC fund"
            ))[0];
            vc +>:RelevantTo(label="known", strength="strong", reason="met at demo day"):+> goal;
        }
        if self.with_barista {
            barista = (me +>:Knows(how_met="test"):+> Person(
                name="Barista Contact", org="Corner Cafe", title="Barista"
            ))[0];
            barista +>:RelevantTo(label="known", strength="weak", reason="local coffee shop regular"):+> goal;
        }

        report {"goal_id": jid(goal)};
    }
}
