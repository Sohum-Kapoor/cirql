"""health.sv.jac — NetworkHealth walker (SOH-200): bridges, weak ties, and
echo-chamber share of the caller's OWN network (PRD Tier 2 #32).

OWNER: Person A. See contracts/walkers.md (`NetworkHealth`) for the exact
report shape and AGENTS.md for ownership rules. This describes the SHAPE of
the caller's network, never a person's worth: no field here ranks or scores
a person, there is no per-person "health"; `people`/`confirmed`/`proposed`/
`ties`/`clusters`/`bridges`/`weak_tie_share`/`echo_share` are all properties
of the graph as a whole. Nothing reads `Knows.last_contact` — relationships
never decay and this walker doesn't touch recency at all. `:priv`, own-root
only, no `by llm`, fully deterministic, bounded by the product's own
500-person cap (nothing here adds a new limit).

Graph G for this walker: nodes = the caller's own `Person`s with
`status == "confirmed"` reachable via `[me ->:Knows:->]`; ties = `Reported`
edges between two such nodes, read as UNDIRECTED (a tie the user was told
about, in either direction, between two people they both know, counts once).
`clusters` = connected components of G with size >= 2, labeled by the most
common non-empty `org` in the component (else "unlabeled"), largest first,
capped at 8. `bridges` = articulation points of G (people whose removal
splits their component into >= 2 pieces), found by simulate-and-recount
removal — cheap and easy to get right at <= 500 nodes, unlike hand-rolling
Tarjan low-links under a deadline — capped at 10. `weak_tie_share` = share
of confirmed people with no Reported tie to anyone else in G (isolated),
rounded to 2 decimals. `echo_share` = share of confirmed people whose `org`
equals the single most common org across ALL confirmed people (not just
those with a tie), rounded to 2 decimals, 0.0 when nobody has an org.
"""

import from schema { Me, Person, Reported, Knows }

# ---------------------------------------------------------------- plain data

obj Graph {
    """Undirected adjacency over the caller's own confirmed-known people.
    `ids` preserves discovery order (the order `[me ->:Knows:->]` returned
    them) so components/samples/labels stay deterministic regardless of
    dict/set iteration order."""
    has id_of: dict[str, Person];
    has ids: list[str];
    has adj: dict[str, list[str]];
    has ties: int;
}

# ---------------------------------------------------------------- helpers

"""Build the undirected tie graph over `confirmed` (already filtered to
`status == "confirmed"`). A `Reported` edge counts as one tie regardless of
which direction it was recorded in, and only when BOTH endpoints are in
`confirmed` — a tie to someone outside the caller's confirmed-known set
never appears here."""
def build_graph(confirmed: list[Person]) -> Graph {
    id_of: dict[str, Person] = {};
    ids: list[str] = [];
    for p in confirmed {
        pid = jid(p);
        if pid in id_of {
            continue;   # defensive: [me ->:Knows:->] should never repeat a person
        }
        id_of[pid] = p;
        ids.append(pid);
    }

    adj: dict[str, list[str]] = {};
    for pid in ids {
        adj[pid] = [];
    }

    seen_pairs: list[str] = [];
    ties = 0;
    for p in confirmed {
        pid = jid(p);
        if pid not in id_of {
            continue;
        }
        for q in [p ->:Reported:->] {
            qid = jid(q);
            if qid == pid or qid not in id_of {
                continue;
            }
            a = pid if pid < qid else qid;
            b = qid if pid < qid else pid;
            key = a + "|" + b;
            if key in seen_pairs {
                continue;
            }
            seen_pairs.append(key);
            ties += 1;
            if qid not in adj[pid] {
                adj[pid].append(qid);
            }
            if pid not in adj[qid] {
                adj[qid].append(pid);
            }
        }
    }

    return Graph(id_of=id_of, ids=ids, adj=adj, ties=ties);
}

"""Connected components of `g` with >= 2 nodes — an isolated confirmed
person (no ties at all) is never its own component here; `weak_tie_share`
is what surfaces those. Discovery order follows `g.ids`, so equal-size ties
are broken the same way every run."""
def find_components(g: Graph) -> list[list[str]] {
    visited: dict[str, bool] = {};
    comps: list[list[str]] = [];
    for start in g.ids {
        if start in visited {
            continue;
        }
        if not g.adj[start] {
            visited[start] = True;
            continue;
        }
        comp: list[str] = [];
        queue: list[str] = [start];
        visited[start] = True;
        idx = 0;
        while idx < len(queue) {
            cur = queue[idx];
            idx += 1;
            comp.append(cur);
            for nb in g.adj[cur] {
                if nb not in visited {
                    visited[nb] = True;
                    queue.append(nb);
                }
            }
        }
        comps.append(comp);
    }
    return comps;
}

def _comp_size_key(comp: list[str]) -> int {
    return len(comp);
}

"""Most common non-empty `org` among the people in `part`, ties broken
alphabetically so the label never depends on traversal/dict order;
"unlabeled" when nobody in `part` has a non-empty org."""
def label_for(part: list[str], g: Graph) -> str {
    counts: dict[str, int] = {};
    for pid in part {
        p = g.id_of[pid];
        org = p.org.strip();
        if not org {
            continue;
        }
        if org in counts {
            counts[org] = counts[org] + 1;
        } else {
            counts[org] = 1;
        }
    }
    if not counts {
        return "unlabeled";
    }
    best = "";
    best_count = -1;
    for org in sorted(counts.keys()) {
        c = counts[org];
        if c > best_count {
            best = org;
            best_count = c;
        }
    }
    return best;
}

