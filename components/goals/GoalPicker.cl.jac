"""Goal picker — the active goal as a compact selector on home. OWNER: Person B.

Tap it to open an inline list: switch to another goal (SetGoal with that goal's
text), "+ New goal" (SetGoal with new text), or close the active goal (CloseGoal,
after a confirm — the goal is kept, just inactive). With no active goal it
becomes the "What are you working toward?" prompt, with earlier goals listed to
reopen. The shell owns the goals and the walker calls; this component only
holds UI state (open / adding / confirming / draft).
"""

import from ..ui.button { Button }
import from ..ui.input { Input }
import from ...lib.utils { cn }

def _gid(g: dict) -> str {
    return (g["_jac_id"] or "") as str;
}

"""One goal in the switch list; a named handler, not a lambda inside a JSX for."""
def:pub GoalOption(goal: dict, is_active: bool, disabled: bool, onPick: Callable[[str], None]) -> JsxElement {
    def handle_pick(e: MouseEvent) {
        onPick(_gid(goal));
    }

    return
        <li>
            <button
                type="button"
                disabled={disabled or is_active}
                aria-current={"true" if is_active else "false"}
                className={cn(
                    "flex w-full items-start gap-2 pt-2.5 pb-2.5 pl-3 pr-3 text-left text-sm transition-colors disabled:cursor-default",
                    "text-foreground" if is_active else "text-muted-foreground hover:bg-muted hover:text-foreground"
                )}
                onClick={handle_pick}
            >
                <span aria-hidden="true" className={cn("w-4 shrink-0 text-primary", "" if is_active else "invisible")}>✓</span>
                <span className="min-w-0 flex-1 break-words">{goal["text"] as str}</span>
            </button>
        </li>;
}

"""New-goal input + Save/Cancel. Enter saves."""
def:pub NewGoalForm(
    draft: str,
    busy: bool,
    autoFocus: bool,
    onDraft: Callable[[str], None],
    onSave: Callable[[], None],
    onCancel: Callable[[], None] | None = None
) -> JsxElement {
    def handle_change(e: ChangeEvent) {
        onDraft(e.target.value);
    }

    def handle_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            e.preventDefault();
            onSave();
        }
    }

    def handle_save(e: MouseEvent) {
        onSave();
    }

    def handle_cancel(e: MouseEvent) {
        if onCancel {
            onCancel();
        }
    }

    return
        <div className="flex flex-col gap-2">
            <Input
                id="new-goal"
                aria-label="New goal"
                placeholder="e.g. Find a co-founder who knows batteries"
                value={draft}
                autoFocus={autoFocus}
                disabled={busy}
                onChange={handle_change}
                onKeyDown={handle_key}
            />
            <div className="flex gap-2">
                <Button className="flex-1" size="sm" disabled={busy or not draft.strip()} onClick={handle_save}>
                    {"Saving…" if busy else "Set goal"}
                </Button>
                {onCancel and
                    <Button size="sm" variant="ghost" disabled={busy} onClick={handle_cancel}>Cancel</Button>}
            </div>
        </div>;
}

