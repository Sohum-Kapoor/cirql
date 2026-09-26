"""Gap alerts under the ranked list + the "Ask my network" sheet. OWNER: Person B.

One card per GapFinder item: "No warm path to {kind}", why_needed, and *Ask my
network*. A gap names a KIND of person, never a person. The sheet prefills the
need with `suggested_need` and the one-line about with the user's card headline;
both are editable. Posting goes through the shell (PostRequest). A gap whose
suggested need was already asked shows the request's status instead of the button.
"""

import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.textarea { Textarea }
import from ..ui.skeleton { Skeleton }
import from ..ui.field { Field, FieldLabel, FieldGroup }
import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody, SheetFooter }
import from .common { StatusChip, req_label }

def:pub GapSkeleton() -> JsxElement {
    return
        <div aria-hidden="true" className="flex flex-col gap-2 rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-4 pr-4">
            <Skeleton className="h-4 w-48" />
            <Skeleton className="h-3.5 w-full" />
        </div>;
}

"""The "Ask my network" bottom sheet: need + one line about you, both editable."""
def:pub AskSheet(
    open: bool,
    kind: str,
    need: str,
    about_line: str,
    busy: bool,
    error: str,
    onNeed: Callable[[str], None],
    onAbout: Callable[[str], None],
    onPost: Callable[[], None],
    onOpenChange: Callable[[bool], None]
) -> JsxElement {
    def handle_need(e: ChangeEvent) {
        onNeed(e.target.value);
    }

    def handle_about(e: ChangeEvent) {
        onAbout(e.target.value);
    }

    def handle_post(e: MouseEvent) {
        onPost();
    }

    def handle_cancel(e: MouseEvent) {
        onOpenChange(False);
    }

    return
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent aria-label="Ask my network">
                <SheetHeader>
                    <SheetTitle>Ask my network</SheetTitle>
                    <SheetDescription>{"No warm path to " + kind + "."}</SheetDescription>
                </SheetHeader>
                <SheetBody>
                    <FieldGroup className="gap-4">
                        <Field>
                            <FieldLabel htmlFor="ask-need">What you're asking for</FieldLabel>
                            <Textarea id="ask-need" rows={2} value={need} disabled={busy} onChange={handle_need} />
                        </Field>
                        <Field>
                            <FieldLabel htmlFor="ask-about">One line about you</FieldLabel>
                            <Input
                                id="ask-about"
                                value={about_line}
                                placeholder="e.g. Student founder building thermal batteries"
                                disabled={busy}
                                onChange={handle_about}
                            />
                        </Field>
                    </FieldGroup>
                    <p className="text-caption text-muted-foreground">
                        Friends' agents see only this need, this line and your handle. Each one checks its own graph; no names cross until everyone involved says yes.
                    </p>
                    {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
                </SheetBody>
                <SheetFooter className="grid grid-cols-2">
                    <Button variant="secondary" disabled={busy} onClick={handle_cancel}>Cancel</Button>
                    <Button disabled={busy or not need.strip()} onClick={handle_post}>
                        {"Posting…" if busy else "Post request"}
                    </Button>
                </SheetFooter>
            </SheetContent>
        </Sheet>;
}

def:pub GapCard(
    idx: int,
    gap: dict,
    asked_status: str,
    onOpen: Callable[[int], None]
) -> JsxElement {
    def handle_open(e: MouseEvent) {
        onOpen(idx);
    }

    return
        <li className="flex flex-col gap-2 rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-4 pr-4">
            <div className="flex items-start justify-between gap-2">
                <span className="text-body font-medium">{"No warm path to " + (gap["kind"] as str)}</span>
                {asked_status and <StatusChip status={asked_status} label={req_label(asked_status)} />}
            </div>
            <p className="text-body-sm text-muted-foreground">{gap["why_needed"] as str}</p>
            {not asked_status and
                <div>
                    <Button size="sm" onClick={handle_open}>Ask my network</Button>
                </div>}
        </li>;
}

def:pub GapAlerts(
    gaps: list[dict],
    pending: bool,
    error: str,
    asked: dict,
    default_about: str,
    busy: bool,
    ask_error: str,
    onAsk: Callable[[str, str], None],
    onRetry: Callable[[], None]
) -> JsxElement {
    has open_idx: int = -1,
        posted: bool = False,
        need: str = "",
        about_line: str = "";

    def open_sheet(i: int) -> None {
        open_idx = i;
        posted = False;
        need = gaps[i]["suggested_need"] as str;
        about_line = default_about;
    }

    def post() -> None {
        posted = True;
        onAsk(need.strip(), about_line.strip());
    }

    def set_open(v: bool) -> None {
        if not v {
            open_idx = -1;
            posted = False;
        }
    }

    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    # The sheet closes itself once the post lands (busy -> idle with no error).
    sheet_gap: dict = gaps[open_idx] if open_idx >= 0 and open_idx < len(gaps) else {};
    sheet_open: bool = open_idx >= 0 and len(gaps) > open_idx and not (posted and not busy and not ask_error);

    if pending and len(gaps) == 0 {
        return
            <section aria-label="Gaps" className="flex flex-col gap-2">
                <span role="status" className="text-caption text-muted-foreground">Looking for gaps in your network…</span>
                <GapSkeleton />
            </section>;
    }
    if error {
        return
            <section aria-label="Gaps" className="flex items-center justify-between gap-2 text-caption text-muted-foreground">
                <span>{error}</span>
                <Button size="xs" variant="ghost" onClick={handle_retry}>Try again</Button>
            </section>;
    }
    if len(gaps) == 0 {
        return <span hidden={True} />;
    }

    return
        <section aria-label="Gaps" className="flex flex-col gap-3">
            <h2 className="text-eyebrow text-muted-foreground">Gaps for this goal</h2>
            <ul className="flex flex-col gap-2">
                {for (i, g) in enumerate(gaps) {
                    <GapCard
                        key={g["kind"] as str}
                        idx={i}
                        gap={g}
                        asked_status={(asked[g["suggested_need"]] or "") as str}
                        onOpen={open_sheet}
                    />
                }}
            </ul>
            <AskSheet
                open={sheet_open}
                kind={(sheet_gap["kind"] or "") as str}
                need={need}
                about_line={about_line}
                busy={busy}
                error={ask_error}
                onNeed={lambda v: str { need = v; }}
                onAbout={lambda v: str { about_line = v; }}
                onPost={post}
                onOpenChange={set_open}
            />
        </section>;
}
