"""Tests for identity.sv.jac (SOH-215, blinded identity tokens).

Annex to identity.sv.jac — run with `jac test identity.sv.jac`. Deterministic:
no model, no network. The two-account test uses the same JacTestClient
harness as exchange.test.jac (copies the server modules into a temp dir next
to a dot-free `idapp.jac`, its own base_path, no `jac clean`) and stubs the
scorer's model call exactly the way exchange.test.jac does.
"""

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import sys;
import tempfile;
import from uuid { uuid4 }
import from identity {
    token, tokens_for, refresh_person_tokens, same_person, match_reason,
    group_same_person, canonical_url, add_link, fill_contact, RefreshIdentityTokens
}
import from schema { Me, Person, Knows }
import from scoring { NeedMatch, NeedMatches }

glob ID_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

# ---------------------------------------------------------------- pure defs

test "identity: tokens are deterministic, kind-prefixed, 32 hex chars" {
    t1 = token("e", "james@acme.com");
    t2 = token("e", "james@acme.com");
    assert t1 == t2;
    assert t1.startswith("e:") and len(t1) == 2 + 32, t1;
    assert token("e", "james@acme.com") != token("e", "jim@acme.com");
    assert token("e", "") == "" and token("e", "not-an-email") == "";
}

test "identity: normalisation (case, punctuation, suffixes, www/scheme, phone formatting)" {
    assert token("e", "  James@ACME.com ") == token("e", "james@acme.com");
    assert token("n", "James Anderson|Acme Corp") == token("n", "james  anderson|ACME, Corp.");
    assert token("n", "Dr. James Anderson|Acme Inc.") == token("n", "James Anderson|acme");
    assert token("n", "James Anderson|Acme").startswith("n:");
    assert token("n", "James Anderson|").startswith("n0:");
    assert token("n", "James Anderson|") == token("n0", "james anderson");
    assert token("n", "James Anderson|Acme") != token("n", "James Anderson|Globex");
    assert token("u", "https://www.Example.com/jim/?utm=1#top") == token("u", "example.com/jim");
    assert token("u", "http://example.com/jim") == token("u", "EXAMPLE.com/jim/");
    assert canonical_url("HTTPS://www.github.com/JimA/") == "github.com/jima";
    assert token("p", "+1 (734) 555-0199") == token("p", "734.555.0199");
    assert token("p", "555-01") == "", "fewer than 7 digits is not a phone";
}

test "identity: same_person on each kind" {
    a_e = [token("n", "James Anderson|Acme"), token("e", "j@acme.com")];
    b_e = [token("n", "Jim A|Other"), token("e", "J@Acme.com")];
    assert same_person(a_e, b_e) == "same" and match_reason(a_e, b_e) == "contact";
    a_p = [token("p", "(734) 555-0199")];
    b_p = [token("p", "+1 734 555 0199")];
    assert same_person(a_p, b_p) == "same" and match_reason(a_p, b_p) == "contact";
    a_u = [token("u", "https://linkedin.com/in/jima")];
    b_u = [token("u", "www.linkedin.com/in/jima/")];
    assert same_person(a_u, b_u) == "same" and match_reason(a_u, b_u) == "contact";
    a_n = [token("n", "James Anderson|Acme Corp"), token("e", "james@acme.com")];
    b_n = [token("n", "James Anderson|Acme"), token("e", "janderson@gmail.com")];
    assert same_person(a_n, b_n) == "same" and match_reason(a_n, b_n) == "name+org";
    a_0 = [token("n", "James Anderson|")];
    b_0 = [token("n", "james anderson|")];
    assert same_person(a_0, b_0) == "likely" and match_reason(a_0, b_0) == "name";
    assert same_person([token("n", "James Anderson|Acme")], [token("n", "James Anderson|Globex")]) == "";
    assert same_person([], []) == "";
}

