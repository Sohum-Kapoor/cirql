"""Person sheet (SOH-207): everything you know about one person, with receipts.

Opened from a GoalRank row or a Today promise. Header (name, org · title, the
known|route|cold label for the active goal, how you met), the relevance reason,
then collapsible sections — Facts (with age), Wants/Offers, Promises (tick to
complete, optimistic), Notes — each row with a source chip that quotes its span.
Actions: Draft follow-up (a draft to copy; nothing sends), Brief me (spoken
recap; audio plays when the server sent any, text always shows), Forget
(confirmed, then the sheet closes and the caller refreshes).

The caller owns `open` and `person_id`; this owns what it loaded.
"""

import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody }
import from ..ui.badge { Badge }
import from ..ui.button { Button, buttonVariants }
import from ..ui.skeleton { Skeleton }
import from ..ui.textarea { Textarea }
import from ..ui.icons { ChevronRightIcon }
import from ..ui.collapsible { Collapsible, CollapsibleTrigger, CollapsibleContent }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogFooter, AlertDialogTitle,
    AlertDialogDescription, AlertDialogAction, AlertDialogCancel
}
import from ..capture.Review { ReviewRow }
import from ..goals.RankList { strength_variant }
import from ..api { person_detail, brief, complete_promise, draft_follow_up, forget }
import from ...lib.text { join_with, short_date }
import from ...lib.utils { cn }

glob _INTENT_LABEL: dict[str, str] = {"need": "wants", "offer": "offers", "open_to": "open to"};

"""Display only: 0 -> "today", 1 -> "1 day ago", 45 -> "1 month ago", 400 -> "1 year ago"."""
def:pub age_label(days: any) -> str {
    if days is None or not ((days as int) >= 0) {
        return "";
    }
    n: int = days as int;
    if n == 0 {
        return "today";
    }
    unit: str = "day";
    count: int = n;
    if n >= 365 {
        unit = "year";
        count = int(n / 365);
    } elif n >= 30 {
        unit = "month";
        count = int(n / 30);
    }
    return str(count) + " " + unit + ("" if count == 1 else "s") + " ago";
}

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

"""One collapsible section; the trigger mirrors HomeView's "People you know"."""
def:pub PersonSection(title: str, count: int, default_open: bool = False, children: any = None) -> JsxElement {
    return
        <Collapsible defaultOpen={default_open} className="overflow-hidden rounded-lg border bg-card shadow-edge">
            <CollapsibleTrigger
                aria-label={title + " — expand or collapse"}
                className={cn(
                    buttonVariants().call(None, {"variant": "ghost", "size": "row"}),
                    "flex-row items-center justify-between rounded-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50 [&[data-state=open]>span>svg]:rotate-90"
                )}
            >
                <span className="flex items-center gap-1.5 text-body-sm font-medium">
                    <ChevronRightIcon className="size-4 text-muted-foreground transition-transform" />
                    {title}
                </span>
                <span className="text-caption tabular-nums text-muted-foreground">{str(count)}</span>
            </CollapsibleTrigger>
            <CollapsibleContent>
                <ul className="flex flex-col divide-y divide-border border-t">{children}</ul>
            </CollapsibleContent>
        </Collapsible>;
}

def:pub FactItem(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    fact: dict = (row["fact"] or {}) as dict;
    key: str = "f-" + _s(fact, "_jac_id");
    url: str = _s(fact, "source_url");
    age: str = age_label(row["age_days"]);
    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <span className="text-body-sm">{_s(fact, "text")}</span>
            <span className="flex flex-wrap items-center gap-1.5 text-caption text-muted-foreground">
                {age and <span>{age}</span>}
                {_s(fact, "status") == "stale" and <Badge variant="outline">stale</Badge>}
                {url and
                    <a href={url} target="_blank" rel="noopener noreferrer" className="inline-flex">
                        <Badge variant="link">web</Badge>
                    </a>}
            </span>
        </ReviewRow>;
}

