"""Answering side of the Exchange — "Asks on the exchange" (Inbox) and the approval
card. OWNER: Person B.

`incoming` is ListIncomingRequests ([IntroRequest], others' asks this user has
not answered). Once answered, a request leaves that list, so the shell keeps
the in-progress reply for this session in `friend[request_id]`:
  { request, reply: ReplyView | {}, draft, revealed_handle, error, busy }
The reply's count and strength come from this user's own graph only
(ReplyToRequest). Every step is a click by this user; nothing sends.

SOH-222: an ask only counts as "Needs your OK" (and only counts toward the
Inbox badge) once this account's agent has actually found something to
approve — `match_count >= 1` on the checked reply, or it hasn't been checked
yet at all (unknown, so it stays visible until checked). A checked reply with
`match_count == 0` has nothing left to approve — `ApprovalView` never shows an
Approve button for it either — so it moves into a collapsed "Other asks on the
exchange" section instead of sitting in the primary list forever.

SOH-226: `friend_status` / `is_zero_match` / the needs-vs-other split
(`split_asks`) live in `components/agent/common.cl.jac` now, the ONE place
both this screen and the Inbox badge compute from — the auto-check that used
to run inside this file called `reply_to_request` on its own, a second path
alongside the shell's `friend_check`, and the two drifted out of sync (the
badge counting a zero-match ask this file had already resolved and hidden
under "Other asks"). The shell drives the check now (`pick_unchecked` +
`friend_check`, same call `open_ask` uses for a manually-opened ask); this
file only renders `friend` as the shell already has it.

SOH-229: since the shell already auto-checks every unchecked ask, the count
is usually in hand by the time a row renders, so the row itself carries the
primary action ("Offer an intro" -> `onOpen`, the same navigation `open_ask`
always did, which now skips straight past the "check my network" step
because the reply already exists) instead of forcing a second screen just to
read the ask. Tapping the row's own title expands it in place (about line,
goal line, match status, the buttons, the handle footer) — one row expanded
at a time, component state, never a route change. "Not now" is a session-only
local hide (no walker call; a refresh brings the ask back), same spirit as
`ActionCard`'s Dismiss but without a server-side equivalent for a friend's
ask. Asks sharing a `need_group_key` (server field when the walker has it,
else the same normalize-lowercase-drop-stopwords-sort a client can do alone)
collapse into one "<N> people are looking for …" row with its own expand.
"""

import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..ui.icons { ChevronLeftIcon, ChevronDownIcon, ChevronRightIcon }
import from .common { StatusChip, DraftBlock, reply_label, ask_title, asker_label, need_sentence, goal_approved_line, handle_caption, need_group_key, same_ask_group }
import from .Requests { match_phrase }
import from ..agent.common { friend_status, is_zero_match, split_asks }
import from ...lib.utils { cn }
import from ...lib.toast { toast }
import from ...lib.text { join_with }

"""SOH-229 item 3: the reply-state sentence under an expanded ask. A
count-0 reply never reaches here — `split_asks` already routes it to
"Other asks" before this file sees it."""
def:pub ask_status_line(ent: dict) -> str {
    reply: dict = (ent["reply"] or {}) as dict;
    if reply["_jac_id"] {
        n: int = (reply["match_count"] or 0) as int;
        return "Cirql already replied: " + str(n) + " of your people may fit. No names were shared.";
    }
    if ent["busy"] {
        return "Checking your people…";
    }
    return "Not checked yet.";
}

