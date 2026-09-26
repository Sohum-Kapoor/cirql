"""Freshness — facts age, intents expire (SOH-190).

OWNER: Person A. See contracts/walkers.md for the exact report shapes and
AGENTS.md for the working rules this file must obey:
  - Relationships never decay: nothing here touches `Knows` or lowers a
    Person. Only `Fact.status` and `Intent.expires_at`/`Fact.valid_to` are
    ever written.
  - A stale fact is FLAGGED, never deleted automatically — `FreshnessSweep`
    only ever sets `Fact.status = "stale"`; `ReconfirmFact` is how a user
    corrects that.
  - An expired intent is reported so callers can act on it (or reconfirm),
    never deleted. `GoalRank`'s `gather_evidence` (goals.sv.jac) already
    skips an intent whose `expires_at` is in the past.
  - `default_expiry` is imported by `capture.sv.jac` and `onboard.sv.jac` to
    give a newly-created Intent with no `expires_at` a sane default. This
    module imports neither of them (no cycle): it only depends on `schema`
    and `datetime`.
  - Every walker here is `:priv` (own-root only, JWT required). No `by llm`
    anywhere in this module.
"""

import from datetime { datetime, timedelta }
import from jaclang { JacRuntime as Jac }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Introduction,
    Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, Knows, Reported, RelevantTo,
    HasIntent, HasGoal, Proposes
}

# ---------------------------------------------------------------- helpers

"""Parse an ISO-8601 timestamp permissively: strips a trailing "Z" and drops
any tzinfo so comparisons against `datetime.now()` (naive) never raise.
Returns None on anything unparsable instead of propagating (unparsable dates
are skipped, never flagged). Mirrors `goals.sv.jac`'s `_parse_naive_utc` —
duplicated here rather than imported so this module stays free of any
dependency other than `schema`/`datetime`."""
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

"""Default expiry for a newly-created Intent with no `expires_at`: a `need`
is time-boxed tighter (90 days) than an `offer`/`open_to` (180 days) — a
need that goes unmet should surface as expired sooner than a standing offer.
Returns the same ISO-8601 shape as `datetime.now().isoformat()`. Exposed for
`capture.sv.jac` and `onboard.sv.jac` to import."""
def default_expiry(kind: str, now: datetime) -> str {
    days = 90 if kind == "need" else 180;
    return (now + timedelta(days=days)).isoformat();
}

"""jobj that never raises; resolves ANY node and NEVER authorizes.
Ownership idiom mirrored from `reads.sv.jac` (`load`/`owner_root`/
`readable`/`my_node`) rather than imported, to keep this module's only
cross-file dependency on `schema`."""
def _load(some_id: str) -> object {
    try {
        return jobj(some_id);
    } except Exception {
        return None;
    }
}

def _owner_root(n: object) -> str {
    return str(getattr(n, "__jac__").root).replace("-", "");
}

def _readable(n: object) -> bool {
    return bool(Jac.check_read_access(getattr(n, "__jac__")));  # jac:ignore[E1053]
}

"""Resolve `some_id` to a node that is BOTH readable AND owned by the
caller's own root; None on any miss (unknown id, wrong owner, no read grant)."""
def _my_node(some_id: str) -> object {
    n = _load(some_id);
    if n is None {
        return None;
    }
    if not _readable(n) {
        return None;
    }
    if _owner_root(n) != jid(root) {
        return None;
    }
    return n;
}

def _not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

# ---------------------------------------------------------------- walkers

walker:priv FreshnessSweep {
    """Flags stale facts, lists expired intents. Never deletes anything —
    GoalRank/scoring already skip an intent past its `expires_at`
    (goals.sv.jac `gather_evidence`). Idempotent: a fact already
    `status == "stale"` is left alone (still counted in `checked_facts`),
    so a second sweep flags nothing new."""
    has stale_after_days: int = 180;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        now = datetime.now();

        # Facts reachable from the caller's own Notes, deduped by jid.
        raw_facts: list[Fact] = [root --> [?:Note] ->:Asserts:->];
        seen_fact_ids: list[str] = [];
        stale_facts: list[Fact] = [];
        checked_facts = 0;

        for f in raw_facts {
            fid = jid(f);
            if fid in seen_fact_ids {
                continue;
            }
            seen_fact_ids.append(fid);
            checked_facts += 1;

            if f.status == "stale" {
                continue;
            }

            is_stale = False;

            if f.valid_to {
                valid_to_dt = _parse_naive_utc(f.valid_to);
                if valid_to_dt is not None and valid_to_dt < now {
                    is_stale = True;
                }
            }

            observed_dt = _parse_naive_utc(f.observed_at);
            if observed_dt is not None {
                age_days = (now - observed_dt).days;
                if age_days > self.stale_after_days {
                    is_stale = True;
                }
            }

            if is_stale {
                f.status = "stale";
                stale_facts.append(f);
            }
        }

        # Intents reachable via AssertsIntent (debrief-captured) or
        # HasIntent (self-onboarded), deduped by jid. Walks every
        # `Me -> HasIntent -> Intent` under root rather than "the one Me"
        # (`[root --> [?:Me]][0]`) deliberately: `:priv` walkers only ever
        # run on the caller's own root, so in real (single-tenant) use
        # there is exactly one Me anyway, and this form sidesteps the
        # "the one Me" ambiguity `reads.test.jac` documents for a shared,
        # persisted test root (`jac-testing`).
        raw_intents: list[Intent] = [root --> [?:Note] ->:AssertsIntent:->];
        raw_intents += [root --> [?:Me] ->:HasIntent:->];

        seen_intent_ids: list[str] = [];
        expired_intents: list[Intent] = [];
        checked_intents = 0;

        for i in raw_intents {
            iid = jid(i);
            if iid in seen_intent_ids {
                continue;
            }
            seen_intent_ids.append(iid);
            checked_intents += 1;

            if not i.expires_at {
                continue;   # no expiry set -> never flagged
            }
            exp_dt = _parse_naive_utc(i.expires_at);
            if exp_dt is None {
                continue;   # unparsable -> skipped, never flagged
            }
            if exp_dt < now {
                expired_intents.append(i);
            }
        }

        report {
            "stale_facts": stale_facts,
            "expired_intents": expired_intents,
            "checked_facts": checked_facts,
            "checked_intents": checked_intents
        };
    }
}

walker:priv ReconfirmFact {
    """The user corrects a stale (or any) fact: re-confirms it, bumps
    `observed_at` to now, and optionally sets a new `valid_to`. Ownership
    idiom as `Receipt` (reads.sv.jac): `[{error: "not_found"}]` for an
    unknown id or one owned by a different root."""
    has fact_id: str;
    has valid_to: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        n = _my_node(self.fact_id);
        if n is None or not isinstance(n, Fact) {
            report _not_found();
            disengage;
        }
        f = n as Fact;
        f.status = "confirmed";
        f.observed_at = datetime.now().isoformat();
        if self.valid_to {
            f.valid_to = self.valid_to;
        }
        report f;
    }
}

walker:priv ReconfirmIntent {
    """The user renews an intent: sets `expires_at` to the given value, or
    `default_expiry(kind, now)` when none is given. Same ownership idiom
    as `ReconfirmFact`."""
    has intent_id: str;
    has expires_at: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        n = _my_node(self.intent_id);
        if n is None or not isinstance(n, Intent) {
            report _not_found();
            disengage;
        }
        it = n as Intent;
        if self.expires_at {
            it.expires_at = self.expires_at;
        } else {
            it.expires_at = default_expiry(it.kind, datetime.now());
        }
        report it;
    }
}
