"""Tests for agent.sv.jac (SOH-223, the agent inbox).

Annex to agent.sv.jac — run with `jac test agent.sv.jac`.

Same harness idiom as exchange.test.jac: JacTestClient cannot target a dotted
`*.sv.jac`, so the test copies every module in agent's import chain into a
fresh temp dir next to a dot-free `agentapp.jac` (unique name: other suites
cache `app`/`exapp`) and gives the client its own base_path. No `jac clean`.
No model: RunAgent makes no `by llm` call, and the one approve path that
reaches the scorer (answer_ask -> ReplyToRequest) runs with `score_need`
stubbed to raise, so the deterministic fallback answers.
"""

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;
import sys;
import json;
import from datetime { datetime }
import from agent {
    make_finding, _rank, _clip, step_new_match, _answer_ask_hits,
    _answer_ask_match_tokens, _first_resolvable_hit, run_agent_for
}
import from schema { AgentAction, Me, Person, Goal, HasGoal, RelevantTo, Note, Fact, Asserts, FactAbout, Knows }

glob AG_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _ag_harness(tmp_dir: str) -> str {
    for name in [
        "agent.sv.jac", "schema.sv.jac", "reads.sv.jac", "goals.sv.jac", "gaps.sv.jac",
        "paths.sv.jac", "tend.sv.jac", "drafts.sv.jac", "scoring.sv.jac", "exchange.sv.jac",
        "cards.sv.jac", "onboard.sv.jac", "identity.sv.jac", "names.sv.jac", "llm.sv.jac",
        "freshness.sv.jac", "walkers.sv.jac"
    ] {
        shutil.copyfile(os.path.join(AG_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "agentapp.jac");
    f = open(harness_path, "w");
    f.write(
        "import from agent { RunAgent, ListAgentActions, ResolveAgentAction, DevSeedAgent }\n"
        "import from exchange { PostRequest, ListMyRequests, ListIncomingRequests, DevMakeCard, DevSeedMatch }\n"
        "import from walkers { DevAddPerson }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"agent-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"agentapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _ag_reg(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _ag_run(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

def _ag_actions(client: JacTestClient, token: str, status: str) -> list[dict] {
    return [dict(r) for r in _ag_run(client, token, "ListAgentActions", {"status": status, "limit": 100})];
}

def _ag_by_kind(rows: list[dict], kind: str) -> list[dict] {
    return [r for r in rows if str(r["action"]["kind"]) == kind];
}

def _ag_stub_scorer() -> any {
    mod = sys.modules.get("scoring");
    if mod is None {
        return None;
    }
    orig = getattr(mod, "score_need");
    def fake(need: str, candidates_text: str) -> any {
        raise RuntimeError("model stubbed out in tests");
    }
    setattr(mod, "score_need", fake);
    return orig;
}

def _ag_restore_scorer(orig: any) {
    mod = sys.modules.get("scoring");
    if mod is not None and orig is not None {
        setattr(mod, "score_need", orig);
    }
}

test "agent: helpers are deterministic (dedup key, rank, clip)" {
    f = make_finding("route", "t", "w", ["e1"], "p1", "g1", "", "d", {"a": 1}, "PathFinder", "x1", True);
    assert str(f["dedup_key"]) == "route|p1|g1||x1";
    assert json.loads(str(f["payload_json"]))["a"] == 1;
    assert _rank("strong") > _rank("medium") and _rank("medium") > _rank("weak");
    assert _rank("") == _rank("weak");
    assert _clip("abcdefghij", 8) == "abcde...";
    assert _clip("  short ", 8) == "short";
}

test "agent: RunAgent proposes, dedups, respects dismiss, reopens snooze, approves; isolated by construction" {
    tmp_dir = tempfile.mkdtemp();
    orig: any = None;
    try {
        cl = JacTestClient.from_file(_ag_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        a = _ag_reg(cl, "agent_a1@example.com");
        b = _ag_reg(cl, "agent_b1@example.com");

        _ag_run(cl, a, "DevMakeCard", {"handle": "agent-alice", "name": "Alice"});
        _ag_run(cl, b, "DevMakeCard", {"handle": "agent-bob", "name": "Bob"});
        seed = dict(_ag_run(cl, a, "DevSeedAgent", {"tag": "t1"})[0]);
        print(f"[agent] seed {seed}");

        # B asks the network for something A's graph has evidence for.
        posted = _ag_run(cl, b, "PostRequest", {"need": "a climate battery investor", "about_line": "Building grid storage", "audience": "everyone"});
        b_req_id = str(posted[0]["_jac_id"]);

        # ---- first run
        run1 = dict(_ag_run(cl, a, "RunAgent", {"reason": "test"})[0]);
        print(f"[agent] run1 {run1}");
        assert int(run1["new"]) >= 3, run1;
        assert "serendipity" in list(run1["skipped"]);
        rows = _ag_actions(cl, a, "open");
        kinds = sorted(set([str(r["action"]["kind"]) for r in rows]));
        print(f"[agent] kinds {kinds}");
        assert len(kinds) >= 3, kinds;
        for k in ["new_match", "ask_network", "route", "promise_due", "answer_ask"] {
            assert k in kinds, (k, kinds);
        }
        for r in rows {
            assert len(list(r["action"]["evidence"])) >= 1, r;       # no evidence, no action
            assert len(list(r["evidence"])) >= 1, r;                  # resolved via Receipt
            assert str(r["action"]["why"]), r;
        }
        nm = _ag_by_kind(rows, "new_match")[0];
        assert str(nm["action"]["person_id"]) == str(seed["maya_id"]);
        assert nm["person"] is not None and str(nm["person"]["_jac_id"]) == str(seed["maya_id"]);
        assert str(seed["fact_id"]) in [str(e["id"]) for e in nm["evidence"]];
        rt = _ag_by_kind(rows, "route")[0];
        assert str(rt["action"]["person_id"]) == str(seed["dev_id"]);
        assert "ask Dev" in str(rt["action"]["title"]), rt;
        assert str(rt["action"]["draft"]).startswith("Hi Dev");
        aa = _ag_by_kind(rows, "answer_ask")[0];
        assert str(aa["action"]["request_id"]) == b_req_id;
        assert str(aa["action"]["dedup_key"]) == "answer_ask|" + b_req_id;
        an0 = _ag_by_kind(rows, "ask_network")[0];
        assert [str(e["kind"]) for e in an0["evidence"]] == ["goal"], an0;
        assert str(an0["evidence"][0]["observed_at"]), an0;
        pd = _ag_by_kind(rows, "promise_due")[0];
        assert str(pd["action"]["draft"]);
        pd_payload = json.loads(str(pd["action"]["payload_json"])) as dict[str, any];
        assert "due" in pd_payload, pd_payload;

        # ---- second run: dedup, nothing new
        run2 = dict(_ag_run(cl, a, "RunAgent", {})[0]);
        assert int(run2["new"]) == 0, run2;
        assert int(run2["total_open"]) == int(run1["total_open"]), (run1, run2);
        assert len(_ag_actions(cl, a, "all")) == len(rows);

        # ---- dismiss new_match, snooze promise_due, run again
        nm_id = str(nm["action"]["_jac_id"]);
        pd_id = str(pd["action"]["_jac_id"]);
        dis = dict(_ag_run(cl, a, "ResolveAgentAction", {"action_id": nm_id, "decision": "dismiss"})[0]);
        assert str(dis["action"]["status"]) == "dismissed" and str(dis["action"]["resolved_at"]);
        sn = dict(_ag_run(cl, a, "ResolveAgentAction", {"action_id": pd_id, "decision": "snooze"})[0]);
        assert str(sn["action"]["status"]) == "snoozed";
        assert pd_id not in [str(r["action"]["_jac_id"]) for r in _ag_actions(cl, a, "open")];
        again = dict(_ag_run(cl, a, "ResolveAgentAction", {"action_id": nm_id, "decision": "approve"})[0]);
        assert str(again["error"]) == "invalid_state";
        bad = dict(_ag_run(cl, a, "ResolveAgentAction", {"action_id": pd_id, "decision": "send"})[0]);
        assert str(bad["error"]) == "invalid_state";

        run3 = dict(_ag_run(cl, a, "RunAgent", {})[0]);
        open3 = _ag_actions(cl, a, "open");
        open3_ids = [str(r["action"]["_jac_id"]) for r in open3];
        assert nm_id not in open3_ids;                       # dismissed never re-proposed
        assert len(_ag_by_kind(open3, "new_match")) == 0;
        assert pd_id in open3_ids;                           # snoozed reappears
        assert len(_ag_actions(cl, a, "all")) == len(rows);  # still no duplicates

        # ---- approve ask_network -> PostRequest (edited need)
        an = _ag_by_kind(open3, "ask_network")[0];
        ap = dict(_ag_run(cl, a, "ResolveAgentAction", {
            "action_id": str(an["action"]["_jac_id"]), "decision": "approve",
            "edited_draft": "a robotics engineer to run two pilots t1"
        })[0]);
        print(f"[agent] approve ask_network {ap}");
        assert str(ap["action"]["status"]) == "approved";
        assert str(ap["action"]["approval_source"]) == "in_app";
        assert str(ap["result"]["step"]) == "posted";
        mine = _ag_run(cl, a, "ListMyRequests", {});
        needs = [str(m["request"]["need"]) for m in mine];
        assert "a robotics engineer to run two pilots t1" in needs, needs;

        # ---- approve a draft-only kind stores the edited draft, sends nothing
        rt_ap = dict(_ag_run(cl, a, "ResolveAgentAction", {
            "action_id": str(rt["action"]["_jac_id"]), "decision": "approve", "edited_draft": "Hi Dev, quick favour?"
        })[0]);
        assert str(rt_ap["result"]["step"]) == "draft_saved";
        assert str(rt_ap["action"]["draft"]) == "Hi Dev, quick favour?";

        # ---- approve promise_due with complete -> Promise done
        pd_ap = dict(_ag_run(cl, a, "ResolveAgentAction", {"action_id": pd_id, "decision": "approve", "complete": True})[0]);
        assert str(pd_ap["result"]["step"]) == "CompletePromise";
        assert bool(pd_ap["result"]["promise"]["done"]);

        # ---- approve answer_ask -> ReplyToRequest (scorer stubbed -> fallback)
        orig = _ag_stub_scorer();
        aa_ap = dict(_ag_run(cl, a, "ResolveAgentAction", {"action_id": str(aa["action"]["_jac_id"]), "decision": "approve"})[0]);
        print(f"[agent] approve answer_ask {aa_ap}");
        assert str(aa_ap["result"]["step"]) == "replied";
        assert str(aa_ap["result"]["reply"]["request_id"]) == b_req_id;

        # ---- isolation: B never sees or resolves A's actions
        b_rows = _ag_actions(cl, b, "all");
        a_ids = [str(r["action"]["_jac_id"]) for r in _ag_actions(cl, a, "all")];
        for r in b_rows {
            assert str(r["action"]["_jac_id"]) not in a_ids;
        }
        stolen = dict(_ag_run(cl, b, "ResolveAgentAction", {"action_id": a_ids[0], "decision": "dismiss"})[0]);
        assert str(stolen["error"]) == "not_found";
        b_run = dict(_ag_run(cl, b, "RunAgent", {})[0]);
        for r in _ag_actions(cl, b, "all") {
            assert str(r["action"]["_jac_id"]) not in a_ids;
            assert str(r["action"]["person_id"]) not in [str(seed["maya_id"]), str(seed["dev_id"])];
        }
        print(f"[agent] B run {b_run}");
    } finally {
        _ag_restore_scorer(orig);
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

# ---------------------------------------------------------------- SOH-223 tune
#
# `step_new_match` and `step_answer_ask`'s deterministic candidate filter are
# exercised directly (same idiom `edits.test.jac` uses for `update_person_for`):
# a hand-built `me`/`goal`/`Person` graph, never through `root spawn`, since a
# walker's own `[root --> [?:Me]][0]` pick is ambiguous once more than one
# test has left a `Me` on the shared persisted `jac-testing` root. Each test
# below passes its OWN `goal` (or `me`) into the plain def, so results never
# leak across tests even though the underlying root is shared.

"""One RelevantTo(person, goal) pair with one resolvable Fact as evidence, so
`step_new_match` can see it. Returns the person's jid."""
def _nm_seed(goal: Goal, name: str, strength: str, observed_at: str) -> str {
    note = (root ++> Note(text=f"{name} note", kind="debrief", captured_at=observed_at))[0];
    fact = (note +>:Asserts(span=f"{name} span"):+> Fact(text=f"{name} is relevant", observed_at=observed_at))[0];
    p = (root ++> Person(name=name))[0];
    fact +>:FactAbout:+> p;
    p +>:RelevantTo(reason=f"{name} matches", strength=strength, evidence=[jid(fact)]):+> goal;
    return jid(p);
}

"""SOH-212 (judge3): a warm path per `gaps.warm_lines_for` — a person `me`
actually `Knows`, with a `RelevantTo(label="known", strength="strong")` edge
into `goal`. Deliberately NO evidence on the edge, so `step_new_match` never
turns this into its own `new_match` finding — this seed exists only to flip
`gaps.warm_lines_for(me, goal)` from empty to non-empty."""
def _warm_seed(me: Me, goal: Goal, name: str, source_note_id: str) -> str {
    p = (root ++> Person(name=name, status="confirmed"))[0];
    me +>:Knows(status="confirmed", source_note=source_note_id):+> p;
    p +>:RelevantTo(reason=f"{name} matches", strength="strong", label="known"):+> goal;
    return jid(p);
}

test "agent tune: step_new_match caps the first run at 3, strong before medium, newest evidence breaks ties" {
    me = (root ++> Me(name="Tune-test FirstRun Me"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Tune-test firstrun goal", created_at="2026-01-01T00:00:00"))[0];

    # 4 strong (oldest -> newest p1..p4) + 2 medium (p6 older than p5), all resolvable.
    p1 = _nm_seed(goal, "Tune FR P1", "strong", "2026-01-01T00:00:01");
    p2 = _nm_seed(goal, "Tune FR P2", "strong", "2026-01-01T00:00:02");
    p3 = _nm_seed(goal, "Tune FR P3", "strong", "2026-01-01T00:00:03");
    p4 = _nm_seed(goal, "Tune FR P4", "strong", "2026-01-01T00:00:04");
    p5 = _nm_seed(goal, "Tune FR P5", "medium", "2026-01-01T00:00:06");
    p6 = _nm_seed(goal, "Tune FR P6", "medium", "2026-01-01T00:00:05");

    current1: dict[str, str] = {};
    findings1 = step_new_match([goal], None, current1, False);
    proposed1 = [f for f in findings1 if bool(f["propose"])];
    proposed_pids1 = sorted([str(f["person_id"]) for f in proposed1]);
    assert len(proposed1) == 3, findings1;
    # newest 3 STRONG people win: p1 (oldest strong) and both mediums (p5, p6,
    # despite newer evidence than p1) are excluded — strong ranks before medium.
    assert proposed_pids1 == sorted([p2, p3, p4]), (proposed_pids1, [p1, p2, p3, p4, p5, p6]);
    assert len(current1) == 6;   # every strength seen is remembered for next run, including the 3 not proposed

    # ---- "second run" with nothing changed (same strengths read back as `prior`) -> nothing new
    findings2 = step_new_match([goal], current1, {}, True);
    proposed2 = [f for f in findings2 if bool(f["propose"])];
    assert len(proposed2) == 0, findings2;
}

test "agent tune: step_new_match proposes only on a real rank rise (medium -> strong)" {
    me = (root ++> Me(name="Tune-test Rise Me"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Tune-test rise goal", created_at="2026-01-01T00:00:00"))[0];
    pid = _nm_seed(goal, "Tune Rise P", "medium", "2026-01-01T00:00:00");
    prior: dict[str, str] = {f"{pid}|{jid(goal)}": "medium"};

    # unchanged (still medium) -> not proposed
    unchanged = step_new_match([goal], prior, {}, True);
    assert len([f for f in unchanged if bool(f["propose"])]) == 0, unchanged;

    # the stored strength rises to strong
    people = [goal <-:RelevantTo:<-];
    rel = [edge people[0] ->:RelevantTo:-> goal][0];
    rel.strength = "strong";

    risen = step_new_match([goal], prior, {}, True);
    proposed = [f for f in risen if bool(f["propose"])];
    assert len(proposed) == 1, risen;
    assert str(proposed[0]["person_id"]) == pid;
}

test "SOH-226: step_new_match's title/why are product copy - first name, quoted goal noun phrase, no raw sentence splice, no '(evidence: ...)'" {
    me = (root ++> Me(name="Copy-test Me"))[0];
    # a legacy goal stored before SOH-226 (raw "I am looking to..." ask) -
    # `goal_noun_phrase` is applied defensively at read time too.
    goal = (me +>:HasGoal:+> Goal(text="I am looking to find a technical cofounder", created_at="2026-01-01T00:00:00"))[0];
    _nm_seed(goal, "Maya Chen", "strong", "2026-01-01T00:00:01");

    findings = step_new_match([goal], None, {}, False);
    assert len(findings) == 1, findings;
    f = findings[0];
    title = str(f["title"]);
    why = str(f["why"]);

    assert title == "Maya: strong match for 'find a technical cofounder'.", title;
    assert "Maya Chen" not in title, "first name only after the first mention";
    assert "I am looking to" not in title and "I'm looking to" not in title, "never splice the raw first-person goal sentence";
    assert "(evidence" not in why.lower(), why;
    assert not why.startswith("The fact"), why;
}

test "agent tune (review fix 5): prior={} from a run that saw zero RelevantTo edges still gets the first-run cap" {
    me = (root ++> Me(name="Tune-test ZeroPrior Me"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Tune-test zeroprior goal", created_at="2026-01-01T00:00:00"))[0];

    p1 = _nm_seed(goal, "Tune ZP P1", "strong", "2026-01-01T00:00:01");
    p2 = _nm_seed(goal, "Tune ZP P2", "strong", "2026-01-01T00:00:02");
    p3 = _nm_seed(goal, "Tune ZP P3", "strong", "2026-01-01T00:00:03");
    p4 = _nm_seed(goal, "Tune ZP P4", "strong", "2026-01-01T00:00:04");

    # prior={} (not None) simulates an earlier AgentRun whose `current` came
    # back empty (e.g. no RelevantTo edges existed yet at the time) — the
    # account has NOT actually had a new_match action proposed yet.
    capped = step_new_match([goal], {}, {}, False);
    proposed_capped = [f for f in capped if bool(f["propose"])];
    assert len(proposed_capped) == 3, capped;   # still capped: nothing has ever been proposed

    # once the account HAS seen a new_match proposal before, the same prior={}
    # is read as a real rise-from-empty and every match is proposed, uncapped.
    uncapped = step_new_match([goal], {}, {}, True);
    proposed_uncapped = [f for f in uncapped if bool(f["propose"])];
    assert len(proposed_uncapped) == 4, uncapped;
}

test "agent tune: answer_ask needs real token overlap; a real 2-token match names them in why" {
    tmp_dir = tempfile.mkdtemp();
    try {
        cl = JacTestClient.from_file(_ag_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data_tune"));
        a = _ag_reg(cl, "agent_tune_a2@example.com");
        b = _ag_reg(cl, "agent_tune_b2@example.com");

        _ag_run(cl, a, "DevMakeCard", {"handle": "tune2-alice", "name": "Alice"});
        _ag_run(cl, b, "DevMakeCard", {"handle": "tune2-bob", "name": "Bob"});
        seed = dict(_ag_run(cl, a, "DevSeedAgent", {"tag": "tune2"})[0]);
        print(f"[agent-tune] seed {seed}");

        posted = _ag_run(cl, b, "PostRequest", {
            "need": "experienced nurses in Detroit", "about_line": "Building a clinic", "audience": "everyone"
        });
        req_id = str(posted[0]["_jac_id"]);

        # ---- A's whole graph (climate/robotics) has no nurse/Detroit tokens -> 0 answer_ask
        run1 = dict(_ag_run(cl, a, "RunAgent", {"reason": "tune-nomatch"})[0]);
        print(f"[agent-tune] run1 {run1}");
        rows1 = _ag_actions(cl, a, "open");
        assert len(_ag_by_kind(rows1, "answer_ask")) == 0, rows1;

        # ---- add one person whose OWN facts share >= 2 tokens with the need
        _ag_run(cl, a, "DevAddPerson", {"name": "Tune Nurse"});
        seedm = dict(_ag_run(cl, a, "DevSeedMatch", {
            "name": "Tune Nurse", "fact": "nurse at Michigan Medicine, Detroit", "offer": ""
        })[0]);
        print(f"[agent-tune] seedm {seedm}");

        run2 = dict(_ag_run(cl, a, "RunAgent", {"reason": "tune-match"})[0]);
        print(f"[agent-tune] run2 {run2}");
        rows2 = _ag_actions(cl, a, "open");
        aa2 = _ag_by_kind(rows2, "answer_ask");
        assert len(aa2) == 1, rows2;   # only the nurse candidate qualifies, capped list stays at 1
        assert str(aa2[0]["action"]["request_id"]) == req_id;
        why = str(aa2[0]["action"]["why"]);
        assert "matches:" in why, why;
        assert "nurse" in why.lower() and "detroit" in why.lower(), why;
    } finally {
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "agent tune (review fix 2): two prefix-only matches (no exact token anywhere) still surface the candidate" {
    p = (root ++> Person(name="Tune Prefix P2"))[0];
    note = (root ++> Note(text="prefix test note 2", kind="debrief", captured_at="2026-01-01T00:00:00"))[0];
    fact = (note +>:Asserts(span="works as a nurse in a hospital"):+> Fact(text="works as a nurse in a hospital", observed_at="2026-01-01T00:00:00"))[0];
    fact +>:FactAbout:+> p;
    cand = {"person": p, "evidence": [{"kind": "fact", "text": fact.text, "jid": jid(fact)}]};

    # "nurses" only PREFIX-matches the fact's "nurse" and "hospitalization"
    # only prefix-matches "hospital" -- there is no EXACT token shared
    # anywhere. scoring.fallback_results' exact-token pre-filter (the old
    # code's first gate) would have excluded this candidate before
    # `_answer_ask_match_tokens` ever saw it.
    hits = _answer_ask_hits([cand], "nurses hospitalization");
    assert len(hits) == 1, hits;
    matched = sorted(hits[0]["matched"] as list[str]);
    assert matched == ["hospitalization", "nurses"], matched;
    assert jid(fact) in (hits[0]["evidence_ids"] as list[str]);
}

test "agent tune (review fix 3): a need's own plural/singular pair (nurse/nurses) counts as ONE token, not two" {
    p = (root ++> Person(name="Tune Dedup P"))[0];
    note = (root ++> Note(text="dedup test note", kind="debrief", captured_at="2026-01-01T00:00:00"))[0];
    fact = (note +>:Asserts(span="works as a nurse"):+> Fact(text="works as a nurse", observed_at="2026-01-01T00:00:00"))[0];
    fact +>:FactAbout:+> p;
    cand = {"person": p, "evidence": [{"kind": "fact", "text": fact.text, "jid": jid(fact)}]};

    # "nurse" and "nurses" are the same `_tok_match` family; only ONE real
    # signal ("nurse" in the candidate's own fact) backs both, so this must
    # NOT count as 2 distinct matches.
    matched = _answer_ask_match_tokens("nurse nurses", cand);
    assert len(matched) == 1, matched;

    hits = _answer_ask_hits([cand], "nurse nurses");
    assert len(hits) == 0, hits;   # still below the 2-distinct-token bar
}

test "agent tune (review fix 4): a bad evidence id on the top hit falls through to the next resolvable hit" {
    note = (root ++> Note(text="resolvable hit test note", kind="debrief", captured_at="2026-01-01T00:00:00"))[0];
    fact = (note +>:Asserts(span="a real fact"):+> Fact(text="a real fact", observed_at="2026-01-01T00:00:00"))[0];

    bad_hit = {"person_id": "p_bad", "evidence_ids": ["not_a_real_id"], "matched": ["x", "y"]};
    good_hit = {"person_id": "p_good", "evidence_ids": [jid(fact)], "matched": ["a", "b"]};

    # top hit's evidence id doesn't resolve to anything -> the OLD code
    # (`top = hits[0]`) would have yielded no action for the whole request;
    # the fixed code falls through to the next hit whose evidence resolves.
    picked = _first_resolvable_hit([bad_hit, good_hit]);
    assert picked is not None, picked;
    chosen = picked as dict[str, any];
    hit = chosen["hit"] as dict[str, any];
    assert str(hit["person_id"]) == "p_good", hit;
    ev = chosen["evidence"] as list[str];
    assert ev == [jid(fact)], ev;

    # every hit's evidence fails to resolve -> None, not an exception
    assert _first_resolvable_hit([bad_hit]) is None;
}

test "SOH-212 (judge3) run_agent_for: an open ask_network action goes stale once its goal gets a warm path; a third run does not re-propose it" {
    me = (root ++> Me(name="Tune-test AskStale Me"))[0];
    goal = (me +>:HasGoal:+> Goal(
        text="Tune-test askstale goal needs a robotics mentor", created_at="2026-01-01T00:00:00"
    ))[0];

    now = datetime.now();

    # ---- first run: no warm path yet -> ask_network open
    run1 = run_agent_for(me, "test", now);
    print(f"[agent-askstale] run1 {run1}");
    an1 = [a for a in [me ->:HasAction:->] if a.kind == "ask_network" and a.goal_id == jid(goal)];
    assert len(an1) == 1, [a.status for a in an1];
    assert an1[0].status == "open";

    # ---- give the goal a warm path (a known, strong, "known"-label RelevantTo)
    note = (root ++> Note(text="Tune-test askstale note", kind="debrief", captured_at="2026-01-02T00:00:00"))[0];
    _warm_seed(me, goal, "Tune AskStale P1", jid(note));

    # ---- second run: the action goes stale; no NEW ask_network is proposed
    run2 = run_agent_for(me, "test", now);
    print(f"[agent-askstale] run2 {run2}");
    an2 = [a for a in [me ->:HasAction:->] if a.kind == "ask_network" and a.goal_id == jid(goal)];
    assert len(an2) == 1, an2;
    assert an2[0].status == "stale", an2[0].status;
    assert an2[0].approval_source == "agent:warm_path_found", an2[0].approval_source;
    assert an2[0].resolved_at, "resolved_at must be stamped when an action goes stale";
    open_after_run2 = [a for a in [me ->:HasAction:->] if a.kind == "ask_network" and a.goal_id == jid(goal) and a.status == "open"];
    assert open_after_run2 == [], "no open ask_network must remain for a goal with a warm path";

    # ---- third run: the warm path still holds -> still stale, never re-proposed
    run3 = run_agent_for(me, "test", now);
    print(f"[agent-askstale] run3 {run3}");
    an3 = [a for a in [me ->:HasAction:->] if a.kind == "ask_network" and a.goal_id == jid(goal)];
    assert len(an3) == 1, "a third run must not re-propose ask_network while the warm path exists";
    assert an3[0].status == "stale";
}