"""One ask, collapsed to its title + status chip; tapping the title expands
it in place. `ent` is the shell's `friend[rid]` entry (or just `{"request":
req}` for one the auto-check hasn't reached yet)."""
def:pub AskRow(
    req: dict,
    ent: dict,
    expanded: bool,
    onToggle: Callable[[str], None],
    onOffer: Callable[[str], None],
    onDismiss: Callable[[str], None]
) -> JsxElement {
    rid: str = (req["_jac_id"] or "") as str;
    status: str = friend_status(ent);
    from_name: str = (req["from_name"] or "") as str;
    from_handle: str = (req["from_handle"] or "") as str;
    goal_text: str = (req["goal_text"] or "") as str;
    about_line: str = (req["about_line"] or "") as str;
    need: str = (req["need"] or "") as str;
    caption: str = handle_caption(from_name, from_handle);
    approved: str = goal_approved_line(from_name, from_handle, goal_text);
    status_line: str = ask_status_line(ent);

    def handle_toggle(e: MouseEvent) {
        onToggle(rid);
    }

    def handle_offer(e: MouseEvent) {
        onOffer(rid);
    }

    def handle_dismiss(e: MouseEvent) {
        onDismiss(rid);
    }

    return
        <li className="flex flex-col">
            <Button
                variant="ghost"
                size="row"
                aria-expanded={expanded}
                className={cn("opacity-60" if status == "declined" or status == "revealed" else "")}
                onClick={handle_toggle}
            >
                <div className="flex items-start justify-between gap-2">
                    <span className="min-w-0 text-body-sm">{ask_title(from_name, from_handle, need)}</span>
                    <StatusChip status={status} label={reply_label(status)} />
                </div>
            </Button>
            {if expanded {
                <div className="flex flex-col gap-2 pt-1 pb-3 pl-3 pr-3">
                    {about_line and
                        <p className="text-body-sm text-muted-foreground">
                            {"About " + asker_label(from_name, from_handle) + ": " + about_line}
                        </p>}
                    {approved and <p className="text-body-sm text-muted-foreground">{approved}</p>}
                    <p className="text-body-sm">{status_line}</p>
                    <div className="flex gap-2">
                        <Button size="sm" className="flex-1" onClick={handle_offer}>Offer an intro</Button>
                        <Button size="sm" variant="secondary" onClick={handle_dismiss}>Not now</Button>
                    </div>
                    {caption and <span className="text-caption text-muted-foreground">{caption}</span>}
                </div>
            }}
        </li>;
}

"""One requester line inside an expanded group: their name/handle, status,
and their own "Offer an intro". No per-requester detail, just the action."""
def:pub AskRequesterLine(ent: dict, friend: dict, onOffer: Callable[[str], None]) -> JsxElement {
    req: dict = (ent["request"] or {}) as dict;
    rid: str = (req["_jac_id"] or "") as str;
    fent: dict = (friend[rid] or {}) as dict;
    status: str = friend_status(fent);
    from_name: str = (req["from_name"] or "") as str;
    from_handle: str = (req["from_handle"] or "") as str;

    def handle_offer(e: MouseEvent) {
        onOffer(rid);
    }

    return
        <li className="flex items-center justify-between gap-2 pt-2 pb-2 pl-1 pr-2">
            <span className="min-w-0 truncate text-body-sm">{asker_label(from_name, from_handle)}</span>
            <div className="flex shrink-0 items-center gap-2">
                <StatusChip status={status} label={reply_label(status)} />
                <Button size="xs" onClick={handle_offer}>Offer an intro</Button>
            </div>
        </li>;
}

"""SOH-229 item 5 (grouping rule per SOH-229 course correction): entries
sharing a `need_group_key` — exact match OR at least 2 shared stems,
transitively, via union-find in `_group_asks` — collapse into one row
titled "<N> people are looking for <shortest need in the group>", expanding
to one line per requester."""
def:pub AskGroupRow(
    group: dict,
    friend: dict,
    expanded_key: str,
    onToggle: Callable[[str], None],
    onOffer: Callable[[str], None],
    onDismiss: Callable[[str], None]
) -> JsxElement {
    group_key: str = (group["key"] or "") as str;
    entries: list[dict] = (group["entries"] or []) as list[dict];
    title_need: str = (group["title_need"] or "") as str;
    if len(entries) <= 1 {
        only: dict = entries[0] if len(entries) == 1 else {};
        req: dict = (only["request"] or {}) as dict;
        rid: str = (req["_jac_id"] or "") as str;
        ent: dict = (friend[rid] or {}) as dict;
        return
            <AskRow
                req={req}
                ent={ent}
                expanded={expanded_key == rid}
                onToggle={onToggle}
                onOffer={onOffer}
                onDismiss={onDismiss}
            />;
    }
    group_id: str = "group:" + group_key;
    is_open: bool = expanded_key == group_id;
    need0: str = title_need;

    def handle_toggle(e: MouseEvent) {
        onToggle(group_id);
    }

    return
        <li className="flex flex-col">
            <Button variant="ghost" size="row" aria-expanded={is_open} onClick={handle_toggle}>
                <div className="flex items-center justify-between gap-2">
                    <span className="min-w-0 text-body-sm">{str(len(entries)) + " people are looking for " + need_sentence(need0) + "."}</span>
                    {<ChevronDownIcon className="size-4 shrink-0 text-muted-foreground" /> if is_open else <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />}
                </div>
            </Button>
            {if is_open {
                <ul className="flex flex-col divide-y divide-border border-t bg-secondary/40 pl-3 pr-1">
                    {for e in entries {
                        <AskRequesterLine
                            key={((e["request"] or {})["_jac_id"] or "") as str}
                            ent={e}
                            friend={friend}
                            onOffer={onOffer}
                        />
                    }}
                </ul>
            }}
        </li>;
}

