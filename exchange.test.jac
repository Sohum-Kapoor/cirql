"""Tests for exchange.sv.jac (SOH-205, the Exchange).

Annex to exchange.sv.jac — run with `jac test exchange.sv.jac`.

Same harness as gate.test.jac / walkers.test.jac: JacTestClient cannot target
a dotted `*.sv.jac` file, so each test copies the live server modules into a
fresh temp dir next to a dot-free `exapp.jac` (not `app.jac`: cards.test.jac, pulled in via exchange -> cards, already cached a module named `app`) and gives the client its own
base_path. No `jac clean` anywhere.

Accounts: A = requester, B = friend, C = bystander, each a REAL registered
account; every walker call runs on that user's own root. The temp dir has no
`.env`, so every `by llm` call fails fast and the deterministic fallbacks run
(OnboardMe still creates Me + Card; scoring uses its fallback; ClaimReveal's
draft uses its template).
"""

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import signal;
import socket;
import subprocess;
import tempfile;
import time;
import requests;
import sys;
import from exchange { request_closed, friend_handles, friend_entries, request_visible, norm_audience }
import from schema { IntroRequest, Me, Person, Knows, Card, FromCard }
import from scoring { NeedMatch, NeedMatches }

glob EX_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _ex_harness(tmp_dir: str) -> str {
    for name in ["exchange.sv.jac", "schema.sv.jac", "scoring.sv.jac", "onboard.sv.jac", "walkers.sv.jac", "cards.sv.jac", "llm.sv.jac", "freshness.sv.jac", "goals.sv.jac", "reads.sv.jac", "handshake.sv.jac"] {
        shutil.copyfile(os.path.join(EX_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "exapp.jac");
    f = open(harness_path, "w");
    f.write(
        "import from walkers { ListPeople, DevAddPerson }\n"
        "import from onboard { OnboardMe }\n"
        "import from exchange { PostRequest, ListIncomingRequests, ReplyToRequest, ListMyRequests, ListMyReplies, "
        "ApproveReply, OptIn, Reveal, ClaimReveal, DeclineRequest, DeclineReply, DevMakeCard, DevSeedMatch }\n"
        "import from cards { PublishCard }\n"
        "import from exchange { ListFriends, BlockHandle, UnblockHandle }\n"
        "import from handshake { OfferHandshake, AcceptHandshake, ListHandshakes }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"exchange-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"exapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _reg(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _run(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

"""OnboardMe (one LLM call; a Card is created even when extraction fails).
Falls back to the dev-only DevMakeCard if no Card came back. Returns the handle."""
def _card(client: JacTestClient, token: str, about: str, name: str) -> str {
    out = _run(client, token, "OnboardMe", {"about": about});
    if out and isinstance(out[0], dict) and isinstance(out[0].get("card"), dict) {
        h = str(out[0]["card"].get("handle", ""));
        if h {
            return h;
        }
    }
    made = _run(client, token, "DevMakeCard", {"handle": name.lower() + "-dev", "name": name});
    return str(made[0]["handle"]);
}

def _ids(x: any, acc: list[str]) -> list[str] {
    if isinstance(x, dict) {
        for (k, v) in x.items() {
            if k == "_jac_id" or k == "id" {
                acc.append(str(v));
            } else {
                _ids(v, acc);
            }
        }
    } elif isinstance(x, list) {
        for v in x {
            _ids(v, acc);
        }
    }
    return acc;
}

def _err(reports: list[any]) -> str {
    if len(reports) == 1 and isinstance(reports[0], dict) and "error" in reports[0] {
        return str(reports[0]["error"]);
    }
    return "";
}

"""SOH-211: the scorer's fallback is weak-only, so a model-free test can no
longer reach approve/opt-in/reveal through it. Stand in for the MODEL (not
the fallback): swap `score_need` in the in-process `scoring` module for a
stub that answers "medium, citing evidence 0" for every candidate, so
post_process still runs. Returns the original to restore in `finally`."""
def _stub_model_medium() -> any {
    mod = sys.modules.get("scoring");
    assert mod is not None, "scoring module not loaded in-process";
    orig = getattr(mod, "score_need");
    def fake(need: str, candidates_text: str) -> NeedMatches {
        n = candidates_text.count("Candidate ");
        return NeedMatches(items=[NeedMatch(index=i, strength="medium", why="Stub: evidence [0] fits.", evidence_indices=[0]) for i in range(n)]);
    }
    setattr(mod, "score_need", fake);
    return orig;
}

def _restore_model(orig: any) {
    mod = sys.modules.get("scoring");
    if mod is not None and orig is not None {
        setattr(mod, "score_need", orig);
    }
}

"""Make exchange.draft_intro raise so ClaimReveal uses intro_template; the
test must not depend on whatever a live model writes (a .env in the cwd
makes byLLM reachable in some runs)."""
def _stub_draft_fails() -> any {
    mod = sys.modules.get("exchange");
    assert mod is not None, "exchange module not loaded in-process";
    orig = getattr(mod, "draft_intro");
    def fake(*args: any) -> str {
        raise RuntimeError("model stubbed out in tests");
    }
    setattr(mod, "draft_intro", fake);
    return orig;
}

def _restore_draft(orig: any) {
    mod = sys.modules.get("exchange");
    if mod is not None and orig is not None {
        setattr(mod, "draft_intro", orig);
    }
}

test "exchange: J4 end to end, then isolation (only the granted Card crosses)" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a1@example.com");
        b = _reg(cl, "ex_b1@example.com");
        c = _reg(cl, "ex_c1@example.com");

        # B knows Priya, with a fact and an offer (dev seed; no LLM Capture).
        _run(cl, b, "DevAddPerson", {"name": "Priya Rao", "me_name": "Bob"});
        seeded = _run(cl, b, "DevSeedMatch", {
            "name": "Priya Rao",
            "fact": "Priya is a partner at a climate-tech seed fund.",
            "offer": "intros to climate-tech seed investors"
        });
        assert "person_id" in dict(seeded[0]), seeded;
        b_priya_id = str(seeded[0]["person_id"]);

        a_handle = _card(cl, a, "I'm Alice, building a battery-recycling startup.", "Alice");
        b_handle = _card(cl, b, "I'm Bob, I run a climate meetup.", "Bob");
        print(f"[ex] handles A={a_handle} B={b_handle}");
        a_reports: list[any] = [];

        # A posts.
        posted = _run(cl, a, "PostRequest", {"audience": "everyone", "need": "a climate-tech seed investor", "about_line": "Building battery recycling"});
        a_reports.extend(posted);
        req = posted[0];
        print(f"[ex] PostRequest -> {req}");
        assert str(req["status"]) == "open" and str(req["from_handle"]) == a_handle;
        req_id = str(req["_jac_id"]);

        # B and C both see it; A does not (own request).
        b_in = [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        c_in = [str(r["_jac_id"]) for r in _run(cl, c, "ListIncomingRequests", {})];
        a_in = [str(r["_jac_id"]) for r in _run(cl, a, "ListIncomingRequests", {})];
        assert req_id in b_in, b_in;
        assert req_id in c_in, c_in;
        assert req_id not in a_in, a_in;

        # B replies: count + strength, no identity. (Model stubbed; see _stub_model_medium.)
        orig = _stub_model_medium();
        try {
            rv = _run(cl, b, "ReplyToRequest", {"request_id": req_id})[0];
        } finally {
            _restore_model(orig);
        }
        print(f"[ex] ReplyToRequest -> {rv}");
        assert "match_person_id" not in dict(rv) and "revealed_card_id" not in dict(rv), rv;
        assert int(rv["match_count"]) >= 0 and str(rv["status"]) == "pending";
        assert int(rv["match_count"]) >= 1, f"seeded offer should keep Priya as medium+: {rv}";
        reply_id = str(rv["_jac_id"]);
        # replied -> no longer incoming for B; a second reply is refused
        assert req_id not in [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        assert _err(_run(cl, b, "ReplyToRequest", {"request_id": req_id})) == "invalid_state";

        # B's own replies, with the friend-private "why" (never in the view).
        b_mine = _run(cl, b, "ListMyReplies", {});
        assert len(b_mine) == 1, b_mine;
        assert str(b_mine[0]["reply"]["_jac_id"]) == reply_id, b_mine;
        assert str(b_mine[0]["request"]["_jac_id"]) == req_id, b_mine;
        assert len(str(b_mine[0]["why"])) > 0, b_mine;
        assert "why" not in dict(b_mine[0]["reply"]), b_mine;
        assert "match_person_id" not in dict(b_mine[0]["reply"]), b_mine;
        # A never sees B's replies here: ListMyReplies is friend-side, over MY OWN replies only.
        assert _run(cl, a, "ListMyReplies", {}) == [];

        # A sees one pending reply, redacted.
        mine = _run(cl, a, "ListMyRequests", {});
        a_reports.extend(mine);
        print(f"[ex] ListMyRequests -> {mine}");
        assert len(mine) == 1, mine;
        assert len(list(mine[0]["replies"])) == 1, mine;
        assert str(mine[0]["replies"][0]["status"]) == "pending";
        assert str(mine[0]["request"]["status"]) == "replied";
        assert "match_person_id" not in dict(mine[0]["replies"][0]);

        # Nothing to claim yet.
        assert _err(_run(cl, a, "ClaimReveal", {"reply_id": reply_id})) == "invalid_state";

        # B's clicks.
        ap = _run(cl, b, "ApproveReply", {"reply_id": reply_id})[0];
        assert str(ap["status"]) == "approved", ap;
        oi = _run(cl, b, "OptIn", {"reply_id": reply_id})[0];
        print(f"[ex] OptIn -> {oi}");
        assert str(oi["reply"]["status"]) == "opted_in" and len(str(oi["opt_in_draft"])) > 0;
        assert "Priya Rao" in str(oi["opt_in_draft"]);
        assert ".)" not in str(oi["opt_in_draft"]), oi["opt_in_draft"];
        rl = _run(cl, b, "Reveal", {"reply_id": reply_id})[0];
        print(f"[ex] Reveal -> {rl}");
        handle = str(rl["revealed_card_handle"]);
        assert handle and str(rl["reply"]["status"]) == "revealed";
        assert "match_person_id" not in dict(rl["reply"]) and "revealed_card_id" not in dict(rl["reply"]);

        # C (bystander) cannot claim.
        assert _err(_run(cl, c, "ClaimReveal", {"reply_id": reply_id})) == "forbidden";

        b_people_before = _run(cl, b, "ListPeople", {});

        # A claims.
        # Model-free: force ClaimReveal's draft onto its deterministic template.
        orig_draft = _stub_draft_fails();
        try {
            claimed = _run(cl, a, "ClaimReveal", {"reply_id": reply_id});
        } finally {
            _restore_draft(orig_draft);
        }
        a_reports.extend(claimed);
        print(f"[ex] ClaimReveal -> {claimed}");
        cr = claimed[0];
        assert str(cr["person"]["name"]) == "Priya Rao";
        assert str(cr["card"]["handle"]) == handle;
        assert len(str(cr["intro_draft"])) > 0;
        assert str(cr["card"]["name"]) in str(cr["intro_draft"]), cr["intro_draft"];
        assert "Alice" in str(cr["intro_draft"]), cr["intro_draft"];
        assert "[Name]" not in str(cr["intro_draft"]), cr["intro_draft"];
        card_id = str(cr["card"]["_jac_id"]);
        a_priya_id = str(cr["person"]["_jac_id"]);
        assert a_priya_id != b_priya_id;

        # Idempotent claim: no duplicate Person, and (SOH-211) the stored draft
        # comes back instead of a second draft.
        again = _run(cl, a, "ClaimReveal", {"reply_id": reply_id});
        assert str(again[0]["person"]["_jac_id"]) == a_priya_id;
        assert str(again[0]["intro_draft"]) == str(cr["intro_draft"]), again;
        assert str(again[0]["card"]["handle"]) == handle, again;

        mine2 = _run(cl, a, "ListMyRequests", {});
        a_reports.extend(mine2);
        assert str(mine2[0]["request"]["status"]) == "revealed", mine2;

        a_people = _run(cl, a, "ListPeople", {});
        a_reports.extend(a_people);
        print(f"[ex] A ListPeople -> {a_people}");
        assert [str(p["name"]) for p in a_people] == ["Priya Rao"], a_people;

        b_people = _run(cl, b, "ListPeople", {});
        assert [str(p["_jac_id"]) for p in b_people] == [str(p["_jac_id"]) for p in b_people_before];
        assert [str(p["name"]) for p in b_people] == ["Priya Rao"];

        # Isolation: no id A was shown belongs to a Person in B's graph; the
        # one foreign graph object A holds is the granted Card.
        b_ids = [str(p["_jac_id"]) for p in b_people];
        a_seen = _ids(a_reports, []);
        leaked = [i for i in a_seen if i in b_ids];
        assert leaked == [], f"B's person ids leaked to A: {leaked}";
        assert card_id in a_seen;
        for p in a_people {
            assert str(p["_jac_id"]) not in b_ids;
        }
        # SOH-211: a reply the friend declines after reveal can no longer be claimed.
        assert _run(cl, b, "DeclineReply", {"reply_id": reply_id}) == ["declined"];
        assert _err(_run(cl, a, "ClaimReveal", {"reply_id": reply_id})) == "reply_declined";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "exchange: state machine refuses skipped or foreign transitions" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a2@example.com");
        b = _reg(cl, "ex_b2@example.com");
        _run(cl, a, "DevMakeCard", {"handle": "alice-sm", "name": "Alice"});
        _run(cl, b, "DevMakeCard", {"handle": "bob-sm", "name": "Bob"});

        # no Card -> no_card
        c = _reg(cl, "ex_c2@example.com");
        assert _err(_run(cl, c, "PostRequest", {"audience": "everyone", "need": "x", "about_line": ""})) == "no_card";

        req_id = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "a designer", "about_line": "hi"})[0]["_jac_id"]);
        rv = _run(cl, b, "ReplyToRequest", {"request_id": req_id})[0];
        reply_id = str(rv["_jac_id"]);
        assert int(rv["match_count"]) == 0 and str(rv["strength"]) == "weak", rv;

        assert _err(_run(cl, b, "OptIn", {"reply_id": reply_id})) == "invalid_state";
        assert _err(_run(cl, b, "Reveal", {"reply_id": reply_id})) == "invalid_state";
        assert _err(_run(cl, a, "ApproveReply", {"reply_id": reply_id})) == "not_found";
        assert _err(_run(cl, a, "DeclineReply", {"reply_id": reply_id})) == "not_found";

        assert _run(cl, b, "DeclineReply", {"reply_id": reply_id}) == ["declined"];
        assert _err(_run(cl, b, "ApproveReply", {"reply_id": reply_id})) == "invalid_state";
        mine = _run(cl, a, "ListMyRequests", {});
        assert str(mine[0]["replies"][0]["status"]) == "declined";
        assert set(mine[0]["replies"][0].keys()) == {"_jac_id", "request_id", "from_handle", "match_count", "strength", "status"};

        assert _err(_run(cl, b, "DeclineRequest", {"request_id": req_id})) in ["not_found", "forbidden"];
        assert _run(cl, a, "DeclineRequest", {"request_id": req_id}) == ["declined"];
        assert str(_run(cl, a, "ListMyRequests", {})[0]["request"]["status"]) == "declined";
        assert _err(_run(cl, a, "DeclineRequest", {"request_id": "not-an-id"})) == "not_found";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "exchange: expired and declined requests are not incoming" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a3@example.com");
        b = _reg(cl, "ex_b3@example.com");
        _run(cl, a, "DevMakeCard", {"handle": "alice-exp", "name": "Alice"});
        _run(cl, b, "DevMakeCard", {"handle": "bob-exp", "name": "Bob"});

        expired = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "old", "about_line": "", "ttl_days": 0})[0]["_jac_id"]);
        live = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "new", "about_line": ""})[0]["_jac_id"]);
        withdrawn = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "withdrawn", "about_line": ""})[0]["_jac_id"]);
        _run(cl, a, "DeclineRequest", {"request_id": withdrawn});

        incoming = [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        assert live in incoming, incoming;
        assert expired not in incoming, incoming;
        assert withdrawn not in incoming, incoming;
        assert _err(_run(cl, b, "ReplyToRequest", {"request_id": expired})) == "invalid_state";

        statuses = {str(x["request"]["_jac_id"]): str(x["request"]["status"]) for x in _run(cl, a, "ListMyRequests", {})};
        assert statuses[expired] == "expired", statuses;
        assert statuses[live] == "open", statuses;
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "exchange: a request whose from_handle equals the friend's handle still reaches the friend" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a4@example.com");
        b = _reg(cl, "ex_b4@example.com");
        # Handles are self-chosen: A picks B's handle.
        _run(cl, a, "DevMakeCard", {"handle": "same-handle", "name": "Alice"});
        _run(cl, b, "DevMakeCard", {"handle": "same-handle", "name": "Bob"});
        req_id = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "a mentor", "about_line": ""})[0]["_jac_id"]);
        b_in = [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        a_in = [str(r["_jac_id"]) for r in _run(cl, a, "ListIncomingRequests", {})];
        assert req_id in b_in, f"same-handle request hidden from friend: {b_in}";
        assert req_id not in a_in, f"own request listed as incoming: {a_in}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "exchange SOH-211: request_closed is true for declined, expired, or past expires_at" {
    open_req = IntroRequest(need="n", from_handle="h", status="open", expires_at="2999-01-01T00:00:00");
    assert not request_closed(open_req);
    assert request_closed(IntroRequest(need="n", from_handle="h", status="declined", expires_at="2999-01-01T00:00:00"));
    assert request_closed(IntroRequest(need="n", from_handle="h", status="expired"));
    assert request_closed(IntroRequest(need="n", from_handle="h", status="revealed", expires_at="2000-01-01T00:00:00"));
    assert not request_closed(IntroRequest(need="n", from_handle="h", status="open", expires_at=""));
}

