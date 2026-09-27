"""Tests for OnboardMe's deterministic pieces — no LLM calls (rate limits).

The extraction obj shape and the get-or-create/dedupe helpers are exercised
here. The LLM extraction path itself is proven live via curl (see the SOH-164
deliverable), not by a test.
"""

import from onboard { OnboardExtraction, name_from_about, handle_from_name, clean_list, clean_text, jid_suffix, find_by_topic, find_goal_by_text, find_intent, looks_like_goal, has_outcome_keyword, strongest_need, promote_strongest_need, activate_first_goal, collect_goals, onboarding_added_how_met, month_day }
import from schema { Me, Interest, Goal, Intent, HasGoal }
import from datetime { datetime }
import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

# ---------------------------------------------------------------- SOH-232
# integration: a Card OnboardMe creates (default visibility "link") must be
# publicly readable via cards.get_card WITHOUT the owner ever running
# PublishCard (audit D: "Public card says 'Not shared' while Settings says
# 'Anyone with the link' and shows a QR" -- the root cause was OnboardMe's
# get-or-create never listing/granting the Card it made). Own harness,
# separate temp dir/base_path per test, no `jac clean` (AGENTS.md). The temp
# dir has no `.env`, so `extract_onboarding`'s one `by llm` call fails fast
# and OnboardMe's own try/except falls back to the deterministic path --
# the Card still gets created and `ensure_card_visible`'d (see onboard.sv.jac
# step 5), same as every other test here avoiding the LLM (SOH-166/205).