"""One count-0 ask, collapsed: no Approve, just the honest line."""
def:pub OtherAskRow(req: dict) -> JsxElement {
    from_name: str = (req["from_name"] or "") as str;
    from_handle: str = (req["from_handle"] or "") as str;
    return
        <li className="flex flex-col gap-1 pt-2.5 pb-2.5 pl-3 pr-3">
            <div className="flex items-start justify-between gap-2">
                <span className="min-w-0 text-body-sm text-muted-foreground">{ask_title(from_name, from_handle, (req["need"] or "") as str)}</span>
            </div>
            {req["about_line"] and <span className="text-caption text-muted-foreground">{req["about_line"] as str}</span>}
            <span className="text-caption text-ink-muted">Cirql found no match; nothing to approve.</span>
        </li>;
}

"""SOH-229: same grouping as the primary list applies here too — `split_asks`
only decides which SECTION a zero-match ask lands in, not whether it groups
with a sibling ask for the same need. A group of one still renders as a
plain `OtherAskRow`."""
def:pub OtherAskGroupRow(group: dict) -> JsxElement {
    has open: bool = False;

    entries: list[dict] = (group["entries"] or []) as list[dict];
    title_need: str = (group["title_need"] or "") as str;

    def toggle(e: MouseEvent) {
        open = not open;
    }

    if len(entries) <= 1 {
        only: dict = entries[0] if len(entries) == 1 else {};
        return <OtherAskRow req={(only["request"] or {}) as dict} />;
    }

    return
        <li className="flex flex-col">
            <Button variant="ghost" size="row" aria-expanded={open} onClick={toggle}>
                <div className="flex items-center justify-between gap-2">
                    <span className="min-w-0 text-body-sm text-muted-foreground">{str(len(entries)) + " people are looking for " + need_sentence(title_need) + "."}</span>
                    {<ChevronDownIcon className="size-4 shrink-0 text-muted-foreground" /> if open else <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />}
                </div>
            </Button>
            {if open {
                <ul className="flex flex-col divide-y divide-border border-t bg-secondary/40">
                    {for e in entries {
                        <OtherAskRow key={((e["request"] or {})["_jac_id"] or "") as str} req={(e["request"] or {}) as dict} />
                    }}
                </ul>
            }}
        </li>;
}

"""Collapsed, default-closed section for asks this account's agent checked and
found zero strong/medium matches for (SOH-222). Still on the exchange, just
nothing to do here. SOH-229: grouped the same way the primary list is
(`_group_asks`), so two zero-match asks for the same need collapse too."""
def:pub OtherAsksSection(other: list[dict]) -> JsxElement {
    has open: bool = False;

    def toggle(e: MouseEvent) {
        open = not open;
    }

    if len(other) == 0 {
        return <span hidden={True} />;
    }
    groups: list[dict] = _group_asks(other);
    return
        <section aria-label="Other asks" className="flex flex-col gap-2">
            <Button
                type="button"
                variant="ghost"
                size="sm"
                className="w-full justify-between px-1"
                aria-expanded={open}
                onClick={toggle}
            >
                <span>{"Other asks (" + str(len(other)) + ")"}</span>
                {<ChevronDownIcon className="size-4" /> if open else <ChevronRightIcon className="size-4" />}
            </Button>
            {if open {
                <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card">
                    {for g in groups {
                        <OtherAskGroupRow key={g["key"] as str} group={g} />
                    }}
                </ul>
            }}
        </section>;
}

