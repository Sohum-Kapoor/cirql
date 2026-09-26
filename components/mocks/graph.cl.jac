"""Mock for `GraphView(goal_id: str = "")` — SOH-185.

Returns EXACTLY the contract shape (contracts/walkers.md, SOH-185 block):
{ nodes: [{ id, kind: "me"|"person"|"goal", label, status, org, title }],
  edges: [{ from, to, kind: "knows"|"reported"|"relevant_to", label, strength }] }

Fifteen nodes: Me, thirteen people (same pseudonymous ids as the GoalRank mock),
and the chosen goal. `relevant_to` edges differ per goal so a goal switch is
visible under `?mock=1`; a goal whose text contains "#empty" (or `graph=0` in
the URL) returns Me alone, i.e. the empty state.
"""

import from .goals { mock_list_goals, mock_goal_text }

def _node(nid: str, kind: str, label: str, status: str, org: str, title: str) -> dict {
    return {"id": nid, "kind": kind, "label": label, "status": status, "org": org, "title": title};
}

def _edge(src: str, dst: str, kind: str, label: str, strength: str) -> dict {
    return {"from": src, "to": dst, "kind": kind, "label": label, "strength": strength};
}

def _people() -> list[dict] {
    return [
        _node("mock-person-maya", "person", "Maya Chen", "confirmed", "Stripe Climate", "Carbon removal lead"),
        _node("mock-person-dev", "person", "Dev Okafor", "confirmed", "Great Lakes Angels", "Associate"),
        _node("mock-person-lena", "person", "Lena Park", "confirmed", "Campus Energy Club", "President"),
        _node("mock-person-sam", "person", "Sam Ruiz", "proposed", "Ruiz Castings", "Plant manager"),
        _node("mock-person-priya", "person", "Priya Raman", "confirmed", "Great Lakes Angels", "Partner"),
        _node("mock-person-omar", "person", "Omar Haddad", "confirmed", "UM Energy Institute", "Research fellow"),
        _node("mock-person-june", "person", "June Alvarez", "proposed", "Rivian", "Battery pack engineer"),
        _node("mock-person-theo", "person", "Theo Brandt", "confirmed", "Zell Lurie Institute", "Program director"),
        _node("mock-person-ana", "person", "Ana Souza", "confirmed", "Form Energy", "Field engineer"),
        _node("mock-person-kofi", "person", "Kofi Mensah", "proposed", "DTE Energy", "Grid planner"),
        _node("mock-person-rae", "person", "Rae Kim", "confirmed", "Ross School", "MBA candidate"),
        _node("mock-person-ben", "person", "Ben Ito", "confirmed", "Ford", "Facilities lead"),
        _node("mock-person-iris", "person", "Iris Novak", "proposed", "Clean Energy Ventures", "Analyst")
    ];
}

def _knows() -> list[dict] {
    me: str = "mock-me";
    return [
        _edge(me, "mock-person-maya", "knows", "worked together at Stripe", "confirmed"),
        _edge(me, "mock-person-dev", "knows", "spring pitch night", "confirmed"),
        _edge(me, "mock-person-lena", "knows", "Campus Energy Club", "confirmed"),
        _edge(me, "mock-person-sam", "knows", "card at the plant tour", "proposed"),
        _edge(me, "mock-person-priya", "knows", "Ross climate panel", "confirmed"),
        _edge(me, "mock-person-omar", "knows", "lab mate", "confirmed"),
        _edge(me, "mock-person-june", "knows", "imported from csv", "proposed"),
        _edge(me, "mock-person-theo", "knows", "Zell Lurie office hours", "confirmed"),
        _edge(me, "mock-person-ana", "knows", "conference dinner", "confirmed"),
        _edge(me, "mock-person-kofi", "knows", "badge photo", "proposed"),
        _edge(me, "mock-person-rae", "knows", "classmate", "confirmed"),
        _edge(me, "mock-person-ben", "knows", "plant tour", "confirmed"),
        _edge(me, "mock-person-iris", "knows", "imported from csv", "proposed")
    ];
}

def _reported() -> list[dict] {
    return [
        _edge("mock-person-priya", "mock-person-dev", "reported", "reported", ""),
        _edge("mock-person-dev", "mock-person-june", "reported", "reported", ""),
        _edge("mock-person-lena", "mock-person-theo", "reported", "reported", ""),
        _edge("mock-person-maya", "mock-person-iris", "reported", "reported", ""),
        _edge("mock-person-ben", "mock-person-sam", "reported", "reported", "")
    ];
}

def _relevance(goal_id: str) -> list[list[str]] {
    if goal_id == "mock-goal-pilot" {
        return [
            ["mock-person-sam", "strong"], ["mock-person-ben", "strong"],
            ["mock-person-lena", "medium"], ["mock-person-kofi", "medium"],
            ["mock-person-dev", "weak"], ["mock-person-ana", "weak"]
        ];
    }
    if goal_id == "mock-goal-raise" {
        return [
            ["mock-person-maya", "strong"], ["mock-person-priya", "strong"],
            ["mock-person-dev", "medium"], ["mock-person-lena", "medium"], ["mock-person-iris", "medium"],
            ["mock-person-sam", "weak"], ["mock-person-theo", "weak"]
        ];
    }
    return [["mock-person-lena", "medium"], ["mock-person-maya", "weak"]];
}

"""The goal GraphView would pick: the given id if it is one of the goals, else the active one."""
def _pick_goal(goal_id: str) -> dict | None {
    goals: list[dict] = mock_list_goals();
    for g in goals {
        if g["_jac_id"] == goal_id {
            return g;
        }
    }
    for g in goals {
        if g["active"] {
            return g;
        }
    }
    return None;
}

def:pub mock_graph_view(goal_id: str) -> dict {
    me: dict = _node("mock-me", "me", "You", "confirmed", "Kiln Labs", "Founder");
    search: str = String(window.location.search);  # jac:ignore[W2001]
    goal: dict | None = _pick_goal(goal_id);
    goal_text: str = (goal["text"] as str) if goal is not None else "";
    if "graph=0" in search or "#empty" in goal_text or "#empty" in mock_goal_text(goal_id) {
        return {"nodes": [me], "edges": []};
    }
    nodes: list[dict] = [me] + _people();
    edges: list[dict] = _knows() + _reported();
    if goal is not None {
        gid: str = goal["_jac_id"] as str;
        nodes = nodes + [_node(gid, "goal", goal_text, "", "", "")];
        for pair in _relevance(gid) {
            edges = edges + [_edge(pair[0], gid, "relevant_to", pair[1], pair[1])];
        }
    }
    return {"nodes": nodes, "edges": edges};
}
