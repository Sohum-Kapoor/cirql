"""NotedCard + ApplyCorrection — "Here's what I noted" (SOH-184).

OWNER: Person A. See contracts/walkers.md for the exact report shapes. Both
walkers are `:priv` (own-root only, JWT required); no `by llm` anywhere in
this module. `person_id` is resolved the same way `drafts.sv.jac`'s
`DraftFollowUp` resolves it: directly among `[me ->:Knows:->]` — a person
only reaches that traversal if this account's own Capture/Import/Confirm
flow created the Knows edge, i.e. "belongs to the caller". An unresolvable
id reports `not_found`; this is the tight, already-scoped check (no need
for `reads.sv.jac`'s fuller jobj/owner_root idiom, which is for resolving
*arbitrary* ids — this walker never needs to).

Rules from AGENTS.md this file must obey:
  - Nothing sends: `share_text` is a plain string the user copies by hand.
    No send button, no side effect beyond what's described below.
  - Every Fact/Intent tie carries its own provenance: a fresh `Note` plus
    `Asserts`/`AssertsIntent` + `FactAbout`/`IntentAbout` edges, same shape
    `capture.sv.jac` writes. `ApplyCorrection` only ever ADDS a node or flips
    an existing Fact's `status` to `"stale"` — never deletes anything.
  - `Knows.last_contact` is never read here.
  - No scores, no relevance words in `share_text` (relevance lives on
    `RelevantTo`, never on a Person — PRD/AGENTS.md).
  - `default_expiry` is imported from `freshness.sv.jac`, the same helper
    `capture.sv.jac`/`onboard.sv.jac` use, rather than reimplemented.
"""

import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise,
    Knows, Asserts, AssertsIntent, FactAbout, IntentAbout, PromiseTo
}
import from freshness { default_expiry }
import from names { display_how_met }

# ---------------------------------------------------------------- errors

def not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

def bad_kind() -> dict[str, str] {
    return {"error": "bad_kind"};
}

def valid_correction_kinds() -> list[str] {
    return ["fact", "need", "offer", "open_to"];
}

# ---------------------------------------------------------------- lookups

"""Same resolution `drafts.sv.jac`'s `DraftFollowUp` uses: `person_id` must
be directly among the caller's own `[me ->:Knows:->]`."""
def find_known_person(me: Me, person_id: str) -> Person | None {
    matches = [p for p in [me ->:Knows:->] if jid(p) == person_id];
    if not matches {
        return None;
    }
    return matches[0];
}

def how_met_for(me: Me, p: Person) -> str {
    edges = [edge me ->:Knows:-> p];
    if edges {
        return display_how_met(edges[0].how_met);
    }
    return "";
}

def gather_person_facts(p: Person) -> list[Fact] {
    facts: list[Fact] = [p <-:FactAbout:<-];
    return facts;
}

def gather_person_intents(p: Person) -> list[Intent] {
    intents: list[Intent] = [p <-:IntentAbout:<-];
    return intents;
}

def gather_person_promises(p: Person) -> list[Promise] {
    promises: list[Promise] = [p <-:PromiseTo:<-];
    return promises;
}

# ---------------------------------------------------------------- dict shapes

def fact_to_dict(f: Fact) -> dict[str, any] {
    return {"id": jid(f), "text": f.text, "observed_at": f.observed_at, "status": f.status};
}

def intent_to_dict(i: Intent) -> dict[str, any] {
    return {"id": jid(i), "kind": i.kind, "text": i.text, "expires_at": i.expires_at};
}

def promise_to_dict(pr: Promise) -> dict[str, any] {
    return {"id": jid(pr), "text": pr.text, "due": pr.due, "done": pr.done};
}

# ---------------------------------------------------------------- share_text

"""Permissive ISO-8601 parse mirroring `freshness.sv.jac`'s own
`_parse_naive_utc` (duplicated rather than imported — that def is private to
its module; this module's only cross-file dependency stays `default_expiry`).
Returns None on anything unparsable rather than raising."""
def _parse_naive_utc(ts: str) -> datetime | None {
    if not ts {
        return None;
    }
    cleaned = ts;
    if cleaned.endswith("Z") {
        cleaned = cleaned[:-1];
    }
    try {
        dt = datetime.fromisoformat(cleaned);
    } except (ValueError, TypeError) {
        return None;
    }
    if dt.tzinfo is not None {
        dt = dt.replace(tzinfo=None);
    }
    return dt;
}

def intent_prefix(kind: str) -> str {
    if kind == "need" {
        return "looking for:";
    }
    if kind == "offer" {
        return "can offer:";
    }
    return "open to:";
}