"""Union-find root lookup with path-halving (plain def, no closures — a
component-level nested def mutating an outer list is asking for trouble on
this compiler)."""
def _uf_find(parent: list[int], x: int) -> int {
    cur: int = x;
    while parent[cur] != cur {
        parent[cur] = parent[parent[cur]];
        cur = parent[cur];
    }
    return cur;
}

"""The shortest (trimmed) `need` text among a group's entries — SOH-229's
group-title rule."""
def _shortest_need(entries: list[dict]) -> str {
    best: str = "";
    have_best: bool = False;
    for e in entries {
        req: dict = (e["request"] or {}) as dict;
        need: str = ((req["need"] or "") as str).strip();
        if not need {
            continue;
        }
        if not have_best or len(need) < len(best) {
            best = need;
            have_best = True;
        }
    }
    return best;
}

"""Stable-order groups of `needs` entries, each
`{"key": str, "entries": [dict], "title_need": str}`. Two entries land in the
same group when `same_ask_group` says their `need_group_key`s match (exact,
or >= 2 shared stems) — transitively, via union-find, so A-B and B-C sharing
stems groups all three even if A and C alone don't. A group of one renders
as a plain row; the title uses the shortest `need` in the group."""
def _group_asks(needs: list[dict]) -> list[dict] {
    n: int = len(needs);
    keys: list[str] = [];
    for e in needs {
        req: dict = (e["request"] or {}) as dict;
        keys = keys + [need_group_key(req)];
    }
    parent: list[int] = [];
    for i in range(n) {
        parent = parent + [i];
    }
    for i in range(n) {
        for j in range(i + 1, n) {
            if same_ask_group(keys[i], keys[j]) {
                ri: int = _uf_find(parent, i);
                rj: int = _uf_find(parent, j);
                if ri != rj {
                    parent[ri] = rj;
                }
            }
        }
    }
    order: list[int] = [];
    by_root: dict = {};
    key_by_root: dict = {};
    for i in range(n) {
        r: int = _uf_find(parent, i);
        if r not in order {
            order = order + [r];
            by_root[r] = [];
            # A blank need_group_key never merges (same_ask_group rejects it),
            # so every such group is a singleton — key it by request id
            # instead of the shared "" so the outer list's React keys stay
            # unique.
            solo_req: dict = (needs[i]["request"] or {}) as dict;
            solo_rid: str = (solo_req["_jac_id"] or "") as str;
            key_by_root[r] = keys[i] if keys[i] else ("solo:" + solo_rid);
        }
        by_root[r] = (by_root[r] as list[dict]) + [needs[i]];
    }
    out: list[dict] = [];
    for r in order {
        entries: list[dict] = by_root[r] as list[dict];
        out = out + [{
            "key": key_by_root[r] as str,
            "entries": entries,
            "title_need": _shortest_need(entries)
        }];
    }
    return out;
}