test "exchange SOH-211: a declined request refuses approve, opt-in, reveal and claim; a declined reply refuses claim" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a6@example.com");
        b = _reg(cl, "ex_b6@example.com");
        _run(cl, a, "DevMakeCard", {"handle": "alice-rc", "name": "Alice"});
        _run(cl, b, "DevMakeCard", {"handle": "bob-rc", "name": "Bob"});

        # Declined reply -> ClaimReveal refuses it (checked before any other state).
        r1 = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "a designer", "about_line": ""})[0]["_jac_id"]);
        reply1 = str(_run(cl, b, "ReplyToRequest", {"request_id": r1})[0]["_jac_id"]);
        assert _run(cl, b, "DeclineReply", {"reply_id": reply1}) == ["declined"];
        assert _err(_run(cl, a, "ClaimReveal", {"reply_id": reply1})) == "reply_declined";

        # Declined request -> every later transition refuses with request_closed.
        r2 = str(_run(cl, a, "PostRequest", {"audience": "everyone", "need": "a mentor", "about_line": ""})[0]["_jac_id"]);
        reply2 = str(_run(cl, b, "ReplyToRequest", {"request_id": r2})[0]["_jac_id"]);
        assert _run(cl, a, "DeclineRequest", {"request_id": r2}) == ["declined"];
        assert _err(_run(cl, b, "ApproveReply", {"reply_id": reply2})) == "request_closed";
        assert _err(_run(cl, b, "OptIn", {"reply_id": reply2})) == "request_closed";
        assert _err(_run(cl, b, "Reveal", {"reply_id": reply2})) == "request_closed";
        assert _err(_run(cl, a, "ClaimReveal", {"reply_id": reply2})) == "request_closed";
        # Ownership is still checked first: A is not the reply's owner.
        assert _err(_run(cl, a, "ApproveReply", {"reply_id": reply2})) == "not_found";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "exchange SOH-211: a handle listed by one root is refused to every other root" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a7@example.com");
        b = _reg(cl, "ex_b7@example.com");
        c = _reg(cl, "ex_c7@example.com");
        d = _reg(cl, "ex_d7@example.com");
        e = _reg(cl, "ex_e7@example.com");

        # Neither card is listed yet, so both DevMakeCards succeed.
        assert str(_run(cl, a, "DevMakeCard", {"handle": "dup-211", "name": "Alice"})[0]["handle"]) == "dup-211";
        assert str(_run(cl, b, "DevMakeCard", {"handle": "dup-211", "name": "Bob"})[0]["handle"]) == "dup-211";
        # A lists first and keeps it; republishing by A is fine.
        assert str(_run(cl, a, "PublishCard", {"visibility": "link"})[0]["handle"]) == "dup-211";
        assert str(_run(cl, a, "PublishCard", {"about": "again", "visibility": "link"})[0]["handle"]) == "dup-211";
        # B cannot list the same handle; C cannot even make it.
        b_pub = _run(cl, b, "PublishCard", {"visibility": "link"});
        print(f"[ex 211] B PublishCard(dup) -> {b_pub}");
        assert _err(b_pub) == "handle_taken", b_pub;
        assert _err(_run(cl, c, "DevMakeCard", {"handle": "dup-211", "name": "Carol"})) == "handle_taken";

        # A handshake_only listing (unreadable to others) still claims its handle.
        _run(cl, d, "DevMakeCard", {"handle": "hs-211", "name": "Dee"});
        assert str(_run(cl, d, "PublishCard", {"visibility": "handshake_only"})[0]["handle"]) == "hs-211";
        assert _err(_run(cl, e, "DevMakeCard", {"handle": "hs-211", "name": "Eve"})) == "handle_taken";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

