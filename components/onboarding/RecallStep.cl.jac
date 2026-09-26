"""Onboarding step 4 — first recall: GoalRank rows for the active goal. OWNER: Person B.

No scores: each row shows a strength word (strong|medium|weak), a label
(known|route|cold), the reason, evidence chips, and a drafted opener as plain
text — nothing sends. Rows render via the shared components/goals/RankList.
"""

import from "..ui.button" { Button }
import from ..goals.RankList { RankList, RankSkeleton }

def:pub RecallStep(
    goal_text: str,
    rows: list[dict],
    pending: bool,
    error: str,
    onDone: Callable[[], None]
) -> JsxElement {
    def handle_done(e: MouseEvent) {
        onDone();
    }

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">First recall</h2>
                <p className="text-body-sm text-muted-foreground">
                    {"For your goal: "}
                    <span className="text-foreground">{goal_text or "—"}</span>
                    {", here's who you already know."}
                </p>
            </div>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            {if pending {
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
