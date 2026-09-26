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
import from .common { StatusChip, req_label }
import from ...lib.utils { cn }

def:pub GapSkeleton() -> JsxElement {
    return
        <div aria-hidden="true" className="flex animate-pulse flex-col gap-2 rounded-md border border-dashed pt-3 pb-3 pl-3 pr-3">
            <span className="h-3.5 w-48 rounded bg-muted" />
            <span className="h-3 w-full rounded bg-muted" />
        </div>;
}

def:pub AskSheet(
    need: str,
    about_line: str,
    busy: bool,
    error: str,
    onNeed: Callable[[str], None],
    onAbout: Callable[[str], None],
    onPost: Callable[[], None],
    onCancel: Callable[[], None]
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
        onCancel();
    }

    return
        <div role="group" aria-label="Ask my network" className="flex flex-col gap-3 border-t pt-3">
            <label className="flex flex-col gap-1.5">
                <span className="text-xs font-medium">What you're asking for</span>
                <Textarea id="ask-need" rows={2} value={need} disabled={busy} onChange={handle_need} />
            </label>
            <label className="flex flex-col gap-1.5">
                <span className="text-xs font-medium">One line about you</span>
                <Input
                    id="ask-about"
                    value={about_line}
                    placeholder="e.g. Student founder building thermal batteries"
                    disabled={busy}
                    onChange={handle_about}
                />
            </label>
            <p className="text-xs text-muted-foreground">
                Friends' agents see only this need, this line and your handle. Each one checks its own graph; no names cross until everyone involved says yes.
            </p>
            {error and <p role="alert" className="text-sm text-destructive/80">{error}</p>}
            <div className="flex gap-2">
                <Button className="flex-1" size="sm" disabled={busy or not need.strip()} onClick={handle_post}>
                    {"Posting…" if busy else "Post request"}
                </Button>
                <Button size="sm" variant="ghost" disabled={busy} onClick={handle_cancel}>Cancel</Button>
            </div>
        </div>;
}

def:pub GapCard(
    idx: int,
    gap: dict,
    asked_status: str,
    is_open: bool,
    onOpen: Callable[[int], None],
    children: any = None
) -> JsxElement {
    def handle_open(e: MouseEvent) {
        onOpen(idx);
    }

    return
        <li className={cn("flex flex-col gap-2 rounded-md border pt-3 pb-3 pl-3 pr-3", "border-primary" if is_open else "border-dashed")}>
            <div className="flex items-start justify-between gap-2">
                <span className="text-sm font-medium">{"No warm path to " + (gap["kind"] as str)}</span>
                {asked_status and <StatusChip status={asked_status} label={req_label(asked_status)} />}
            </div>
            <p className="text-sm text-muted-foreground">{gap["why_needed"] as str}</p>
            {is_open and children}
            {not is_open and not asked_status and
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
        need: str = "",
        about_line: str = "";

    def open_sheet(i: int) -> None {
        open_idx = i;
        need = gaps[i]["suggested_need"] as str;
        about_line = default_about;
    }

    def post() -> None {
        onAsk(need.strip(), about_line.strip());
    }

    def cancel() -> None {
        open_idx = -1;
    }

    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    if pending and len(gaps) == 0 {
        return
            <section aria-label="Gaps" className="flex flex-col gap-2">
                <span role="status" className="text-xs text-muted-foreground">Looking for gaps in your network…</span>
                <GapSkeleton />
            </section>;
    }
    if error {
        return
            <section aria-label="Gaps" className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
                <span>{error}</span>
                <Button size="xs" variant="ghost" onClick={handle_retry}>Try again</Button>
            </section>;
    }
    if len(gaps) == 0 {
        return <span hidden={True} />;
    }

    return
        <section aria-label="Gaps" className="flex flex-col gap-2">
            <h2 className="text-sm font-medium">Gaps for this goal</h2>
            <ul className="flex flex-col gap-2">
                {for (i, g) in enumerate(gaps) {
                    <GapCard
                        key={g["kind"] as str}
                        idx={i}
                        gap={g}
                        asked_status={(asked[g["suggested_need"]] or "") as str}
                        is_open={open_idx == i and not asked[g["suggested_need"]]}
                        onOpen={open_sheet}
                    >
                        <AskSheet
                            need={need}
                            about_line={about_line}
                            busy={busy}
                            error={ask_error}
                            onNeed={lambda v: str { need = v; }}
                            onAbout={lambda v: str { about_line = v; }}
                            onPost={post}
                            onCancel={cancel}
                        />
                    </GapCard>
                }}
            </ul>
        </section>;
}
