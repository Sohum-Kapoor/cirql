"""PathFinder — the warmest EVIDENCED route to a person (SOH-194).

OWNER: Person A. See contracts/walkers.md for the exact report shape and
AGENTS.md for the working rules this file must obey:
  - No edge between two people means UNKNOWN, not "never met" — "no known
    route" is always a valid, non-error answer; it is never confused with
    "not_found" (the target isn't reachable from Me by ANY traversal at all).
  - A route hop must be an edge with provenance: a `Knows` edge from Me, or a
    `Reported` edge between two people carrying a non-empty `source_note`.
    Sharing an `org` is CONTEXT to display, never a hop.
  - Relationships never decay: `Knows.last_contact` is display only and is
    never used to rank or gate a route — only `days_since_contact` (display)
    is derived from it. Ties are never broken by `last_contact`.
  - `:priv`, own-root only, no `by llm`.
"""

import from datetime { datetime }
import from schema { Me, Person, Note, Knows, Reported }
import from goals { compute_days_since_contact }
import from reads { load, my_node }

# ---------------------------------------------------------------- plain data

obj Candidate {
    """One candidate (parent, edge, node) offering a route to `q_node` at the
    current BFS round — collected so ties for the SAME node in the SAME round
    can be resolved by `_pick_warmest` instead of first-found-wins."""
    has parent_person: Person;
    has redge: Reported;
    has q_node: Person;
}

# ---------------------------------------------------------------- helpers

"""Walk the parent-pointer chain back from `pjid` to the level-0 ancestor
(the person Me knows directly who started this chain) and return that
person's `Knows.status` ("confirmed" | "reported" | "proposed"), or "" if
`pjid` has no recorded parent chain yet (defensive; should not happen)."""
def _ancestor_knows_status(pjid: str, parent: dict[str, str], edge_used: dict[str, object]) -> str {
    cur = pjid;
    status = "";
    steps = 0;
    while steps < 20 {
        steps += 1;
        anc_edge = edge_used[cur] if cur in edge_used else None;
        if isinstance(anc_edge, Knows) {
            status = (anc_edge as Knows).status;
            break;
        }
        if cur not in parent {
            break;
        }
        nxt = parent[cur];
        if not nxt {
            break;
        }
        cur = nxt;
    }
    return status;
}

"""The connecting Reported edge's evidence Note's `captured_at`, or "" when
the source_note is empty or unresolvable. ISO-8601 strings sort correctly by
recency, which is all `_pick_warmest` needs."""
def _evidence_observed_at(re: Reported) -> str {
    if not re.source_note {
        return "";
    }
    note_obj = load(re.source_note);
    if isinstance(note_obj, Note) {
        return (note_obj as Note).captured_at;
    }
    return "";
}

"""Warmest = fewest hops first (guaranteed by BFS round order); among
several routes reaching the SAME node in the SAME round: prefer the chain
whose level-0 Knows edge is `status == "confirmed"` over reported/proposed,
then prefer the more recent evidence `observed_at`. Never `last_contact`."""
def _pick_warmest(cands: list[Candidate], parent: dict[str, str], edge_used: dict[str, object]) -> Candidate {
    best = cands[0];
    best_status = _ancestor_knows_status(jid(best.parent_person), parent, edge_used);
    best_obs = _evidence_observed_at(best.redge);

    for cand in cands[1:] {
        status = _ancestor_knows_status(jid(cand.parent_person), parent, edge_used);
        obs = _evidence_observed_at(cand.redge);

        if status == "confirmed" and best_status != "confirmed" {
            best = cand;
            best_status = status;
            best_obs = obs;
            continue;
        }
        if best_status == "confirmed" and status != "confirmed" {
            continue;   # best stays
        }
        if obs > best_obs {
            best = cand;
            best_status = status;
            best_obs = obs;
        }
    }
    return best;
}

