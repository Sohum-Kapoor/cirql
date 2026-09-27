"""Client shell — OWNER: Person B.

One stateful shell component; handler bodies live in frontend.impl.jac
(`jac guide jac-cl-organization`). Sections are stateless components in
components/ (onboarding steps in components/onboarding/). Walkers that are not
live yet go through components/api.cl.jac, the single mock/live swap point.

Views: auth -> loading (GetMe) -> onboarding (4 steps) | home.
home -> capture (Guided | Paste | Voice, Capture call) -> review (extraction +
source chips + inline edit/remove, SOH-209) -> home. Voice (SOH-168): record ->
Transcribe -> editable transcript -> Capture(audio_ref). Person / promise edits
that no walker can write yet are kept on this device (lib/local_edits) and
overlaid on the people list and rankings at render time.
home is three tabs under a bottom tab bar (SOH-213), the tab remembered for the
session (lib/session):
  Home   = goal picker (ListGoals / SetGoal / CloseGoal) + GoalRank for the active
           goal, cached per goal_id for the session (SOH-170), + GapFinder alerts
           (cached per goal_id, run after GoalRank: it reads the RelevantTo edges).
  Asks   = "Needs your OK" (ListIncomingRequests) + "Your asks" (ListMyRequests);
           the tab badge counts friends' asks waiting on you + unseen reveals.
  People = people list / graph / Today.
Capture opens on Voice by default; the last-used capture mode is remembered.
Deep links: Capture -> Done lands on Home; back from a request / ask lands on Asks.
home -> request (requester's detail + reveal card) | ask (friend's approval card).
Polling only while home / a request detail is on screen (see Poller): every 5 s
on the Asks tab, every 15 s on the other tabs (only the Asks badge needs it).
TODO(SOH-172): Matchmaker fallback second act skipped — the 9 PM gate passed.
"""

import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import ".assets.main.css";
# Appearance (SOH-206): importing lib/theme applies the stored Light/Dark/System
# choice to <html> at module load, before the first React render.
import from .lib.theme { BOOT_THEME }

import from .components.AuthCard { AuthCard }
import from .components.HomeView { HomeView }
import from .components.onboarding.StepIndicator { StepIndicator }
import from .components.onboarding.AboutStep { AboutStep }
import from .components.onboarding.CardStep { CardStep }
import from .components.onboarding.PeopleStep { PeopleStep }
import from .components.onboarding.RecallStep { RecallStep }
import from .components.capture.CaptureForm { CaptureForm }
import from .components.capture.Review { Review }
import from .components.capture.guided { empty_guided, guided_text, how_met_line, remember_met, guided_names }
import from .lib.local_edits { local_view, local_rows }
import from react { useEffect }
import from .lib.session { session_tab, save_tab, session_cap_kind, save_cap_kind, clear_session_ui }
import from .components.api { onboard_me, capture, goal_rank, list_people, list_goals, set_goal, close_goal, mocks_on }
import from .components.api {
    gap_finder, publish_card, post_request, list_my_requests, decline_request, claim_reveal,
    list_incoming_requests, reply_to_request, approve_reply, opt_in, reveal, decline_reply
}
import from .components.mocks.exchange { mock_as_friend, mock_set_as_friend }
import from .components.exchange.common { Poller, req_active }
import from .components.exchange.Requests { RequestDetail }
import from .components.exchange.Inbox { ApprovalView, asks_needing_you }
import from .lib.text { join_lines }

sv import from walkers { GetMe }
sv import from schema { Person }

glob STEP_LABELS: list[str] = ["About you", "Your card", "Bring five people", "First recall"];

# GoalRank cache, keyed by goal_id (SOH-170). Plain module dicts (not reactive):
# async handlers read these instead of `has` state, which is a stale render-time
# snapshot after an `await` — so two rankings in flight never clobber each other.
# `publish_rank()` copies them into the reactive `rank_*` mirrors to re-render.
# RANK_ROWS[goal_id] is {"ok": True, "rows": [...]} when cached (a non-empty wrapper, so an
# empty ranking still counts as cached), None when invalidated / never ranked.
# RANK_STALE[goal_id] = True after a new note: the server's cached RelevantTo edges are
# out of date, so the next rank of that goal asks GoalRank for refresh=True.
glob RANK_ROWS: dict = {},
     RANK_PENDING: dict = {},
     RANK_ERRORS: dict = {},
     RANK_STALE: dict = {};