def:pub IntentItem(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    intent: dict = (row["intent"] or {}) as dict;
    key: str = "i-" + _s(intent, "_jac_id");
    kind: str = _s(intent, "kind");
    expired: bool = bool(row["expired"]);
    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <div className="flex flex-wrap items-center gap-1.5">
                <Badge variant={"default" if kind == "need" else "secondary"}>{_INTENT_LABEL[kind] or kind}</Badge>
                {expired and <Badge variant="outline">expired</Badge>}
            </div>
            <span className={cn("text-body-sm", "text-muted-foreground" if expired else "")}>{_s(intent, "text")}</span>
        </ReviewRow>;
}

def:pub PromiseItem(
    row: dict,
    is_done: bool,
    open_key: str,
    onToggle: Callable[[str], None],
    onCheck: Callable[[str, bool], None]
) -> JsxElement {
    promise: dict = (row["promise"] or {}) as dict;
    prid: str = _s(promise, "_jac_id");
    key: str = "p-" + prid;
    due: str = _s(promise, "due");

    def handle_check(e: ChangeEvent) {
        onCheck(prid, bool(e.target.checked));
    }

    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <label className="flex items-start gap-2.5">
                <input
                    type="checkbox"
                    checked={is_done}
                    onChange={handle_check}
                    className="mt-0.5 size-4 shrink-0 accent-primary"
                />
                <span className="flex flex-col gap-0.5">
                    <span className={cn("text-body-sm", "text-muted-foreground line-through" if is_done else "")}>
                        {_s(promise, "text")}
                    </span>
                    {due and <span className="text-caption text-muted-foreground">{"due " + (short_date(due) or due)}</span>}
                </span>
            </label>
        </ReviewRow>;
}

def:pub NoteItem(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    note: dict = (row["note"] or {}) as dict;
    key: str = "n-" + _s(note, "_jac_id");
    span: str = _s(row, "span");
    return
        <ReviewRow row_key={key} is_open={open_key == key} span={span} note_text={_s(note, "text")} onToggle={onToggle}>
            <span className="line-clamp-3 text-body-sm">{_s(note, "text") or span}</span>
            <span className="text-caption text-muted-foreground">
                {join_with([s for s in [_s(note, "kind"), short_date(_s(note, "captured_at"))] if s], " · ")}
            </span>
        </ReviewRow>;
}