"""Needs-your-OK + Other, split by `split_asks` (SOH-226: the same call the
Inbox badge uses) — this component only renders `friend` as the shell has
it. The shell (`frontend.impl.jac`) runs the actual check, sequentially, up
to 5 unchecked asks at a time, through the SAME `friend_check` a manually-
opened ask uses (`pick_unchecked` in `agent/common.cl.jac`); a checking entry
shows here as "checking" via `friend_status` the moment `friend[rid].busy` is
set, no local polling of its own. SOH-229: `needs` is further grouped by
`need_group_key` and any row this session dismissed ("Not now") is filtered
out locally before either happens."""
def:pub AsksSection(
    incoming: list[dict],
    friend: dict,
    onOpen: Callable[[str], None],
    title: str = "Asks",
    onChecked: Callable[[], None] | None = None
) -> JsxElement {
    has expanded_key: str = "",
        hidden_ids: list[str] = [];

    split: dict = split_asks(incoming, friend, []);
    all_needs: list[dict] = (split["needs"] or []) as list[dict];
    other: list[dict] = (split["other"] or []) as list[dict];
    needs: list[dict] = [e for e in all_needs if (((e["request"] or {})["_jac_id"] or "") as str) not in hidden_ids];
    checking_now: int = 0;
    for e in needs {
        rid: str = ((e["request"] or {})["_jac_id"] or "") as str;
        if friend_status((friend[rid] or {}) as dict) == "checking" {
            checking_now = checking_now + 1;
        }
    }
    groups: list[dict] = _group_asks(needs);

    def toggle_expand(k: str) -> None {
        expanded_key = "" if expanded_key == k else k;
    }

    def offer_intro(rid: str) -> None {
        onOpen(rid);
    }

    def undo_dismiss(rid: str) -> None {
        hidden_ids = [h for h in hidden_ids if h != rid];
    }

    """SOH-229 item 5: "Not now" is a session-only local hide (no walker
    call — the ask is still on the exchange). A toast with Undo makes that
    reversible instead of a silent, un-recoverable disappearance."""
    def dismiss_now(rid: str) -> None {
        hidden_ids = hidden_ids + [rid];
        if expanded_key == rid {
            expanded_key = "";
        }
        def do_undo() -> None {
            undo_dismiss(rid);
        }
        toast("Ask hidden", "info", do_undo);
    }

    if len(all_needs) == 0 and len(other) == 0 {
        return <span hidden={True} />;
    }
    return
        <div className="flex flex-col gap-3">
            {checking_now > 0 and
                <p role="status" className="text-caption text-muted-foreground">
                    {"Checking " + str(checking_now) + (" ask" if checking_now == 1 else " asks") + " against your people…"}
                </p>}
            {if len(groups) > 0 {
                <section aria-label={title} className="flex flex-col gap-3">
                    <h2 className="text-eyebrow text-muted-foreground">{title}</h2>
                    <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                        {for g in groups {
                            <AskGroupRow
                                key={g["key"] as str}
                                group={g}
                                friend={friend}
                                expanded_key={expanded_key}
                                onToggle={toggle_expand}
                                onOffer={offer_intro}
                                onDismiss={dismiss_now}
                            />
                        }}
                    </ul>
                </section>
            }}
            <OtherAsksSection other={other} />
        </div>;
}