test "identity: group_same_person groups intersecting replies, never across strangers" {
    j1 = [token("n", "James Anderson|Acme"), token("e", "a@x.com")];
    j2 = [token("n", "James Anderson|Acme Corp"), token("e", "b@y.com")];
    j3 = [token("n", "Jim|Globex"), token("e", "a@x.com")];
    other = [token("n", "Priya Rao|Fund")];
    g = group_same_person([
        {"id": "r1", "tokens": j1}, {"id": "r2", "tokens": j2},
        {"id": "r3", "tokens": j3}, {"id": "r4", "tokens": other}, {"id": "r5", "tokens": []}
    ]);
    groups = g["groups"] as list[list[str]];
    assert len(groups) == 1 and sorted(groups[0]) == ["r1", "r2", "r3"], groups;
    same_as = g["same_as"] as dict[str, list[str]];
    reason = g["same_reason"] as dict[str, str];
    assert sorted(same_as["r1"]) == ["r2", "r3"];
    assert same_as["r4"] == [] and same_as["r5"] == [];
    assert reason["r1"] == "contact" and reason["r2"] == "name+org" and reason["r3"] == "contact";
    assert reason["r4"] == "";
}

# ---------------------------------------------------------------- graph defs

test "identity: refresh_person_tokens, add_link, fill_contact never overwrite" {
    tag = str(uuid4())[:8];
    p = Person(name=f"Idtest {tag}", org="Acme", email="keep@acme.com");
    toks = refresh_person_tokens(p);
    assert toks == p.identity_tokens and len(toks) == 2, toks;
    assert add_link(p, "https://www.example.com/idtest/") == True;
    assert add_link(p, "http://example.com/idtest") == False, "same canonical form";
    assert add_link(p, "https://vertexaisearch.cloud.google.com/grounding-api-redirect/abc") == False;
    fill_contact(p, "other@acme.com", "734-555-0100", ["github.com/idtest"]);
    assert p.email == "keep@acme.com";
    assert p.phone == "734-555-0100";
    assert len(p.links) == 2, p.links;
    assert token("p", "7345550100") in p.identity_tokens;
    assert token("u", "github.com/idtest") in p.identity_tokens;
    assert tokens_for(p) == p.identity_tokens;
}

test "identity: RefreshIdentityTokens updates people on root" {
    tag = str(uuid4())[:8];
    me = (root ++> Me(name=f"Idtest Me {tag}"))[0];
    p = (me +>:Knows(how_met="test", status="confirmed"):+> Person(name=f"Idtest Walk {tag}", org="Acme", email=f"{tag}@acme.com"))[0];
    assert p.identity_tokens == [];
    result = root spawn RefreshIdentityTokens();
    assert len(result.reports) == 1;
    assert int(result.reports[0]["updated"]) >= 1, result.reports;
    assert token("e", f"{tag}@acme.com") in p.identity_tokens, p.identity_tokens;
    again = root spawn RefreshIdentityTokens();
    assert int(again.reports[0]["updated"]) == 0 or token("e", f"{tag}@acme.com") in p.identity_tokens;
}

# ---------------------------------------------------------------- two accounts, through the walkers

