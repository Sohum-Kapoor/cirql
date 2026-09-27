"""gaps.sv.jac — GapFinder walker (SOH-203).

OWNER: Person A. See `contracts/walkers.md` (`GapFinder`) for the reported
shape and AGENTS.md for ownership rules. A gap is a statement about the
user's own graph, never about a person: this file's report never names a
person, only a kind of person.
"""

import from llm { llm }
import from datetime { datetime }
import from schema { Me, Person, Goal, HasGoal, Knows, Reported, RelevantTo, FactAbout, IntentAbout }


obj NeededKind {
    has kind: str;
    has why_needed: str;
    has suggested_need: str;
    has covered_by: list[int];
}
sem NeededKind.kind = "A kind of person this goal needs, as a short noun phrase such as 'climate-tech VC' or 'wheelchair user willing to test a prototype'; never a specific person.";
sem NeededKind.why_needed = "One sentence on why the goal needs this kind of person.";
sem NeededKind.suggested_need = "The request a friend's agent could act on, in plain words a non-native English speaker understands: one short sentence, everyday words, no jargon, 14 words or fewer, e.g. 'someone who invests in young climate companies and reads student emails'; no names.";
sem NeededKind.covered_by = "The # numbers of listed warm people who already are this kind of person or can directly provide it; empty if none.";

obj GapExtraction {
    has kinds: list[NeededKind];
}
sem GapExtraction.kinds = "Two to four kinds of people the goal needs, most important first.";

def find_gaps(goal: str, warm_people: str) -> GapExtraction by llm(temperature=0.2);
sem find_gaps = "Given a goal and an anonymized summary of the warm people already available for it, list the kinds of people the goal still needs that none of those warm people already are or provide.";
sem find_gaps.goal = "The user's goal, verbatim.";
sem find_gaps.warm_people = "One line per warm person already available for this goal - role, label, strength, reason, and short evidence snippets, with NO names - or the literal string 'none' if there are no warm people yet.";

"""Deterministic filter over the LLM's raw extraction: a kind is a gap iff
none of its covered_by indices fall within [0, warm_count) (i.e. no listed
warm person already covers it). Cleans strings, drops entries with any
empty field, dedupes by lowercase kind (first occurrence wins), caps at 4."""
def compute_gaps(x: GapExtraction, warm_count: int) -> list[dict[str, str]] {
    out: list[dict[str, str]] = [];
    seen: list[str] = [];
    for k in x.kinds {
        covered = False;
        for idx in k.covered_by {
            if idx >= 0 and idx < warm_count {
                covered = True;
            }
        }
        if covered {
            continue;
        }
        kind = k.kind.strip();
        why = k.why_needed.strip();
        need = k.suggested_need.strip();
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

walker:priv GapFinder {
    """Report the kinds of people a goal needs for which there is no warm
    (known/route, strong/medium) path in the caller's graph. Never names a
    person - only kinds of people. Goal not found (or no Me yet) -> []."""
    has goal_id: str;
    has reports: list[dict[str, str]] = [];

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

        warm_lines = warm_lines_for(me, goal);
        warm_count = len(warm_lines);
        warm_summary = "\n".join(warm_lines) if warm_lines else "none";

        try {
            extraction = find_gaps(goal.text, warm_summary);
        } except Exception {
            disengage;
        }

        for gap in compute_gaps(extraction, warm_count) {
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