# ---------------------------------------------------------------- real-server restart (SOH-205 hosted bug)
# Same subprocess idiom as walkers.test.jac's "persistence: person survives
# real server restart": own temp dir (its own .jac store), free port, own
# process group, killed by group.

def _ex_free_port() -> int {
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    s.bind(("127.0.0.1", 0));
    port = s.getsockname()[1];
    s.close();
    return int(port);
}

def _ex_tail(log_path: str, n: int = 4000) -> str {
    try {
        f = open(log_path, "rb");
        data = f.read();
        f.close();
        return data[-n:].decode("utf-8", errors="replace");
    } except OSError {
        return "<no log available>";
    }
}

def _ex_kill(proc: (subprocess.Popen[bytes] | None)) {
    if proc is None {
        return;
    }
    try {
        os.killpg(os.getpgid(proc.pid), int(signal.SIGTERM));
    } except OSError { }
    try {
        proc.wait(timeout=5);
    } except subprocess.TimeoutExpired {
        try {
            os.killpg(os.getpgid(proc.pid), int(signal.SIGKILL));
        } except OSError { }
        try {
            proc.wait(timeout=5);
        } except subprocess.TimeoutExpired { }
    }
}

def _ex_start(tmp_dir: str, port: int) -> subprocess.Popen[bytes] {
    log_path = os.path.join(tmp_dir, f"server_{port}.log");
    log_file = open(log_path, "wb");
    proc = subprocess.Popen(
        ["jac", "start", "exapp.jac", "--port", str(port), "-n"],
        cwd=tmp_dir,
        stdin=subprocess.DEVNULL,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        start_new_session=True
    );
    log_file.close();
    deadline = time.time() + 20.0;
    ready = False;
    while time.time() < deadline and not ready {
        if proc.poll() is not None {
            break;
        }
        try {
            sock = socket.create_connection(("127.0.0.1", port), timeout=0.5);
            sock.close();
            ready = True;
        } except OSError {
            time.sleep(0.3);
        }
    }
    if not ready {
        tail = _ex_tail(log_path);
        _ex_kill(proc);
        assert False, f"exchange harness server on port {port} did not come up; log tail:\n{tail}";
    }
    return proc;
}

