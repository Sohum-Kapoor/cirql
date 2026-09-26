"""Client shell — OWNER: Person B.

One stateful shell component; handler bodies live in frontend.impl.jac
(`jac guide jac-cl-organization`). Sections are stateless components in
components/ (onboarding steps in components/onboarding/). Walkers that are not
live yet go through components/api.cl.jac, the single mock/live swap point.

Views: auth -> loading (GetMe) -> onboarding (4 steps) | home.
home -> capture (form, Capture call) -> review (extraction + source chips) -> home.
home = goal picker (ListGoals / SetGoal / CloseGoal) + GoalRank for the active
goal, cached per goal_id for the session (SOH-170) + people list.
"""

import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
import ".assets.main.css";

import from .components.AuthCard { AuthCard }
import from .components.HomeView { HomeView }
import from .components.onboarding.StepIndicator { StepIndicator }
import from .components.onboarding.AboutStep { AboutStep }
import from .components.onboarding.CardStep { CardStep }
import from .components.onboarding.PeopleStep { PeopleStep }
import from .components.onboarding.RecallStep { RecallStep }
import from .components.capture.CaptureForm { CaptureForm }
import from .components.capture.Review { Review }
import from .components.api { onboard_me, capture, goal_rank, list_people, list_goals, set_goal, close_goal }
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
glob RANK_ROWS: dict = {},
     RANK_PENDING: dict = {},
     RANK_ERRORS: dict = {};

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

def empty_rows() -> list[dict] {
    return [{"name": "", "how": ""} for _ in range(5)];
}

def:pub app -> JsxElement {
    has view: str = "auth",
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
        cap_kind: str = "debrief",
        cap_pending: bool = False,
        cap_error: str = "",
        cap_note: str = "",
        cap_result: dict = {},
        goals_list: list[dict] = [],
        goals_loaded: bool = False,
        goal_busy: bool = False,
        goal_error: str = "",
        rank_cache: dict = {},
        rank_pending_map: dict = {},
        rank_error_map: dict = {};

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
    def set_row(i: int, field: str, value: str) -> None;
    async def submit_people -> None;
    def skip_people -> None;
    def people_next -> None;
    async def start_recall -> None;
    def finish -> None;
    def open_capture -> None;
    def close_capture -> None;
    async def submit_capture -> None;
    def capture_done -> None;
    def capture_retry -> None;
    async def load_goals -> None;
    def publish_rank -> None;
    async def ensure_rank(goal_id: str, force: bool = False) -> None;
    async def switch_goal(goal_id: str) -> None;
    async def create_goal(text: str) -> None;
    async def end_goal(goal_id: str) -> None;
    def rerank -> None;

    goals: list[dict] = (onboard["goals"] or []) as list[dict];
    interests: list[dict] = (onboard["interests"] or []) as list[dict];
    active_goals: list[dict] = [g for g in goals if g["active"]];
    active_goal_text: str = (active_goals[0]["text"] as str) if len(active_goals) > 0 else "";
    home_goal_id: str = active_goal_id(goals_list);
    home_entry: dict = (rank_cache[home_goal_id] or {}) as dict if home_goal_id else {};
    home_cached: bool = True if home_entry["ok"] else False;
    home_rows: list[dict] = (home_entry["rows"] or []) as list[dict];

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
                <p key="loading" className="text-sm text-muted-foreground">Loading your graph…</p>
            } elif view == "home" {
                <HomeView
                    key="home"
                    people={people}
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
                    onSwitchGoal={switch_goal}
                    onCreateGoal={create_goal}
                    onCloseGoal={end_goal}
                    onRerank={rerank}
                />
            } elif view == "capture" {
                <CaptureForm
                    key="capture"
                    text={cap_text}
                    kind={cap_kind}
                    pending={cap_pending}
                    error={cap_error}
                    onTextChange={lambda v: str { cap_text = v; }}
                    onKindChange={lambda v: str { cap_kind = v; }}
                    onSubmit={submit_capture}
                    onBack={close_capture}
                />
            } elif view == "review" {
                <Review
                    key="review"
                    result={cap_result}
                    note_text={cap_note}
                    known={people}
                    onDone={capture_done}
                    onRetry={capture_retry}
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
                        onFieldChange={set_card_field}
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
                        onDone={finish}
                    />
                }
            }}
        </main>;
}
