"""Logged-in home: goal picker, who can help with the active goal (GoalRank),
then the people you know (collapsed). Capture stays pinned at the bottom.
Stateless apart from the picker's own UI state. OWNER: Person B.

Switching goals only swaps the ranked list: the shell keeps GoalRank results per
goal_id for the session, and a goal that isn't cached yet shows a loading state
on the list alone — the header, picker and people list stay put.
"""

import from .ui.button { Button }
import from .goals.GoalPicker { GoalPicker }
import from .goals.RankList { RankList, is_partial }
import from ..lib.text { join_with }
sv import from ..schema { Person }

"""Placeholder rows while a goal ranks for the first time (list only)."""
def:pub RankSkeleton() -> JsxElement {
    return
        <ul aria-hidden="true" className="flex flex-col divide-y divide-border rounded-md border">
            {for i in range(3) {
                <li key={str(i)} className="flex animate-pulse flex-col gap-2 pt-3 pb-3 pl-3 pr-3">
                    <div className="flex items-center justify-between gap-2">
                        <span className="h-3.5 w-32 rounded bg-muted" />
                        <span className="h-4 w-20 rounded-full bg-muted" />
                    </div>
                    <span className="h-3 w-full rounded bg-muted" />
                    <span className="h-3 w-2/3 rounded bg-muted" />
                </li>
            }}
        </ul>;
}

def:pub HomeView(
    people: list[Person],
    status: str,
    goals: list[dict],
    rank_rows: list[dict],
    rank_cached: bool,
    rank_pending: bool,
    rank_error: str,
    goals_loaded: bool,
    goal_busy: bool,
    goal_error: str,
    onRefresh: Callable[[], None],
    onLogout: Callable[[], None],
    onCapture: Callable[[], None],
    onSwitchGoal: Callable[[str], None],
    onCreateGoal: Callable[[str], None],
    onCloseGoal: Callable[[str], None],
    onRerank: Callable[[], None]
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    def handle_refresh(e: MouseEvent) {
        onRefresh();
    }

    def handle_logout(e: MouseEvent) {
        onLogout();
    }

    def handle_rerank(e: MouseEvent) {
        onRerank();
    }

    has_active: bool = len([g for g in goals if g["active"]]) > 0;
    partial: bool = is_partial(rank_rows);

    return
        <div className="flex flex-col gap-5 pb-20">
            <header className="flex items-center justify-between gap-2">
                <h1 className="text-base font-semibold tracking-tight">Cirql</h1>
                <div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={handle_refresh}>Refresh</Button>
                    <Button size="sm" variant="outline" onClick={handle_logout}>Log out</Button>
                </div>
            </header>
            {if not goals_loaded {
                <p className="rounded-md border pt-3 pb-3 pl-3 pr-3 text-sm text-muted-foreground">Loading your goals…</p>
            } else {
                <GoalPicker
                    goals={goals}
                    busy={goal_busy}
                    error={goal_error}
                    onSwitch={onSwitchGoal}
                    onCreate={onCreateGoal}
                    onClose={onCloseGoal}
                />
            }}
            {has_active and
                <section aria-label="Who can help" className="flex flex-col gap-2">
                    <div className="flex items-center justify-between gap-2">
                        <h2 className="text-sm font-medium">Who can help</h2>
                        <div className="flex items-center gap-2">
                            {rank_pending and
                                <span role="status" className="text-xs text-muted-foreground">Walking your graph…</span>}
                            <Button
                                size="xs"
                                variant="outline"
                                disabled={rank_pending}
                                aria-label="Re-rank for this goal"
                                onClick={handle_rerank}
                            >
                                Re-rank
                            </Button>
                        </div>
                    </div>
                    {rank_error and <p role="alert" className="text-sm text-destructive/80">{rank_error}</p>}
                    {partial and not rank_pending and
                        <p role="status" className="rounded-md border border-dashed bg-muted pt-2 pb-2 pl-3 pr-3 text-xs text-muted-foreground">
                            Ranking is partial right now — tap Re-rank in a minute.
                        </p>}
                    {if len(rank_rows) > 0 {
                        <RankList rows={rank_rows} dim={rank_pending} />
                    } elif rank_pending or not rank_cached {
                        <RankSkeleton />
                    } elif not rank_error {
                        <p className="rounded-md border border-dashed pt-4 pb-4 pl-3 pr-3 text-sm text-muted-foreground">
                            {"No one yet — "}
                            <button
                                type="button"
                                className="font-medium text-primary underline-offset-4 hover:underline"
                                onClick={handle_capture}
                            >
                                capture a conversation
                            </button>
                            {" to start."}
                        </p>
                    }}
                </section>}
            <details className="group rounded-md border">
                <summary className="flex cursor-pointer list-none items-baseline justify-between pt-2.5 pb-2.5 pl-3 pr-3">
                    <span className="text-sm font-medium">
                        <span aria-hidden="true" className="inline-block pr-1.5 text-muted-foreground transition-transform group-open:rotate-90">▸</span>
                        People you know
                    </span>
                    <span className="text-xs tabular-nums text-muted-foreground">{str(len(people))}</span>
                </summary>
                {if len(people) == 0 {
                    <p className="border-t pt-3 pb-3 pl-3 pr-3 text-sm text-muted-foreground">
                        {"No one yet — "}
                        <button
                            type="button"
                            className="font-medium text-primary underline-offset-4 hover:underline"
                            onClick={handle_capture}
                        >
                            capture a conversation
                        </button>
                        {" to start."}
                    </p>
                } else {
                    <ul className="flex flex-col divide-y divide-border border-t">
                        {for (idx, p) in enumerate(people) {
                            <li key={str(idx)} className="flex flex-col pt-2 pb-2 pl-3 pr-3">
                                <span className="text-sm">{p.name}</span>
                                {(p.title or p.org) and
                                    <span className="text-xs text-muted-foreground">
                                        {join_with([s for s in [p.title, p.org] if s], ", ")}
                                    </span>}
                            </li>
                        }}
                    </ul>
                }}
            </details>
            {status and <p className="text-xs text-muted-foreground">{status}</p>}
            <div className="fixed inset-x-0 bottom-0 z-10 border-t bg-background/90 backdrop-blur">
                <div className="mx-auto w-full max-w-md pt-3 pb-4 pl-4 pr-4">
                    <Button className="w-full" size="lg" onClick={handle_capture}>Capture a conversation</Button>
                </div>
            </div>
        </div>;
}
