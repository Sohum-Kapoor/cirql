"""Mocks for `ListGoals`, `SetGoal(text)`, `CloseGoal(goal_id)` — SOH-169/170. OWNER: Person B.

Exact contract shapes (contracts/walkers.md, v1.1): ListGoals -> [Goal], SetGoal
-> [Goal] (creates, or reactivates identical text; deactivates every other goal),
CloseGoal -> ["closed"] | ["not_found"] (active False, never deleted).

State lives in the module-level MOCK_GOALS glob so switching / creating / closing
survives across calls under `?mock=1`. Seeded with the same two goals the
OnboardMe mock reports. Dev-only: `?mock=1&goals=0` starts with no goals.
"""

glob MOCK_GOALS: dict[str, any] = {"goals": [], "ready": False, "n": 0};

def _seed() -> None {
    if MOCK_GOALS["ready"] {
        return;
    }
    MOCK_GOALS["ready"] = True;
    search: str = String(window.location.search);  # jac:ignore[W2001]
    if "goals=0" in search {
        MOCK_GOALS["goals"] = [];
        return;
    }
    MOCK_GOALS["goals"] = [
        {
            "_jac_id": "mock-goal-raise",
            "text": "Raise a $750k pre-seed for Kiln Labs by December",
            "created_at": "2026-09-26T16:05:00Z",
            "active": True
        },
        {
            "_jac_id": "mock-goal-pilot",
            "text": "Land a first pilot with a Midwest manufacturer",
            "created_at": "2026-09-26T16:05:00Z",
            "active": False
        }
    ];
}

def _copy(g: dict[str, any]) -> dict[str, any] {
    return {**g};
}

def:pub mock_list_goals() -> list[dict[str, any]] {
    _seed();
    return [_copy(g) for g in (MOCK_GOALS["goals"] as list[dict[str, any]])];
}

def:pub mock_goal_text(goal_id: str) -> str {
    _seed();
    for g in MOCK_GOALS["goals"] as list[dict[str, any]] {
        if g["_jac_id"] == goal_id {
            return g["text"] as str;
        }
    }
    return "";
}

def:pub mock_set_goal(text: str) -> dict[str, any] {
    _seed();
    goals: list[dict[str, any]] = MOCK_GOALS["goals"] as list[dict[str, any]];
    target_id: str = "";
    for g in goals {
        if g["text"] == text and not target_id {
            target_id = g["_jac_id"] as str;
        }
    }
    if not target_id {
        n: int = (MOCK_GOALS["n"] as int) + 1;
        MOCK_GOALS["n"] = n;
        target_id = "mock-goal-new-" + str(n);
        goals = goals + [
            {"_jac_id": target_id, "text": text, "created_at": "2026-09-26T20:00:00Z", "active": True}
        ];
    }
    next_goals: list[dict[str, any]] = [];
    found: dict[str, any] = {};
    for g in goals {
        ng: dict[str, any] = {**g};
        ng["active"] = g["_jac_id"] == target_id;
        if ng["active"] {
            found = ng;
        }
        next_goals = next_goals + [ng];
    }
    MOCK_GOALS["goals"] = next_goals;
    return _copy(found);
}

def:pub mock_close_goal(goal_id: str) -> str {
    _seed();
    status: str = "not_found";
    next_goals: list[dict[str, any]] = [];
    for g in MOCK_GOALS["goals"] as list[dict[str, any]] {
        ng: dict[str, any] = {**g};
        if g["_jac_id"] == goal_id {
            ng["active"] = False;
            status = "closed";
        }
        next_goals = next_goals + [ng];
    }
    MOCK_GOALS["goals"] = next_goals;
    return status;
}
