"""Tests for OnboardMe's deterministic pieces — no LLM calls (rate limits).

The extraction obj shape and the get-or-create/dedupe helpers are exercised
here. The LLM extraction path itself is proven live via curl (see the SOH-164
deliverable), not by a test.
"""

import from onboard { OnboardExtraction, name_from_about, handle_from_name, clean_list, jid_suffix, find_by_topic, find_goal_by_text, find_intent, looks_like_goal, activate_first_goal }
import from schema { Me, Interest, Goal, Intent, HasGoal }

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

test "SOH-212 name_from_about: the speaker's own name when stated, else empty" {
    assert name_from_about("I'm Sam, a nurse in Ann Arbor.") == "Sam";
    assert name_from_about("Hi! My name is Amara Osei and I study housing.") == "Amara Osei";
    assert name_from_about("I am a community organizer in Detroit.") == "";
    assert name_from_about("Community organizer, Detroit. I'm Rosa.") == "Rosa";
    assert name_from_about("") == "";
}
