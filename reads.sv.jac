"""Reads — Receipt, ListPromises, CompletePromise, GraphView (SOH-186/187/185).

OWNER: Person A. See contracts/walkers.md for the exact report shapes. Every
walker here is `:priv` (own-root only, JWT required) and reads/writes ONLY the
caller's own graph — a resolved id that belongs to another account (readable
or not) reports `not_found`, never the other account's data. No `by llm`
anywhere in this module; every field is copied straight off a node or edge.
Idioms (jobj/jid/owner_root/check_read_access, `[edge a ->:E:-> b]`, reverse
traversal `[x <-:E:<-]`) reused verbatim from exchange.sv.jac and goals.sv.jac.
"""

import from jaclang { JacRuntime as Jac }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, HasGoal, RelevantTo
}

# ---------------------------------------------------------------- helpers

"""jobj that never raises; resolves ANY node and NEVER authorizes."""
def load(some_id: str) -> object {
    try {
        return jobj(some_id);
    } except Exception {
        return None;
    }
}

"""Root id (dash-less hex) of whoever created node n. Idiom from exchange.sv.jac."""
def owner_root(n: object) -> str {
    return str(getattr(n, "__jac__").root).replace("-", "");
}

def readable(n: object) -> bool {
    return bool(Jac.check_read_access(getattr(n, "__jac__")));  # jac:ignore[E1053]
}

"""Resolve `some_id` to a node that is BOTH readable AND owned by the
caller's own root; None on any miss (unknown id, wrong owner, no read grant).
This is what keeps a Card allow_root'ed to us for Exchange out of Receipt."""
def my_node(some_id: str) -> object {
    n = load(some_id);
    if n is None {
        return None;
    }
    if not readable(n) {
        return None;
    }
    if owner_root(n) != jid(root) {
        return None;
    }
    return n;
}

def not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

# ---------------------------------------------------------------- Receipt

