"""Goal picker — the active goal as a compact selector on home. OWNER: Person B.

Tap it to open a bottom sheet (SOH-206): switch to another goal (SetGoal with
that goal's text), "New goal" (SetGoal with new text), or close the active goal
(CloseGoal, after an alert-dialog confirm — the goal is kept, just inactive). With no active goal it
becomes the "What are you working toward?" prompt, with earlier goals listed to
reopen. The shell owns the goals and the walker calls; this component only
holds UI state (open / adding / confirming / draft).
"""

import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody, SheetFooter }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription,
    AlertDialogFooter, AlertDialogAction, AlertDialogCancel
}
import from ..ui.icons { CheckIcon, ChevronDownIcon, PlusIcon }
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
            <Button
                variant="ghost"
                size="row"
                disabled={disabled or is_active}
                aria-current={"true" if is_active else "false"}
                className={cn(
                    "flex-row items-start gap-2 disabled:opacity-100",
                    "text-foreground" if is_active else "text-muted-foreground hover:text-foreground"
                )}
                onClick={handle_pick}
            >
                <CheckIcon className={cn("mt-0.5 size-4 shrink-0 text-link", "" if is_active else "invisible")} />
                <span className="min-w-0 flex-1 break-words text-body-sm">{goal["text"] as str}</span>
            </Button>
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
                <Button className="flex-1" disabled={busy or not draft.strip()} onClick={handle_save}>
                    {"Saving…" if busy else "Set goal"}
                </Button>
                {onCancel and
                    <Button variant="ghost" disabled={busy} onClick={handle_cancel}>Cancel</Button>}
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

    def open_sheet(e: MouseEvent) {
        open = True;
        adding = False;
        confirming = False;
    }

    def set_open(v: bool) -> None {
        open = v;
        if not v {
            adding = False;
        }
    }

    def set_confirming(v: bool) -> None {
        confirming = v;
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

    def do_close(e: MouseEvent) {
        confirming = False;
        open = False;
        onClose(active_id);
    }

    if not active_id {
        return
            <section aria-label="Goal" className="flex flex-col gap-4 rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4 shadow-edge">
                <div className="flex flex-col gap-1">
                    <h2 className="text-subhead font-medium">What are you working toward?</h2>
                    <p className="text-body-sm text-muted-foreground">
                        One goal at a time. Cirql ranks the people you know against it.
                    </p>
                </div>
                <NewGoalForm draft={draft} busy={busy} autoFocus={False} onDraft={set_draft} onSave={save_new} />
                {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
                {len(others) > 0 and
                    <div className="flex flex-col gap-2">
                        <span className="text-eyebrow text-muted-foreground">Earlier goals — tap to reopen</span>
                        <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-md border bg-background">
                            {for g in others {
                                <GoalOption key={_gid(g)} goal={g} is_active={False} disabled={busy} onPick={pick} />
                            }}
                        </ul>
                    </div>}
            </section>;
    }

    return
        <section aria-label="Goal" className="flex flex-col gap-2">
            <Button
                variant="secondary"
                size="row"
                aria-haspopup="dialog"
                aria-expanded={open}
                className="flex-row items-center gap-3 rounded-lg"
                onClick={open_sheet}
            >
                <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="text-eyebrow text-muted-foreground">Goal</span>
                    <span className="line-clamp-2 text-body font-medium">{active["text"] as str}</span>
                </div>
                <ChevronDownIcon className="size-4 shrink-0 text-muted-foreground" />
            </Button>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            <Sheet open={open} onOpenChange={set_open}>
                <SheetContent id="goal-sheet">
                    <SheetHeader>
                        <SheetTitle>Goals</SheetTitle>
                        <SheetDescription>One active goal. Switching keeps each goal's ranking.</SheetDescription>
                    </SheetHeader>
                    <SheetBody>
                        <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card">
                            <GoalOption key={active_id} goal={active} is_active={True} disabled={busy} onPick={pick} />
                            {for g in others {
                                <GoalOption key={_gid(g)} goal={g} is_active={False} disabled={busy} onPick={pick} />
                            }}
                        </ul>
                    </SheetBody>
                    <SheetFooter>
                        {if adding {
                            <NewGoalForm
                                draft={draft}
                                busy={busy}
                                autoFocus={True}
                                onDraft={set_draft}
                                onSave={save_new}
                                onCancel={cancel_new}
                            />
                        } else {
                            <div className="flex items-center justify-between gap-2">
                                <Button variant="secondary" disabled={busy} onClick={start_add}>
                                    <PlusIcon />
                                    New goal
                                </Button>
                                <Button variant="ghost" className="text-muted-foreground" disabled={busy} onClick={ask_close}>Close this goal</Button>
                            </div>
                        }}
                    </SheetFooter>
                </SheetContent>
            </Sheet>
            <AlertDialog open={confirming} onOpenChange={set_confirming}>
                <AlertDialogContent aria-label="Close goal">
                    <AlertDialogHeader>
                        <AlertDialogTitle>Close this goal?</AlertDialogTitle>
                        <AlertDialogDescription>
                            {"“" + (active["text"] as str) + "” — its ranking is cleared; the goal stays in your list to reopen."}
                        </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                        <AlertDialogCancel disabled={busy}>Keep it</AlertDialogCancel>
                        <AlertDialogAction variant="destructive" disabled={busy} onClick={do_close}>Close goal</AlertDialogAction>
                    </AlertDialogFooter>
                </AlertDialogContent>
            </AlertDialog>
        </section>;
}
