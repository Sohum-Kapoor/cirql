"""Walkers — the API the client calls with `root spawn`.

OWNER: Person A. One file per walker family is fine once this grows
(see `jac guide jac-impl-files`); keep report shapes matching contracts/walkers.md.

Every walker here is `:priv` (JWT required, runs on the caller's own root) except
PublishCard's public read, which lives in server/card_public.jac.
"""

import from schema { Me, Person, Knows, Goal, HasGoal, Card, Owns }

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
    """Report every Person the caller knows (Me -Knows-> Person)."""
    has reports: list[Person] = [];

    can collect with Root entry {
        for p in [root --> [?:Me] ->:Knows:->] {
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
