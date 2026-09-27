"""Walkers — the API the client calls with `root spawn`.

OWNER: Person A. One file per walker family is fine once this grows
(see `jac guide jac-impl-files`); keep report shapes matching contracts/walkers.md.

Every walker here is `:priv` (JWT required, runs on the caller's own root) except
PublishCard's public read (`get_card`, SOH-178), which will live in a root-level
`*.sv.jac`.
"""

import from schema { Me, Person, Knows, Goal, HasGoal, Card, Owns, Circle, InCircle, Event, MetAt }

"""SOH-217: `ListPeople`'s filter logic as a plain def so `walkers.test.jac`
can exercise it directly on hand-built Person nodes (no Me/Knows traversal
needed) — same "extract the deterministic part" idiom `edits.sv.jac`'s
`update_person_for` uses. Archived people are excluded unless
`include_archived`; `circle_id`/`event_id` (when non-empty) require the
person to have a matching `InCircle`/`MetAt` edge."""
def filter_people(people: list[Person], circle_id: str, event_id: str, include_archived: bool) -> list[Person] {
    result: list[Person] = [];
    for p in people {
        if not include_archived and p.archived {
            continue;
        }
        if len(circle_id.strip()) > 0 {
            in_circle = False;
            for c in [p ->:InCircle:->] {
                if jid(c) == circle_id {
                    in_circle = True;
                    break;
                }
            }
            if not in_circle {
                continue;
            }
        }
        if len(event_id.strip()) > 0 {
            at_event = False;
            for ev in [p ->:MetAt:->] {
                if jid(ev) == event_id {
                    at_event = True;
                    break;
                }
            }
            if not at_event {
                continue;
            }
        }
        result.append(p);
    }
    return result;
}

walker:priv Ping {
    """Smoke test: proves auth + spawn + report work end to end."""
    has reports: list[str] = [];

    can go with Root entry {
        report "ok";
    }
}

walker:priv GetMe {
    """Report the caller's Me node, or nothing if onboarding hasn't run."""
    has reports: list[Me] = [];

    can find with Root entry {
        for m in [root --> [?:Me]] {
            report m;
        }
    }
}

walker:priv ListPeople {
    """Report every Person the caller knows (Me -Knows-> Person).
    SOH-217: optionally filtered to one circle (`InCircle`) and/or one
    event (`MetAt`); archived people (`Person.archived`) are excluded
    unless `include_archived=True`. Keeps the original report shape
    (`list[Person]`, no wrapper dict)."""
    has circle_id: str = "";
    has event_id: str = "";
    has include_archived: bool = False;
    has reports: list[Person] = [];

    can collect with Root entry {
        people: list[Person] = [root --> [?:Me] ->:Knows:->];
        for p in filter_people(people, self.circle_id, self.event_id, self.include_archived) {
            report p;
        }
    }
}

walker:priv ListGoals {
    has reports: list[Goal] = [];

    can collect with Root entry {
        for g in [root --> [?:Me] ->:HasGoal:->] {
            report g;
        }
    }
}

walker:priv DevAddPerson {
    """Dev/test helper: get-or-create the caller's Me, attach a Person via
    Knows, report the Person. Replaced by OnboardMe + Capture (SOH-164/166)."""
    has name: str;
    has me_name: str = "me";
    has reports: list[Person] = [];

    can add with Root entry {
        existing = [root --> [?:Me]];
        if existing {
            me = existing[0];
        } else {
            me = (root ++> Me(name=self.me_name))[0];
        }
        p = (me +>:Knows(how_met="test"):+> Person(name=self.name))[0];
        report p;
    }
}
