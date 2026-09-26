"""Handler bodies for the client shell. OWNER: Person B."""

# ---------------------------------------------------------------- auth

impl app.signup -> None {
    signup_result: dict | None = None;
    login_ok: bool = False;
    auth_pending = True;
    status = "";
    try {
        signup_result = await jacSignup(email, password);
    } except Exception as e {
        auth_pending = False;
        status = "signup failed: " + str(e);
        return;
    }
    if not signup_result["success"] {
        auth_pending = False;
        status = "signup failed (email may be in use)";
        return;
    }
    login_ok = await jacLogin(email, password);
    auth_pending = False;
    if not login_ok {
        status = "login after signup failed";
        return;
    }
    status = "";
    enter();
}

impl app.login -> None {
    ok: bool = False;
    auth_pending = True;
    status = "";
    try {
        ok = await jacLogin(email, password);
    } except Exception as e {
        ok = False;
    }
    auth_pending = False;
    if not ok {
        status = "invalid credentials";
        return;
    }
    enter();
}

impl app.logout -> None {
    jacLogout();
    view = "auth";
    people = [];
    password = "";
    step = 1;
    about = "";
    about_error = "";
    onboard = {};
    card = {};
    rows = empty_rows();
    captured_count = -1;
    capture_error = "";
    rank_rows = [];
    rank_error = "";
    cap_text = "";
    cap_kind = "debrief";
    cap_error = "";
    cap_note = "";
    cap_result = {};
    for k in list(RANK_ROWS.keys()) {
        RANK_ROWS[k] = None;
        RANK_PENDING[k] = False;
        RANK_ERRORS[k] = "";
    }
    publish_rank();
    goals_list = [];
    goals_loaded = False;
    goal_error = "";
    status = "logged out";
}

# ---------------------------------------------------------------- routing after login

"""GetMe reports a Me -> home; no Me yet -> onboarding step 1."""
impl app.enter -> None {
    me_list: list = [];
    view = "loading";
    try {
        me_result = root spawn GetMe();
        me_list = me_result.reports;
    } except Exception as e {
        me_list = [];
    }
    if len(me_list) > 0 {
        view = "home";
        refresh();
        load_goals();
    } else {
        step = 1;
        view = "onboarding";
    }
}

impl app.refresh -> None {
    found: list[Person] = [];
    try {
        found = await list_people();
        status = "";
    } except Exception as e {
        status = "couldn't reach the server";
    }
    people = found;
}

# ---------------------------------------------------------------- onboarding

"""Step 1 -> OnboardMe(about)."""
impl app.submit_about -> None {
    out: dict = {};
    about_pending = True;
    about_error = "";
    try {
        out = await onboard_me(about);
    } except Exception as e {
        about_pending = False;
        about_error = "Couldn't read that. " + str(e);
        return;
    }
    onboard = out;
    card = (out["card"] or {}) as dict;
    about_pending = False;
    step = 2;
}

"""Step 2 edits are local only (PublishCard is Tier 1)."""
impl app.set_card_field(field: str, value: any) -> None {
    # `{**card, field: value}` compiles to a literal "field" key in JS; copy then set.
    next_card: dict = {**card};
    next_card[field] = value;
    card = next_card;
}

impl app.set_row(i: int, field: str, value: str) -> None {
    next_rows: list[dict] = [];
    for (idx, r) in enumerate(rows) {
        next_row: dict = {**r};
        if idx == i {
            next_row[field] = value;
        }
        next_rows = next_rows + [next_row];
    }
    rows = next_rows;
}

"""Step 3 -> one paste blob ("Name — how.\n...") -> Capture(text, kind="paste")."""
impl app.submit_people -> None {
    lines: list[str] = [];
    for r in rows {
        name: str = (r["name"] as str).strip();
        how: str = (r["how"] as str).strip().rstrip(".");
        if name {
            lines = lines + [(name + " — " + how + ".") if how else (name + ".")];
        }
    }
    if len(lines) == 0 {
        capture_error = "Add at least one person, or skip.";
        return;
    }
    blob: str = join_lines(lines);
    out: dict = {};
    capture_pending = True;
    capture_error = "";
    try {
        out = await capture(blob, "paste");
    } except Exception as e {
        capture_pending = False;
        capture_error = "Couldn't capture those. " + str(e);
        return;
    }
    captured_count = len((out["people"] or []) as list);
    capture_pending = False;
}

impl app.skip_people -> None {
    step = 4;
    start_recall();
}

impl app.people_next -> None {
    step = 4;
    start_recall();
}

"""Step 4 -> GoalRank(goal_id=<active goal _jac_id>)."""
impl app.start_recall -> None {
    all_goals: list[dict] = (onboard["goals"] or []) as list[dict];
    goal_id: str = "";
    for g in all_goals {
        if g["active"] and not goal_id {
            goal_id = g["_jac_id"] as str;
        }
    }
    out: list[dict] = [];
    rank_rows = [];
    rank_error = "";
    if not goal_id {
        return;
    }
    rank_pending = True;
    try {
        out = await goal_rank(goal_id);
    } except Exception as e {
        rank_pending = False;
        rank_error = "Couldn't rank your network. " + str(e);
        return;
    }
    rank_rows = out;
    rank_pending = False;
    # Seed the home cache so landing on home doesn't spend a second GoalRank.
    RANK_ROWS[goal_id] = {"ok": True, "rows": out};
    publish_rank();
}

impl app.finish -> None {
    view = "home";
    refresh();
    load_goals();
}

# ---------------------------------------------------------------- capture (SOH-167)

impl app.open_capture -> None {
    cap_error = "";
    view = "capture";
}

