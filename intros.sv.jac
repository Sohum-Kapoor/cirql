"""AdvanceIntroduction — the Introduction state machine (+ a dev creator).

OWNER: Person A. See contracts/walkers.md `AdvanceIntroduction(intro_id, to_state,
approval_source)` for the exact report shape. Matchmaker is DEFERRED (SOH-171) —
not built here. `sent` is unreachable this weekend: any transition to it is
rejected, deterministically, regardless of the current state.
"""

import from datetime { datetime }
import from schema { Me, Person, Knows, Introduction, Proposes }

# ---------------------------------------------------------------- state machine

glob NON_TERMINAL_STATES: list[str] = ["proposed", "reviewed", "awaiting_permission", "approved", "draft_ready"];
glob ANY_STATE_EXITS: list[str] = ["declined", "canceled", "expired"];
glob FORWARD_TRANSITIONS: dict[str, str] = {
    "proposed": "reviewed",
    "reviewed": "awaiting_permission",
    "awaiting_permission": "approved",
    "approved": "draft_ready"
};

# Deterministic transition map. `sent` is unreachable this weekend: rejected
# from every state. Terminal states (declined | canceled | expired) accept no
# further transitions. Moving to `approved` requires approval_source to be
# "offline" or "in_app".
def is_valid_transition(from_state: str, to_state: str, approval_source: str) -> bool {
    if to_state == "sent" {
        return False;
    }
    if from_state not in NON_TERMINAL_STATES {
        return False;
    }
    if to_state != "approved" and approval_source != "" {
        return False;   # approval_source only ever applies to an approved transition
    }
    if to_state in ANY_STATE_EXITS {
        return True;
    }
    if to_state not in NON_TERMINAL_STATES {
        return False;
    }
    if FORWARD_TRANSITIONS.get(from_state) != to_state {
        return False;
    }
    if to_state == "approved" and approval_source != "offline" and approval_source != "in_app" {
        return False;
    }
    return True;
}

# ---------------------------------------------------------------- walkers

walker:priv AdvanceIntroduction {
    """Advance one Introduction under the caller's root through the state
    machine. Always reports exactly one { ok, introduction, error, from, to }."""
    has intro_id: str;
    has to_state: str;
    has approval_source: str = "";
    has reports: list[dict] = [];

    can go with Root entry {
        found: Introduction | None = None;
        for i in [root --> [?:Introduction]] {
            if jid(i) == self.intro_id {
                found = i;
            }
        }
        if found is None {
            report {"ok": False, "introduction": None, "error": "not_found", "from": "", "to": self.to_state};
        } else {
            intro = found as Introduction;
            from_state = intro.state;
            if is_valid_transition(from_state, self.to_state, self.approval_source) {
                if self.to_state == "approved" {
                    intro.approval_source = self.approval_source;
                }
                intro.state = self.to_state;
                report {"ok": True, "introduction": intro, "error": None, "from": from_state, "to": self.to_state};
            } else {
                report {"ok": False, "introduction": None, "error": "invalid_transition", "from": from_state, "to": self.to_state};
            }
        }
    }
}

walker:priv DevProposeIntroduction {
    """Dev/test helper, not for the client: creates
    root ++> Introduction(state="proposed") with two Proposes edges to the
    given Person ids. Both must be under the caller's Me via Knows, else
    reports []."""
    has a_id: str;
    has b_id: str;
    has rationale_a: str = "";
    has rationale_b: str = "";
    has reports: list[Introduction] = [];

    can go with Root entry {
        a_node: Person | None = None;
        b_node: Person | None = None;
        for p in [root --> [?:Me] ->:Knows:->] {
            if jid(p) == self.a_id {
                a_node = p;
            }
            if jid(p) == self.b_id {
                b_node = p;
            }
        }
        if a_node is not None and b_node is not None {
            a = a_node as Person;
            b = b_node as Person;
            now = datetime.now().isoformat();
            intro = (root ++> Introduction(
                state="proposed",
                rationale_a=self.rationale_a,
                rationale_b=self.rationale_b,
                created_at=now
            ))[0];
            intro +>:Proposes:+> a;
            intro +>:Proposes:+> b;
            report intro;
        }
    }
}