"""Type-dispatch helper, deterministic and testable directly on hand-built
node objects (no jobj/ownership involved) — see reads.test.jac."""
def receipt_for(n: object) -> dict[str, str] {
    if isinstance(n, Fact) {
        f = n as Fact;
        note_text = "";
        span = "";
        source_note_id = "";
        captured_at = "";
        notes: list[Note] = [f <-:Asserts:<-];
        if notes {
            note = notes[0];
            note_text = note.text;
            source_note_id = jid(note);
            captured_at = note.captured_at;
            spans = [e.span for e in [edge note ->:Asserts:-> f]];
            if spans {
                span = spans[0];
            }
        }
        return {
            "kind": "fact", "id": jid(f), "text": f.text,
            "source_note_id": source_note_id, "span": span,
            "note_text": note_text, "captured_at": captured_at,
            "source_kind": f.source_kind, "source_url": f.source_url
        };
    }

    if isinstance(n, Intent) {
        i = n as Intent;
        note_text = "";
        span = "";
        source_note_id = "";
        captured_at = "";
        notes: list[Note] = [i <-:AssertsIntent:<-];
        if notes {
            note = notes[0];
            note_text = note.text;
            source_note_id = jid(note);
            captured_at = note.captured_at;
            spans = [e.span for e in [edge note ->:AssertsIntent:-> i]];
            if spans {
                span = spans[0];
            }
        }
        return {
            "kind": "intent", "id": jid(i), "text": i.text,
            "source_note_id": source_note_id, "span": span,
            "note_text": note_text, "captured_at": captured_at,
            "source_kind": i.source_kind, "source_url": ""
        };
    }

    if isinstance(n, Promise) {
        pr = n as Promise;
        note_text = "";
        span = "";
        source_note_id = "";
        captured_at = "";
        notes: list[Note] = [pr <-:AssertsPromise:<-];
        if notes {
            note = notes[0];
            note_text = note.text;
            source_note_id = jid(note);
            captured_at = note.captured_at;
            spans = [e.span for e in [edge note ->:AssertsPromise:-> pr]];
            if spans {
                span = spans[0];
            }
        }
        return {
            "kind": "promise", "id": jid(pr), "text": pr.text,
            "source_note_id": source_note_id, "span": span,
            "note_text": note_text, "captured_at": captured_at,
            "source_kind": "", "source_url": ""
        };
    }

    if isinstance(n, Person) {
        p = n as Person;
        note_text = "";
        span = "";
        source_note_id = "";
        captured_at = "";
        mention_notes: list[Note] = [p <-:Mentions:<-];
        if mention_notes {
            note = mention_notes[0];
            spans = [e.span for e in [edge note ->:Mentions:-> p]];
            if spans {
                span = spans[0];
            }
            note_text = note.text;
            source_note_id = jid(note);
            captured_at = note.captured_at;
        } else {
            know_edges = [edge p <-:Knows:<-];
            if know_edges {
                ke = know_edges[0];
                if ke.source_note {
                    note_obj = load(ke.source_note);
                    if isinstance(note_obj, Note) {
                        note = note_obj as Note;
                        note_text = note.text;
                        source_note_id = jid(note);
                        captured_at = note.captured_at;
                    }
                }
            }
        }
        return {
            "kind": "person", "id": jid(p), "text": p.name,
            "source_note_id": source_note_id, "span": span,
            "note_text": note_text, "captured_at": captured_at,
            "source_kind": "", "source_url": ""
        };
    }

    if isinstance(n, Note) {
        note = n as Note;
        return {
            "kind": "note", "id": jid(note), "text": note.text,
            "source_note_id": "", "span": "",
            "note_text": note.text, "captured_at": note.captured_at,
            "source_kind": "", "source_url": ""
        };
    }

    if isinstance(n, Card) {
        c = n as Card;
        return {
            "kind": "card", "id": jid(c), "text": c.handle,
            "source_note_id": "", "span": "",
            "note_text": "", "captured_at": "",
            "source_kind": "self", "source_url": ""
        };
    }

    if isinstance(n, Goal) {
        g = n as Goal;
        return {
            "kind": "goal", "id": jid(g), "text": g.text,
            "source_note_id": "", "span": "",
            "note_text": "", "captured_at": "",
            "source_kind": "", "source_url": ""
        };
    }

    return not_found();
}

walker:priv Receipt {
    """Resolve id -> owned node -> receipt_for; not_found on any miss."""
    has id: str;
    has reports: list[dict[str, str]] = [];

    can go with Root entry {
        n = my_node(self.id);
        if n is None {
            report not_found();
            return;
        }
        report receipt_for(n);
    }
}

# ---------------------------------------------------------------- ListPromises / CompletePromise

"""Every Promise asserted by one of the caller's own Notes, deduped by jid,
each paired with its asserting Note's id/span and its PromiseTo target."""
def list_promises_raw() -> list[dict[str, object]] {
    items: list[dict[str, object]] = [];
    seen: list[str] = [];
    for note in [root --> [?:Note]] {
        for pr in [note ->:AssertsPromise:->] {
            k = jid(pr);
            if k in seen {
                continue;
            }
            seen.append(k);
            spans = [e.span for e in [edge note ->:AssertsPromise:-> pr]];
            span = spans[0] if spans else "";
            to_list: list[Person] = [pr ->:PromiseTo:->];
            to_person = to_list[0] if to_list else None;
            items.append({
                "promise": pr, "to": to_person,
                "source_note_id": jid(note), "span": span
            });
        }
    }
    return items;
}

"""Open (done == False) first ordered by due ascending with "" due last,
then done ones (same due ordering within each group)."""
def _promise_sort_key(item: dict[str, object]) -> tuple[int, int, str] {
    promise = item["promise"] as Promise;
    done_rank = 1 if promise.done else 0;
    due = promise.due;
    due_empty_rank = 1 if not due else 0;
    return (done_rank, due_empty_rank, due);
}