# GapFinder cache, keyed by goal_id — same shape and rules as RANK_* above.
glob GAP_ROWS: dict = {},
     GAP_PENDING: dict = {},
     GAP_ERRORS: dict = {};

# Exchange state (SOH-172). Module-level for the same stale-snapshot reason;
# `publish_ex()` copies it into the reactive `ex` mirror.
#   mine: ListMyRequests rows, newest first     incoming: ListIncomingRequests
#   friend[request_id]: this session's reply in progress (the request leaves
#     ListIncomingRequests once answered) — { request, reply, draft, revealed_handle, error, busy }
#   claims[reply_id]: ClaimReveal result or { error }; claiming[reply_id]: in flight
glob EX: dict = {"mine": [], "incoming": [], "friend": {}, "claims": {}, "claiming": {}, "mine_busy": False, "inc_busy": False};

def empty_ex() -> dict {
    return {"mine": [], "incoming": [], "friend": {}, "claims": {}, "claiming": {}, "mine_busy": False, "inc_busy": False};
}

def _by_created(item: dict) -> str {
    return ((item["request"] or {})["created_at"] or "") as str;
}

def friend_get(rid: str) -> dict {
    return {**((EX["friend"][rid] or {}) as dict)};
}

def friend_put(rid: str, ent: dict) -> None {
    fr: dict = {**(EX["friend"] as dict)};
    fr[rid] = ent;
    EX["friend"] = fr;
}

def err_text(code: str) -> str {
    if code == "no_card" {
        return "You need a card first — finish onboarding.";
    }
    if code == "not_found" {
        return "That ask is gone (withdrawn or expired).";
    }
    if code == "invalid_state" {
        return "That step already happened or isn't possible yet — go back and reopen it.";
    }
    if code == "forbidden" {
        return "That isn't yours to change.";
    }
    return "Something went wrong (" + code + ").";
}

"""First sentence of an about-me, capped — the ask sheet's default one-liner."""
def first_line(text: str) -> str {
    t: str = text.strip();
    cut: int = t.index(". ") if ". " in t else len(t);
    line: str = t[:cut].strip().rstrip(".");
    return line[:117] + "…" if len(line) > 120 else line;
}

"""Does any ask still need polling (moving, or revealed but not yet claimed)?"""
def mine_wants_poll(mine: list[dict], claims: dict) -> bool {
    for item in mine {
        st: str = ((item["request"] or {})["status"] or "") as str;
        if req_active(st) {
            return True;
        }
        if st == "revealed" {
            for r in (item["replies"] or []) as list[dict] {
                if r["status"] == "revealed" and not (claims[r["_jac_id"]] or {})["card"] {
                    return True;
                }
            }
        }
    }
    return False;
}

"""Copy of goal `g` with `active` set to whether it is `active_id`."""
def mark_active(g: dict, active_id: str) -> dict {
    out: dict = {**g};
    out["active"] = g["_jac_id"] == active_id;
    return out;
}

def active_goal_id(goals: list[dict]) -> str {
    for g in goals {
        if g["active"] {
            return (g["_jac_id"] or "") as str;
        }
    }
    return "";
}

def empty_voice() -> dict {
    return {"text": "", "audio_ref": "", "error": "", "mime": ""};
}

def empty_rows() -> list[dict] {
    return [{"name": "", "how": ""} for _ in range(5)];
}

