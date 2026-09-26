"""GamePlan — a pre-event plan from a guest list (SOH-197, Tier 2 #27).

OWNER: Person A. See contracts/walkers.md for the exact report shape and
AGENTS.md for the working rules this file must obey:
  - Deterministic, no `by llm` anywhere. Openers reuse whatever GoalRank
    already cached on `RelevantTo.opener`; a fresh line is built only when
    that cache is empty, from a Fact/Intent already in the graph.
  - Relationships never decay: nothing here reads `Knows.last_contact`.
  - `:priv`, own-root only. Reuses `paths.sv.jac`'s `find_path`, `goals.sv.jac`'s
    `gather_evidence`, and `reads.sv.jac`'s `list_promises_raw` rather than
    re-implementing them.

Guest-name resolution per name (normalized, case-insensitive; see `match_known`
and `find_reported_route`):
  1. Every person under `[me ->:Knows:->]` (confirmed or proposed) whose full
     name matches exactly, or — for a single-token guest name only — whose
     first name token matches, is a candidate. Exactly one candidate -> known.
     Two or more (deduped by jid, whichever rule found them) -> ambiguous.
  2. Else: a `Reported` edge one hop out of any known person, whose target's
     full name matches -> route (`via` = that known person's name, `hops`
     from `find_path`).
  3. Else: unknown.
"""

import from datetime { datetime }
import from schema {
    Me, Person, Goal, Fact, Promise,
    Knows, Reported, RelevantTo, HasGoal, FactAbout
}
import from paths { find_path }
import from goals { gather_evidence }
import from reads { list_promises_raw }

# ---------------------------------------------------------------- helpers

def _norm(s: str) -> str {
    return s.strip().lower();
}

"""Every person under `[me ->:Knows:->]` (any status) whose name matches
`guest_name` by exact full-name equality, or — only when `guest_name` is a
single token — by first-name-token equality. Deduped by jid."""
def match_known(me: Me, guest_name: str) -> list[Person] {
    key = _norm(guest_name);
    single = " " not in key;
    seen: list[str] = [];
    out: list[Person] = [];

    for p in [me ->:Knows:->] {
        full = _norm(p.name);
        matched = full == key;
        if not matched and single {
            parts = p.name.strip().split(" ");
            first = _norm(parts[0]) if parts else full;
            matched = first == key;
        }
        if matched {
            pid = jid(p);
            if pid not in seen {
                seen.append(pid);
                out.append(p);
            }
        }
    }
    return out;
}

"""One `Reported` hop out of any known person, matched by exact full-name
equality against the reported target. Returns `{"via": Person, "target":
Person}` for the first match found, or None."""
def find_reported_route(me: Me, guest_name: str) -> dict[str, Person] | None {
    key = _norm(guest_name);
    for p in [me ->:Knows:->] {
        for q in [p ->:Reported:->] {
            if _norm(q.name) == key {
                return {"via": p, "target": q};
            }
        }
    }
    return None;
}

def active_goal(me: Me) -> Goal | None {
    for g in [me ->:HasGoal:->] {
        if g.active {
            return g;
        }
    }
    return None;
}

"""Text of the first open (done == False) Promise addressed to `person_id`,
or "". Reuses `reads.sv.jac`'s `list_promises_raw` rather than re-walking
`Note ->:AssertsPromise:-> Promise ->:PromiseTo:-> Person` here."""
def open_promise_for(person_id: str) -> str {
    for it in list_promises_raw() {
        to = it["to"];
        if to is None {
            continue;
        }
        to_person = to as Person;
        if jid(to_person) != person_id {
            continue;
        }
        pr = it["promise"] as Promise;
        if not pr.done {
            return pr.text;
        }
    }
    return "";
}

"""The most-recently-observed Fact about `p`, or ""."""
def recent_fact_for(p: Person) -> str {
    facts: list[Fact] = [p <-:FactAbout:<-];
    if not facts {
        return "";
    }
    best = facts[0];
    for f in facts[1:] {
        if f.observed_at > best.observed_at {
            best = f;
        }
    }
    return best.text;
}

"""Cached `RelevantTo.opener` if non-empty, else a line naming one Fact/
Intent about `p` (via `goals.sv.jac`'s `gather_evidence`), else ""."""
def opener_for(p: Person, cached_opener: str) -> str {
    if cached_opener {
        return cached_opener;
    }
    items = gather_evidence(p, datetime.now());
    for item in items {
        if item.kind == "fact" or item.kind == "intent" {
            parts = p.name.strip().split(" ");
            first_name = parts[0] if parts else p.name;
            return f"Ask {first_name} about {item.span}.";
        }
    }
    return "";
}

"""why_talk priority for a known person: open promise > strong/medium goal
relevance > a recent fact > a generic line."""
def why_talk_for(display_name: str, open_promise: str, goal_strength: str, goal_text: str, recent_fact: str) -> str {
    if open_promise {
        return f"You promised {display_name}: {open_promise}";
    }
    if goal_strength == "strong" or goal_strength == "medium" {
        return f"{display_name} is a {goal_strength} match for your goal '{goal_text}'.";
    }
    if recent_fact {
        return f"You noted about {display_name}: {recent_fact}";
    }
    return "You know them; say hello.";
}

