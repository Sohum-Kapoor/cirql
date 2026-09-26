"""Tests for OnboardMe's deterministic pieces — no LLM calls (rate limits).

The extraction obj shape and the get-or-create/dedupe helpers are exercised
here. The LLM extraction path itself is proven live via curl (see the SOH-164
deliverable), not by a test.
"""

import from onboard { OnboardExtraction, handle_from_name, clean_list, jid_suffix, find_by_topic, find_goal_by_text, find_intent }

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