def:pub GoalPicker(
    goals: list[dict],
    busy: bool,
    error: str,
    onSwitch: Callable[[str], None],
    onCreate: Callable[[str], None],
    onClose: Callable[[str], None]
) -> JsxElement {
    has open: bool = False,
        adding: bool = False,
        confirming: bool = False,
        draft: str = "";

    active_goals: list[dict] = [g for g in goals if g["active"]];
    active: dict = active_goals[0] if len(active_goals) > 0 else {};
    active_id: str = _gid(active) if len(active_goals) > 0 else "";
    others: list[dict] = [g for g in goals if not g["active"]];

    def toggle_open(e: MouseEvent) {
        open = not open;
        adding = False;
        confirming = False;
    }

    def pick(goal_id: str) -> None {
        open = False;
        confirming = False;
        onSwitch(goal_id);
    }

    def set_draft(v: str) -> None {
        draft = v;
    }

    def save_new() -> None {
        text: str = draft.strip();
        if not text {
            return;
        }
        onCreate(text);
        draft = "";
        adding = False;
        open = False;
    }

    def cancel_new() -> None {
        draft = "";
        adding = False;
    }

    def start_add(e: MouseEvent) {
        adding = True;
        confirming = False;
    }

    def ask_close(e: MouseEvent) {
        confirming = True;
        adding = False;
    }

    def keep(e: MouseEvent) {
        confirming = False;
    }

    def do_close(e: MouseEvent) {
        confirming = False;
        open = False;
        onClose(active_id);
    }

    if not active_id {
        return
            <section aria-label="Goal" className="flex flex-col gap-3 rounded-md border bg-card pt-4 pb-4 pl-3 pr-3">
                <div className="flex flex-col gap-1">
                    <h2 className="text-base font-semibold tracking-tight">What are you working toward?</h2>
                    <p className="text-sm text-muted-foreground">
                        One goal at a time. Cirql ranks the people you know against it.
                    </p>
                </div>
                <NewGoalForm draft={draft} busy={busy} autoFocus={False} onDraft={set_draft} onSave={save_new} />
                {error and <p role="alert" className="text-sm text-destructive/80">{error}</p>}
                {len(others) > 0 and
                    <div className="flex flex-col gap-1">
                        <span className="text-xs font-medium text-muted-foreground">Earlier goals — tap to reopen</span>
                        <ul className="flex flex-col divide-y divide-border rounded-md border">
                            {for g in others {
                                <GoalOption key={_gid(g)} goal={g} is_active={False} disabled={busy} onPick={pick} />
                            }}
                        </ul>
                    </div>}
            </section>;
    }

    return
        <section aria-label="Goal" className="flex flex-col gap-2">
            <button
                type="button"
                aria-expanded={open}
                aria-controls="goal-sheet"
                className={cn(
                    "flex w-full items-center gap-3 rounded-md border pt-2.5 pb-2.5 pl-3 pr-3 text-left transition-colors",
                    "border-primary bg-accent" if open else "bg-card hover:bg-muted"
                )}
                onClick={toggle_open}
            >
                <div className="flex min-w-0 flex-1 flex-col">
                    <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Goal</span>
                    <span className="line-clamp-2 text-sm font-medium">{active["text"] as str}</span>
                </div>
                <span aria-hidden="true" className={cn("shrink-0 text-muted-foreground transition-transform", "rotate-180" if open else "")}>▾</span>
            </button>
            {error and <p role="alert" className="text-sm text-destructive/80">{error}</p>}
            {open and
                <div id="goal-sheet" className="flex flex-col gap-2 rounded-md border bg-popover pt-1 pb-2 shadow-sm">
                    <ul className="flex flex-col divide-y divide-border">
                        <GoalOption key={active_id} goal={active} is_active={True} disabled={busy} onPick={pick} />
                        {for g in others {
                            <GoalOption key={_gid(g)} goal={g} is_active={False} disabled={busy} onPick={pick} />
                        }}
                    </ul>
                    <div className="flex flex-col gap-2 border-t pt-2 pl-3 pr-3">
                        {if adding {
                            <NewGoalForm
                                draft={draft}
                                busy={busy}
                                autoFocus={True}
                                onDraft={set_draft}
                                onSave={save_new}
                                onCancel={cancel_new}
                            />
                        } elif confirming {
                            <div role="alertdialog" aria-label="Close goal" className="flex flex-col gap-2">
                                <p className="text-sm">
                                    {"Close “" + (active["text"] as str) + "”? Its ranking is cleared; the goal stays in your list to reopen."}
                                </p>
                                <div className="flex gap-2">
                                    <Button className="flex-1" size="sm" variant="destructive" disabled={busy} onClick={do_close}>Close goal</Button>
                                    <Button className="flex-1" size="sm" variant="outline" disabled={busy} onClick={keep}>Keep it</Button>
                                </div>
                            </div>
                        } else {
                            <div className="flex items-center justify-between gap-2">
                                <Button size="sm" variant="ghost" disabled={busy} onClick={start_add}>+ New goal</Button>
                                <Button size="sm" variant="ghost" className="text-muted-foreground" disabled={busy} onClick={ask_close}>Close this goal</Button>
                            </div>
                        }}
                    </div>
                </div>}
        </section>;
}