def route_why_talk(display_name: str, via_name: str) -> str {
    return f"You don't know {display_name} yet, but {via_name} can introduce you.";
}

# ---------------------------------------------------------------- assembly

"""Deterministic, testable directly on a hand-built `me` (no jobj/ownership
involved beyond `find_path`'s own Note lookups) — see plan.test.jac. See the
module docstring and contracts/walkers.md for the exact resolution rule and
report shape. Capped at `GAMEPLAN_CAP` names; the rest are never silently
dropped - they come back in `not_processed` (SOH-212)."""
glob GAMEPLAN_CAP: int = 60;

"""`total_names`, `processed`, `truncated`, `not_processed` for a guest list."""
def cap_report(names: list[str]) -> dict[str, any] {
    total = len(names);
    processed = total if total <= GAMEPLAN_CAP else GAMEPLAN_CAP;
    return {
        "total_names": total,
        "processed": processed,
        "truncated": total > GAMEPLAN_CAP,
        "not_processed": list(names[GAMEPLAN_CAP:])
    };
}

def game_plan_for(me: Me, names: list[str], event: str) -> dict[str, any] {
    capped = names[:GAMEPLAN_CAP];
    cap = cap_report(names);
    goal = active_goal(me);
    goal_text = goal.text if goal is not None else "";

    known_out: list[dict[str, any]] = [];
    routes_out: list[dict[str, any]] = [];
    unknown_out: list[str] = [];
    ambiguous_out: list[dict[str, any]] = [];

    promise_names: list[str] = [];
    goal_names: list[str] = [];
    other_known_names: list[str] = [];
    route_names: list[str] = [];

    for guest_name in capped {
        candidates = match_known(me, guest_name);

        if len(candidates) >= 2 {
            ambiguous_out.append({"name": guest_name, "candidates": candidates});
            continue;
        }

        if len(candidates) == 1 {
            p = candidates[0];
            open_promise = open_promise_for(jid(p));

            goal_label = "";
            goal_strength = "";
            cached_opener = "";
            if goal is not None {
                g = goal as Goal;
                matched = [edge p ->:RelevantTo:-> g];
                if matched {
                    re = matched[0];
                    goal_label = re.label;
                    goal_strength = re.strength;
                    cached_opener = re.opener;
                }
            }

            recent_fact = recent_fact_for(p);
            opener = opener_for(p, cached_opener);
            why_talk = why_talk_for(guest_name, open_promise, goal_strength, goal_text, recent_fact);

            known_out.append({
                "name": guest_name, "person": p, "why_talk": why_talk,
                "open_promise": open_promise, "opener": opener,
                "goal_label": goal_label, "goal_strength": goal_strength
            });

            if open_promise {
                promise_names.append(guest_name);
            } elif goal_strength == "strong" or goal_strength == "medium" {
                goal_names.append(guest_name);
            } else {
                other_known_names.append(guest_name);
            }
            continue;
        }

        route = find_reported_route(me, guest_name);
        if route is not None {
            r = route as dict[str, Person];
            via_person = r["via"];
            target = r["target"];

            path = find_path(me, target, 3);
            if path["found"] {
                hops_list = path["hops"] as list[dict[str, any]];
                hops = len(hops_list);
            } else {
                hops = 2;   # one known hop + one reported hop, by construction
            }

            routes_out.append({
                "name": guest_name, "person": target, "via": via_person.name,
                "hops": hops, "why_talk": route_why_talk(guest_name, via_person.name)
            });
            route_names.append(guest_name);
            continue;
        }

        unknown_out.append(guest_name);
    }

    suggested_order = promise_names + goal_names + other_known_names + route_names;

    return {
        "event": event,
        "known": known_out,
        "routes": routes_out,
        "unknown": unknown_out,
        "ambiguous": ambiguous_out,
        "suggested_order": suggested_order,
        "total_names": cap["total_names"],
        "processed": cap["processed"],
        "truncated": cap["truncated"],
        "not_processed": cap["not_processed"]
    };
}

# ---------------------------------------------------------------- walker

walker:priv GamePlan {
    """Pre-event game plan from a guest list. No `by llm`, no graph writes.
    Reports one dict — see contracts/walkers.md."""
    has names: list[str];
    has event: str = "";
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            cap = cap_report(self.names);
            report {
                "event": self.event, "known": [], "routes": [],
                "unknown": self.names[:GAMEPLAN_CAP], "ambiguous": [], "suggested_order": [],
                "total_names": cap["total_names"], "processed": cap["processed"],
                "truncated": cap["truncated"], "not_processed": cap["not_processed"]
            };
            return;
        }
        me = existing[0];
        report game_plan_for(me, self.names, self.event);
    }
}
