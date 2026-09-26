"""WhoNeedsWhatIHave — the reverse ask (SOH-198, Tier 2 #28): PostRequest
(exchange.sv.jac) broadcasts a need; this walker answers "who out there needs
what I have?" by scoring every OTHER open, non-expired shared IntroRequest
against the caller's own network.

OWNER: Person A. See contracts/walkers.md `WhoNeedsWhatIHave` for the exact
report shape.

Product rules this file must obey (AGENTS.md + SOH-198):
  - Runs on the CALLER'S OWN ROOT ONLY. It only ever READS the shared
    Exchange (`all_requests`, `shared_replies`, both reused from
    `exchange.sv.jac`) and scores against the caller's own graph
    (`scoring.sv.jac`'s `score_against_need`) — it never writes to another
    root, never creates an `IntroReply`.
  - It NEVER posts a reply itself. `ReplyToRequest` (exchange.sv.jac) is the
    only walker that does that; this one only surfaces candidates for the
    user to act on.
  - It never names the requester beyond `IntroRequest.from_handle` — the
    same redaction the rest of the Exchange already enforces (no identity
    until every party has approved).
  - One `by llm` call PER REQUEST SCORED (via `score_against_need`), so the
    number of requests scored per call is capped at `limit` — the candidate
    list is filtered, sorted newest-first, and truncated to `limit` BEFORE
    any scoring happens (`select_candidates`).
  - `dry_run` is reserved for a future "post this reply for me" action; it
    changes nothing this weekend (this walker never posts either way) and is
    accepted only so the client can pass it now and mean something later.

`select_candidates` / `assemble` are kept as plain `def`s (not walker methods)
so `reverse.test.jac` can exercise the ordering / limit / already_replied /
exclusion rules directly on hand-built `IntroRequest` nodes, without an LLM
and without a multi-user JacTestClient harness (score results are hand-built
too, keyed by request jid, exactly like `score_against_need`'s own output
shape: `{"person_id", "strength", "why", "evidence_ids"}`).
"""

import from schema { Me, IntroRequest, IntroReply }
import from exchange { all_requests, shared_replies, owner_root, my_me, now_iso }
import from scoring { score_against_need }


# ---------------------------------------------------------------- deterministic helpers

"""Sort key for newest-`created_at`-first ordering (`PostRequest` always
sets `created_at` to `datetime.now().isoformat()`, so plain string comparison
orders correctly)."""
def _created_at_key(req: IntroRequest) -> str {
    return req.created_at;
}

"""Every request in `requests` that is: not posted by me (`my_request_ids`),
not declined, and not expired (`expires_at` set and `< now`) — same filter
`ListIncomingRequests` (exchange.sv.jac) applies, MINUS its "not yet answered
by me" exclusion (WhoNeedsWhatIHave wants to show already-answered requests
too, flagged via `already_replied`, not hide them). Sorted newest-first, then
capped at `limit` — this is the exact set that gets scored, so the model-call
budget is bounded by `limit` regardless of how many requests are open."""
def select_candidates(requests: list[IntroRequest], my_request_ids: list[str], now: str, limit: int) -> list[IntroRequest] {
    kept: list[IntroRequest] = [];
    for req in requests {
        if jid(req) in my_request_ids {
            continue;
        }
        if req.status == "declined" {
            continue;
        }
        if req.expires_at and req.expires_at < now {
            continue;
        }
        kept.append(req);
    }
    ordered = sorted(kept, key=_created_at_key, reverse=True);
    if len(ordered) > limit {
        ordered = ordered[:limit];
    }
    return ordered;
}

"""Deterministic assembly: re-derives the exact same candidate set
`select_candidates` produced (own/declined/expired excluded, newest-first,
capped at `limit`) and, for each, folds its pre-computed `scored[jid]` (one
`score_against_need`-shaped list — `{"strength","why",...}` per matched
person in MY graph) down to the report shape. Kept apart from the walker so
`reverse.test.jac` can hand-build `requests` + `scored` and assert ordering /
limit / already_replied / exclusions without any LLM or server.

  - `kept` = matches with strength `strong` or `medium` (`weak` never counts
    toward `match_count`, matching `ReplyToRequest`'s own `kept` idiom).
  - `strength` = the best kept match's strength, else `"weak"`.
  - `top_why` = the best kept match's `why`, else `""`.
  - A request with `match_count == 0` is STILL returned (strength `"weak"`)
    so the user sees what's out there, not just what's promising.
  - `already_replied` = a shared `IntroReply` for that request, owned by me,
    exists (`replied_request_ids`, computed by the walker from
    `shared_replies()`).
  - Final order: strong -> medium -> weak, newest-first within each bucket
    (the bucket append preserves `select_candidates`'s newest-first order,
    so no second sort is needed here)."""
def assemble(
    requests: list[IntroRequest],
    scored: dict[str, list[dict[str, any]]],
    my_request_ids: list[str],
    replied_request_ids: list[str],
    now: str,
    limit: int
) -> list[dict[str, any]] {
    candidates = select_candidates(requests, my_request_ids, now, limit);

    strong: list[dict[str, any]] = [];
    medium: list[dict[str, any]] = [];
    weak: list[dict[str, any]] = [];

    for req in candidates {
        rid = jid(req);
        if rid in scored {
            matches = scored[rid];
        } else {
            matches = [];
        }
        kept = [m for m in matches if m["strength"] == "strong" or m["strength"] == "medium"];
        strength = "weak";
        top_why = "";
        if kept {
            strength = str(kept[0]["strength"]);
            top_why = str(kept[0]["why"]);
        }
        entry = {
            "request": req,
            "match_count": len(kept),
            "strength": strength,
            "top_why": top_why,
            "already_replied": rid in replied_request_ids
        };
        if strength == "strong" {
            strong.append(entry);
        } elif strength == "medium" {
            medium.append(entry);
        } else {
            weak.append(entry);
        }
    }

    return strong + medium + weak;
}

# ---------------------------------------------------------------- walker

walker:priv WhoNeedsWhatIHave {
    """The reverse ask: score every other open, non-expired shared
    IntroRequest against MY graph and report who I could help, strongest
    first. Own root only; never posts a reply. See module docstring and
    contracts/walkers.md for the exact rules and shape."""
    has limit: int = 5;
    has dry_run: bool = True;
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        m = my_me();
        if m is None {
            return;
        }
        me = m as Me;
        me_root = jid(root);
        now = now_iso();

        requests = all_requests();
        my_request_ids = [jid(r) for r in requests if owner_root(r) == me_root];
        candidates = select_candidates(requests, my_request_ids, now, self.limit);

        scored: dict[str, list[dict[str, any]]] = {};
        for req in candidates {
            scored[jid(req)] = score_against_need(me, req.need, [req.from_handle]);
        }

        replied_request_ids = [r.request_id for r in shared_replies() if owner_root(r) == me_root];

        results = assemble(requests, scored, my_request_ids, replied_request_ids, now, self.limit);
        for r in results {
            report r;
        }
    }
}
