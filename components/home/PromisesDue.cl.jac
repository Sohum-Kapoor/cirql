"""Promises due — the first thing on Home's "Today" surface (SOH-226).

Up to `HOME_PROMISE_PREVIEW` open promises, soonest due first (`ListPromises`
already reports open before done, ascending by due within each group), each
row: who it's to, what was promised, when it's due, and a Done button
(optimistic, reverted on failure — same `complete_promise` call
`promises/Today.cl.jac` uses; no snooze exists client-side yet). "See all"
hands off to People > Today, same list, ungrouped. Empty: one sentence and a
Capture button. `refresh_key` bumps (the shell does this when the person
sheet closes) re-read the list — same signal `promises/Today.cl.jac` uses.
"""

import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..api { list_promises, complete_promise }
import from ...lib.text { due_label }

glob HOME_PROMISE_PREVIEW: int = 3;

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

"""due_label's "Due Mon Sep 28" as a sentence-cased row line: "due Mon Sep 28".
`due` may still be raw, un-normalized text ("Monday") when a promise hasn't
gone through `dates.sv.jac`'s `parse_due` yet — same fallback
`promises/Today.cl.jac` uses (`short_date(due) or due`): show the raw text
rather than a blank line."""
def _due_line(due: str) -> str {
    lbl: str = due_label(due);
    if lbl.startswith("Due ") {
        return "due " + lbl[4:];
    }
    if lbl {
        return lbl;
    }
    return "due " + due;
}

def:pub PromiseDueRow(
    row: dict,
    busy: bool,
    onDone: Callable[[str], None],
    onOpenPerson: Callable[[str], None]
) -> JsxElement {
    promise: dict = (row["promise"] or {}) as dict;
    prid: str = _s(promise, "_jac_id");
    due: str = _s(promise, "due");
    pid: str = _s(row["to"], "_jac_id");
    name: str = _s(row["to"], "name") or "Someone";

    def handle_done(e: MouseEvent) {
        onDone(prid);
    }

    def handle_person(e: MouseEvent) {
        if pid {
            onOpenPerson(pid);
        }
    }

    return
        <li className="flex items-start justify-between gap-3 pt-2.5 pb-2.5 pl-4 pr-3">
            <span className="flex min-w-0 flex-col gap-0.5">
                {if pid {
                    <Button variant="link" size="inline" className="w-fit text-body-sm font-medium" onClick={handle_person}>{name}</Button>
                } else {
                    <span className="text-body-sm font-medium">{name}</span>
                }}
                <span className="text-body-sm text-muted-foreground">{_s(promise, "text")}</span>
                {due and <span className="text-caption text-muted-foreground">{_due_line(due)}</span>}
            </span>
            <Button size="sm" variant="outline" disabled={busy} onClick={handle_done} className="shrink-0 self-center">
                Done
            </Button>
        </li>;
}

def:pub PromisesDue(
    onOpenPerson: Callable[[str], None],
    onSeeAll: Callable[[], None],
    onCapture: Callable[[], None],
    refresh_key: int = 0
) -> JsxElement {
    has rows: list[dict] = [],
        loaded: bool = False,
        load_error: str = "",
        busy_map: dict = {},
        retry_tick: int = 0;

    async can with [refresh_key, retry_tick] entry {
        load_error = "";
        got: list[dict] = [];
        try {
            got = await list_promises();
        } except Exception as err {
            load_error = "Couldn't load your promises. " + str(err);
        }
        rows = got;
        loaded = True;
    }

    def retry_load() {
        retry_tick = retry_tick + 1;
    }

    async def mark_done(prid: str) {
        after: dict = {**busy_map};
        after[prid] = True;
        busy_map = after;
        reply: dict = {};
        failed: bool = False;
        try {
            reply = await complete_promise(prid, True);
            if reply["error"] {
                failed = True;
            }
        } except Exception {
            failed = True;
        }
        if not failed {
            rows = [r for r in rows if _s(r["promise"], "_jac_id") != prid];
        }
        cleared: dict = {**busy_map};
        cleared[prid] = False;
        busy_map = cleared;
    }

    def see_all(e: MouseEvent) {
        onSeeAll();
    }

    def go_capture(e: MouseEvent) {
        onCapture();
    }

    open_rows: list[dict] = [r for r in rows if not bool(r["promise"]["done"])];
    preview: list[dict] = open_rows[:HOME_PROMISE_PREVIEW];
    more: int = len(open_rows) - HOME_PROMISE_PREVIEW;

    return
        <section aria-label="Promises due" className="flex flex-col gap-3">
            <div className="flex items-baseline justify-between">
                <h2 className="text-eyebrow text-muted-foreground">Promises due</h2>
                {len(open_rows) > 0 and <span className="text-caption tabular-nums text-muted-foreground">{str(len(open_rows))}</span>}
            </div>
            {load_error and
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{load_error}</p>
                    <Button size="sm" variant="outline" onClick={retry_load}>Retry</Button>
                </div>}
            {if not loaded {
                <div role="status" aria-label="Loading your promises" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-3 w-1/3" />
                </div>
            } elif len(open_rows) == 0 and not load_error {
                <div className="flex flex-col gap-2 rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4">
                    <p className="text-body-sm text-muted-foreground">
                        Nothing due. Debrief a conversation and promises land here.
                    </p>
                    <div>
                        <Button size="sm" onClick={go_capture}>Capture</Button>
                    </div>
                </div>
            } else {
                <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                    {for row in preview {
                        <PromiseDueRow
                            key={_s(row["promise"], "_jac_id")}
                            row={row}
                            busy={True if busy_map[_s(row["promise"], "_jac_id")] else False}
                            onDone={mark_done}
                            onOpenPerson={onOpenPerson}
                        />
                    }}
                </ul>
                if more > 0 {
                    <Button variant="ghost" className="w-full text-muted-foreground" onClick={see_all}>
                        {"See all (" + str(len(open_rows)) + ")"}
                    </Button>
                }
            }}
        </section>;
}
