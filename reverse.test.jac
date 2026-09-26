"""Tests for reverse.sv.jac (SOH-198, WhoNeedsWhatIHave — the reverse ask).

Annex to reverse.sv.jac — run with `jac test reverse.sv.jac`. Deterministic
only: no LLM (the scorer's fallback path is never exercised here — we hand-
build `scored` directly instead), no server. Per AGENTS.md's Tend-specific
gotcha ("never take `[root --> [?:Me]][0]` in a helper tests call, and every
test shares ONE persisted root"), every test here calls `select_candidates` /
`assemble` directly on hand-built `IntroRequest` nodes and hand-built `scored`
dicts, never `root spawn WhoNeedsWhatIHave(...)` — so one test's fixtures
never leak into another's assertions, and no per-run name suffix is needed.

`assemble` re-derives the same candidate set `select_candidates` produces
(own/declined/expired excluded, newest-first, capped at `limit`), so testing
`assemble` alone exercises both.
"""

import from reverse { select_candidates, assemble, bounded, REVERSE_MAX_LIMIT }
import from schema { IntroRequest }


def _req(need: str, from_handle: str, created_at: str, status: str = "open", expires_at: str = "") -> IntroRequest {
    return (root ++> IntroRequest(
        need=need,
        from_handle=from_handle,
        about_line="",
        status=status,
        created_at=created_at,
        expires_at=expires_at
    ))[0];
}

def _match(strength: str, why: str = "some reason") -> dict[str, any] {
    return {"person_id": "p", "strength": strength, "why": why, "evidence_ids": []};
}

def _needs(result: list[dict[str, any]]) -> list[str] {
    return [(item["request"] as IntroRequest).need for item in result];
}

test "select_candidates: own requests excluded, declined excluded, expired excluded, newest-first, capped at limit" {
    mine = _req("my own need", "me-handle", "2026-09-26T09:00:00");
    declined = _req("declined need", "other-handle", "2026-09-26T10:00:00", status="declined");
    expired = _req("expired need", "other-handle", "2026-09-26T08:00:00", expires_at="2026-09-25T00:00:00");
    older = _req("older need", "other-handle", "2026-09-26T09:30:00");
    newer = _req("newer need", "other-handle", "2026-09-26T11:00:00");

    requests = [mine, declined, expired, older, newer];
    my_request_ids = [jid(mine)];
    now = "2026-09-26T12:00:00";

    result = select_candidates(requests, my_request_ids, now, 5);
    needs = [r.need for r in result];
    assert needs == ["newer need", "older need"], f"got {needs}";

    capped = select_candidates(requests, my_request_ids, now, 1);
    assert [r.need for r in capped] == ["newer need"], "limit must cap the scored candidate set";
}

test "assemble: match_count and strength come from the best kept (strong/medium) match; weak alone counts as zero" {
    strong_req = _req("needs a strong match", "h1", "2026-09-26T09:00:00");
    medium_req = _req("needs a medium match", "h2", "2026-09-26T08:00:00");
    weak_only_req = _req("needs only a weak match", "h3", "2026-09-26T07:00:00");
    no_match_req = _req("needs nothing found", "h4", "2026-09-26T06:00:00");

    requests = [strong_req, medium_req, weak_only_req, no_match_req];
    scored = {
        jid(strong_req): [_match("weak"), _match("strong", "cites evidence 0"), _match("medium")],
        jid(medium_req): [_match("weak"), _match("medium", "cites evidence 1")],
        jid(weak_only_req): [_match("weak"), _match("weak")],
        jid(no_match_req): []
    };

    result = assemble(requests, scored, [], [], "2026-09-26T12:00:00", 10);
    by_need = {(item["request"] as IntroRequest).need: item for item in result};

    strong_entry = by_need["needs a strong match"];
    assert strong_entry["strength"] == "strong";
    assert strong_entry["match_count"] == 2, "both the strong and medium matches are kept, weak is not";
    assert strong_entry["top_why"] == "cites evidence 0";

    medium_entry = by_need["needs a medium match"];
    assert medium_entry["strength"] == "medium";
    assert medium_entry["match_count"] == 1;
    assert medium_entry["top_why"] == "cites evidence 1";

    weak_entry = by_need["needs only a weak match"];
    assert weak_entry["strength"] == "weak";
    assert weak_entry["match_count"] == 0, "a weak-only match never counts toward match_count";
    assert weak_entry["top_why"] == "";

    none_entry = by_need["needs nothing found"];
    assert none_entry["strength"] == "weak";
    assert none_entry["match_count"] == 0;
    assert none_entry["top_why"] == "";
}

