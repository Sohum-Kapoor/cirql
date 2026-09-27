"""One AgentAction as a card (SOH-224). OWNER: Person B.

kind label + icon · title · one-line why · the person (tap -> PersonSheet) ·
evidence chips (tap -> the quoted span; RankList's EvidenceChip + Review's
SourceQuote, imported, not copied) · the draft in an editable textarea with Copy
(never Send) · Approve (label says exactly what happens), Dismiss, and Snooze in
the overflow. Once resolved (optimistically, by the shell) the card shrinks to a
one-line receipt in place. `row` is one ListAgentActions report:
{ action, person, evidence }.
"""

import from ..ui.button { Button, buttonVariants }
import from ..ui.textarea { Textarea }
import from ..ui.icons { MoreIcon, ChevronRightIcon, CheckIcon }
import from ..ui.dropdown_menu { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem }
import from ..goals.RankList { EvidenceChip }
import from ..capture.Review { SourceQuote }
import from .common { KindIcon, kind_label, approve_label, resolved_label, ago_words, since_iso, promise_due_label, payload_of }
import from ..exchange.common { ask_title }
import from ...lib.text { join_with }
import from ...lib.utils { cn }

"""The person this action is about: a row-sized button that opens their sheet."""
def:pub ActionPerson(person: dict, onOpen: Callable[[str], None]) -> JsxElement {
    pid: str = (person["_jac_id"] or "") as str;
    name: str = (person["name"] or "") as str;
    sub: str = join_with([s for s in [(person["title"] or "") as str, (person["org"] or "") as str] if s], ", ");
    initials: str = join_with([w[0] for w in name.split(" ") if w][:2], "");

    def handle(e: MouseEvent) {
        if pid {
            onOpen(pid);
        }
    }

    return
        <button
            type="button"
            onClick={handle}
            aria-label={"Open " + name}
            className="-ml-1 flex min-h-11 w-[calc(100%+0.5rem)] items-center gap-2.5 rounded-md pt-1 pb-1 pl-1 pr-1 text-left outline-none transition-colors hover:bg-secondary focus-visible:ring-2 focus-visible:ring-ring/50"
        >
            <span aria-hidden="true" className="flex size-8 shrink-0 items-center justify-center rounded-full bg-secondary text-caption font-medium text-ink-muted">
                {initials}
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
                <span className="truncate text-body-sm font-medium">{name}</span>
                {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
            </span>
            <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />
        </button>;
}

"""Resolved: a one-line receipt where the card was."""
def:pub ResolvedRow(act: dict) -> JsxElement {
    status: str = (act["status"] or "") as str;
    positive: bool = status == "approved" or status == "done";
    return
        <li
            data-action-id={act["_jac_id"] as str}
            data-status={status}
            role="status"
            className="flex items-center gap-2 rounded-lg border border-dashed border-border-strong pt-2.5 pb-2.5 pl-3 pr-3"
        >
            {if positive {
                <CheckIcon className="size-4 shrink-0 text-success-text" />
            } else {
                <KindIcon kind={act["kind"] as str} className="size-4 shrink-0 text-muted-foreground" />
            }}
            <span className="min-w-0 truncate text-body-sm">
                <span className="font-medium">{resolved_label(act["kind"] as str, status)}</span>
                <span className="text-muted-foreground">{" · " + (act["title"] as str)}</span>
            </span>
        </li>;
}

def:pub ActionCard(
    row: dict,
    pending: bool,
    error: str,
    onApprove: Callable[[str, str], None],
    onDismiss: Callable[[str], None],
    onSnooze: Callable[[str], None],
    onOpenPerson: Callable[[str], None]
) -> JsxElement {
    act: dict = (row["action"] or {}) as dict;
    aid: str = (act["_jac_id"] or "") as str;
    kind: str = (act["kind"] or "") as str;
    person: dict = (row["person"] or {}) as dict;
    evidence: list[dict] = (row["evidence"] or []) as list[dict];
    first_name: str = ((person["name"] or "") as str).split(" ")[0];
    ago: str = ago_words(since_iso((act["created_at"] or "") as str));
    created_title: str = (act["created_at"] or "") as str;
    eyebrow_text: str = promise_due_label(act) if kind == "promise_due" else kind_label(kind);

    # SOH-229: for an answer_ask card, title from from_name/handle + need
    # (same words as the Exchange Inbox's ask_title) — read defensively, the
    # server may not carry from_name yet; falls back to the server's own
    # title when the payload has no need at all.
    display_title: str = (act["title"] or "") as str;
    if kind == "answer_ask" {
        payload: dict = payload_of(act);
        ask_need: str = (payload["need"] or "") as str;
        if ask_need {
            display_title = ask_title((payload["from_name"] or "") as str, (payload["from_handle"] or "") as str, ask_need);
        }
    }

    has draft_text: str = (act["draft"] or "") as str,
        open_key: str = "",
        copied: bool = False;

    def toggle(k: str) -> None {
        open_key = "" if open_key == k else k;
    }

    open_span: str = "";
    for (i, ev) in enumerate(evidence) {
        if open_key == aid + ":" + str(i) {
            open_span = (ev["span"] or "") as str;
        }
    }

    def handle_draft(e: ChangeEvent) {
        draft_text = e.target.value;
        copied = False;
    }

    async def do_copy -> None {
        ok: bool = True;
        try {
            await navigator.clipboard.writeText(draft_text);  # jac:ignore[E1030]
        } except Exception as e {
            ok = False;
        }
        copied = ok;
    }

    def handle_approve(e: MouseEvent) {
        onApprove(aid, draft_text);
    }

    def handle_dismiss(e: MouseEvent) {
        onDismiss(aid);
    }

    def handle_snooze(e: any) {
        onSnooze(aid);
    }

    if act["status"] and act["status"] != "open" {
        return <ResolvedRow act={act} />;
    }

    draft_to: str = ("Draft to " + first_name) if first_name else "Draft";
    return
        <li
            data-action-id={aid}
            data-kind={kind}
            aria-label={kind_label(kind) + ": " + display_title}
            aria-busy={pending}
            className={cn("flex flex-col gap-3 rounded-lg border bg-card pt-3 pb-4 pl-4 pr-2 shadow-edge transition-opacity", "opacity-70" if pending else "")}
        >
            <div className="flex min-h-8 items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-1.5 text-eyebrow text-muted-foreground" title={created_title}>
                    <KindIcon kind={kind} />
                    <span className="truncate">{eyebrow_text}</span>
                    {(ago and kind != "promise_due") and <span className="shrink-0 font-normal normal-case tracking-normal text-ink-tertiary">{"· " + ago}</span>}
                </span>
                <DropdownMenu modal={False}>
                    <DropdownMenuTrigger
                        aria-label={"More for: " + display_title}
                        disabled={pending}
                        className={buttonVariants().call(None, {"variant": "ghost", "size": "icon-sm", "className": "shrink-0 text-muted-foreground"})}
                    >
                        <MoreIcon className="size-4" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end" sideOffset={6} className="w-52">
                        <DropdownMenuGroup>
                            <DropdownMenuItem onSelect={handle_snooze}>Snooze until the next run</DropdownMenuItem>
                        </DropdownMenuGroup>
                    </DropdownMenuContent>
                </DropdownMenu>
            </div>
            <div className="flex flex-col gap-1 pr-2">
                <h3 className="text-body font-medium">{display_title}</h3>
                {act["why"] and <p className="text-body-sm text-ink-muted">{act["why"] as str}</p>}
            </div>
            {if person["_jac_id"] {
                <div className="pr-2">
                    <ActionPerson person={person} onOpen={onOpenPerson} />
                </div>
            }}
            {len(evidence) > 0 and
                <div className="flex flex-col gap-2 pr-2">
                    <div className="flex flex-wrap gap-1.5" aria-label="Evidence">
                        {for (i, ev) in enumerate(evidence) {
                            <EvidenceChip
                                key={aid + ":" + str(i)}
                                chip_key={aid + ":" + str(i)}
                                ev={ev}
                                is_open={open_key == aid + ":" + str(i)}
                                onToggle={toggle}
                            />
                        }}
                    </div>
                    {open_key and <SourceQuote span={open_span} note_text="" />}
                </div>}
            {if act["draft"] {
                <div className="flex flex-col gap-2 rounded-md border bg-secondary pt-3 pb-3 pl-3 pr-3 mr-2">
                    <div className="flex items-center justify-between gap-2">
                        <label htmlFor={"draft-" + aid} className="text-eyebrow text-muted-foreground">{draft_to + " · edit freely"}</label>
                        <Button size="xs" variant="secondary" onClick={do_copy}>{"Copied" if copied else "Copy"}</Button>
                    </div>
                    <Textarea
                        id={"draft-" + aid}
                        rows={4}
                        value={draft_text}
                        disabled={pending}
                        onChange={handle_draft}
                        className="bg-card text-body-sm"
                    />
                    <span className="text-caption text-muted-foreground">Nothing sends. Copy it into your own message.</span>
                </div>
            }}
            {error and <p role="alert" className="pr-2 text-body-sm text-destructive">{error}</p>}
            <div className="flex gap-2 pr-2">
                <Button className="flex-1" disabled={pending} onClick={handle_approve}>
                    {"Saving…" if pending else approve_label(kind, bool(act["draft"]))}
                </Button>
                <Button variant="secondary" disabled={pending} onClick={handle_dismiss}>Dismiss</Button>
            </div>
        </li>;
}