"""Is `target_jid` reachable from `me` by ANY Knows/Reported traversal at
all — ignoring confirmed/proposed status and the source_note requirement?
This is the ONLY question that decides `not_found` (target not under the
caller's graph at all) versus "no known route" (target is somewhere in the
caller's network, just not by a valid evidenced route within `max_depth`)."""
def _broad_reachable(me: Me, target_jid: str) -> bool {
    visited: dict[str, bool] = {};
    queue: list[Person] = [p for p in [me ->:Knows:->] if not p.archived];
    for p in queue {
        visited[jid(p)] = True;
    }
    if target_jid in visited {
        return True;
    }

    idx = 0;
    while idx < len(queue) {
        cur = queue[idx];
        idx += 1;
        for q in [cur ->:Reported:->] {
            if q.archived {
                continue;   # SOH-220
            }
            qjid = jid(q);
            if qjid in visited {
                continue;
            }
            visited[qjid] = True;
            if qjid == target_jid {
                return True;
            }
            queue.append(q);
        }
    }
    return False;
}

def _not_found() -> dict[str, any] {
    return {"found": False, "target": None, "hops": [], "context": [], "reason": "not_found"};
}

# ---------------------------------------------------------------- find_path

"""Deterministic, testable directly on hand-built `me`/`target` nodes (no
jobj/ownership involved beyond resolving a `source_note` id) — see
paths.test.jac. See the module docstring and contracts/walkers.md for the
exact algorithm and report shape.

BFS from Me: level 0 = `[me ->:Knows:->]` restricted to
`Person.status == "confirmed" and Knows.status != "proposed"`; each further
level follows `Reported` edges out of the frontier, only edges carrying a
non-empty `source_note`; visited set by jid (cycle-safe); stops once the
target is found or `effective_max_depth` (given `max_depth`, hard-capped at
4) hop-counts are exhausted. A person reached only via a `Reported` edge
whose OWN `Person.status == "proposed"` may still BE the target, but is
never expanded further as an intermediate hop."""
def find_path(me: Me, target: Person, max_depth: int) -> dict[str, any] {
    now = datetime.now();

    effective_max_depth = max_depth;
    if effective_max_depth > 4 {
        effective_max_depth = 4;
    }
    if effective_max_depth < 1 {
        effective_max_depth = 1;
    }

    target_jid = jid(target);

    # ---- level 0
    level0: list[Person] = [];
    knows_edge_for: dict[str, Knows] = {};
    for p in [me ->:Knows:->] {
        matched = [edge me ->:Knows:-> p];
        if not matched {
            continue;
        }
        ke0 = matched[0];
        if p.status == "confirmed" and ke0.status != "proposed" and not p.archived {
            level0.append(p);
            knows_edge_for[jid(p)] = ke0;
        }
    }

    # ---- context (display only, independent of the actual route)
    context: list[str] = [];
    if target.org {
        for p in level0 {
            if p.org and p.org == target.org {
                line = f"same org as you: {p.org}";
                if line not in context {
                    context.append(line);
                }
            }
        }
    }

    # ---- restricted BFS with parent pointers
    visited: dict[str, bool] = {};
    parent: dict[str, str] = {};       # child jid -> parent jid ("" = Me)
    edge_used: dict[str, object] = {}; # child jid -> the Knows|Reported edge used to reach it
    via_type: dict[str, str] = {};     # child jid -> "knows" | "reported"
    person_by_jid: dict[str, Person] = {};

    for p in level0 {
        pjid = jid(p);
        if pjid in visited {
            continue;
        }
        visited[pjid] = True;
        parent[pjid] = "";
        edge_used[pjid] = knows_edge_for[pjid];
        via_type[pjid] = "knows";
        person_by_jid[pjid] = p;
    }

    found_target = target_jid in visited;
    current_frontier = list(level0);
    depth = 1;   # level0 = hop count 1

    while depth < effective_max_depth and current_frontier and not found_target {
        candidates_for_q: dict[str, list[Candidate]] = {};

        for parent_person in current_frontier {
            for q in [parent_person ->:Reported:->] {
                if q.archived {
                    continue;   # SOH-220
                }
                qjid = jid(q);
                if qjid in visited {
                    continue;
                }
                redges = [edge parent_person ->:Reported:-> q];
                if not redges {
                    continue;
                }
                re = redges[0];
                if not re.source_note {
                    continue;   # no provenance -> never a hop
                }
                if qjid not in candidates_for_q {
                    candidates_for_q[qjid] = [];
                }
                candidates_for_q[qjid].append(Candidate(parent_person=parent_person, redge=re, q_node=q));
            }
        }

        next_frontier: list[Person] = [];
        for qjid in candidates_for_q {
            cands = candidates_for_q[qjid];
            winner = _pick_warmest(cands, parent, edge_used);

            visited[qjid] = True;
            parent[qjid] = jid(winner.parent_person);
            edge_used[qjid] = winner.redge;
            via_type[qjid] = "reported";
            person_by_jid[qjid] = winner.q_node;

            if qjid == target_jid {
                found_target = True;
            }
            if winner.q_node.status != "proposed" {
                next_frontier.append(winner.q_node);   # proposed people never expand further
            }
        }

        depth += 1;
        current_frontier = next_frontier;
    }

    if target_jid not in visited {
        if _broad_reachable(me, target_jid) {
            return {
                "found": False, "target": target, "hops": [], "context": context,
                "reason": "No known route. Unknown is not never met."
            };
        }
        return _not_found();
    }

    # ---- rebuild hops from target back to the level-0 entry point
    chain: list[str] = [];
    cur = target_jid;
    while cur != "" {
        chain.append(cur);
        cur = parent[cur];
    }
    chain.reverse();

    hops: list[dict[str, any]] = [];
    for pjid in chain {
        p = person_by_jid[pjid];
        via = via_type[pjid];
        edge_obj = edge_used[pjid];
        evidence: dict[str, str] | None = None;
        days: int | None = None;

        if via == "knows" {
            ke = edge_obj as Knows;
            if ke.source_note {
                note_obj = load(ke.source_note);
                if isinstance(note_obj, Note) {
                    note = note_obj as Note;
                    evidence = {"id": jid(note), "kind": "note", "span": "", "observed_at": note.captured_at};
                }
            }
            days = compute_days_since_contact(ke.last_contact, now);
        } else {
            hop_re = edge_obj as Reported;
            if hop_re.source_note {
                note_obj = load(hop_re.source_note);
                if isinstance(note_obj, Note) {
                    note = note_obj as Note;
                    evidence = {"id": jid(note), "kind": "note", "span": hop_re.span, "observed_at": note.captured_at};
                }
            }
            days = None;
        }

        hops.append({"person": p, "via": via, "evidence": evidence, "days_since_contact": days});
    }

    n_reported = len(hops) - 1;
    if n_reported <= 0 {
        reason = "Known directly.";
    } else {
        hop_word = "hop" if n_reported == 1 else "hops";
        first_name = (hops[0]["person"] as Person).name;
        reason = f"Reported route via {first_name} ({n_reported} {hop_word}).";
    }

    return {"found": True, "target": target, "hops": hops, "context": context, "reason": reason};
}

# ---------------------------------------------------------------- walker

walker:priv PathFinder {
    """The warmest EVIDENCED route to a person under the caller's own graph.
    "No known route" is a valid answer (target somewhere in the caller's
    network, no valid hop within max_depth); an id that doesn't resolve to a
    Person owned by the caller, or resolves but isn't reachable by ANY
    traversal from Me, reports `not_found`. Reports one dict — see
    contracts/walkers.md."""
    has target_person_id: str;
    has max_depth: int = 3;
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report _not_found();
            return;
        }
        me = existing[0];

        n = my_node(self.target_person_id);
        if n is None or not isinstance(n, Person) {
            report _not_found();
            return;
        }
        target = n as Person;

        report find_path(me, target, self.max_depth);
    }
}