walker:priv ListPromises {
    has reports: list[dict[str, object]] = [];

    can go with Root entry {
        items = sorted(list_promises_raw(), key=_promise_sort_key);
        for it in items {
            report it;
        }
    }
}

walker:priv CompletePromise {
    """Flip Promise.done. Ownership check as in Receipt; not_found on any miss."""
    has promise_id: str;
    has done: bool = True;
    has reports: list[object] = [];

    can go with Root entry {
        n = my_node(self.promise_id);
        if n is None or not isinstance(n, Promise) {
            report not_found();
            return;
        }
        pr = n as Promise;
        pr.done = self.done;
        report pr;
    }
}

# ---------------------------------------------------------------- GraphView

def me_node_dict(me: Me) -> dict[str, str] {
    return {"id": jid(me), "kind": "me", "label": me.name, "status": "", "org": "", "title": ""};
}

def person_node_dict(p: Person) -> dict[str, str] {
    return {"id": jid(p), "kind": "person", "label": p.name, "status": p.status, "org": p.org, "title": p.title};
}

def goal_node_dict(g: Goal) -> dict[str, str] {
    return {"id": jid(g), "kind": "goal", "label": g.text, "status": "", "org": "", "title": ""};
}

"""Deterministic, testable: Me + every known Person (capped at 300) + the
chosen Goal (given id, else the active one, else none); Knows/Reported/
RelevantTo edges among them. Pulled out of the walker body so a test block
can call it on a `me` it just built, without the shared-persisted-test-root
ambiguity of `[root --> [?:Me]][0]` (jac-testing: one root accumulates every
test's Me across a run)."""
def graph_view_for(me: Me, goal_id: str) -> dict[str, object] {
    nodes: list[dict[str, str]] = [me_node_dict(me)];
    edges: list[dict[str, str]] = [];

    people: list[Person] = [];
    people_jids: list[str] = [];

    for p in [me ->:Knows:->] {
        if len(people) >= 300 {
            break;
        }
        people.append(p);
        people_jids.append(jid(p));
        nodes.append(person_node_dict(p));
        know_edges = [edge me ->:Knows:-> p];
        if know_edges {
            ke = know_edges[0];
            edges.append({
                "from": jid(me), "to": jid(p), "kind": "knows",
                "label": ke.how_met, "strength": ke.status
            });
        }
    }

    for a in people {
        for b in [a ->:Reported:->] {
            bid = jid(b);
            if bid in people_jids {
                edges.append({
                    "from": jid(a), "to": bid, "kind": "reported",
                    "label": "reported", "strength": ""
                });
            }
        }
    }

    goals: list[Goal] = [me ->:HasGoal:->];
    goal: Goal | None = None;
    if goal_id {
        for g in goals {
            if jid(g) == goal_id {
                goal = g;
            }
        }
    }
    if goal is None {
        for g in goals {
            if g.active {
                goal = g;
            }
        }
    }

    if goal is not None {
        gg = goal as Goal;
        nodes.append(goal_node_dict(gg));
        for rp in [gg <-:RelevantTo:<-] {
            matched = [edge rp ->:RelevantTo:-> gg];
            if matched {
                re = matched[0];
                edges.append({
                    "from": jid(rp), "to": jid(gg), "kind": "relevant_to",
                    "label": re.label, "strength": re.strength
                });
            }
        }
    }

    return {"nodes": nodes, "edges": edges};
}

walker:priv GraphView {
    """Resolves the caller's own Me, then delegates to `graph_view_for`.
    Reports one dict {nodes, edges}. No LLM anywhere in this module."""
    has goal_id: str = "";
    has reports: list[dict[str, object]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report {"nodes": [], "edges": []};
            return;
        }
        me = existing[0];
        report graph_view_for(me, self.goal_id);
    }
}