def:pub app -> JsxElement {
    has view: str = "auth",
        open_person_id: str = "",
        email: str = "",
        password: str = "",
        status: str = "",
        auth_pending: bool = False,
        people: list[Person] = [],
        step: int = 1,
        about: str = "",
        about_pending: bool = False,
        about_error: str = "",
        onboard: dict = {},
        card: dict = {},
        rows: list[dict] = empty_rows(),
        capture_pending: bool = False,
        capture_error: str = "",
        captured_count: int = -1,
        rank_rows: list[dict] = [],
        rank_pending: bool = False,
        rank_error: str = "",
        cap_text: str = "",
        cap_kind: str = session_cap_kind(),
        cap_guided: dict = empty_guided(),
        cap_voice: dict = empty_voice(),
        cap_how_met: str = "",
        cap_met_names: list[str] = [],
        cap_pending: bool = False,
        cap_error: str = "",
        cap_note: str = "",
        cap_result: dict = {},
        goals_list: list[dict] = [],
        goals_loaded: bool = False,
        goal_busy: bool = False,
        goal_error: str = "",
        onb_goal_busy: bool = False,
        onb_goal_error: str = "",
        rank_cache: dict = {},
        rank_pending_map: dict = {},
        rank_error_map: dict = {},
        gap_cache: dict = {},
        gap_pending_map: dict = {},
        gap_error_map: dict = {},
        ex: dict = empty_ex(),
        open_req_id: str = "",
        open_ask_id: str = "",
        ask_busy: bool = False,
        ask_error: str = "",
        req_busy: bool = False,
        req_error: str = "",
        me_name: str = "",
        me_about: str = "",
        as_friend: bool = False,
        tab: str = session_tab(),
        seen_reveals: list[str] = [];

    can with entry {
        if jacIsLoggedIn() {
            enter();
        }
    }

    async def signup -> None;
    async def login -> None;
    def logout -> None;
    async def refresh -> None;
    async def enter -> None;
    async def submit_about -> None;
    def set_card_field(field: str, value: any) -> None;
    async def onb_switch_goal(goal_id: str) -> None;
    async def onb_create_goal(text: str) -> None;
    async def onb_close_goal(goal_id: str) -> None;
    def set_row(i: int, field: str, value: str) -> None;
    async def submit_people -> None;
    def skip_people -> None;
    def people_next -> None;
    async def start_recall -> None;
    async def recall_add_goal(text: str) -> None;
    def finish -> None;
    def open_capture -> None;
    def close_capture -> None;
    async def submit_capture -> None;
    def capture_done -> None;
    def capture_retry -> None;
    def set_guided(field: str, value: any) -> None;
    def set_cap_result(next_result: dict) -> None;
    async def load_goals -> None;
    def publish_rank -> None;
    async def ensure_rank(goal_id: str, force: bool = False) -> None;
    async def switch_goal(goal_id: str) -> None;
    async def create_goal(text: str) -> None;
    async def end_goal(goal_id: str) -> None;
    def rerank -> None;
    def publish_gaps -> None;
    async def ensure_gaps(goal_id: str, force: bool = False) -> None;
    def retry_gaps -> None;
    def publish_ex -> None;
    async def load_mine -> None;
    async def load_incoming -> None;
    def poll_home -> None;
    def poll_request -> None;
    async def post_ask(need: str, about_line: str) -> None;
    def open_request(rid: str) -> None;
    async def cancel_request(rid: str) -> None;
    async def claim(reply_id: str) -> None;
    def open_ask(rid: str) -> None;
    async def friend_check(rid: str) -> None;
    async def friend_approve(rid: str) -> None;
    async def friend_opt_in(rid: str) -> None;
    async def friend_reveal(rid: str) -> None;
    async def friend_decline(rid: str) -> None;
    def back_home -> None;
    def toggle_as_friend -> None;
    def set_tab(next_tab: str) -> None;
    def set_cap_kind(kind: str) -> None;
    def mark_seen(ids: list[str]) -> None;

    goals: list[dict] = (onboard["goals"] or []) as list[dict];
    interests: list[dict] = (onboard["interests"] or []) as list[dict];
    active_goals: list[dict] = [g for g in goals if g["active"]];
    active_goal_text: str = (active_goals[0]["text"] as str) if len(active_goals) > 0 else "";
    home_goal_id: str = active_goal_id(goals_list);
    home_entry: dict = (rank_cache[home_goal_id] or {}) as dict if home_goal_id else {};
    home_cached: bool = True if home_entry["ok"] else False;
    home_rows: list[dict] = local_rows((home_entry["rows"] or []) as list[dict]);
    people_shown: list[Person] = [local_view("person", p) for p in people];
    gap_entry: dict = (gap_cache[home_goal_id] or {}) as dict if home_goal_id else {};
    home_gaps: list[dict] = (gap_entry["rows"] or []) as list[dict];
    ex_mine: list[dict] = (ex["mine"] or []) as list[dict];
    ex_claims: dict = (ex["claims"] or {}) as dict;
    asked: dict = {};
    for item in ex_mine {
        req: dict = (item["request"] or {}) as dict;
        st: str = (req["status"] or "") as str;
        if st != "declined" and st != "expired" {
            asked[req["need"]] = st;
        }
    }
    default_about: str = ((card["headline"] or "") as str) or first_line(me_about);
    open_item: dict = {};
    for item in ex_mine {
        if (item["request"] or {})["_jac_id"] == open_req_id {
            open_item = item;
        }
    }
    open_ask_entry: dict = ((ex["friend"] or {})[open_ask_id] or {}) as dict if open_ask_id else {};
    unseen_reveals: list[str] = [];
    for rid in Object.keys(ex_claims) {  # jac:ignore[W2001]
        if (ex_claims[rid] or {})["card"] and rid not in seen_reveals {
            unseen_reveals = unseen_reveals + [rid];
        }
    }
    asks_badge: int = asks_needing_you((ex["incoming"] or []) as list[dict], (ex["friend"] or {}) as dict) + len(unseen_reveals);
    # A reveal is "seen" once the Asks tab is on screen.
    useEffect(lambda {
        if view == "home" and tab == "asks" and len(unseen_reveals) > 0 {
            mark_seen(unseen_reveals);
        }
    }, [view, tab, len(unseen_reveals)]);
    poll_home_on: bool = view == "home";
    poll_home_ms: int = 5000 if tab == "asks" else 15000;
    poll_req_on: bool = view == "request" and mine_wants_poll(ex_mine, ex_claims);

    return
        <main className="mx-auto flex min-h-svh w-full max-w-md flex-col gap-6 pt-6 pb-10 pl-4 pr-4">
            {if view == "auth" {
                <AuthCard
                    key="auth"
                    email={email}
                    password={password}
                    pending={auth_pending}
                    status={status}
                    onEmailChange={lambda v: str { email = v; }}
                    onPasswordChange={lambda v: str { password = v; }}
                    onLogin={login}
                    onSignup={signup}
                />
            } elif view == "loading" {
                <p key="loading" role="status" data-theme-boot={BOOT_THEME} className="pt-10 text-body-sm text-muted-foreground">Loading your graph…</p>
            } elif view == "home" {
                <HomeView
                    key="home"
                    people={people_shown}
                    status={status}
                    goals={goals_list}
                    rank_rows={home_rows}
                    rank_cached={home_cached}
                    rank_pending={True if home_goal_id and rank_pending_map[home_goal_id] else False}
                    rank_error={((rank_error_map[home_goal_id] or "") as str) if home_goal_id else ""}
                    goals_loaded={goals_loaded}
                    goal_busy={goal_busy}
                    goal_error={goal_error}
                    onRefresh={refresh}
                    onLogout={logout}
                    onCapture={open_capture}
                    open_person_id={open_person_id}
                    onPersonOpened={lambda { open_person_id = ""; }}
                    onSwitchGoal={switch_goal}
                    onCreateGoal={create_goal}
                    onCloseGoal={end_goal}
                    onRerank={rerank}
                    tab={tab}
                    onTab={set_tab}
                    asks_badge={asks_badge}
                    gaps={home_gaps}
                    gaps_pending={True if home_goal_id and gap_pending_map[home_goal_id] else False}
                    gaps_error={((gap_error_map[home_goal_id] or "") as str) if home_goal_id else ""}
                    asked={asked}
                    default_about={default_about}
                    ask_busy={ask_busy}
                    ask_error={ask_error}
                    mine={ex_mine}
                    claims={ex_claims}
                    incoming={(ex["incoming"] or []) as list[dict]}
                    friend={(ex["friend"] or {}) as dict}
                    mock_mode={mocks_on()}
                    as_friend={as_friend}
                    onAsk={post_ask}
                    onRetryGaps={retry_gaps}
                    onOpenRequest={open_request}
                    onOpenAsk={open_ask}
                    onToggleFriend={toggle_as_friend}
                />
            } elif view == "request" {
                <RequestDetail
                    key={"request-" + open_req_id}
                    item={open_item}
                    claims={ex_claims}
                    claiming={(ex["claiming"] or {}) as dict}
                    busy={req_busy}
                    error={req_error}
                    onBack={back_home}
                    onCancel={cancel_request}
                    onClaim={claim}
                />
            } elif view == "ask" {
                <ApprovalView
                    key={"ask-" + open_ask_id}
                    ask={open_ask_entry}
                    onBack={back_home}
                    onCheck={friend_check}
                    onApprove={friend_approve}
                    onOptIn={friend_opt_in}
                    onReveal={friend_reveal}
                    onDecline={friend_decline}
                />
            } elif view == "capture" {
                <CaptureForm
                    key="capture"
                    mode={cap_kind}
                    text={cap_text}
                    guided={cap_guided}
                    voice={cap_voice}
                    pending={cap_pending}
                    error={cap_error}
                    onModeChange={set_cap_kind}
                    onTextChange={lambda v: str { cap_text = v; }}
                    onGuidedField={set_guided}
                    onVoice={lambda v: dict { cap_voice = v; }}
                    onSubmit={submit_capture}
                    onBack={close_capture}
                    onPhotoResult={lambda r: dict, note: str { cap_result = r; cap_note = note; cap_error = ""; view = "review"; }}
                />
            } elif view == "review" {
                <Review
                    key="review"
                    result={cap_result}
                    note_text={cap_note}
                    known={people_shown}
                    how_met_hint={cap_how_met}
                    met_names={cap_met_names}
                    onDone={capture_done}
                    onRetry={capture_retry}
                    onResult={set_cap_result}
                    onOpenPerson={lambda pid: str { capture_done(); open_person_id = pid; }}
                />
            } else {
                <StepIndicator key="indicator" step={step} total={4} label={STEP_LABELS[step - 1]} />
                if step == 1 {
                    <AboutStep
                        key="step-1"
                        about={about}
                        pending={about_pending}
                        error={about_error}
                        onAboutChange={lambda v: str { about = v; }}
                        onContinue={submit_about}
                    />
                } elif step == 2 {
                    <CardStep
                        key="step-2"
                        card={card}
                        goals={goals}
                        interests={interests}
                        goal_busy={onb_goal_busy}
                        goal_error={onb_goal_error}
                        onFieldChange={set_card_field}
                        onSwitchGoal={onb_switch_goal}
                        onCreateGoal={onb_create_goal}
                        onCloseGoal={onb_close_goal}
                        onContinue={lambda { step = 3; }}
                    />
                } elif step == 3 {
                    <PeopleStep
                        key="step-3"
                        rows={rows}
                        pending={capture_pending}
                        error={capture_error}
                        captured_count={captured_count}
                        onRowChange={set_row}
                        onCapture={submit_people}
                        onSkip={skip_people}
                        onNext={people_next}
                    />
                } else {
                    <RecallStep
                        key="step-4"
                        goal_text={active_goal_text}
                        rows={rank_rows}
                        pending={rank_pending}
                        error={rank_error}
                        goal_busy={onb_goal_busy}
                        onAddGoal={recall_add_goal}
                        onDone={finish}
                    />
                }
            }}
            {poll_home_on and <Poller key={"poll-home-" + str(poll_home_ms)} ms={poll_home_ms} onTick={poll_home} />}
            {poll_req_on and <Poller key="poll-request" ms={5000} onTick={poll_request} />}
        </main>;
}
