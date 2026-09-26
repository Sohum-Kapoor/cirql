"""Client shell — OWNER: Person B.

One stateful shell component; handler bodies live in frontend.impl.jac
(`jac guide jac-cl-organization`). Sections are stateless components in
components/ (onboarding steps in components/onboarding/). Walkers that are not
live yet go through components/api.cl.jac, the single mock/live swap point.

Views: auth -> loading (GetMe) -> onboarding (4 steps) | home.
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
import from .components.api { onboard_me, capture, goal_rank }
import from .lib.text { join_lines }

sv import from walkers { Ping, GetMe, ListPeople }
sv import from schema { Person }

glob STEP_LABELS: list[str] = ["About you", "Your card", "Bring five people", "First recall"];

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
        rank_error: str = "";

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

    goals: list[dict] = (onboard["goals"] or []) as list[dict];
    interests: list[dict] = (onboard["interests"] or []) as list[dict];
    active_goals: list[dict] = [g for g in goals if g["active"]];
    active_goal_text: str = (active_goals[0]["text"] as str) if len(active_goals) > 0 else "";

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
                <HomeView key="home" people={people} status={status} onRefresh={refresh} onLogout={logout} />
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