"""Plain-text message the user can paste to the person: an intro line, one
line per non-stale Fact and non-expired Intent, and a closing line. Never a
Promise (those are the caller's own commitments, not the person's to
correct) and never a score/relevance word."""
def build_share_text(p: Person, facts: list[Fact], intents: list[Intent], now: datetime) -> str {
    lines: list[str] = [f"Hi {p.name}, here's what I have noted about you so I get it right. Correct anything:"];

    for f in facts {
        if f.status == "stale" {
            continue;
        }
        date_part = f.observed_at[:10] if f.observed_at else "";
        if date_part {
            lines.append(f"- {f.text} (noted {date_part})");
        } else {
            lines.append(f"- {f.text}");
        }
    }

    for i in intents {
        if i.expires_at {
            exp_dt = _parse_naive_utc(i.expires_at);
            if exp_dt is not None and exp_dt < now {
                continue;
            }
        }
        lines.append(f"- {intent_prefix(i.kind)} {i.text}");
    }

    lines.append("Reply with fixes and I'll update my notes.");
    return "\n".join(lines);
}

# ---------------------------------------------------------------- NotedCard

"""Deterministic, testable directly on hand-built nodes: the card-on-them
plus its `share_text`. See contracts/walkers.md for the exact shape."""
def noted_card_for(me: Me, p: Person) -> dict[str, any] {
    facts = gather_person_facts(p);
    intents = gather_person_intents(p);
    promises = gather_person_promises(p);
    now = datetime.now();
    return {
        "person": p,
        "facts": [fact_to_dict(f) for f in facts],
        "intents": [intent_to_dict(i) for i in intents],
        "promises": [promise_to_dict(pr) for pr in promises],
        "how_met": how_met_for(me, p),
        "share_text": build_share_text(p, facts, intents, now)
    };
}

walker:priv NotedCard {
    """Reports one dict (see `noted_card_for`), or `{ error: "not_found" }`
    when `person_id` isn't one of the caller's own known people."""
    has person_id: str;
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report not_found();
            disengage;
        }
        me = existing[0];

        person = find_known_person(me, self.person_id);
        if person is None {
            report not_found();
            disengage;
        }

        report noted_card_for(me, person);
    }
}

# ---------------------------------------------------------------- ApplyCorrection

"""Deterministic, testable directly on a hand-built Person (no Me/walker
needed): writes the correction Note + Fact/Intent + edges, and — for a fact
naming `replace_fact_id` — flips the old Fact's status to `"stale"` (never
deletes it). Returns `{ "fact": Fact }` or `{ "intent": Intent }`. Caller
(the walker below) has already validated `kind` and resolved `person`."""
def apply_correction_for(person: Person, text: str, replace_fact_id: str, kind: str, now_dt: datetime, replace_intent_id: str = "") -> dict[str, any] {
    now = now_dt.isoformat();
    note = (root ++> Note(kind="correction", text=text, captured_at=now))[0];

    # SOH-166: an Intent has no status, so "stale, never deleted" means its
    # expires_at is set to now (same ISO shape freshness writes).
    if replace_intent_id {
        for old_it in [person <-:IntentAbout:<-] {
            if jid(old_it) == replace_intent_id {
                old_it.expires_at = now;
            }
        }
    }

    if kind == "fact" {
        f = (note +>:Asserts(span=text):+> Fact(
            text=text, observed_at=now, status="confirmed", source_kind="self"
        ))[0];
        f +>:FactAbout:+> person;

        if replace_fact_id {
            for old in gather_person_facts(person) {
                if jid(old) == replace_fact_id {
                    old.status = "stale";
                }
            }
        }

        return {"fact": f};
    }

    it = (note +>:AssertsIntent(span=text):+> Intent(
        kind=kind, text=text, source_kind="self",
        expires_at=default_expiry(kind, now_dt)
    ))[0];
    it +>:IntentAbout:+> person;
    return {"intent": it};
}

walker:priv ApplyCorrection {
    """Records what the person told you back as SELF-asserted. Reports
    `[{ fact: Fact }]` or `[{ intent: Intent }]`, or `[{ error: "not_found" }]`
    / `[{ error: "bad_kind" }]`. `kind` is validated BEFORE `person_id` is
    resolved, so a bad kind is reported the same way regardless of whether
    the caller also got the person id right. See contracts/walkers.md."""
    has person_id: str;
    has text: str;
    has replace_fact_id: str = "";
    has replace_intent_id: str = "";   # SOH-166: expire this Intent (expires_at = now) and add the replacement
    has kind: str = "fact";
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        if self.kind not in valid_correction_kinds() {
            report bad_kind();
            disengage;
        }

        existing = [root --> [?:Me]];
        if not existing {
            report not_found();
            disengage;
        }
        me = existing[0];

        person = find_known_person(me, self.person_id);
        if person is None {
            report not_found();
            disengage;
        }

        now_dt = datetime.now();
        report apply_correction_for(person, self.text, self.replace_fact_id, self.kind, now_dt, replace_intent_id=self.replace_intent_id);
    }
}
