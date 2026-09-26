"""The one swap point between mocks and live walkers. OWNER: Person B.

Screens call these functions, never the mocks or `root spawn` directly. When a
walker lands on main, flip its branch to the live `root spawn` form below (and
delete its mock). Each function returns the walker's first report — exactly the
shape in contracts/walkers.md.
"""

import from .mocks.onboard { mock_onboardme }
import from .mocks.capture { mock_capture }
import from .mocks.goalrank { mock_goalrank }
# LIVE SWAP: OnboardMe / Capture / GoalRank are not in walkers.sv.jac yet, and an
# `sv import` of a missing walker fails `jac check` (W1101 + E1032 on `.reports`).
# When SOH-164/166/169 land: uncomment this import, uncomment the `root spawn`
# lines in each function below, and set USE_MOCKS = False.
# sv import from ..walkers { OnboardMe, Capture, GoalRank }

glob USE_MOCKS: bool = True,
     MOCK_DELAY_MS: int = 600;

async def fake_delay(ms: int) {
    await new(Promise, lambda(resolve: any, reject: any) { setTimeout(resolve, ms); });
}

"""OnboardMe(about) -> { me, interests, goals, intents, card, note_id }"""
async def:pub onboard_me(about: str) -> dict {
    out: dict = {};
    if USE_MOCKS {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_onboardme(about);
        return out;
    }
    # TODO(SOH-164) live:
    # result = root spawn OnboardMe(about=about);
    # out = result.reports[0];
    # return out;
    raise Exception("OnboardMe is not live yet (SOH-164)");
}

"""Capture(text, kind) -> { note_id, people, facts, intents, promises, ties }"""
async def:pub capture(text: str, kind: str) -> dict {
    out: dict = {};
    if USE_MOCKS {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_capture(text, kind);
        return out;
    }
    # TODO(SOH-166) live:
    # result = root spawn Capture(text=text, kind=kind);
    # out = result.reports[0];
    # return out;
    raise Exception("Capture is not live yet (SOH-166)");
}

"""GoalRank(goal_id) -> [{ person, label, strength, reason, evidence, days_since_contact, opener }]"""
async def:pub goal_rank(goal_id: str) -> list[dict] {
    rows: list[dict] = [];
    if USE_MOCKS {
        await fake_delay(MOCK_DELAY_MS);
        rows = mock_goalrank(goal_id);
        return rows;
    }
    # TODO(SOH-169) live:
    # result = root spawn GoalRank(goal_id=goal_id);
    # rows = result.reports;
    # return rows;
    raise Exception("GoalRank is not live yet (SOH-169)");
}
