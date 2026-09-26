"""Onboarding step 4 — first recall: GoalRank rows for the active goal. OWNER: Person B.

No scores: each row shows a strength word (strong|medium|weak), a label
(known|route|cold), the reason, and a drafted opener as plain text — nothing sends.
"""

import from "..ui.button" { Button }
import from "..ui.badge" { Badge }
import from "...lib.text" { join_with }

def _strength_variant(strength: str) -> str {
    if strength == "strong" {
        return "default";
    }
    if strength == "medium" {
        return "secondary";
    }
    return "outline";
}

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
                <h2 className="text-lg font-semibold tracking-tight">First recall</h2>
                <p className="text-sm text-muted-foreground">
                    {"For your goal: "}
                    <span className="text-foreground">{goal_text or "—"}</span>
                    {", here's who you already know."}
                </p>
            </div>
            {error and <p className="text-sm text-destructive/80">{error}</p>}
            {if pending {
                <p className="rounded-md border pt-4 pb-4 pl-3 pr-3 text-sm text-muted-foreground">Walking your graph…</p>
            } elif len(rows) == 0 and not error {
                <p className="rounded-md border border-dashed pt-4 pb-4 pl-3 pr-3 text-sm text-muted-foreground">
                    No one yet — capture a conversation to start.
                </p>
            } else {
                <ul className="flex flex-col divide-y divide-border rounded-md border">
                    {for row in rows {
                        <li key={row["person"]["_jac_id"]} className="flex flex-col gap-1 pt-3 pb-3 pl-3 pr-3">
                            <div className="flex items-start justify-between gap-2">
                                <div className="flex min-w-0 flex-col">
                                    <span className="truncate text-sm font-medium">{row["person"]["name"]}</span>
                                    <span className="truncate text-xs text-muted-foreground">
                                        {join_with([s for s in [row["person"]["title"] as str, row["person"]["org"] as str] if s], ", ")}
                                    </span>
                                </div>
                                <div className="flex shrink-0 gap-1">
                                    <Badge variant={_strength_variant(row["strength"] as str)}>{row["strength"]}</Badge>
                                    <Badge variant="outline">{row["label"]}</Badge>
                                </div>
                            </div>
                            <p className="text-sm">{row["reason"]}</p>
                            <p className="text-xs italic text-muted-foreground">{"Opener: " + row["opener"]}</p>
                        </li>
                    }}
                </ul>
            }}
            <Button className="w-full" disabled={pending} onClick={handle_done}>Done</Button>
        </div>;
}
