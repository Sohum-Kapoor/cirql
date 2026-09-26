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
    } else {
        step = 1;
        view = "onboarding";
    }
}

impl app.refresh -> None {
    found: list[Person] = [];
    try {
        ping = root spawn Ping();
        status = "server says: " + str(ping.reports[0]);
        found = await list_people();
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
}

impl app.finish -> None {
    view = "home";
    refresh();
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

"""Done -> home, refresh ListPeople so new people show up; clear the form."""
impl app.capture_done -> None {
    cap_text = "";
    cap_note = "";
    cap_result = {};
    view = "home";
    refresh();
}

"""Empty extraction -> back to the form with the text kept."""
impl app.capture_retry -> None {
    cap_result = {};
    view = "capture";
}