def _id_harness(tmp_dir: str) -> str {
    for name in [
        "identity.sv.jac", "names.sv.jac", "exchange.sv.jac", "schema.sv.jac", "scoring.sv.jac",
        "onboard.sv.jac", "walkers.sv.jac", "cards.sv.jac", "llm.sv.jac", "freshness.sv.jac",
        "goals.sv.jac", "reads.sv.jac"
    ] {
        shutil.copyfile(os.path.join(ID_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "idapp.jac");
    f = open(harness_path, "w");
    # DevSetContact is harness-only (never shipped): sets org/email on one of MY people by name.
    f.write(
        "import from schema { Me, Person, Knows }\n"
        "import from walkers { DevAddPerson }\n"
        "import from exchange { PostRequest, ReplyToRequest, ListMyRequests, DevMakeCard, DevSeedMatch }\n"
        "import from identity { RefreshIdentityTokens, refresh_person_tokens }\n"
        "walker:priv DevSetContact {\n"
        "    has name: str;\n"
        "    has org: str = \"\";\n"
        "    has email: str = \"\";\n"
        "    has reports: list[object] = [];\n"
        "    can go with Root entry {\n"
        "        for p in [root --> [?:Me] ->:Knows:->] {\n"
        "            if p.name == self.name {\n"
        "                p.org = self.org;\n"
        "                p.email = self.email;\n"
        "                report {\"tokens\": refresh_person_tokens(p)};\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "}\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"identity-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"idapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _id_reg(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _id_run(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

def _id_stub_medium() -> any {
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

def _id_restore(orig: any) {
    mod = sys.modules.get("scoring");
    if mod is not None and orig is not None {
        setattr(mod, "score_need", orig);
    }
}

def _id_friend(tc: JacTestClient, tok: str, handle: str, org: str, email: str) -> list[str] {
    _id_run(tc, tok, "DevMakeCard", {"handle": handle, "name": handle});
    _id_run(tc, tok, "DevAddPerson", {"name": "James Anderson", "me_name": handle});
    seeded = _id_run(tc, tok, "DevSeedMatch", {
        "name": "James Anderson",
        "fact": "James is VP of partnerships at a battery maker.",
        "offer": "intros to battery-recycling buyers"
    });
    assert "person_id" in dict(seeded[0]), seeded;
    out = _id_run(tc, tok, "DevSetContact", {"name": "James Anderson", "org": org, "email": email});
    return list(out[0]["tokens"]);
}

test "identity: two friends holding James Anderson / Acme with different emails -> same person by name+org, no tokens in reports" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_id_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _id_reg(cl, "id_a1@example.com");
        b = _id_reg(cl, "id_b1@example.com");
        c = _id_reg(cl, "id_c1@example.com");
        d = _id_reg(cl, "id_d1@example.com");
        _id_run(cl, a, "DevMakeCard", {"handle": "ida-alice", "name": "Alice"});
        tb = _id_friend(cl, b, "idb-bob", "Acme Corp", "james@acme.com");
        tc = _id_friend(cl, c, "idc-cara", "ACME", "janderson@gmail.com");
        td = _id_friend(cl, d, "idd-dan", "Globex", "james@globex.com");
        assert same_person(tb, tc) == "same" and match_reason(tb, tc) == "name+org", (tb, tc);
        assert same_person(tb, td) == "";

        req = _id_run(cl, a, "PostRequest", {"need": "a battery-recycling buyer", "about_line": "Building battery recycling"})[0];
        req_id = str(req["_jac_id"]);

        orig = _id_stub_medium();
        try {
            rb = _id_run(cl, b, "ReplyToRequest", {"request_id": req_id})[0];
            rc = _id_run(cl, c, "ReplyToRequest", {"request_id": req_id})[0];
            rd = _id_run(cl, d, "ReplyToRequest", {"request_id": req_id})[0];
        } finally {
            _id_restore(orig);
        }
        for rv in [rb, rc, rd] {
            assert "match_tokens" not in dict(rv), rv;
            assert int(rv["match_count"]) >= 1, rv;
        }
        rb_id = str(rb["_jac_id"]);
        rc_id = str(rc["_jac_id"]);
        rd_id = str(rd["_jac_id"]);

        mine = _id_run(cl, a, "ListMyRequests", {});
        print(f"[id] ListMyRequests -> {mine}");
        assert len(mine) == 1, mine;
        views: list[dict[str, any]] = list(mine[0]["replies"]);
        assert len(views) == 3, views;
        groups = list(mine[0]["same_person_groups"]);
        assert len(groups) == 1 and sorted(groups[0]) == sorted([rb_id, rc_id]), groups;
        by_id: dict[str, dict[str, any]] = {};
        for v in views {
            assert "match_tokens" not in dict(v), v;
            by_id[str(v["_jac_id"])] = v;
        }
        assert list(by_id[rb_id]["same_as"]) == [rc_id] and str(by_id[rb_id]["same_reason"]) == "name+org";
        assert list(by_id[rc_id]["same_as"]) == [rb_id] and str(by_id[rc_id]["same_reason"]) == "name+org";
        assert list(by_id[rd_id]["same_as"]) == [] and str(by_id[rd_id]["same_reason"]) == "";
        assert "match_tokens" not in str(mine), "no token field anywhere in the requester's report";

        # Isolation: B sees none of A's requests; RefreshIdentityTokens runs on B's own root only.
        assert _id_run(cl, b, "ListMyRequests", {}) == [];
        assert int(_id_run(cl, a, "RefreshIdentityTokens", {})[0]["updated"]) == 0, "A knows nobody";
    } finally {
        if client is not None {
            (client as JacTestClient).close();
        }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
