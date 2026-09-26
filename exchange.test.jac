"""Tests for exchange.sv.jac (SOH-205, the Exchange).

Annex to exchange.sv.jac — run with `jac test exchange.sv.jac`.

Same harness as gate.test.jac / walkers.test.jac: JacTestClient cannot target
a dotted `*.sv.jac` file, so each test copies the live server modules into a
fresh temp dir next to a dot-free `app.jac` and gives the client its own
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
import tempfile;

glob EX_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _ex_harness(tmp_dir: str) -> str {
    for name in ["exchange.sv.jac", "schema.sv.jac", "scoring.sv.jac", "onboard.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(EX_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from walkers { ListPeople, DevAddPerson }\n"
        "import from onboard { OnboardMe }\n"
        "import from exchange { PostRequest, ListIncomingRequests, ReplyToRequest, ListMyRequests, "
        "ApproveReply, OptIn, Reveal, ClaimReveal, DeclineRequest, DeclineReply, DevMakeCard, DevSeedMatch }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"exchange-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
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
        posted = _run(cl, a, "PostRequest", {"need": "a climate-tech seed investor", "about_line": "Building battery recycling"});
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

        # B replies: count + strength, no identity.
        rv = _run(cl, b, "ReplyToRequest", {"request_id": req_id})[0];
        print(f"[ex] ReplyToRequest -> {rv}");
        assert "match_person_id" not in dict(rv) and "revealed_card_id" not in dict(rv), rv;
        assert int(rv["match_count"]) >= 0 and str(rv["status"]) == "pending";
        assert int(rv["match_count"]) >= 1, f"seeded offer should keep Priya as medium+: {rv}";
        reply_id = str(rv["_jac_id"]);
        # replied -> no longer incoming for B; a second reply is refused
        assert req_id not in [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        assert _err(_run(cl, b, "ReplyToRequest", {"request_id": req_id})) == "invalid_state";

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
        rl = _run(cl, b, "Reveal", {"reply_id": reply_id})[0];
        print(f"[ex] Reveal -> {rl}");
        handle = str(rl["revealed_card_handle"]);
        assert handle and str(rl["reply"]["status"]) == "revealed";
        assert "match_person_id" not in dict(rl["reply"]) and "revealed_card_id" not in dict(rl["reply"]);

        # C (bystander) cannot claim.
        assert _err(_run(cl, c, "ClaimReveal", {"reply_id": reply_id})) == "forbidden";

        b_people_before = _run(cl, b, "ListPeople", {});

        # A claims.
        claimed = _run(cl, a, "ClaimReveal", {"reply_id": reply_id});
        a_reports.extend(claimed);
        print(f"[ex] ClaimReveal -> {claimed}");
        cr = claimed[0];
        assert str(cr["person"]["name"]) == "Priya Rao";
        assert str(cr["card"]["handle"]) == handle;
        assert len(str(cr["intro_draft"])) > 0;
        card_id = str(cr["card"]["_jac_id"]);
        a_priya_id = str(cr["person"]["_jac_id"]);
        assert a_priya_id != b_priya_id;

        # Idempotent claim: no duplicate Person.
        again = _run(cl, a, "ClaimReveal", {"reply_id": reply_id});
        assert str(again[0]["person"]["_jac_id"]) == a_priya_id;

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
        assert _err(_run(cl, c, "PostRequest", {"need": "x", "about_line": ""})) == "no_card";

        req_id = str(_run(cl, a, "PostRequest", {"need": "a designer", "about_line": "hi"})[0]["_jac_id"]);
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

        expired = str(_run(cl, a, "PostRequest", {"need": "old", "about_line": "", "ttl_days": 0})[0]["_jac_id"]);
        live = str(_run(cl, a, "PostRequest", {"need": "new", "about_line": ""})[0]["_jac_id"]);
        withdrawn = str(_run(cl, a, "PostRequest", {"need": "withdrawn", "about_line": ""})[0]["_jac_id"]);
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
        req_id = str(_run(cl, a, "PostRequest", {"need": "a mentor", "about_line": ""})[0]["_jac_id"]);
        b_in = [str(r["_jac_id"]) for r in _run(cl, b, "ListIncomingRequests", {})];
        a_in = [str(r["_jac_id"]) for r in _run(cl, a, "ListIncomingRequests", {})];
        assert req_id in b_in, f"same-handle request hidden from friend: {b_in}";
        assert req_id not in a_in, f"own request listed as incoming: {a_in}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
