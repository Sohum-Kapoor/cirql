"""The one swap point between mocks and live walkers. OWNER: Person B.

Screens call these functions, never the mocks or `root spawn` directly. When a
walker lands on main, flip its branch to the live `root spawn` form below. Mocks
stay as a demo fallback (`USE_MOCKS`). `onboard_me` / `capture` return the walker's
single report; `goal_rank` / `list_people` return the whole report list — exactly
the shapes in contracts/walkers.md.

Dev-only override: `?mock=1` in the page URL routes every call here through the
mocks (no Gemini budget spent) even though `USE_MOCKS` ships False.
"""

import from .mocks.onboard { mock_onboardme }
import from .mocks.capture { mock_capture, mock_list_people }
import from .mocks.goalrank { mock_goalrank }
# LIVE: OnboardMe lives in onboard.sv.jac, Capture in capture.sv.jac, GoalRank in
# goals.sv.jac (not all in walkers.sv.jac as this comment used to assume).
sv import from ..onboard { OnboardMe }
sv import from ..capture { Capture }
sv import from ..goals { GoalRank }
sv import from ..walkers { ListPeople }
sv import from ..schema { Person }

glob USE_MOCKS: bool = False,
     MOCK_DELAY_MS: int = 600;

"""True when mocks are on: the ship flag, or `?mock=1` in the URL (dev only)."""
def:pub mocks_on() -> bool {
    if USE_MOCKS {
        return True;
    }
    search: str = String(window.location.search);  # jac:ignore[W2001]
    return "mock=1" in search;
}

async def fake_delay(ms: int) {
    await new(Promise, lambda(resolve: any, reject: any) { setTimeout(resolve, ms); });
}

"""OnboardMe(about) -> { me, interests, goals, intents, card, note_id }"""
async def:pub onboard_me(about: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_onboardme(about);
        return out;
    }
    result = root spawn OnboardMe(about=about);
    if not result.reports {
        raise Exception("OnboardMe returned no report");
    }
    out = result.reports[0];
    return out;
}

"""Capture(text, kind) -> { note_id, people, facts, intents, promises, ties }"""
async def:pub capture(text: str, kind: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_capture(text, kind);
        return out;
    }
    result = root spawn Capture(text=text, kind=kind);
    if not result.reports {
        raise Exception("Capture returned no report");
    }
    out = result.reports[0];
    return out;
}

"""GoalRank(goal_id) -> [{ person, label, strength, reason, evidence, days_since_contact, opener }]"""
async def:pub goal_rank(goal_id: str) -> list[dict] {
    rows: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        rows = mock_goalrank(goal_id);
        return rows;
    }
    result = root spawn GoalRank(goal_id=goal_id);
    rows = result.reports;
    return rows;
}

"""ListPeople() -> [Person]. In mock mode, the people mock captures produced."""
async def:pub list_people() -> list[Person] {
    found: list[Person] = [];
    if mocks_on() {
        found = mock_list_people() as list[Person];
        return found;
    }
    result = root spawn ListPeople();
    found = result.reports;
    return found;
}
