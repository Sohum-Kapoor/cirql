"""Onboarding step 4 — first recall: GoalRank rows for the active goal. OWNER: Person B.

No scores: each row shows a strength word (strong|medium|weak), a label
(known|route|cold), the reason, evidence chips, and a drafted opener as plain
text — nothing sends. Rows render via the shared components/goals/RankList.

With no active goal (skipped step 2, or OnboardMe's extraction never surfaced
one — see components/onboarding/CardStep.cl.jac) there is nothing to rank: this
shows a human prompt and the shared NewGoalForm (components/goals/GoalPicker.cl.jac)
instead of a bare "—" or a misleading "capture a conversation" line.
"""

import from "..ui.button" { Button }
import from ..goals.RankList { RankList, RankSkeleton }
import from ..goals.GoalPicker { NewGoalForm }

def:pub RecallStep(
    goal_text: str,
    rows: list[dict],
    pending: bool,
    error: str,
    goal_busy: bool,
    onAddGoal: Callable[[str], None],
    onDone: Callable[[], None]
) -> JsxElement {
    has draft: str = "";

    def handle_done(e: MouseEvent) {
        onDone();
    }

    def set_draft(v: str) {
        draft = v;
    }

    def save_goal() -> None {
        text: str = draft.strip();
        if not text {
            return;
        }
        onAddGoal(text);
        draft = "";
    }

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">First recall</h2>
                {if goal_text {
                    <p className="text-body-sm text-muted-foreground">
                        {"For your goal: "}
                        <span className="text-foreground">{goal_text}</span>
                        {", here's who you already know."}
                    </p>
                } else {
                    <p className="text-body-sm text-muted-foreground">
                        Add a goal to see who can help.
                    </p>
                }}
            </div>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            {if not goal_text {
                <NewGoalForm draft={draft} busy={goal_busy} autoFocus={False} onDraft={set_draft} onSave={save_goal} />
            } elif pending {
                <div className="flex flex-col gap-2">
                    <span role="status" className="text-caption text-muted-foreground">Walking your graph…</span>
                    <RankSkeleton />
                </div>
            } elif len(rows) == 0 and not error {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    No one yet — capture a conversation to start.
                </p>
            } else {
                <RankList rows={rows} />
            }}
            <Button className="w-full" size="lg" disabled={pending} onClick={handle_done}>Done</Button>
        </div>;
}
