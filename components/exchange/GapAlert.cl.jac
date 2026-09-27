"""Gap alerts under the ranked list + the "Ask my network" sheet. OWNER: Person B.

One card per GapFinder item: "No warm path to {kind}", why_needed, and *Ask my
network*. A gap names a KIND of person, never a person. The sheet prefills the
need with `suggested_need` and the one-line about with the user's card headline;
both are editable. *Who sees it* (SOH-218): Everyone (default) or Friends
(handles of Cards you hold; disabled with a hint when ListFriends is empty).
Posting goes through the shell (PostRequest with that audience). A gap whose
suggested need was already asked shows the request's status instead of the button.
"""

import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.textarea { Textarea }
import from ..ui.skeleton { Skeleton }
import from ..ui.field { Field, FieldLabel, FieldGroup }
import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody, SheetFooter }
import from ..ui.tabs { Tabs, TabsList, TabsTrigger }
import from .common { StatusChip, req_label }

"""A gap's `kind` never carries its own article ("climate-tech VC", "founder
who has raised for hardware"). Prefix "a"/"an" for the single-card sentence."""
def _a_or_an(kind: str) -> str {
    if not kind {
        return "";
    }
    first: str = kind[0:1].lower();
    if first in "aeiou" {
        return "an " + kind;
    }
    return "a " + kind;
}

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
    onOpenChange: Callable[[bool], None],
    about_locked: bool = False,
    audience: str = "everyone",
    onAudience: Callable[[str], None] | None = None,
    friends_count: int = 0,
    audience_locked: bool = False
) -> JsxElement {
    # about_locked / audience_locked (SOH-224): an agent's ask_network card posts
    # through ResolveAgentAction, which takes only the need (no about line, no
    # audience yet), so both show read-only and the ask goes to everyone.
    # audience (SOH-218): "everyone" | "friends"; Friends needs >= 1 friend.
    friends_ok: bool = friends_count > 0 and not audience_locked;
    aud: str = "friends" if audience == "friends" and friends_ok else "everyone";
    aud_hint: str = "";
    if audience_locked {
        aud_hint = "This ask goes to everyone on Cirql for now.";
    } elif friends_count == 0 {
        aud_hint = "Exchange cards with someone to add friends.";
    } elif aud == "friends" {
        aud_hint = "Only your " + str(friends_count) + (" friend" if friends_count == 1 else " friends") + " can see it: people whose card you hold.";
    } else {
        aud_hint = "Anyone on Cirql can see it.";
    }

    def handle_audience(v: str) -> None {
        if onAudience and (v == "everyone" or friends_ok) {
            onAudience(v);
        }
    }

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
                                readOnly={about_locked}
                                aria-readonly={about_locked}
                                onChange={handle_about}
                            />
                        </Field>
                        <Field>
                            <span id="ask-audience-label" className="text-body-sm leading-snug font-medium text-foreground">Who sees it</span>
                            <Tabs value={aud} onValueChange={handle_audience} className="gap-1.5">
                                <TabsList aria-labelledby="ask-audience-label" className="w-full">
                                    <TabsTrigger value="everyone" disabled={busy}>Everyone</TabsTrigger>
                                    <TabsTrigger value="friends" disabled={busy or not friends_ok}>Friends</TabsTrigger>
                                </TabsList>
                            </Tabs>
                            <span data-audience-hint="" className="text-caption text-muted-foreground">{aud_hint}</span>
                        </Field>
                    </FieldGroup>
                    <p className="text-caption text-muted-foreground">
                        They see only this need, this line and your handle. Each check runs against their own people; no names cross until everyone involved says yes.
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

"""Home's single gap card (SOH-226): one card for the highest-priority gap
(`gaps[0]`) instead of the full dense list — "Looking for someone specific?",
the gap's role in plain words, and one *Ask your network* button that opens
the same `AskSheet`. No gap: one muted line, no disappearing section."""
def:pub GapSingle(
    gaps: list[dict],
    pending: bool,
    error: str,
    asked: dict,
    default_about: str,
    busy: bool,
    ask_error: str,
    onAsk: Callable[[str, str, str], None],
    onRetry: Callable[[], None],
    friends_count: int = 0
) -> JsxElement {
    has open: bool = False,
        posted: bool = False,
        need: str = "",
        about_line: str = "",
        audience: str = "everyone";

    def open_sheet(e: MouseEvent) {
        if len(gaps) == 0 {
            return;
        }
        open = True;
        posted = False;
        need = gaps[0]["suggested_need"] as str;
        about_line = default_about;
        audience = "everyone";
    }

    def post() -> None {
        posted = True;
        onAsk(need.strip(), about_line.strip(), "friends" if audience == "friends" and friends_count > 0 else "everyone");
    }

    def set_open(v: bool) -> None {
        if not v {
            open = False;
            posted = False;
        }
    }

    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    gap: dict = {};
    if len(gaps) > 0 {
        gap = gaps[0];
    }
    asked_status: str = "";
    if len(gaps) > 0 {
        asked_status = (asked[gap["suggested_need"]] or "") as str;
    }
    sheet_open: bool = open and not (posted and not busy and not ask_error);

    if pending and len(gaps) == 0 {
        return
            <section aria-label="Gap" className="flex flex-col gap-2 rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-4 pr-4">
                <span role="status" className="text-caption text-muted-foreground">Looking for gaps in your network…</span>
                <Skeleton className="h-3.5 w-full" />
            </section>;
    }
    if error {
        return
            <section aria-label="Gap" className="flex items-center justify-between gap-2 rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-4 pr-4 text-caption text-muted-foreground">
                <span>{error}</span>
                <Button size="xs" variant="ghost" onClick={handle_retry}>Try again</Button>
            </section>;
    }
    if len(gaps) == 0 {
        return <p className="text-caption text-muted-foreground">Your people cover this goal.</p>;
    }

    return
        <section aria-label="Gap" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
            <h2 className="text-body font-medium">Looking for someone specific?</h2>
            <p className="text-body-sm text-muted-foreground">{"No warm path yet to " + _a_or_an(gap["kind"] as str) + "."}</p>
            {if asked_status {
                <div><StatusChip status={asked_status} label={req_label(asked_status)} /></div>
            } else {
                <div><Button onClick={open_sheet}>Ask your network</Button></div>
            }}
            <AskSheet
                open={sheet_open}
                kind={(gap["kind"] or "") as str}
                need={need}
                about_line={about_line}
                busy={busy}
                error={ask_error}
                onNeed={lambda v: str { need = v; }}
                onAbout={lambda v: str { about_line = v; }}
                onPost={post}
                onOpenChange={set_open}
                audience={audience}
                onAudience={lambda v: str { audience = v; }}
                friends_count={friends_count}
            />
        </section>;
}

def:pub GapAlerts(
    gaps: list[dict],
    pending: bool,
    error: str,
    asked: dict,
    default_about: str,
    busy: bool,
    ask_error: str,
    onAsk: Callable[[str, str, str], None],
    onRetry: Callable[[], None],
    friends_count: int = 0
) -> JsxElement {
    has open_idx: int = -1,
        posted: bool = False,
        need: str = "",
        about_line: str = "",
        audience: str = "everyone";

    def open_sheet(i: int) -> None {
        open_idx = i;
        posted = False;
        need = gaps[i]["suggested_need"] as str;
        about_line = default_about;
        audience = "everyone";
    }

    def post() -> None {
        posted = True;
        onAsk(need.strip(), about_line.strip(), "friends" if audience == "friends" and friends_count > 0 else "everyone");
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
                audience={audience}
                onAudience={lambda v: str { audience = v; }}
                friends_count={friends_count}
            />
        </section>;
}