impl app.close_capture -> None {
    cap_error = "";
    view = "home";
}

"""Capture(text, kind) -> review. The note is saved server-side even when the
extraction comes back empty; the review screen says so."""
impl app.submit_capture -> None {
    text: str = cap_text.strip();
    if not text {
        cap_error = "Write something first.";
        return;
    }
    out: dict = {};
    cap_pending = True;
    cap_error = "";
    try {
        out = await capture(text, cap_kind);
    } except Exception as e {
        cap_pending = False;
        cap_error = "Couldn't capture that — your text is still here. " + str(e);
        return;
    }
    cap_note = text;
    cap_result = out;
    cap_pending = False;
    view = "review";
}

"""Done -> home, refresh ListPeople so new people show up; clear the form.
The new note can change who helps with the active goal, so its cached GoalRank
is dropped and re-ranked (the old rows are gone; the list shows its skeleton)."""
impl app.capture_done -> None {
    gid: str = active_goal_id(goals_list);
    cap_text = "";
    cap_note = "";
    cap_result = {};
    view = "home";
    refresh();
    if gid {
        RANK_ROWS[gid] = None;
        publish_rank();
        ensure_rank(gid);
    }
}

"""Empty extraction -> back to the form with the text kept."""
impl app.capture_retry -> None {
    cap_result = {};
    view = "capture";
}

# ---------------------------------------------------------------- goals + ranking (SOH-170)

impl app.publish_rank -> None {
    rank_cache = {**RANK_ROWS};
    rank_pending_map = {**RANK_PENDING};
    rank_error_map = {**RANK_ERRORS};
}

"""ListGoals -> goals_list; rank the active goal unless it's cached."""
impl app.load_goals -> None {
    found: list[dict] = [];
    try {
        found = await list_goals();
    } except Exception as e {
        goal_error = "Couldn't load your goals. " + str(e);
        goals_loaded = True;
        return;
    }
    goals_list = found;
    goals_loaded = True;
    gid: str = active_goal_id(found);
    if gid {
        ensure_rank(gid);
    }
}

"""GoalRank(goal_id) into the cache. Skips when cached (unless `force`) or
already in flight. A forced re-rank keeps the old rows on screen (dimmed)."""
impl app.ensure_rank(goal_id: str, force: bool = False) -> None {
    if not goal_id {
        return;
    }
    entry: dict = (RANK_ROWS[goal_id] or {}) as dict;
    if entry["ok"] and not force {
        publish_rank();
        return;
    }
    if RANK_PENDING[goal_id] {
        return;
    }
    RANK_PENDING[goal_id] = True;
    RANK_ERRORS[goal_id] = "";
    publish_rank();
    out: list[dict] = [];
    try {
        out = await goal_rank(goal_id);
    } except Exception as e {
        RANK_PENDING[goal_id] = False;
        RANK_ERRORS[goal_id] = "Couldn't rank your network for this goal. Tap Re-rank to try again.";
        publish_rank();
        return;
    }
    RANK_ROWS[goal_id] = {"ok": True, "rows": out};
    RANK_PENDING[goal_id] = False;
    publish_rank();
}

"""Switch = SetGoal(<that goal's text>). The header flips and the list renders
from cache (or starts ranking) immediately; SetGoal persists it alongside."""
impl app.switch_goal(goal_id: str) -> None {
    target: dict = {};
    for g in goals_list {
        if g["_jac_id"] == goal_id {
            target = g;
        }
    }
    if not target["_jac_id"] or target["active"] {
        return;
    }
    before: list[dict] = goals_list;
    goals_list = [mark_active(g, goal_id) for g in before];
    goal_error = "";
    ensure_rank(goal_id);
    saved: dict = {};
    try {
        saved = await set_goal(target["text"] as str);
    } except Exception as e {
        goals_list = before;
        goal_error = "Couldn't switch goals — try again. " + str(e);
        return;
    }
}

"""+ New goal -> SetGoal(text) (reactivates an identical goal) -> rank it."""
impl app.create_goal(text: str) -> None {
    clean: str = text.strip();
    if not clean {
        return;
    }
    before: list[dict] = goals_list;
    saved: dict = {};
    goal_busy = True;
    goal_error = "";
    try {
        saved = await set_goal(clean);
    } except Exception as e {
        goal_busy = False;
        goal_error = "Couldn't save that goal. " + str(e);
        return;
    }
    gid: str = (saved["_jac_id"] or "") as str;
    new_goal: dict = {**saved};
    new_goal["active"] = True;
    kept: list[dict] = [mark_active(g, gid) for g in before if g["_jac_id"] != gid];
    goals_list = [new_goal] + kept;
    goal_busy = False;
    ensure_rank(gid);
}

"""CloseGoal(goal_id): inactive, never deleted; its RelevantTo edges are gone
server-side, so drop its cached ranking too."""
impl app.end_goal(goal_id: str) -> None {
    before: list[dict] = goals_list;
    out: str = "";
    goal_busy = True;
    goal_error = "";
    try {
        out = await close_goal(goal_id);
    } except Exception as e {
        goal_busy = False;
        goal_error = "Couldn't close that goal. " + str(e);
        return;
    }
    goal_busy = False;
    if out != "closed" {
        goal_error = "That goal wasn't found — refresh and try again.";
        return;
    }
    next_goals: list[dict] = [];
    for g in before {
        ng: dict = {**g};
        if g["_jac_id"] == goal_id {
            ng["active"] = False;
        }
        next_goals = next_goals + [ng];
    }
    goals_list = next_goals;
    RANK_ROWS[goal_id] = None;
    publish_rank();
}

impl app.rerank -> None {
    ensure_rank(active_goal_id(goals_list), True);
}