def:pub PersonSheet(
    person_id: str,
    open: bool,
    on_close: Callable[[], None],
    on_forgotten: Callable[[str], None] | None = None
) -> JsxElement {
    has detail: dict = {},
        loaded_for: str = "",
        load_error: str = "",
        open_key: str = "",
        done_map: dict = {},
        draft_text: str = "",
        draft_busy: bool = False,
        draft_error: str = "",
        copied: bool = False,
        brief_text: str = "",
        brief_audio: str = "",
        brief_note: str = "",
        brief_busy: bool = False,
        confirm_open: bool = False,
        forget_busy: bool = False,
        forget_error: str = "";

    async can with [person_id, open] entry {
        if not open or not person_id {
            return;
        }
        detail = {};
        loaded_for = "";
        load_error = "";
        open_key = "";
        done_map = {};
        draft_text = "";
        draft_error = "";
        copied = False;
        brief_text = "";
        brief_audio = "";
        brief_note = "";
        forget_error = "";
        got: dict = {};
        try {
            got = await person_detail(person_id);
            detail = got;
            loaded_for = person_id;
        } except Exception as err {
            load_error = "Couldn't load this person. " + str(err);
            loaded_for = person_id;
        }
    }

    def handle_open_change(v: bool) -> None {
        if not v {
            on_close();
        }
    }

    def toggle(key: str) -> None {
        open_key = "" if open_key == key else key;
    }

    async def check_promise(prid: str, done: bool) -> None {
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

    async def run_draft -> None {
        draft_busy = True;
        draft_error = "";
        copied = False;
        reply: dict = {};
        try {
            reply = await draft_follow_up(person_id, "");
            if reply["error"] {
                draft_error = "Couldn't draft for this person.";
            } else {
                draft_text = (reply["draft"] or "") as str;
            }
        } except Exception as err {
            draft_error = "Couldn't draft right now. " + str(err);
        }
        draft_busy = False;
    }

    def edit_draft(e: ChangeEvent) {
        draft_text = e.target.value;
        copied = False;
    }

    async def copy_draft -> None {
        try {
            board: any = navigator.clipboard;
            await board.writeText(draft_text);
            copied = True;
        } except Exception {
            copied = False;
        }
    }

    async def run_brief -> None {
        brief_busy = True;
        brief_note = "";
        brief_audio = "";
        reply: dict = {};
        try {
            reply = await brief(person_id, True);
            if reply["error"] {
                brief_note = "Couldn't brief on this person.";
            } else {
                brief_text = (reply["text"] or "") as str;
                b64: str = (reply["audio_b64"] or "") as str;
                if b64 {
                    brief_audio = "data:" + ((reply["mime"] or "audio/mpeg") as str) + ";base64," + b64;
                } elif reply["voice_error"] {
                    brief_note = "Voice unavailable — text only.";
                }
            }
        } except Exception as err {
            brief_note = "Couldn't brief right now. " + str(err);
        }
        brief_busy = False;
    }

    def ask_forget(e: MouseEvent) {
        forget_error = "";
        confirm_open = True;
    }

    def set_confirm(v: bool) -> None {
        confirm_open = v;
    }

    async def do_forget(e: MouseEvent) -> None {
        e.preventDefault();
        forget_busy = True;
        forget_error = "";
        reply: dict = {};
        gone_id: str = person_id;
        try {
            reply = await forget(gone_id);
            if reply["error"] {
                forget_error = "Couldn't forget this person.";
            } else {
                confirm_open = False;
                on_close();
                if on_forgotten {
                    on_forgotten(gone_id);
                }
            }
        } except Exception as err {
            forget_error = "Couldn't forget right now. " + str(err);
        }
        forget_busy = False;
    }

    ready: bool = loaded_for == person_id and loaded_for != "";
    missing: bool = ready and bool(detail["error"]);
    person: dict = (detail["person"] or {}) as dict;
    rel: dict = (detail["relevance"] or {}) as dict;
    facts: list[dict] = (detail["facts"] or []) as list[dict];
    intents: list[dict] = (detail["intents"] or []) as list[dict];
    promises: list[dict] = (detail["promises"] or []) as list[dict];
    notes: list[dict] = (detail["notes"] or []) as list[dict];
    how_met: str = _s(detail, "how_met");
    sub: str = join_with([s for s in [_s(person, "org"), _s(person, "title")] if s], " · ");
    done_of: dict = {};
    for row in promises {
        prid: str = _s(row["promise"], "_jac_id");
        flag: str = (done_map[prid] or "") as str;
        done_of[prid] = (flag == "1") if flag else bool(row["promise"]["done"]);
    }

    return
        <Sheet open={open} onOpenChange={handle_open_change}>
            <SheetContent aria-label="Person">
                {if not ready {
                    <SheetHeader>
                        <SheetTitle className="sr-only">Loading</SheetTitle>
                        <SheetDescription className="sr-only">Loading this person</SheetDescription>
                        <div role="status" aria-label="Loading" className="flex flex-col gap-2">
                            <Skeleton className="h-5 w-40" />
                            <Skeleton className="h-3.5 w-56" />
                        </div>
                    </SheetHeader>
                    <SheetBody>
                        <Skeleton className="h-3.5 w-full" />
                        <Skeleton className="h-12 w-full rounded-lg" />
                        <Skeleton className="h-12 w-full rounded-lg" />
                    </SheetBody>
                } elif load_error or missing {
                    <SheetHeader>
                        <SheetTitle>Not found</SheetTitle>
                        <SheetDescription>
                            {load_error or "This person isn't in your graph any more."}
                        </SheetDescription>
                    </SheetHeader>
                } else {
                    <SheetHeader>
                        <div className="flex flex-wrap items-center gap-2">
                            <SheetTitle>{_s(person, "name")}</SheetTitle>
                            {rel and _s(rel, "label") and <Badge variant="outline">{_s(rel, "label")}</Badge>}
                            {rel and _s(rel, "strength") and
                                <Badge variant={strength_variant(_s(rel, "strength"))}>{_s(rel, "strength")}</Badge>}
                        </div>
                        <SheetDescription>
                            {join_with([s for s in [sub, ("met: " + how_met) if how_met else ""] if s], " — ") or "No details yet"}
                        </SheetDescription>
                    </SheetHeader>
                    <SheetBody className="gap-4">
                        {rel and _s(rel, "reason") and
                            <p className="text-body-sm text-muted-foreground">{_s(rel, "reason")}</p>}
                        <div className="grid grid-cols-2 gap-2">
                            <Button variant="secondary" disabled={draft_busy} onClick={run_draft}>
                                {"Drafting…" if draft_busy else "Draft follow-up"}
                            </Button>
                            <Button variant="secondary" disabled={brief_busy} onClick={run_brief}>
                                {"Briefing…" if brief_busy else "Brief me"}
                            </Button>
                        </div>
                        {draft_error and <p role="alert" className="text-body-sm text-destructive">{draft_error}</p>}
                        {draft_text and
                            <div className="flex flex-col gap-2">
                                <span className="text-eyebrow text-muted-foreground">Draft — copy it; nothing sends</span>
                                <Textarea aria-label="Follow-up draft" value={draft_text} onChange={edit_draft} />
                                <Button size="sm" variant="outline" className="self-end" onClick={copy_draft}>
                                    {"Copied" if copied else "Copy"}
                                </Button>
                            </div>}
                        {(brief_text or brief_note) and
                            <div className="flex flex-col gap-2 rounded-md border-l-2 border-primary bg-secondary pt-2 pb-2 pl-3 pr-3">
                                <span className="text-eyebrow text-muted-foreground">Brief</span>
                                {brief_audio and <audio controls={True} autoPlay={True} src={brief_audio} className="w-full" />}
                                {brief_text and <p className="text-body-sm">{brief_text}</p>}
                                {brief_note and <p className="text-caption text-muted-foreground">{brief_note}</p>}
                            </div>}
                        <PersonSection title="Facts" count={len(facts)} default_open={True}>
                            {for row in facts {
                                <FactItem key={_s(row["fact"], "_jac_id")} row={row} open_key={open_key} onToggle={toggle} />
                            }}
                        </PersonSection>
                        <PersonSection title="Wants / offers" count={len(intents)}>
                            {for row in intents {
                                <IntentItem key={_s(row["intent"], "_jac_id")} row={row} open_key={open_key} onToggle={toggle} />
                            }}
                        </PersonSection>
                        <PersonSection title="Promises" count={len(promises)} default_open={len(promises) > 0}>
                            {for row in promises {
                                <PromiseItem
                                    key={_s(row["promise"], "_jac_id")}
                                    row={row}
                                    is_done={bool(done_of[_s(row["promise"], "_jac_id")])}
                                    open_key={open_key}
                                    onToggle={toggle}
                                    onCheck={check_promise}
                                />
                            }}
                        </PersonSection>
                        <PersonSection title="Notes" count={len(notes)}>
                            {for row in notes {
                                <NoteItem key={_s(row["note"], "_jac_id")} row={row} open_key={open_key} onToggle={toggle} />
                            }}
                        </PersonSection>
                        <Button variant="destructive" className="w-full" onClick={ask_forget}>Forget this person</Button>
                    </SheetBody>
                    <AlertDialog open={confirm_open} onOpenChange={set_confirm}>
                        <AlertDialogContent>
                            <AlertDialogHeader>
                                <AlertDialogTitle>{"Forget " + (_s(person, "name") or "this person") + "?"}</AlertDialogTitle>
                                <AlertDialogDescription>
                                    Removes them and everything only about them from your graph. Your notes stay.
                                </AlertDialogDescription>
                            </AlertDialogHeader>
                            {forget_error and <p role="alert" className="text-body-sm text-destructive">{forget_error}</p>}
                            <AlertDialogFooter>
                                <AlertDialogCancel disabled={forget_busy}>Cancel</AlertDialogCancel>
                                <AlertDialogAction variant="destructive" disabled={forget_busy} onClick={do_forget}>
                                    {"Forgetting…" if forget_busy else "Forget"}
                                </AlertDialogAction>
                            </AlertDialogFooter>
                        </AlertDialogContent>
                    </AlertDialog>
                }}
            </SheetContent>
        </Sheet>;
}
