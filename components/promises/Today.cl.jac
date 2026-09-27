"""Today (SOH-187): every promise you made, Open then Done.

Each row: the promise, "to {name}" (tap opens the person sheet), due when set,
a checkbox that completes it (optimistic, reverted on failure), and a source
chip quoting the words it came from. `refresh_key` bumps (the shell does this
when the person sheet closes) re-read the list.
"""

import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..capture.Review { ReviewRow }
import from ..api { list_promises, complete_promise }
import from ...lib.text { short_date }
import from ...lib.utils { cn }

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

def:pub TodayRow(
    row: dict,
    is_done: bool,
    open_key: str,
    onToggle: Callable[[str], None],
    onCheck: Callable[[str, bool], None],
    onOpenPerson: Callable[[str], None]
) -> JsxElement {
    promise: dict = (row["promise"] or {}) as dict;
    prid: str = _s(promise, "_jac_id");
    key: str = "t-" + prid;
    due: str = _s(promise, "due");
    pid: str = _s(row["to"], "_jac_id");
    name: str = _s(row["to"], "name");

    def handle_check(e: ChangeEvent) {
        onCheck(prid, bool(e.target.checked));
    }

    def handle_person(e: MouseEvent) {
        if pid {
            onOpenPerson(pid);
        }
    }

    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <label className="flex items-start gap-2.5">
                <input
                    type="checkbox"
                    checked={is_done}
                    onChange={handle_check}
                    aria-label={("Mark not done: " if is_done else "Mark done: ") + _s(promise, "text")}
                    className="mt-0.5 size-4 shrink-0 accent-primary"
                />
                <span className={cn("text-body-sm", "text-muted-foreground line-through" if is_done else "")}>
                    {_s(promise, "text")}
                </span>
            </label>
            <span className="flex flex-wrap items-center gap-x-2 pl-6.5 text-caption text-muted-foreground">
                {if pid {
                    <Button variant="link" size="inline" className="text-caption" onClick={handle_person}>{"to " + name}</Button>
                }}
                {due and <span>{"due " + (short_date(due) or due)}</span>}
            </span>
        </ReviewRow>;
}

def:pub TodayGroup(title: str, count: int, children: any = None) -> JsxElement {
    return
        <section className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between">
                <h2 className="text-eyebrow text-muted-foreground">{title}</h2>
                <span className="text-caption tabular-nums text-muted-foreground">{str(count)}</span>
            </div>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">{children}</ul>
        </section>;
}

def:pub Today(on_open_person: Callable[[str], None], refresh_key: int = 0) -> JsxElement {
    has promise_rows: list[dict] = [],
        loaded: bool = False,
        load_error: str = "",
        open_key: str = "",
        done_map: dict = {},
        retry_tick: int = 0;

    async can with [refresh_key, retry_tick] entry {
        load_error = "";
        got: list[dict] = [];
        try {
            got = await list_promises();
            promise_rows = got;
            done_map = {};
        } except Exception as err {
            load_error = "Couldn't load your promises. " + str(err);
        }
        loaded = True;
    }

    def retry_load() {
        retry_tick = retry_tick + 1;
    }

    def toggle(key: str) {
        open_key = "" if open_key == key else key;
    }

    async def check(prid: str, done: bool) {
        before: dict = {**done_map};
        after: dict = {**done_map};
        after[prid] = "1" if done else "0";
        done_map = after;
        reply: dict = {};
        try {
            reply = await complete_promise(prid, done);
            if reply["error"] {
                done_map = before;
            }
        } except Exception {
            done_map = before;
        }
    }

    open_list: list[dict] = [];
    done_list: list[dict] = [];
    for row in promise_rows {
        prid: str = _s(row["promise"], "_jac_id");
        flag: str = (done_map[prid] or "") as str;
        is_done: bool = (flag == "1") if flag else bool(row["promise"]["done"]);
        if is_done {
            done_list.append(row);
        } else {
            open_list.append(row);
        }
    }

    return
        <div className="flex flex-col gap-6">
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
            } elif len(promise_rows) == 0 and not load_error {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    Nothing promised yet. Debrief a conversation and promises land here.
                </p>
            } else {
                if len(open_list) > 0 {
                    <TodayGroup title="Open" count={len(open_list)}>
                        {for row in open_list {
                            <TodayRow
                                key={_s(row["promise"], "_jac_id")}
                                row={row}
                                is_done={False}
                                open_key={open_key}
                                onToggle={toggle}
                                onCheck={check}
                                onOpenPerson={on_open_person}
                            />
                        }}
                    </TodayGroup>
                }
                if len(done_list) > 0 {
                    <TodayGroup title="Done" count={len(done_list)}>
                        {for row in done_list {
                            <TodayRow
                                key={_s(row["promise"], "_jac_id")}
                                row={row}
                                is_done={True}
                                open_key={open_key}
                                onToggle={toggle}
                                onCheck={check}
                                onOpenPerson={on_open_person}
                            />
                        }}
                    </TodayGroup>
                }
            }}
        </div>;
}