glob ONBOARD_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _ob_harness(tmp_dir: str) -> str {
    for name in ["onboard.sv.jac", "cards.sv.jac", "schema.sv.jac", "freshness.sv.jac", "goals.sv.jac", "scoring.sv.jac", "reads.sv.jac", "llm.sv.jac"] {
        shutil.copyfile(os.path.join(ONBOARD_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "onbapp.jac");
    f = open(harness_path, "w");
    f.write("import from onboard { OnboardMe }\nimport from cards { get_card, PublishCard }\n");
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"onboard-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"onbapp.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _ob_reg(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _ob_run(client: JacTestClient, token: str, wname: str, body: dict) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

def _ob_get_card_anon(client: JacTestClient, handle: str) -> dict[str, any] {
    client.clear_auth();
    resp = client.post("/function/get_card", json={"handle": handle});
    assert resp.ok, f"get_card failed: {resp.status_code} {resp.text}";
    return dict(resp.data["result"]);
}

test "SOH-232: OnboardMe's Card is publicly readable via get_card without ever running PublishCard" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ob_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _ob_reg(cl, "onboard_soh232_a@example.com");
        b = _ob_reg(cl, "onboard_soh232_b@example.com");

        out = _ob_run(cl, a, "OnboardMe", {"about": "I build accessible robots in Ann Arbor.", "name": "Priya SOH232"});
        card = dict(out[0]["card"]);
        handle = str(card["handle"]);
        assert handle, f"OnboardMe never created a Card: {out}";

        found = _ob_get_card_anon(cl, handle);
        print(f"[onboard 232] anonymous get_card({handle}) right after OnboardMe (no PublishCard) -> {found}");
        assert found["found"], f"OnboardMe's Card was not publicly readable until PublishCard ran (audit D): {found}";
        assert str(found["name"]) == "Priya SOH232";

        # Same read, from a second REGISTERED account's own token (get_card
        # is `def:pub`, but a token-holder's `root` is their own graph, not
        # `root.shared` -- proves it reaches the shared CardDirectory either
        # way, not only for an anonymous caller).
        cl.set_auth_token(b);
        resp_b = cl.post("/function/get_card", json={"handle": handle});
        assert resp_b.ok, f"get_card as B failed: {resp_b.status_code} {resp_b.text}";
        found_b = dict(resp_b.data["result"]);
        print(f"[onboard 232] B's own-token get_card({handle}) -> {found_b}");
        assert found_b["found"], f"OnboardMe's Card was not readable from a second account's own token: {found_b}";

        # A handle nobody published/onboarded is still not_found (isolation).
        missing = _ob_get_card_anon(cl, "no-such-onboard-232-handle");
        assert not missing["found"];
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "SOH-232: an explicit handshake_only PublishCard after OnboardMe stays unreadable via get_card" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_ob_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data_hs"));
        client = cl;
        a = _ob_reg(cl, "onboard_soh232_hs_a@example.com");

        onboarded = _ob_run(cl, a, "OnboardMe", {"about": "I run a climate fund.", "name": "Devon SOH232"});
        handle = str(dict(onboarded[0]["card"])["handle"]);
        visible = _ob_get_card_anon(cl, handle);
        assert visible["found"], f"pre-condition: OnboardMe's card should start public: {visible}";

        republished = _ob_run(cl, a, "PublishCard", {"visibility": "handshake_only"});
        assert str(republished[0]["visibility"]) == "handshake_only";

        hidden = _ob_get_card_anon(cl, handle);
        print(f"[onboard 232 hs] get_card({handle}) after handshake_only republish -> {hidden}");
        assert not hidden["found"], f"handshake_only card leaked through get_card: {hidden}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "OnboardExtraction obj holds the fields the walker copies out" {
    extraction = OnboardExtraction(
        name="Sam",
        interests=["accessible robotics", "climate tech"],
        goals=["Ship a VC-ready pitch this summer."],
        needs=["feedback from wheelchair users"],
        offers=["intros to robotics faculty"],
        headline="Builder of accessible robots.",
        card_about="I build accessible robotics and run the campus hackathon.",
        links=["github.com/sam-builds"]
    );
    assert extraction.name == "Sam";
    assert len(extraction.interests) == 2;
    assert extraction.needs[0] == "feedback from wheelchair users";
}

test "handle_from_name slugifies deterministically" {
    assert handle_from_name("Sam") == "sam";
    assert handle_from_name("Sam T. Builder") == "sam-t-builder";
    assert handle_from_name("me") == "me";
    assert handle_from_name("!!!") == "me";
    assert handle_from_name("--Sam--") == "sam";
}

test "clean_list strips, drops empties, dedupes case-insensitively in order" {
    out = clean_list([" Robotics ", "robotics", "", "  ", "Climate Tech", "climate tech", "AI"]);
    assert out == ["Robotics", "Climate Tech", "AI"];
}

test "jid_suffix lowercases the last 6 alnum chars" {
    assert jid_suffix("b859ebb2d4b34d308478bf4bf17812d9") == "7812d9";
    assert jid_suffix("ABC123") == "abc123";
}

test "find_by_topic, find_goal_by_text, find_intent dedupe helpers" {
    interests = [Interest(topic="climate tech"), Interest(topic="robotics")];
    hit = find_by_topic(interests, "robotics");
    assert hit is not None and hit.topic == "robotics";
    assert find_by_topic(interests, "not-there") is None;

    goals = [Goal(text="Ship a demo.", created_at="2026-01-01T00:00:00")];
    g = find_goal_by_text(goals, "Ship a demo.");
    assert g is not None and g.text == "Ship a demo.";
    assert find_goal_by_text(goals, "Other goal.") is None;

    intents = [Intent(kind="need", text="Feedback from users", source_kind="self")];
    i = find_intent(intents, "need", "feedback from users");
    assert i is not None and i.text == "Feedback from users";
    assert find_intent(intents, "offer", "feedback from users") is None;
    assert find_intent(intents, "need", "no match") is None;
}

test "looks_like_goal accepts asks, rejects descriptions of what they do/build" {
    assert looks_like_goal("Raise a pre-seed round from climate-tech investors");
    assert looks_like_goal("Land a summer 2027 VC internship");
    assert not looks_like_goal("I am a robotics engineer");
    assert not looks_like_goal("I'm building an accessible robot");
    assert not looks_like_goal("I build accessible robots");
    assert not looks_like_goal("I work on climate tech");
    assert not looks_like_goal("We build a robotics startup");
    assert not looks_like_goal("We are a climate tech company");
    assert not looks_like_goal("i am case-insensitive too");
}

test "SOH-164 looks_like_goal: an 'I'm ...' phrasing still counts as a goal when it names an outcome" {
    assert looks_like_goal("I'm raising a pre-seed round from climate-tech investors");
    assert looks_like_goal("We are looking to hire our first co-founder this fall");
    assert not looks_like_goal("I'm building an accessible robot");
}

test "SOH-164 has_outcome_keyword / strongest_need" {
    assert has_outcome_keyword("pre-seed funding");
    assert has_outcome_keyword("intros to climate-tech investors");
    assert not has_outcome_keyword("a nice conversation");

    assert strongest_need([]) == "";
    assert strongest_need(["a nice conversation"]) == "a nice conversation";
    assert strongest_need(["pre-seed funding", "intros to climate-tech investors"]) == "intros to climate-tech investors";
}

test "SOH-164 promote_strongest_need: no goal stated, two needs -> one active Goal with the promoted text" {
    me = (root ++> Me(name="promote-empty-goals-test-me"))[0];
    existing_goals: list[Goal] = [me ->:HasGoal:->];
    goals: list[Goal] = [];
    needs = ["pre-seed funding", "intros to climate-tech investors"];

    goals = promote_strongest_need(me, existing_goals, goals, needs, "2026-01-01T00:00:00");

    assert len(goals) == 1, f"expected one promoted goal, got {len(goals)}";
    assert goals[0].text == "intros to climate-tech investors";
    assert goals[0].active;
    on_root = [me ->:HasGoal:->];
    assert len(on_root) == 1;
}

test "SOH-164 promote_strongest_need: goals already present -> no promotion" {
    me = (root ++> Me(name="promote-goals-present-test-me"))[0];
    stated = (me +>:HasGoal:+> Goal(text="Raise a pre-seed round", created_at="2026-01-01T00:00:00"))[0];
    existing_goals: list[Goal] = [me ->:HasGoal:->];
    goals: list[Goal] = [stated];
    needs = ["intros to climate-tech investors"];

    goals = promote_strongest_need(me, existing_goals, goals, needs, "2026-01-01T00:00:00");

    assert len(goals) == 1;
    assert goals[0].text == "Raise a pre-seed round";
    on_root = [me ->:HasGoal:->];
    assert len(on_root) == 1, "no need should have been promoted to a second Goal";
}

test "SOH-164 promote_strongest_need: no needs -> no goal" {
    me = (root ++> Me(name="promote-no-needs-test-me"))[0];
    existing_goals: list[Goal] = [me ->:HasGoal:->];
    goals: list[Goal] = [];

    goals = promote_strongest_need(me, existing_goals, goals, [], "2026-01-01T00:00:00");

    assert len(goals) == 0;
    on_root = [me ->:HasGoal:->];
    assert len(on_root) == 0;
}

test "activate_first_goal: exactly one active goal, first extracted wins, pre-existing goals deactivated" {
    me = (root ++> Me(name="activate-test-me"))[0];
    pre_existing = (me +>:HasGoal:+> Goal(text="Pre-existing goal", created_at="2026-01-01T00:00:00", active=True))[0];
    g1 = (me +>:HasGoal:+> Goal(text="First extracted goal", created_at="2026-01-01T00:00:00", active=True))[0];
    g2 = (me +>:HasGoal:+> Goal(text="Second extracted goal", created_at="2026-01-01T00:00:00", active=True))[0];

    activate_first_goal(me, [g1, g2]);

    assert g1.active;
    assert not g2.active;
    assert not pre_existing.active;
}

test "activate_first_goal is a no-op on an empty goal list" {
    me = (root ++> Me(name="activate-noop-test-me"))[0];
    g = (me +>:HasGoal:+> Goal(text="Untouched goal", created_at="2026-01-01T00:00:00", active=True))[0];

    activate_first_goal(me, []);

    assert g.active;
}

test "SOH-225 find_goal_by_text: near-duplicate phrasing matches, a distinct goal does not" {
    goals = [Goal(text="Land a summer 2027 climate-tech VC internship", created_at="2026-01-01T00:00:00")];
    g = find_goal_by_text(goals, "land a climate-tech VC internship for summer 2027");
    assert g is not None and g.text == "Land a summer 2027 climate-tech VC internship";
    assert find_goal_by_text(goals, "Find a mentor in accessible robotics") is None;
}

test "SOH-225 collect_goals: two near-duplicate extracted goal texts in one batch yield a single goal" {
    me = (root ++> Me(name="collect-goals-batch-test-me"))[0];
    existing_goals: list[Goal] = [me ->:HasGoal:->];

    goals = collect_goals(me, existing_goals, [
        "Land a summer 2027 climate-tech VC internship",
        "land a climate-tech VC internship for summer 2027"
    ], "2026-01-01T00:00:00");

    assert len(goals) == 1, f"expected one goal, got {len(goals)}: {[g.text for g in goals]}";
    on_root = [me ->:HasGoal:->];
    assert len(on_root) == 1, "collect_goals must not create a second Goal node for the near-duplicate";
}

test "SOH-225 collect_goals: dedupes against a goal already on the root, and still creates a genuinely different one" {
    me = (root ++> Me(name="collect-goals-existing-test-me"))[0];
    pre = (me +>:HasGoal:+> Goal(text="Land a climate-tech VC internship for summer 2027", created_at="2026-01-01T00:00:00"))[0];
    existing_goals = [me ->:HasGoal:->];

    goals = collect_goals(me, existing_goals, [
        "Land a summer 2027 climate-tech VC internship",
        "Find a mentor in accessible robotics"
    ], "2026-01-02T00:00:00");

    assert len(goals) == 2;
    assert jid(goals[0]) == jid(pre), "the near-duplicate must reuse the pre-existing goal, not create a new one";
    assert goals[1].text == "a mentor in accessible robotics", "SOH-226: new goal text is stored as a noun phrase (leading 'Find ' stripped, lowercased)";
    on_root = [me ->:HasGoal:->];
    assert len(on_root) == 2;
}

test "SOH-212 clean_text strips only trailing sentence punctuation/whitespace, never internal text" {
    assert clean_text("Identify promising Jac teams to follow after JacHacks. ") == "Identify promising Jac teams to follow after JacHacks";
    assert clean_text("Land an internship!") == "Land an internship";
    assert clean_text("Find a co-founder??") == "Find a co-founder";
    assert clean_text("  Multiple   spaces kept internally  ") == "Multiple   spaces kept internally";
    assert clean_text("Mr. Fixit.") == "Mr. Fixit";
    assert clean_text("") == "";
    assert clean_text("!!!") == "";
}

test "SOH-212 clean_list also strips trailing punctuation (goal/intent/interest storage)" {
    out = clean_list([
        "Identify promising Jac teams to follow after JacHacks. ",
        "Land an internship!",
        "  Robotics  "
    ]);
    assert out == ["Identify promising Jac teams to follow after JacHacks", "Land an internship", "Robotics"];
}

test "SOH-212 collect_goals stores a goal with its trailing punctuation stripped" {
    me = (root ++> Me(name="collect-goals-clean-test-me"))[0];
    existing_goals: list[Goal] = [me ->:HasGoal:->];

    goals = collect_goals(me, existing_goals, ["Identify promising Jac teams to follow after JacHacks. "], "2026-01-01T00:00:00");

    assert len(goals) == 1;
    assert goals[0].text == "identify promising Jac teams to follow after JacHacks", f"trailing '. ' leaked into the stored goal text, or SOH-226's noun-phrase lowercasing regressed: {goals[0].text!r}";
}

test "SOH-212 month_day / onboarding_added_how_met: hand-written-style date, no leading zero" {
    dt = datetime(2026, 9, 26);
    assert month_day(dt) == "Sep 26";
    assert onboarding_added_how_met(dt) == "added when you set up Cirql (Sep 26)";

    dt2 = datetime(2026, 1, 5);
    assert month_day(dt2) == "Jan 5", f"expected no leading zero on the day, got {month_day(dt2)!r}";
}

test "SOH-212 name_from_about: the speaker's own name when stated, else empty" {
    assert name_from_about("I'm Sam, a nurse in Ann Arbor.") == "Sam";
    assert name_from_about("Hi! My name is Amara Osei and I study housing.") == "Amara Osei";
    assert name_from_about("I am a community organizer in Detroit.") == "";
    assert name_from_about("Community organizer, Detroit. I'm Rosa.") == "Rosa";
    assert name_from_about("") == "";
}