test "assemble: entries with match_count == 0 are still returned, ordered strong -> medium -> weak, newest-first within each bucket" {
    weak_new = _req("weak new", "h", "2026-09-26T12:00:00");
    weak_old = _req("weak old", "h", "2026-09-26T09:00:00");
    strong_new = _req("strong new", "h", "2026-09-26T11:00:00");
    strong_old = _req("strong old", "h", "2026-09-26T10:00:00");
    medium_only = _req("medium only", "h", "2026-09-26T08:00:00");
    zero_match = _req("zero match", "h", "2026-09-26T07:00:00");

    requests = [weak_new, weak_old, strong_new, strong_old, medium_only, zero_match];
    scored = {
        jid(weak_new): [_match("weak")],
        jid(weak_old): [_match("weak")],
        jid(strong_new): [_match("strong")],
        jid(strong_old): [_match("strong")],
        jid(medium_only): [_match("medium")],
        jid(zero_match): []
    };

    result = assemble(requests, scored, [], [], "2026-09-26T13:00:00", 10);
    needs = _needs(result);
    assert needs == [
        "strong new", "strong old", "medium only",
        "weak new", "weak old", "zero match"
    ], f"got {needs}";
    assert result[-1]["match_count"] == 0, "a zero-match entry is still returned, at weak strength";
}

test "assemble: already_replied reflects a shared reply request_id owned by me; limit truncates before scoring/ordering" {
    r1 = _req("need one", "h1", "2026-09-26T11:00:00");
    r2 = _req("need two", "h2", "2026-09-26T10:00:00");
    r3 = _req("need three", "h3", "2026-09-26T09:00:00");

    requests = [r1, r2, r3];
    scored = {
        jid(r1): [_match("strong")],
        jid(r2): [_match("medium")],
        jid(r3): [_match("strong")]
    };
    replied_request_ids = [jid(r2)];

    result = assemble(requests, scored, [], replied_request_ids, "2026-09-26T12:00:00", 10);
    by_need = {(item["request"] as IntroRequest).need: item for item in result};
    assert not by_need["need one"]["already_replied"];
    assert by_need["need two"]["already_replied"];
    assert not by_need["need three"]["already_replied"];

    # limit=2 caps the CANDIDATE set (newest-first) before anything else, so
    # "need three" (oldest) never appears even though it would score strong.
    capped = assemble(requests, scored, [], replied_request_ids, "2026-09-26T12:00:00", 2);
    assert _needs(capped) == ["need one", "need two"], f"got {_needs(capped)}";
}

test "assemble: own requests never appear even if they would otherwise score" {
    mine = _req("my own need", "me", "2026-09-26T11:00:00");
    theirs = _req("their need", "them", "2026-09-26T10:00:00");
    requests = [mine, theirs];
    scored = {jid(mine): [_match("strong")], jid(theirs): [_match("strong")]};

    result = assemble(requests, scored, [jid(mine)], [], "2026-09-26T12:00:00", 10);
    assert _needs(result) == ["their need"], f"got {_needs(result)}";
}

test "SOH-211: WhoNeedsWhatIHave's limit is clamped to [0, 25] before it drives model calls" {
    assert REVERSE_MAX_LIMIT == 25;
    assert bounded(1000, REVERSE_MAX_LIMIT) == 25;
    assert bounded(5, REVERSE_MAX_LIMIT) == 5;
    assert bounded(-3, REVERSE_MAX_LIMIT) == 0;
}