"""Articulation points of `g`, found by simulate-and-recount removal: for
every node `v` in a component of size >= 3 (a 2-node component can never
have a cut vertex — removing either side just leaves one lone person, never
a split), BFS the rest of that component without ever crossing through `v`;
more than one resulting piece means `v` bridges them. Cheap and easy to get
right at <= 500 people; capped at 10 bridges, `g.ids` discovery order."""
def find_bridges(g: Graph, comps: list[list[str]]) -> list[dict[str, object]] {
    results: list[dict[str, object]] = [];
    for comp in comps {
        if len(results) >= 10 {
            break;
        }
        if len(comp) < 3 {
            continue;
        }
        for v in comp {
            others = [pid for pid in comp if pid != v];
            visited: dict[str, bool] = {};
            parts: list[list[str]] = [];
            for start in others {
                if start in visited {
                    continue;
                }
                part: list[str] = [];
                queue: list[str] = [start];
                visited[start] = True;
                idx = 0;
                while idx < len(queue) {
                    cur = queue[idx];
                    idx += 1;
                    part.append(cur);
                    for nb in g.adj[cur] {
                        if nb == v {
                            continue;
                        }
                        if nb not in visited {
                            visited[nb] = True;
                            queue.append(nb);
                        }
                    }
                }
                parts.append(part);
            }
            if len(parts) >= 2 {
                connects: list[str] = [];
                for part in parts {
                    connects.append(label_for(part, g));
                }
                results.append({"person": g.id_of[v], "connects": connects});
                if len(results) >= 10 {
                    break;
                }
            }
        }
    }
    return results;
}

"""Most common non-empty `org` across every confirmed person (not only
those with a tie), ties broken alphabetically; "" when nobody has an org."""
def most_common_org(confirmed: list[Person]) -> str {
    counts: dict[str, int] = {};
    for p in confirmed {
        org = p.org.strip();
        if not org {
            continue;
        }
        if org in counts {
            counts[org] = counts[org] + 1;
        } else {
            counts[org] = 1;
        }
    }
    if not counts {
        return "";
    }
    best = "";
    best_count = -1;
    for org in sorted(counts.keys()) {
        c = counts[org];
        if c > best_count {
            best = org;
            best_count = c;
        }
    }
    return best;
}

"""Round a non-negative share to 2 decimals without relying on `round()`'s
overload resolution (unresolved for a plain `float` here on this compiler)."""
def _round2(x: float) -> float {
    return int(x * 100.0 + 0.5) / 100.0;
}

"""Nearest integer percent for display, from an already-2-decimal share."""
def _pct(x: float) -> int {
    return int(x * 100.0 + 0.5);
}

def _empty_health() -> dict[str, object] {
    return {
        "people": 0, "confirmed": 0, "proposed": 0, "ties": 0,
        "clusters": [], "bridges": [], "weak_tie_share": 0.0, "echo_share": 0.0,
        "notes": []
    };
}

"""Deterministic, testable directly on a hand-built `me` (no jobj/ownership
involved) — see health.test.jac. See the module docstring and
contracts/walkers.md for the exact definitions."""
def network_health_for(me: Me) -> dict[str, object] {
    known: list[Person] = [p for p in [me ->:Knows:->] if not p.archived];  # SOH-220
    people = len(known);
    confirmed_people = [p for p in known if p.status == "confirmed"];
    confirmed = len(confirmed_people);
    proposed = len([p for p in known if p.status == "proposed"]);

    if confirmed == 0 {
        return _empty_health();
    }

    g = build_graph(confirmed_people);
    comps = find_components(g);
    comps_sorted = sorted(comps, key=_comp_size_key, reverse=True);

    clusters: list[dict[str, object]] = [];
    for comp in comps_sorted[:8] {
        names = [g.id_of[pid].name for pid in comp[:3]];
        clusters.append({"label": label_for(comp, g), "size": len(comp), "sample": names});
    }

    bridges = find_bridges(g, comps);

    isolated = 0;
    for pid in g.ids {
        if not g.adj[pid] {
            isolated += 1;
        }
    }
    weak_tie_share = _round2(isolated / confirmed);

    top_org = most_common_org(confirmed_people);
    echo_count = 0;
    if top_org {
        for p in confirmed_people {
            if p.org.strip() == top_org {
                echo_count += 1;
            }
        }
    }
    echo_share = _round2(echo_count / confirmed) if top_org else 0.0;

    notes: list[str] = [];
    if weak_tie_share > 0 {
        pct = _pct(weak_tie_share);
        notes.append(
            f"{pct}% of your people are not connected to anyone else you know "
            "— your network is wide, not clustered."
        );
    }
    if echo_share > 0 {
        pct2 = _pct(echo_share);
        notes.append(f"One org ({top_org}) is {pct2}% of your network.");
    }
    for b in bridges {
        connects = b["connects"] as list[str];
        distinct: list[str] = [];
        for c in connects {
            if c not in distinct {
                distinct.append(c);
            }
        }
        if len(distinct) >= 2 {
            person = b["person"] as Person;
            notes.append(
                f"{person.name} is the only link between your {distinct[0]} "
                f"cluster and your {distinct[1]} cluster."
            );
            break;
        }
    }
    notes = notes[:3];

    return {
        "people": people, "confirmed": confirmed, "proposed": proposed,
        "ties": g.ties, "clusters": clusters, "bridges": bridges,
        "weak_tie_share": weak_tie_share, "echo_share": echo_share, "notes": notes
    };
}

# ---------------------------------------------------------------- walker

walker:priv NetworkHealth {
    """Health of the caller's OWN network: bridges, weak ties, echo-chamber
    share. Never a per-person score — see contracts/walkers.md. Reports one
    dict; no `Me` yet reports the all-zero/empty shape."""
    has reports: list[dict[str, object]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report _empty_health();
            return;
        }
        me = existing[0];
        report network_health_for(me);
    }
}