def _ex_register(base: str, user: str) -> str {
    reg = requests.post(f"{base}/user/register", json={
        "identities": [{"type": "username", "value": user}],
        "credential": {"type": "password", "password": "password123"}
    });
    assert reg.ok, reg.text;
    return str(reg.json()["data"]["token"]);
}

def _ex_login(base: str, user: str) -> str {
    login = requests.post(f"{base}/user/login", json={
        "identity": {"type": "username", "value": user},
        "credential": {"type": "password", "password": "password123"}
    });
    assert login.ok, login.text;
    return str(login.json()["data"]["token"]);
}

def _ex_call(base: str, token: str, wname: str, body: dict) -> list[any] {
    resp = requests.post(
        f"{base}/walker/{wname}",
        headers={"Authorization": f"Bearer {token}"},
        json=body
    );
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.json()["data"]["reports"]);
}

test "exchange: B's reply is visible to A after a real server restart" {
    tmp_dir = tempfile.mkdtemp();
    proc1: (subprocess.Popen[bytes] | None) = None;
    proc2: (subprocess.Popen[bytes] | None) = None;
    try {
        _ex_harness(tmp_dir);
        port = _ex_free_port();
        base = f"http://127.0.0.1:{port}";
        proc1 = _ex_start(tmp_dir, port);

        a = _ex_register(base, "rs_a@example.com");
        b = _ex_register(base, "rs_b@example.com");
        _ex_call(base, a, "DevMakeCard", {"handle": "alice-rs", "name": "Alice"});
        _ex_call(base, b, "DevMakeCard", {"handle": "bob-rs", "name": "Bob"});
        _ex_call(base, b, "DevAddPerson", {"name": "Priya Rao", "me_name": "Bob"});
        _ex_call(base, b, "DevSeedMatch", {
            "name": "Priya Rao",
            "fact": "Priya is a partner at a climate-tech seed fund.",
            "offer": "intros to climate-tech seed investors"
        });
        req_id = str(_ex_call(base, a, "PostRequest", {"audience": "everyone", "need": "a climate-tech seed investor", "about_line": "battery recycling"})[0]["_jac_id"]);
        rv = _ex_call(base, b, "ReplyToRequest", {"request_id": req_id})[0];
        assert str(rv["status"]) == "pending", rv;
        reply_id = str(rv["_jac_id"]);
        b_req_id = str(_ex_call(base, b, "PostRequest", {"audience": "everyone", "need": "a designer", "about_line": ""})[0]["_jac_id"]);

        _ex_kill(proc1);
        proc1 = None;

        port2 = _ex_free_port();
        base2 = f"http://127.0.0.1:{port2}";
        proc2 = _ex_start(tmp_dir, port2);
        a2 = _ex_login(base2, "rs_a@example.com");
        mine = _ex_call(base2, a2, "ListMyRequests", {});
        print(f"[ex-restart] ListMyRequests after restart -> {mine}");
        assert len(mine) == 1, mine;
        replies = mine[0]["replies"] as list[dict[str, any]];
        assert len(replies) == 1, f"reply lost across restart: {mine}";
        assert str(replies[0]["_jac_id"]) == reply_id, replies;
        assert str(replies[0]["status"]) == "pending", replies;
        assert str(mine[0]["request"]["status"]) == "replied", mine;
        assert set(replies[0].keys()) == {"_jac_id", "request_id", "from_handle", "match_count", "strength", "status"}, replies;

        # B's own request (B did not create the Exchange) survives the restart too.
        a_in = [str(r["_jac_id"]) for r in _ex_call(base2, a2, "ListIncomingRequests", {})];
        assert b_req_id in a_in, f"B's request lost across restart: {a_in}";

        # A new shared write in the NEW process must not hide the old ones.
        c2 = _ex_register(base2, "rs_c@example.com");
        _ex_call(base2, c2, "DevMakeCard", {"handle": "carol-rs", "name": "Carol"});
        _ex_call(base2, c2, "ReplyToRequest", {"request_id": req_id});
        mine2 = _ex_call(base2, a2, "ListMyRequests", {});
        assert len(mine2) == 1 and len(list(mine2[0]["replies"])) == 2, f"expected B's and C's replies: {mine2}";

        # Finish the handshake across the restart: B approves, opts in, reveals; A claims.
        b2 = _ex_login(base2, "rs_b@example.com");
        assert _ex_call(base2, b2, "ApproveReply", {"reply_id": reply_id})[0]["status"] == "approved";
        assert _ex_call(base2, b2, "OptIn", {"reply_id": reply_id})[0]["reply"]["status"] == "opted_in";
        rl = _ex_call(base2, b2, "Reveal", {"reply_id": reply_id})[0];
        assert str(rl["reply"]["status"]) == "revealed", rl;
        assert _err(_ex_call(base2, c2, "ClaimReveal", {"reply_id": reply_id})) == "forbidden";
        cr = _ex_call(base2, a2, "ClaimReveal", {"reply_id": reply_id})[0];
        assert str(cr["person"]["name"]) == "Priya Rao", cr;
        assert str(cr["card"]["handle"]) == str(rl["revealed_card_handle"]), cr;
    } finally {
        if proc1 is not None { _ex_kill(proc1); }
        if proc2 is not None { _ex_kill(proc2); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

# ---------------------------------------------------------------- SOH-218 friend-gated Exchange

test "exchange SOH-218: friend_handles finds FromCard edges and card: markers, nothing else" {
    me = (root ++> Me(name="friends-218"))[0];
    tag = jid(me)[:10];
    via_edge = (me +>:Knows(how_met="handshake", source_note=""):+> Person(name="Via Edge"))[0];
    card = (root ++> Card(handle=f"edge-{tag}", name="Via Edge"))[0];
    via_edge +>:FromCard(handle=f"edge-{tag}", received_at="2026-09-26T10:00:00"):+> card;
    me +>:Knows(how_met="handshake", source_note=f"card:mark-{tag}"):+> Person(name="Via Marker");
    me +>:Knows(how_met="met at a talk", source_note="some-note-jid"):+> Person(name="Not A Friend");
    assert friend_handles(me) == [f"edge-{tag}", f"mark-{tag}"], friend_handles(me);
    entries = friend_entries(me);
    assert len(entries) == 2, entries;
    assert str(entries[0]["since"]) == "2026-09-26T10:00:00" and str(entries[1]["since"]) == "", entries;
    p0 = entries[0]["person"];
    assert isinstance(p0, Person) and (p0 as Person).name == "Via Edge";
}

test "exchange SOH-218: request_visible gates on audience, friendship and blocks" {
    fr = IntroRequest(need="n", from_handle="pal", audience="friends");
    ev = IntroRequest(need="n", from_handle="stranger", audience="everyone");
    odd = IntroRequest(need="n", from_handle="stranger", audience="bogus");
    assert request_visible(fr, ["pal"], []);
    assert not request_visible(fr, [], []);
    assert request_visible(ev, [], []);
    assert not request_visible(odd, [], []);
    assert not request_visible(ev, [], ["stranger"]);
    assert not request_visible(fr, ["pal"], ["pal"]);
    assert norm_audience("Everyone") == "everyone" and norm_audience("x") == "friends" and norm_audience("") == "friends";
}

test "exchange SOH-218: friends-only requests reach friends only; blocks hide both sides" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ex_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "ex_a218@example.com");
        b = _reg(cl, "ex_b218@example.com");
        c = _reg(cl, "ex_c218@example.com");
        a_handle = str(_run(cl, a, "PublishCard", {"headline": "Founder", "about": "Battery recycling.", "visibility": "link", "name": "Alice"})[0]["handle"]);
        b_handle = str(_run(cl, b, "PublishCard", {"headline": "Organizer", "visibility": "link", "name": "Bob"})[0]["handle"]);
        c_handle = str(_run(cl, c, "DevMakeCard", {"handle": "carol-218", "name": "Carol"})[0]["handle"]);

        # No handshake yet: nobody is anybody's friend.
        assert _run(cl, b, "ListFriends", {}) == [];

        # A offers, B accepts: B now holds A's Card; A materializes B's on ListHandshakes.
        offer_id = str(_run(cl, a, "OfferHandshake", {"to_handle": b_handle})[0]["offer_id"]);
        accepted = _run(cl, b, "AcceptHandshake", {"offer_id": offer_id})[0];
        assert "person" in dict(accepted), accepted;
        _run(cl, a, "ListHandshakes", {});

        b_friends = _run(cl, b, "ListFriends", {});
        print(f"[ex 218] B ListFriends -> {b_friends}");
        assert [str(f["handle"]) for f in b_friends] == [a_handle], b_friends;
        assert str(b_friends[0]["person"]["name"]) == "Alice", b_friends;
        assert "since" in dict(b_friends[0]);
        assert [str(f["handle"]) for f in _run(cl, a, "ListFriends", {})] == [b_handle];
        assert _run(cl, c, "ListFriends", {}) == [];

        # Default audience is friends; junk normalizes to friends.
        fr = _run(cl, a, "PostRequest", {"need": "a seed investor", "about_line": ""})[0];
        assert str(fr["audience"]) == "friends", fr;
        fr_id = str(fr["_jac_id"]);
        junk = _run(cl, a, "PostRequest", {"need": "a designer", "about_line": "", "audience": "bogus"})[0];
        assert str(junk["audience"]) == "friends", junk;
        ev = _run(cl, a, "PostRequest", {"need": "a mentor", "about_line": "", "audience": "everyone"})[0];
        assert str(ev["audience"]) == "everyone", ev;
        ev_id = str(ev["_jac_id"]);

        b_in = [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        c_in = [str(r["_jac_id"]) for r in _run(cl, c, "ListIncomingRequests", {})];
        assert fr_id in b_in and ev_id in b_in, b_in;
        assert fr_id not in c_in, f"non-friend saw a friends-only request: {c_in}";
        assert ev_id in c_in, c_in;
        assert _err(_run(cl, c, "ReplyToRequest", {"request_id": fr_id})) == "not_visible";

        # B answers the friends-only request; C answers the everyone one.
        b_reply = str(_run(cl, b, "ReplyToRequest", {"request_id": fr_id})[0]["_jac_id"]);
        c_reply = _run(cl, c, "ReplyToRequest", {"request_id": ev_id})[0];
        assert str(c_reply["from_handle"]) == c_handle, c_reply;
        mine = {str(x["request"]["_jac_id"]): [str(r["from_handle"]) for r in x["replies"]] for x in _run(cl, a, "ListMyRequests", {})};
        assert mine[ev_id] == [c_handle], mine;

        # Requester side: A blocks C -> C's reply disappears from A's view.
        blk = _run(cl, a, "BlockHandle", {"handle": c_handle});
        assert blk == [{"blocked": [c_handle]}], blk;
        mine2 = {str(x["request"]["_jac_id"]): list(x["replies"]) for x in _run(cl, a, "ListMyRequests", {})};
        assert mine2[ev_id] == [], mine2;
        assert _run(cl, a, "BlockHandle", {"handle": c_handle}) == [{"blocked": [c_handle]}];

        # Friend side: B blocks A -> none of A's requests show; reply refused; own reply hidden.
        assert _run(cl, b, "BlockHandle", {"handle": a_handle}) == [{"blocked": [a_handle]}];
        b_in2 = [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        assert ev_id not in b_in2 and fr_id not in b_in2, b_in2;
        assert _err(_run(cl, b, "ReplyToRequest", {"request_id": ev_id})) == "not_visible";
        assert [str(x["reply"]["_jac_id"]) for x in _run(cl, b, "ListMyReplies", {})] == [], "blocked request's reply still listed";

        # Unblock restores; A's block list is untouched by B's.
        assert _run(cl, b, "UnblockHandle", {"handle": a_handle}) == [{"blocked": []}];
        assert ev_id in [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        assert [str(x["reply"]["_jac_id"]) for x in _run(cl, b, "ListMyReplies", {})] == [b_reply];
        assert _err(_run(cl, b, "BlockHandle", {"handle": "  "})) == "bad_handle";
        assert _run(cl, a, "UnblockHandle", {"handle": "nobody"}) == [{"blocked": [c_handle]}];
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