def:pub ApprovalView(
    ask: dict,
    onBack: Callable[[], None],
    onCheck: Callable[[str], None],
    onApprove: Callable[[str], None],
    onOptIn: Callable[[str], None],
    onReveal: Callable[[str], None],
    onDecline: Callable[[str], None]
) -> JsxElement {
    req: dict = (ask["request"] or {}) as dict;
    reply: dict = (ask["reply"] or {}) as dict;
    status: str = friend_status(ask);
    busy: bool = True if ask["busy"] else False;
    rid: str = (req["_jac_id"] or "") as str;
    reply_id: str = (reply["_jac_id"] or "") as str;
    from_name: str = (req["from_name"] or "") as str;
    from_handle: str = (req["from_handle"] or "") as str;
    goal_text: str = (req["goal_text"] or "") as str;
    asker: str = asker_label(from_name, from_handle);
    approved: str = goal_approved_line(from_name, from_handle, goal_text);
    caption: str = handle_caption(from_name, from_handle);
    n: int = (reply["match_count"] or 0) as int;
    # SOH-229 item 3: the actual match words when the shell threaded them
    # through from the originating action's payload (`matched`) — no
    # identity, just the tokens that lined up; read defensively off either
    # side, empty when neither carries any.
    matched: list[str] = (req["matched"] or reply["matched"] or []) as list[str];
    matched_text: str = ("Matches: " + join_with(matched, ", ")) if len(matched) > 0 else "";

    def handle_back(e: MouseEvent) {
        onBack();
    }

    def handle_check(e: MouseEvent) {
        onCheck(rid);
    }

    def handle_approve(e: MouseEvent) {
        onApprove(rid);
    }

    def handle_opt_in(e: MouseEvent) {
        onOptIn(rid);
    }

    def handle_reveal(e: MouseEvent) {
        onReveal(rid);
    }

    def handle_decline(e: MouseEvent) {
        onDecline(rid);
    }

    can_decline: bool = reply_id != "" and status in ["pending", "approved", "opted_in"];

    return
        <div className="flex flex-col gap-4 pb-10">
            <header className="-ml-2 flex items-center gap-2">
                <Button size="sm" variant="ghost" onClick={handle_back}>
                    <ChevronLeftIcon />
                    Inbox
                </Button>
            </header>
            {if not rid {
                <p className="text-body-sm text-muted-foreground">This ask isn't available anymore.</p>
            } else {
                <section aria-label="Ask from a friend" className="flex flex-col gap-4 rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4 shadow-edge">
                    <div className="flex items-start justify-between gap-2">
                        <span className="text-eyebrow text-muted-foreground">{"Ask from " + asker}</span>
                        <StatusChip status={status} label={reply_label(status)} />
                    </div>
                    <h2 className="text-subhead font-medium">{ask_title(from_name, from_handle, (req["need"] or "") as str)}</h2>
                    {req["about_line"] and <p className="text-body-sm text-muted-foreground">{"About " + asker + ": " + (req["about_line"] as str)}</p>}
                    {approved and <p className="text-body-sm text-muted-foreground">{approved}</p>}
                    {if status == "new" or status == "checking" {
                        if busy {
                            <div role="status" className="flex flex-col gap-2 rounded-md bg-secondary pt-3 pb-3 pl-3 pr-3">
                                <span className="text-body-sm text-muted-foreground">Checking your people on this phone…</span>
                                <Skeleton className="h-3 w-2/3" />
                            </div>
                        } else {
                            <div>
                                <Button size="sm" onClick={handle_check}>Check my network</Button>
                            </div>
                        }
                    } elif reply_id and n == 0 {
                        <p className="rounded-md bg-secondary pt-3 pb-3 pl-3 pr-3 text-body-sm">
                            {"No strong or medium match in your network. " + asker + " sees a count of 0. No names."}
                        </p>
                    } elif reply_id {
                        <div className="flex flex-col gap-2 rounded-md border border-border-strong bg-secondary pt-3 pb-3 pl-3 pr-3">
                            <p className="text-body font-medium">{"You have " + match_phrase(reply) + " in your network."}</p>
                            <div className="flex flex-col gap-0.5">
                                <span className="text-eyebrow text-muted-foreground">Why it fits</span>
                                {matched_text and <p className="text-caption text-ink-muted">{matched_text}</p>}
                                <p className="text-caption text-ink-muted">Cirql checked your people on this device; nothing leaves it until you approve.</p>
                            </div>
                        </div>
                    }}
                    {if ask["draft"] {
                        <DraftBlock
                            title="Opt-in note to your contact · draft"
                            text={ask["draft"] as str}
                            note="Nothing sends. Copy it into your own message."
                        />
                    }}
                    {if ask["error"] {
                        <p role="alert" className="text-body-sm text-destructive">{ask["error"] as str}</p>
                    }}
                    {if status == "pending" and n > 0 {
                        <p className="text-caption text-muted-foreground">{"Offering an intro asks your contact. " + asker + " still sees only the count until they say yes."}</p>
                        <div className="flex gap-2">
                            <Button className="flex-1" disabled={busy} onClick={handle_approve}>Offer an intro</Button>
                            <Button variant="secondary" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "approved" {
                        <p className="text-caption text-muted-foreground">
                            Approved. Next your contact says yes or no. For this demo, the button below stands in for their reply.
                        </p>
                        <div className="flex gap-2">
                            <Button className="flex-1" disabled={busy} onClick={handle_opt_in}>Contact opted in (stand-in)</Button>
                            <Button variant="secondary" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "opted_in" {
                        <p className="text-caption text-muted-foreground">
                            {"Your contact said yes. Reveal grants their card read-only to " + asker + ". That card only."}
                        </p>
                        <div className="flex gap-2">
                            <Button className="flex-1" disabled={busy} onClick={handle_reveal}>Reveal card</Button>
                            <Button variant="secondary" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "revealed" {
                        <p className="rounded-md bg-success/10 pt-3 pb-3 pl-3 pr-3 text-body-sm text-success-text">
                            {"Card granted read-only to " + asker + ". The three-way intro is drafted on their phone."}
                        </p>
                        <div>
                            <Button className="flex-1" onClick={handle_back}>Back to Inbox</Button>
                        </div>
                    } elif status == "declined" {
                        <p className="text-body-sm text-muted-foreground">{"Declined. " + asker + " is not told why."}</p>
                    }}
                    {if can_decline and busy {
                        <span role="status" className="text-caption text-muted-foreground">Working…</span>
                    }}
                    {caption and <span className="text-caption text-muted-foreground">{caption}</span>}
                </section>
            }}
        </div>;
}
