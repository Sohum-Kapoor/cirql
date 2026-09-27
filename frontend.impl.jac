"""Handler bodies for the client shell. OWNER: Person B."""

# ---------------------------------------------------------------- auth

impl app.signup -> None {
    signup_result: dict | None = None;
    login_ok: bool = False;
    signup_pending = True;
    status = "";
    try {
        signup_result = await jacSignup(email, password);
    } except Exception as e {
        signup_pending = False;
        status = "Couldn't create the account. That email may already be in use.";
        return;
    }
    if not signup_result["success"] {
        signup_pending = False;
        status = "Couldn't create the account. That email may already be in use.";
        return;
    }
    login_ok = await jacLogin(email, password);
    signup_pending = False;
    if not login_ok {
        status = "Account created, but sign-in failed. Try logging in.";
        return;
    }
    status = "";
    enter();
}

impl app.login -> None {
    if not email.strip() or not password.strip() {
        status = "Enter your email and password.";
        return;
    }
    ok: bool = False;
    login_pending = True;
    status = "";
    try {
        ok = await jacLogin(email, password);
    } except Exception as e {
        ok = False;
    }
    login_pending = False;
    if not ok {
        status = "Invalid email or password.";
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
    onboard_name = "";
    about_error = "";
    onboard = {};
    card = {};
    rows = empty_rows();
    capture_error = "";
    rank_rows = [];
    rank_error = "";
    cap_text = "";
    cap_kind = "voice";
    tab = "home";
    clear_session_ui();
    cap_guided = empty_guided();
    cap_voice = empty_voice();
    cap_how_met = "";
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
    for k in list(GAP_ROWS.keys()) {
        GAP_ROWS[k] = None;
        GAP_PENDING[k] = False;
        GAP_ERRORS[k] = "";
    }
    publish_gaps();
    EX["mine"] = [];
    EX["incoming"] = [];
    EX["friend"] = {};
    EX["claims"] = {};
    EX["claiming"] = {};
    EX["friends"] = [];
    INCOMING_SIG = "";
    publish_ex();
    AGENT["rows"] = [];
    AGENT["loaded"] = False;
    AGENT["running"] = False;
    AGENT["error"] = "";
    AGENT["pending"] = {};
    AGENT["errors"] = {};
    AGENT["last_run"] = {};
    AGENT["queued"] = "";
    publish_agent();
    open_req_id = "";
    open_ask_id = "";
    ask_error = "";
    req_error = "";
    me_name = "";
    me_about = "";
    status = "";
    clear_onboard_progress();
    clear_cache();
}

# ---------------------------------------------------------------- routing after login

"""SOH-236: paint last session's people/goals/rank/gap rows from localStorage
immediately on mount, before any network call lands, and flip straight to Home
so a returning user never sees the full "Loading your people…" screen. `enter`
still runs its live loads right after this and will override anything that
turns out stale (a real GetMe answer, onboarding, or a logged-out redirect)."""
impl app.hydrate_cache -> None {
    cached_people: any = cache_get("people");
    if cached_people {
        people = cached_people as list[Person];
        view = "home";
    }
    cached_goals: any = cache_get("goals");
    if cached_goals {
        goals_list = cached_goals as list[dict];
    }
    cached_rank: any = cache_get("rank");
    if cached_rank {
        rd: dict = cached_rank as dict;
        for k in list(rd.keys()) {
            RANK_ROWS[k] = rd[k];
        }
        publish_rank();
    }
    cached_gaps: any = cache_get("gaps");
    if cached_gaps {
        gd: dict = cached_gaps as dict;
        for k in list(gd.keys()) {
            GAP_ROWS[k] = gd[k];
        }
        publish_gaps();
    }
}

"""GetMe reports a Me -> home; no Me yet -> onboarding step 1. Either way,
first checks for onboarding progress this tab already had in flight (SOH-232):
`OnboardMe` (step 1) already creates the Me node, so a bare "Me exists" check
would otherwise drop a mid-onboarding reload/re-login on Home with zero
people. `finish` clears the saved progress once onboarding actually
completes, so a returning, fully onboarded user still lands on Home.

SOH-236: ListPeople / ListGoals / ListPromises start alongside GetMe instead
of waiting behind it (none of the three depend on its answer) — ListPromises'
result is discarded here, fired only to warm the 60s reader cache PromisesDue
reads moments later. A GetMe exception (a stale/reset session token auth
still accepts but that resolves to nothing) is treated as logged out rather
than "new account, needs onboarding" — a genuinely new account never throws
here, it just reports zero people. The full-screen "Loading your people…" only
shows when `hydrate_cache` had nothing to paint — a returning user with a
cache already sees last session's rows instead."""
impl app.enter -> None {
    me_list: list = [];
    if len(people) == 0 {
        view = "loading";
    }
    refresh();
    load_goals();
    warm_promises();
    ok: bool = True;
    try {
        me_result = root spawn GetMe();
        me_list = me_result.reports;
    } except Exception as e {
        ok = False;
    }
    if not ok {
        logout();
        return;
    }
    progress: dict = load_onboard_progress();
    saved_step: int = (progress["step"] or 0) as int;
    resumable: bool = saved_step >= 1 and saved_step <= 4 and owns_progress(progress);
    if len(me_list) > 0 {
        me_name = (me_list[0].name or "") as str;
        me_about = (me_list[0].about or "") as str;
        if resumable {
            step = saved_step;
            onboard_name = ((progress["name"] or me_name) as str);
            about = ((progress["about"] or me_about) as str);
            card = (progress["card"] or {}) as dict;
            rows = (progress["rows"] or empty_rows()) as list[dict];
            onboard = (progress["onboard"] or {}) as dict;
            view = "onboarding";
            return;
        }
        view = "home";
        load_mine();
        load_incoming();
        load_friends();
        agent_on_open();
    } elif resumable {
        step = saved_step;
        onboard_name = ((progress["name"] or "") as str);
        about = ((progress["about"] or "") as str);
        card = (progress["card"] or {}) as dict;
        rows = (progress["rows"] or empty_rows()) as list[dict];
        onboard = (progress["onboard"] or {}) as dict;
        view = "onboarding";
    } else {
        step = 1;
        view = "onboarding";
    }
}

impl app.refresh -> None {
    found: list[Person] = [];
    ok: bool = True;
    try {
        found = await list_people();
        status = "";
    } except Exception as e {
        status = "couldn't reach the server";
        ok = False;
    }
    people = found;
    if ok {
        cache_set("people", found);
    }
}

# ---------------------------------------------------------------- onboarding

"""Step 1 -> OnboardMe(about, name). `name` (the signup field) wins over
anything the walker extracts from `about` — the card handle is derived from
it, so `me-xxxx` never reaches the graph centre node."""
impl app.submit_about -> None {
    out: dict = {};
    about_pending = True;
    about_error = "";
    clean_name: str = onboard_name.strip();
    if not clean_name {
        about_pending = False;
        about_error = "Your name is required.";
        return;
    }
    try {
        out = await onboard_me(about, clean_name);
    } except Exception as e {
        about_pending = False;
        about_error = "Couldn't read that. " + str(e);
        return;
    }
    onboard = out;
    card = (out["card"] or {}) as dict;
    reported_name: str = ((out["me"] or {})["name"] or "") as str;
    me_name = reported_name or clean_name;
    me_about = about;
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

"""Card step goal actions (GoalPicker.onSwitch): SetGoal(<that goal's text>)
against `onboard["goals"]` — mirrors `switch_goal` but scoped to onboarding
state, never `goals_list` (owned by the home view)."""
impl app.onb_switch_goal(goal_id: str) -> None {
    existing: list[dict] = (onboard["goals"] or []) as list[dict];
    target: dict = {};
    for g in existing {
        if g["_jac_id"] == goal_id {
            target = g;
        }
    }
    if not target["_jac_id"] or target["active"] {
        return;
    }
    before: dict = onboard;
    next_onboard: dict = {**onboard};
    next_onboard["goals"] = [mark_active(g, goal_id) for g in existing];
    onboard = next_onboard;
    onb_goal_error = "";
    onb_goal_busy = True;
    saved: dict = {};
    try {
        saved = await set_goal(target["text"] as str);
    } except Exception as e {
        onboard = before;
        onb_goal_busy = False;
        onb_goal_error = "Couldn't switch goals. Try again. " + str(e);
        return;
    }
    onb_goal_busy = False;
}

"""Card step goal actions (GoalPicker.onCreate / RecallStep.onAddGoal):
SetGoal(text) — creates or reactivates a goal and deactivates every other one
under `onboard["goals"]`."""
impl app.onb_save_goal(text: str) -> str {
    clean: str = text.strip();
    if not clean {
        return "";
    }
    existing: list[dict] = (onboard["goals"] or []) as list[dict];
    saved: dict = {};
    onb_goal_busy = True;
    onb_goal_error = "";
    try {
        saved = await set_goal(clean);
    } except Exception as e {
        onb_goal_busy = False;
        onb_goal_error = "Couldn't save that goal. " + str(e);
        return "";
    }
    gid: str = (saved["_jac_id"] or "") as str;
    new_goal: dict = {**saved};
    new_goal["active"] = True;
    kept: list[dict] = [mark_active(g, gid) for g in existing if g["_jac_id"] != gid];
    next_onboard: dict = {**onboard};
    next_onboard["goals"] = [new_goal] + kept;
    onboard = next_onboard;
    onb_goal_busy = False;
    return gid;
}

"""Card step goal actions (GoalPicker.onClose): CloseGoal(goal_id) — inactive,
never deleted, scoped to `onboard["goals"]`."""
impl app.onb_close_goal(goal_id: str) -> None {
    existing: list[dict] = (onboard["goals"] or []) as list[dict];
    out: str = "";
    onb_goal_busy = True;
    onb_goal_error = "";
    try {
        out = await close_goal(goal_id);
    } except Exception as e {
        onb_goal_busy = False;
        onb_goal_error = "Couldn't close that goal. " + str(e);
        return;
    }
    onb_goal_busy = False;
    if out != "closed" {
        onb_goal_error = "That goal wasn't found. Refresh and try again.";
        return;
    }
    next_goals: list[dict] = [];
    for g in existing {
        ng: dict = {**g};
        if g["_jac_id"] == goal_id {
            ng["active"] = False;
        }
        next_goals = next_goals + [ng];
    }
    next_onboard: dict = {**onboard};
    next_onboard["goals"] = next_goals;
    onboard = next_onboard;
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

"""Step 3 -> one paste blob ("Name: how.\n...") -> Capture(text, kind="paste");
one Continue, no second click (SOH-232): success advances to step 4 and ranks
the active goal immediately, failure stays on step 3 with the error (the
button becomes Retry)."""
impl app.submit_people -> None {
    lines: list[str] = [];
    for r in rows {
        name: str = (r["name"] as str).strip();
        how: str = (r["how"] as str).strip().rstrip(".");
        if name {
            lines = lines + [(name + ": " + how + ".") if how else (name + ".")];
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
        out = await capture(blob, "paste", "", "added when you set up Cirql (" + today_month_day() + ")");
    } except Exception as e {
        capture_pending = False;
        capture_error = "Couldn't add your people. " + str(e);
        return;
    }
    capture_pending = False;
    step = 4;
    start_recall();
}

impl app.skip_people -> None {
    step = 4;
    start_recall();
}

"""Step 4 -> GoalRank(goal_id=<active goal _jac_id>)."""
impl app.start_recall(known_goal_id: str = "") -> None {
    # `known_goal_id` lets a caller that just saved a goal rank it directly: `onboard`
    # read here is this render's value, not the one set a moment ago (stale closure).
    all_goals: list[dict] = (onboard["goals"] or []) as list[dict];
    goal_id: str = known_goal_id;
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

"""Step 4's own inline add-goal (RecallStep.onAddGoal, shown when OnboardMe
never surfaced or activated a goal): SetGoal(text), then rank it immediately —
`start_recall` already ran once this render and returned early with no goal_id."""
impl app.onb_create_goal(text: str) -> None {
    await onb_save_goal(text);
}
impl app.recall_add_goal(text: str) -> None {
    new_gid: str = "";
    new_gid = await onb_save_goal(text);
    if new_gid {
        start_recall(new_gid);
    }
}

impl app.finish -> None {
    clear_onboard_progress();
    set_tab("home");
    view = "home";
    refresh();
    load_goals();
    load_mine();
    load_incoming();
    load_friends();
    agent_on_open();
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

"""Capture -> review. Guided: the composed (or hand-edited) prose, kind "debrief";
Paste: the free text, kind "paste"; Voice: the checked transcript, kind "debrief"
+ Transcribe's audio_ref. The note is saved server-side even when the extraction
comes back empty; the review screen says so."""
impl app.submit_capture -> None {
    mode: str = cap_kind;
    note: str = "";
    walker_kind: str = "debrief";
    audio: str = "";
    met_line: str = "";
    if mode == "guided" {
        note = guided_text(cap_guided).strip();
        met_line = how_met_line(cap_guided);
    } elif mode == "voice" {
        note = ((cap_voice["text"] or "") as str).strip();
        audio = (cap_voice["audio_ref"] or "") as str;
    } else {
        note = cap_text.strip();
        walker_kind = "paste";
    }
    if not note {
        cap_error = "Write something first.";
        return;
    }
    out: dict = {};
    cap_pending = True;
    cap_error = "";
    try {
        out = await capture(note, walker_kind, audio, met_line);
    } except Exception as e {
        cap_pending = False;
        cap_error = "Couldn't capture that. Your text is still here. " + str(e);
        return;
    }
    if mode == "guided" {
        remember_met((cap_guided["met"] or "") as str);
    }
    cap_note = note;
    cap_how_met = met_line;
    cap_met_names = guided_names(cap_guided) if mode == "guided" else [];
    cap_result = out;
    cap_pending = False;
    view = "review";
}

"""One guided-form field. `{**d, field: v}` would make a key literally named
"field" in JS, so copy then set."""
impl app.set_guided(field: str, value: any) -> None {
    nxt: dict = {**cap_guided};
    nxt[field] = value;
    cap_guided = nxt;
}

"""Review edits / removals replace the Capture report in place (SOH-209)."""
impl app.set_cap_result(next_result: dict) -> None {
    cap_result = next_result;
}

"""Done -> home, refresh ListPeople so new people show up; clear the form.
The new note can change who helps with the active goal, so its cached GoalRank
is dropped and re-ranked (the old rows are gone; the list shows its skeleton).

Landing (SOH-226): exactly one person touched -> open their sheet directly
(reuses HomeView's existing open_person_id hook, SOH-207); several -> a
confirmation strip on Home ("Added X and Y · 2 facts · 1 promise") naming the
first one, auto-dismissed after 4 s (frontend.cl.jac); none (everything was
removed in Review, or nothing extracted) -> plain Home, nothing to land on."""
impl app.capture_done -> None {
    gid: str = active_goal_id(goals_list);
    cap_people: list[dict] = (cap_result["people"] or []) as list[dict];
    cap_facts_n: int = len((cap_result["facts"] or []) as list);
    cap_promises_n: int = len((cap_result["promises"] or []) as list);
    landing_pid: str = "";
    landing_strip: dict = {};
    if len(cap_people) == 1 {
        landing_pid = _cap_person_id(cap_people[0]);
    } elif len(cap_people) > 1 {
        landing_strip = capture_strip(cap_people, cap_facts_n, cap_promises_n);
    }
    cap_text = "";
    cap_guided = empty_guided();
    cap_voice = empty_voice();
    cap_how_met = "";
    cap_note = "";
    cap_result = {};
    set_tab("home");
    view = "home";
    refresh();
    # SOH-236: mark every goal's ranking/gaps stale WITHOUT clearing the rows —
    # the forced re-rank below already keeps stale rows on screen (dimmed via
    # RANK_PENDING/GAP_PENDING) instead of a skeleton for two chained LLM calls.
    for k in list(RANK_ROWS.keys()) {
        RANK_STALE[k] = True;
    }
    for k in list(GAP_ROWS.keys()) {
        GAP_STALE[k] = True;
    }
    publish_rank();
    publish_gaps();
    if gid {
        RANK_STALE[gid] = True;
        ensure_rank(gid, True);
    }
    # A new note is exactly what the agent looks at: routes, gaps, follow-ups.
    run_agent_now("capture");
    if landing_pid {
        open_person_id = landing_pid;
    } elif landing_strip {
        post_capture = landing_strip;
    }
}

"""Empty extraction -> back to the form with the text kept."""
impl app.capture_retry -> None {
    cap_result = {};
    view = "capture";
}

"""Confirmation strip dismissed by hand (SOH-226) — same as its 4 s timeout."""
impl app.dismiss_post_capture -> None {
    post_capture = {};
}

"""Confirmation strip's "View <name>" (SOH-226) -> the first touched person's sheet."""
impl app.view_captured_person -> None {
    pid: str = (post_capture["person_id"] or "") as str;
    post_capture = {};
    if pid {
        open_person_id = pid;
    }
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
    cache_set("goals", found);
    gid: str = active_goal_id(found);
    if gid {
        ensure_rank(gid);
    }
}

"""GoalRank(goal_id) into the cache. Skips when cached (unless `force` or
marked stale) or already in flight. A forced re-rank keeps the old rows on
screen (dimmed)."""
impl app.ensure_rank(goal_id: str, force: bool = False) -> None {
    if not goal_id {
        return;
    }
    entry: dict = (RANK_ROWS[goal_id] or {}) as dict;
    if entry["ok"] and not force and not RANK_STALE[goal_id] {
        publish_rank();
        ensure_gaps(goal_id);
        return;
    }
    if RANK_PENDING[goal_id] {
        return;
    }
    RANK_PENDING[goal_id] = True;
    RANK_ERRORS[goal_id] = "";
    publish_rank();
    out: list[dict] = [];
    refresh_srv: bool = force or bool(RANK_STALE[goal_id]);
    try {
        out = await goal_rank(goal_id, refresh_srv);
    } except Exception as e {
        RANK_PENDING[goal_id] = False;
        RANK_ERRORS[goal_id] = "Couldn't rank your network for this goal. Tap Re-rank to try again.";
        publish_rank();
        return;
    }
    RANK_ROWS[goal_id] = {"ok": True, "rows": out};
    RANK_STALE[goal_id] = False;
    RANK_PENDING[goal_id] = False;
    publish_rank();
    cache_set("rank", RANK_ROWS);
    # GapFinder reads the RelevantTo edges GoalRank just rebuilt.
    ensure_gaps(goal_id, force);
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
        goal_error = "Couldn't switch goals. Try again. " + str(e);
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
        goal_error = "That goal wasn't found. Refresh and try again.";
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
    GAP_ROWS[goal_id] = None;
    publish_rank();
    publish_gaps();
}

impl app.rerank -> None {
    ensure_rank(active_goal_id(goals_list), True);
}

# ---------------------------------------------------------------- gaps (SOH-172)

impl app.publish_gaps -> None {
    gap_cache = {**GAP_ROWS};
    gap_pending_map = {**GAP_PENDING};
    gap_error_map = {**GAP_ERRORS};
}

"""GapFinder(goal_id) into the cache (an LLM call: once per goal unless forced
by Re-rank / a new note / a claimed reveal, or marked stale by a new note)."""
impl app.ensure_gaps(goal_id: str, force: bool = False) -> None {
    if not goal_id {
        return;
    }
    entry: dict = (GAP_ROWS[goal_id] or {}) as dict;
    if (entry["ok"] and not force and not GAP_STALE[goal_id]) or GAP_PENDING[goal_id] {
        publish_gaps();
        return;
    }
    GAP_PENDING[goal_id] = True;
    GAP_ERRORS[goal_id] = "";
    publish_gaps();
    out: list[dict] = [];
    try {
        out = await gap_finder(goal_id);
    } except Exception as e {
        GAP_PENDING[goal_id] = False;
        GAP_ERRORS[goal_id] = "Couldn't check this goal for gaps.";
        publish_gaps();
        return;
    }
    GAP_ROWS[goal_id] = {"ok": True, "rows": out};
    GAP_STALE[goal_id] = False;
    GAP_PENDING[goal_id] = False;
    publish_gaps();
    cache_set("gaps", GAP_ROWS);
}

impl app.retry_gaps -> None {
    ensure_gaps(active_goal_id(goals_list), True);
}

# ---------------------------------------------------------------- exchange (SOH-172)

impl app.publish_ex -> None {
    ex = {
        "mine": EX["mine"],
        "incoming": EX["incoming"],
        "friends": EX["friends"],
        "friend": {**(EX["friend"] as dict)},
        "claims": {**(EX["claims"] as dict)},
        "claiming": {**(EX["claiming"] as dict)}
    };
}

"""ListMyRequests -> EX.mine (newest first). A revealed reply that hasn't been
claimed yet is claimed right away (once): that is the card arriving."""
impl app.load_mine -> None {
    if EX["mine_busy"] {
        return;
    }
    EX["mine_busy"] = True;
    found: list[dict] = [];
    try {
        found = await list_my_requests();
    } except Exception as e {
        EX["mine_busy"] = False;
        return;
    }
    EX["mine_busy"] = False;
    EX["mine"] = sorted(found, key=_by_created, reverse=True);
    publish_ex();
    for item in found {
        for r in (item["replies"] or []) as list[dict] {
            rid: str = r["_jac_id"] as str;
            if r["status"] == "revealed" and not EX["claims"][rid] and not EX["claiming"][rid] {
                claim(rid);
            }
        }
    }
}

"""ListFriends -> EX.friends (SOH-218). Only the count is used: Friends as an ask
audience needs at least one. A failure leaves the list empty (Friends disabled)."""
impl app.load_friends -> None {
    found: list[dict] = [];
    try {
        found = await list_friends();
    } except Exception as e {
        found = [];
    }
    EX["friends"] = found;
    publish_ex();
}

"""SOH-236: a poll tick whose ids/statuses/my_reply match the last published
result is dropped here instead of re-publishing (which would re-render every
people row for nothing)."""
impl app.load_incoming -> None {
    if EX["inc_busy"] {
        return;
    }
    EX["inc_busy"] = True;
    found: list[dict] = [];
    try {
        found = await list_incoming_requests();
    } except Exception as e {
        EX["inc_busy"] = False;
        return;
    }
    EX["inc_busy"] = False;
    sig: str = incoming_sig(found);
    if sig == INCOMING_SIG {
        return;
    }
    INCOMING_SIG = sig;
    EX["incoming"] = found;
    publish_ex();
}

"""Home tick: the inbox always; your asks only while one is still moving."""
impl app.poll_home -> None {
    load_incoming();
    if mine_wants_poll(EX["mine"] as list[dict], EX["claims"] as dict) {
        load_mine();
    }
}

impl app.poll_request -> None {
    load_mine();
}

"""Ask my network -> PostRequest(need, about_line). A user with no Card yet
(PostRequest reports no_card) gets one via PublishCard, then it retries once.
(Gap-alert path only; an agent's ask_network card posts via ResolveAgentAction.)
`audience` (SOH-218): "everyone" (default) | "friends"."""
impl app.post_ask(need: str, about_line: str, audience: str = "everyone", goal_text: str = "") -> None {
    if not need {
        return;
    }
    out: dict = {};
    made: dict = {};
    ask_busy = True;
    ask_error = "";
    try {
        out = await post_request(need, about_line, audience, goal_text);
        if (out["error"] or "") == "no_card" {
            made = await publish_card(me_name or "me", about_line, me_about);
            if made["error"] {
                ask_busy = False;
                ask_error = err_text(made["error"] as str);
                return;
            }
            out = await post_request(need, about_line, audience, goal_text);
        }
    } except Exception as e {
        ask_busy = False;
        ask_error = "Couldn't post that. Try again. " + str(e);
        return;
    }
    if out["error"] {
        ask_busy = False;
        ask_error = err_text(out["error"] as str);
        return;
    }
    # Show it immediately; the next ListMyRequests replaces this row.
    EX["mine"] = [{"request": out, "replies": []}] + (EX["mine"] as list[dict]);
    publish_ex();
    ask_busy = False;
    load_mine();
}

impl app.open_request(rid: str) -> None {
    open_req_id = rid;
    req_error = "";
    view = "request";
    load_mine();
}

impl app.cancel_request(rid: str) -> None {
    out: str = "";
    req_busy = True;
    req_error = "";
    try {
        out = await decline_request(rid);
    } except Exception as e {
        req_busy = False;
        req_error = "Couldn't withdraw it. Try again. " + str(e);
        return;
    }
    req_busy = False;
    if out != "declined" {
        req_error = err_text(out);
        return;
    }
    load_mine();
}

"""ClaimReveal(reply_id): the requester reads the granted Card and gets the
Person + Knows{how_met="intro via <friend>"} in their own graph. Then the
people list refreshes and every ranking / gap list is stale."""
impl app.claim(reply_id: str) -> None {
    gid: str = active_goal_id(goals_list);
    claims_now: dict = {};
    out: dict = {};
    claiming_now: dict = {**(EX["claiming"] as dict)};
    claiming_now[reply_id] = True;
    EX["claiming"] = claiming_now;
    publish_ex();
    try {
        out = await claim_reveal(reply_id);
    } except Exception as e {
        out = {"error": "failed: " + str(e)};
    }
    claims_now = {**(EX["claims"] as dict)};
    claims_now[reply_id] = out;
    EX["claims"] = claims_now;
    claiming_now = {**(EX["claiming"] as dict)};
    claiming_now[reply_id] = False;
    EX["claiming"] = claiming_now;
    publish_ex();
    if out["error"] {
        return;
    }
    refresh();
    for k in list(RANK_ROWS.keys()) {
        RANK_ROWS[k] = None;
        RANK_STALE[k] = True;
    }
    for k in list(GAP_ROWS.keys()) {
        GAP_ROWS[k] = None;
    }
    publish_rank();
    publish_gaps();
    if gid {
        ensure_rank(gid, True);
    }
}

"""Friend opens an ask: the approval card; the first open runs ReplyToRequest.

`auto_check` (SOH-229): False from `answer_ask_action`'s already-answered
fallback, where the reply is known to already exist server-side but its data
never made it back to this device (dismiss doesn't carry it; the mapped
ReplyToRequest failing "invalid_state" doesn't either) -- checking again would
only hit the same wall and surface an error the user didn't cause. Every other
caller (a plain "Needs your OK" open) keeps the default and auto-checks as
before."""
impl app.open_ask(rid: str, auto_check: bool = True) -> None {
    ent: dict = friend_get(rid);
    if not ent["request"] {
        for r in EX["incoming"] as list[dict] {
            if r["_jac_id"] == rid {
                ent["request"] = r;
            }
        }
        friend_put(rid, ent);
        publish_ex();
    }
    open_ask_id = rid;
    view = "ask";
    # SOH-232: `resolve_ask_entry` folds in the request's own `my_reply`
    # (this account's past reply, carried by ListIncomingRequests even after
    # it answered) before deciding whether to check — a fresh page load
    # never re-runs `reply_to_request` for an ask already answered.
    resolved: dict = resolve_ask_entry((ent["request"] or {}) as dict, (EX["friend"] or {}) as dict);
    if auto_check and ent["request"] and not (resolved["reply"] or {})["_jac_id"] and not ent["busy"] {
        friend_check(rid);
    }
}

"""ReplyToRequest: score the need against MY graph only; count + strength back."""
impl app.friend_check(rid: str) -> None {
    ent: dict = friend_get(rid);
    # SOH-226: guaranteed here (not just by `open_ask`) — the shell's own
    # auto-check driver (`start_auto_checks`) calls this directly, and once
    # a checked ask leaves ListIncomingRequests (answered) this `request` is
    # the only way `split_asks`'s "extra" bucket still finds it, so a
    # zero-match ask doesn't just vanish instead of landing under "Other asks".
    if not ent["request"] {
        for r in EX["incoming"] as list[dict] {
            if r["_jac_id"] == rid {
                ent["request"] = r;
            }
        }
    }
    ent["busy"] = True;
    ent["error"] = "";
    friend_put(rid, ent);
    publish_ex();
    out: dict = {};
    made: dict = {};
    try {
        out = await reply_to_request(rid);
        if (out["error"] or "") == "no_card" {
            made = await publish_card(me_name or "me", "", me_about);
            if not made["error"] {
                out = await reply_to_request(rid);
            }
        }
    } except Exception as e {
        out = {"error": "failed: " + str(e)};
    }
    ent = friend_get(rid);
    ent["busy"] = False;
    if out["error"] {
        ent["error"] = err_text(out["error"] as str);
    } else {
        ent["reply"] = out;
    }
    friend_put(rid, ent);
    publish_ex();
    load_incoming();
}

impl app.friend_approve(rid: str) -> None {
    ent: dict = friend_get(rid);
    reply_id: str = ((ent["reply"] or {})["_jac_id"] or "") as str;
    if not reply_id {
        return;
    }
    ent["busy"] = True;
    ent["error"] = "";
    friend_put(rid, ent);
    publish_ex();
    out: dict = {};
    try {
        out = await approve_reply(reply_id);
    } except Exception as e {
        out = {"error": "failed: " + str(e)};
    }
    ent = friend_get(rid);
    ent["busy"] = False;
    if out["error"] {
        ent["error"] = err_text(out["error"] as str);
    } else {
        ent["reply"] = out;
    }
    friend_put(rid, ent);
    publish_ex();
}

impl app.friend_opt_in(rid: str) -> None {
    ent: dict = friend_get(rid);
    reply_id: str = ((ent["reply"] or {})["_jac_id"] or "") as str;
    if not reply_id {
        return;
    }
    ent["busy"] = True;
    ent["error"] = "";
    friend_put(rid, ent);
    publish_ex();
    out: dict = {};
    try {
        out = await opt_in(reply_id);
    } except Exception as e {
        out = {"error": "failed: " + str(e)};
    }
    ent = friend_get(rid);
    ent["busy"] = False;
    if out["error"] {
        ent["error"] = err_text(out["error"] as str);
    } else {
        ent["reply"] = out["reply"];
        ent["draft"] = out["opt_in_draft"];
    }
    friend_put(rid, ent);
    publish_ex();
}

impl app.friend_reveal(rid: str) -> None {
    ent: dict = friend_get(rid);
    reply_id: str = ((ent["reply"] or {})["_jac_id"] or "") as str;
    if not reply_id {
        return;
    }
    ent["busy"] = True;
    ent["error"] = "";
    friend_put(rid, ent);
    publish_ex();
    out: dict = {};
    try {
        out = await reveal(reply_id);
    } except Exception as e {
        out = {"error": "failed: " + str(e)};
    }
    ent = friend_get(rid);
    ent["busy"] = False;
    if out["error"] {
        ent["error"] = err_text(out["error"] as str);
    } else {
        ent["reply"] = out["reply"];
        ent["revealed_handle"] = out["revealed_card_handle"];
    }
    friend_put(rid, ent);
    publish_ex();
}

impl app.friend_decline(rid: str) -> None {
    ent: dict = friend_get(rid);
    reply_id: str = ((ent["reply"] or {})["_jac_id"] or "") as str;
    if not reply_id {
        return;
    }
    ent["busy"] = True;
    ent["error"] = "";
    friend_put(rid, ent);
    publish_ex();
    out: str = "";
    try {
        out = await decline_reply(reply_id);
    } except Exception as e {
        out = "failed: " + str(e);
    }
    ent = friend_get(rid);
    ent["busy"] = False;
    if out == "declined" {
        next_reply: dict = {**((ent["reply"] or {}) as dict)};
        next_reply["status"] = "declined";
        ent["reply"] = next_reply;
    } else {
        ent["error"] = err_text(out);
    }
    friend_put(rid, ent);
    publish_ex();
}

"""Back from a request / an ask -> the Inbox tab they were opened from."""
impl app.back_home -> None {
    set_tab("inbox");
    view = "home";
    open_req_id = "";
    open_ask_id = "";
    req_error = "";
    load_mine();
    load_incoming();
}

"""Dev-only (?mock=1): your own asks also land in your inbox, answered as a
mock friend, so the whole loop clicks through in one browser."""
impl app.toggle_as_friend -> None {
    on: bool = not mock_as_friend();
    mock_set_as_friend(on);
    as_friend = on;
    load_incoming();
}

# ---------------------------------------------------------------- tabs (SOH-213)

"""Home · Inbox · People, remembered for the session (sessionStorage)."""
impl app.set_tab(next_tab: str) -> None {
    tab = next_tab;
    save_tab(next_tab);
}

"""Capture mode (voice | guided | paste), remembered for the session."""
impl app.set_cap_kind(kind: str) -> None {
    cap_kind = kind;
    cap_error = "";
    save_cap_kind(kind);
}

"""Drives the SOH-222 auto-check (SOH-226: the single source both the
"Needs your OK" list and the Inbox badge read from) — up to 5 asks not yet
checked, through the exact same `friend_check` a manually-opened ask uses.
Reads the module-level EX/AGENT state directly (not the render-scope
`incoming_shown`/`friend_shown` locals, which aren't in scope for an `impl`
method) — same "covered" exclusion as the render does, so this never checks
a request an open `answer_ask` AgentAction already represents."""
impl app.start_auto_checks -> None {
    rows: list[dict] = AGENT["rows"] as list[dict];
    covered_now: list[str] = covered_requests(rows);
    incoming_now: list[dict] = [r for r in (EX["incoming"] as list[dict]) if r["_jac_id"] not in covered_now];
    friend_now: dict = EX["friend"] as dict;
    todo: list[str] = pick_unchecked(incoming_now, friend_now, 5);
    if len(todo) > 0 {
        run_auto_checks(todo);
    }
}

"""Concurrent (SOH-236): each `friend_check` is started without waiting on the
one before it — up to 5 LLM-backed ReplyToRequest calls run at once instead of
serially. `friend_check` already reads/writes `EX["friend"][rid]` fresh on
each resolve (never a stale pre-await snapshot), so calls for different ids
never clobber each other; the same rid is never in `ids` twice in one batch
(`pick_unchecked` de-dupes)."""
impl app.run_auto_checks(ids: list[str]) -> None {
    for rid in ids {
        friend_check(rid);
    }
}

# ---------------------------------------------------------------- agent inbox (SOH-224)

impl app.publish_agent -> None {
    agent_view = {
        "rows": AGENT["rows"],
        "loaded": AGENT["loaded"],
        "running": AGENT["running"],
        "error": AGENT["error"],
        "pending": {**(AGENT["pending"] as dict)},
        "errors": {**(AGENT["errors"] as dict)},
        "last_run": AGENT["last_run"]
    };
}

"""ListAgentActions("open") -> AGENT.rows. A row whose resolve is still in flight
keeps its optimistic local state (the server hasn't answered yet)."""
impl app.load_actions -> None {
    found: list[dict] = [];
    try {
        found = await list_agent_actions("open", 30);
    } except Exception as e {
        AGENT["loaded"] = True;
        AGENT["error"] = "Couldn't load your suggestions.";
        publish_agent();
        return;
    }
    merged: list[dict] = [];
    for r in found {
        aid: str = ((r["action"] or {})["_jac_id"] or "") as str;
        local: dict = agent_row(aid);
        merged = merged + [local if (AGENT["pending"] as dict)[aid] and local["action"] else r];
    }
    AGENT["rows"] = merged;
    AGENT["loaded"] = True;
    publish_agent();
}

"""ListAgentActions first (whatever's already stored renders right away), then
RunAgent, then ListAgentActions again to pick up what it found (SOH-236: this
used to await RunAgent before the first load, so stored suggestions stayed
behind a full skeleton for the whole run). One run at a time; a trigger that
arrives mid-run (e.g. Capture -> Done while the open-run is going) runs once
more after it. `running` stays true the whole time, so the two skeleton cards
(not a full-list skeleton, once `loaded` is true) sit on top of the real rows
until the second load lands."""
impl app.run_agent_now(reason: str) -> None {
    if not agent_available() {
        AGENT["loaded"] = True;
        publish_agent();
        return;
    }
    if AGENT["running"] {
        AGENT["queued"] = reason;
        return;
    }
    AGENT["running"] = True;
    AGENT["error"] = "";
    publish_agent();
    await load_actions();
    out: dict = {};
    try {
        out = await run_agent(reason);
    } except Exception as e {
        out = {"error": "failed"};
    }
    if out["error"] {
        AGENT["error"] = "Couldn't finish that check. Try again.";
    } else {
        last: dict = {
            "ran_at": (out["ran_at"] or "") as str,
            "new": (out["new"] or 0) as int,
            "total_open": (out["total_open"] or 0) as int,
            "ms": now_ms()
        };
        save_agent_run(last);
        AGENT["last_run"] = last;
    }
    await load_actions();
    AGENT["running"] = False;
    publish_agent();
    again: str = (AGENT["queued"] or "") as str;
    if again {
        AGENT["queued"] = "";
        run_agent_now(again);
    }
}

"""Entering home: run the agent if it hasn't run in the last 10 minutes this
session, else just list what it already found."""
impl app.agent_on_open -> None {
    AGENT["last_run"] = session_agent_run();
    publish_agent();
    age: int = agent_run_age_ms();
    if age < 0 or age > AGENT_STALE_MS {
        run_agent_now("open");
    } else {
        load_actions();
    }
}

impl app.run_agent_manual -> None {
    run_agent_now("manual");
}

"""ResolveAgentAction, optimistic: the card turns into its receipt at once; on an
error it comes back as it was with an inline message."""
impl app.resolve_action(aid: str, decision: str, edited: str) -> None {
    row: dict = agent_row(aid);
    act: dict = (row["action"] or {}) as dict;
    if not act["_jac_id"] or (AGENT["pending"] as dict)[aid] {
        return;
    }
    prev_status: str = (act["status"] or "open") as str;
    prev_draft: str = (act["draft"] or "") as str;
    sent_draft: str = edited if decision == "approve" else "";
    agent_patch(aid, agent_status_for((act["kind"] or "") as str, decision), sent_draft);
    agent_map_put("pending", aid, True);
    agent_map_put("errors", aid, "");
    publish_agent();
    out: dict = {};
    # promise_due: approving means "Mark promise done" -> CompletePromise server-side.
    complete: bool = decision == "approve" and act["kind"] == "promise_due";
    try {
        out = await resolve_agent_action(aid, decision, sent_draft, complete);
    } except Exception as e {
        out = {"error": "failed"};
    }
    agent_map_put("pending", aid, False);
    code: str = resolve_error(out);
    if code {
        agent_patch(aid, prev_status, prev_draft);
        agent_map_put("errors", aid, agent_err_text(code));
        publish_agent();
        return;
    }
    srv: dict = (out["action"] or {}) as dict;
    if srv["status"] {
        agent_patch(aid, srv["status"] as str, (srv["draft"] or "") as str);
    }
    publish_agent();
}

"""ask_network Approve (SOH-223): the prefilled ask sheet's *Post request* ->
ResolveAgentAction(approve, edited_draft=<confirmed need>). SK's walker calls
PostRequest server-side (audience "everyone"), so the client does NOT post it
again. Not optimistic: the sheet shows busy / the error, and only a success
turns the card into "Ask posted"; then ListMyRequests shows it under Your asks.
The about line is the action payload's (the walker takes no edited one), so
the sheet shows it read-only."""
impl app.post_ask_action(aid: str, need: str, about_line: str) -> None {
    row: dict = agent_row(aid);
    act: dict = (row["action"] or {}) as dict;
    if not act["_jac_id"] or not need or (AGENT["pending"] as dict)[aid] {
        return;
    }
    out: dict = {};
    ask_busy = True;
    ask_error = "";
    agent_map_put("pending", aid, True);
    agent_map_put("errors", aid, "");
    publish_agent();
    made: dict = {};
    try {
        out = await resolve_agent_action(aid, "approve", need);
        # No Card yet (the walker's PostRequest step reports no_card; the action is
        # left open): make one the same way the gap path does, then retry once.
        if resolve_error(out) == "no_card" {
            made = await publish_card(me_name or "me", about_line, me_about);
            if not made["error"] {
                out = await resolve_agent_action(aid, "approve", need);
            }
        }
    } except Exception as e {
        out = {"error": "failed"};
    }
    agent_map_put("pending", aid, False);
    code: str = resolve_error(out);
    if code {
        ask_busy = False;
        ask_error = err_text(code) if code in ["no_card", "forbidden"] else agent_err_text(code);
        publish_agent();
        return;
    }
    srv: dict = (out["action"] or {}) as dict;
    agent_patch(aid, ((srv["status"] or "approved") as str), need);
    publish_agent();
    # result = { step: "posted", request }: show it under Your asks at once; the
    # ListMyRequests below replaces the row.
    posted: dict = ((out["result"] or {})["request"] or {}) as dict;
    if posted["_jac_id"] {
        EX["mine"] = [{"request": posted, "replies": []}] + [m for m in (EX["mine"] as list[dict]) if (m["request"] or {})["_jac_id"] != posted["_jac_id"]];
        publish_ex();
    }
    ask_busy = False;
    load_mine();
}

"""answer_ask Approve (SOH-223 amendment): resolve FIRST, the walker runs
ReplyToRequest and returns { step: "replied", reply }, then open the existing
friend reply flow on that reply (so the client never calls ReplyToRequest twice).
On an error the card stays with an inline message and nothing opens.

SOH-229 race: the shell's own auto-check (start_auto_checks -> pick_unchecked ->
friend_check) can answer this same request before this tap lands (it is not
filtered by an answer_ask card that has not been created yet). Two defenses:
if `friend[rid]` already carries a reply, resolve through the dismiss path
instead of approve (ResolveAgentAction takes no "how this was resolved" note, so
there is no way to tell it "already answered"; dismiss is the only decision that
never calls ReplyToRequest, so it always succeeds); if it comes back
"invalid_state" anyway (the rarer case, the race lands between this tap and its
own round trip), treat that the same as success rather than show it. Either way
the card resolves as if approved (that is what actually happened for the
person), and the approval view opens on the reply that already exists."""
impl app.answer_ask_action(aid: str, rid: str) -> None {
    row: dict = agent_row(aid);
    act: dict = (row["action"] or {}) as dict;
    if not act["_jac_id"] or (AGENT["pending"] as dict)[aid] {
        return;
    }
    agent_map_put("pending", aid, True);
    agent_map_put("errors", aid, "");
    publish_agent();
    already: dict = friend_get(rid);
    has_reply: bool = ((already["reply"] or {})["_jac_id"] or "") as str != "";
    out: dict = {};
    try {
        out = await resolve_agent_action(aid, "dismiss" if has_reply else "approve", "");
    } except Exception as e {
        out = {"error": "failed"};
    }
    agent_map_put("pending", aid, False);
    code: str = resolve_error(out);
    already_handled: bool = has_reply or code == "invalid_state";
    if code and not already_handled {
        agent_map_put("errors", aid, agent_err_text(code));
        publish_agent();
        return;
    }
    agent_patch(aid, "approved", "");
    publish_agent();
    reply: dict = ((out["result"] or {})["reply"] or {}) as dict;
    ent: dict = friend_get(rid);
    if not ent["request"] {
        for r in EX["incoming"] as list[dict] {
            if r["_jac_id"] == rid {
                ent["request"] = r;
            }
        }
    }
    if not ent["request"] {
        # Fallback when the request is not in the loaded list: build it from the
        # action's payload (need/from_handle/from_name/goal_text, SOH-229), never
        # from the title, which is already a full sentence.
        pl_fb: dict = (payload_of(act) or {}) as dict;
        ent["request"] = {
            "_jac_id": rid,
            "need": ((pl_fb["need"] or "") as str) or (act["title"] as str),
            "from_handle": (pl_fb["from_handle"] or "") as str,
            "from_name": (pl_fb["from_name"] or "") as str,
            "about_line": (pl_fb["about_line"] or "") as str,
            "goal_text": (pl_fb["goal_text"] or "") as str,
            "matched": (pl_fb["matched"] or [])
        };
    }
    if reply["_jac_id"] {
        ent["reply"] = reply;
    }
    # SOH-229 item 3 ("Why it fits"): thread this action's own `matched`
    # tokens (SOH-223's `agent.sv.jac` tune, `payload_json.matched`) onto the
    # request object the approval view reads — read-only, never identity,
    # and only present when this device's own AgentAction found it.
    req_with_matched: dict = {**((ent["request"] or {}) as dict)};
    if not req_with_matched["matched"] {
        req_with_matched["matched"] = (payload_of(act)["matched"] or []);
    }
    ent["request"] = req_with_matched;
    friend_put(rid, ent);
    publish_ex();
    # SOH-229: only let the approval view auto-check again when it actually has
    # reply data to show for a "not yet checked" state; the already-handled
    # fallback above has neither (dismiss never returns one; a mapped
    # ReplyToRequest failing "invalid_state" doesn't either). Auto-checking
    # then would just hit the same wall and show an error the tap didn't cause.
    have_reply_data: bool = ((ent["reply"] or {})["_jac_id"] or "") as str != "";
    open_ask(rid, have_reply_data);
}
