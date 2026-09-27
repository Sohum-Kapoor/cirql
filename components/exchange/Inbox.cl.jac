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
"""

import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..ui.icons { ChevronLeftIcon, ChevronDownIcon, ChevronRightIcon }
import from .common { StatusChip, DraftBlock, reply_label }
import from .Requests { match_phrase }
import from ..api { reply_to_request }
import from ...lib.utils { cn }

"""The ask in one line. Only a friends-audience ask (SOH-218) is from a friend;
an "everyone" ask can come from anyone on Cirql, so it doesn't claim friendship."""
def:pub ask_line(req: dict) -> str {
    who: str = "A friend" if req["audience"] == "friends" else "Someone on Cirql";
    return who + " is looking for " + ((req["need"] or "") as str) + ".";
}

def:pub friend_status(ent: dict) -> str {
    reply: dict = (ent["reply"] or {}) as dict;
    if reply["status"] {
        return reply["status"] as str;
    }
    if ent["busy"] {
        return "checking";
    }
    return "new";
}

"""True once ReplyToRequest has actually run for this ask (this session, or
carried over as `reply`) and found no strong/medium match. `ApprovalView`
never offers Approve at `match_count == 0`, so there is nothing left for the
user to do here — the honest answer is "no match", not "needs your OK"."""
def:pub is_zero_match(ent: dict) -> bool {
    reply: dict = (ent["reply"] or {}) as dict;
    if not reply["_jac_id"] {
        return False;
    }
    n: int = (reply["match_count"] or 0) as int;
    return n == 0;
}

"""How many friends' asks are waiting on this user (part of the Inbox tab badge, SOH-213/224):
every unanswered incoming ask, plus this session's replies still mid-way
(needs your OK / approved / contact said yes). Revealed, declined, and a
checked-but-zero-match ask (SOH-222) don't count."""
def:pub asks_needing_you(incoming: list[dict], friend: dict) -> int {
    n: int = 0;
    ids: list[str] = [];
    for r in incoming {
        rid: str = r["_jac_id"] as str;
        ids = ids + [rid];
        ent: dict = (friend[rid] or {}) as dict;
        st: str = friend_status(ent);
        if st != "revealed" and st != "declined" and not is_zero_match(ent) {
            n = n + 1;
        }
    }
    for rid in Object.keys(friend) {  # jac:ignore[W2001]
        ent: dict = friend[rid] as dict;
        if rid not in ids and ent["request"] and friend_status(ent) in ["pending", "approved", "opted_in"] and not is_zero_match(ent) {
            n = n + 1;
        }
    }
    return n;
}

def:pub AskRow(req: dict, status: str, onOpen: Callable[[str], None]) -> JsxElement {
    rid: str = req["_jac_id"] as str;

    def handle_open(e: MouseEvent) {
        onOpen(rid);
    }

    return
        <li>
            <Button
                variant="ghost"
                size="row"
                className={cn("opacity-60" if status == "declined" or status == "revealed" else "")}
                onClick={handle_open}
            >
                <div className="flex items-start justify-between gap-2">
                    <span className="min-w-0 text-body-sm">{ask_line(req)}</span>
                    <StatusChip status={status} label={reply_label(status)} />
                </div>
                {req["about_line"] and <span className="text-caption text-muted-foreground">{req["about_line"] as str}</span>}
                <span className="text-caption text-muted-foreground">{"from @" + (req["from_handle"] as str)}</span>
            </Button>
        </li>;
}

"""One count-0 ask, collapsed: no Approve, just the honest line."""
def:pub OtherAskRow(req: dict) -> JsxElement {
    return
        <li className="flex flex-col gap-1 pt-2.5 pb-2.5 pl-3 pr-3">
            <div className="flex items-start justify-between gap-2">
                <span className="min-w-0 text-body-sm text-muted-foreground">{ask_line(req)}</span>
            </div>
            {req["about_line"] and <span className="text-caption text-muted-foreground">{req["about_line"] as str}</span>}
            <span className="text-caption text-muted-foreground">{"from @" + (req["from_handle"] as str)}</span>
            <span className="text-caption text-ink-muted">Cirql found no match; nothing to approve.</span>
        </li>;
}

"""Collapsed, default-closed section for asks this account's agent checked and
found zero strong/medium matches for (SOH-222). Still on the exchange, just
nothing to do here."""
def:pub OtherAsksSection(other: list[dict]) -> JsxElement {
    has open: bool = False;

    def toggle(e: MouseEvent) {
        open = not open;
    }

    if len(other) == 0 {
        return <span hidden={True} />;
    }
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
                    {for e in other {
                        <OtherAskRow key={(e["request"] or {})["_jac_id"] as str} req={e["request"] as dict} />
                    }}
                </ul>
            }}
        </section>;
}

"""Sequential SOH-222 auto-check: on Inbox load, run ReplyToRequest (the exact
call `open_ask`/`friend_check` run for a manually-opened ask, `reply_to_request`
from `api.cl.jac`) for up to 5 asks this account hasn't checked yet — so a
brand-new account doesn't have to open every stranger's ask by hand before
"Needs your OK" settles into its real bucket. Results are kept only in this
component's own `has` state (an overlay on top of `friend`, never written back
to it): `checked_ids` is the dedup guard, so a request already queued this
mount is never re-sent even if the effect re-renders."""
def:pub AsksSection(
    incoming: list[dict],
    friend: dict,
    onOpen: Callable[[str], None],
    title: str = "Asks"
) -> JsxElement {
    has auto: dict = {},
        checked_ids: list[str] = [],
        auto_total: int = 0,
        auto_done: int = 0,
        auto_running: bool = False;

    """`friend`'s own entry for `rid`, overlaid with this component's own
    auto-checked reply when `friend` doesn't already have a real one."""
    def merged_ent(rid: str) -> dict {
        base: dict = (friend[rid] or {}) as dict;
        base_reply: dict = (base["reply"] or {}) as dict;
        if base_reply["_jac_id"] {
            return base;
        }
        ar: dict = (auto[rid] or {}) as dict;
        if not ar["_jac_id"] {
            return base;
        }
        merged: dict = {**base};
        merged["reply"] = ar;
        return merged;
    }

    async can with entry {
        todo: list[str] = [];
        for r in incoming {
            rid: str = (r["_jac_id"] or "") as str;
            if rid and rid not in checked_ids and friend_status(merged_ent(rid)) == "new" {
                todo = todo + [rid];
            }
        }
        if len(todo) > 0 {
            batch: list[str] = todo[:5];
            checked_local: list[str] = checked_ids + batch;
            checked_ids = checked_local;
            auto_total = len(batch);
            auto_done = 0;
            auto_running = True;
            acc: dict = {**auto};
            done_local: int = 0;
            for rid in batch {
                reply: dict = await reply_to_request(rid);
                if reply["_jac_id"] {
                    acc[rid] = reply;
                }
                done_local = done_local + 1;
                auto_done = done_local;
                auto = acc;
            }
            auto_running = False;
        }
    }

    ids: list[str] = [];
    for r in incoming {
        ids = ids + [r["_jac_id"] as str];
    }
    extra: list[dict] = [];
    for rid in Object.keys(friend) {  # jac:ignore[W2001]
        entry: dict = friend[rid] as dict;
        if rid not in ids and entry["request"] {
            extra = extra + [entry];
        }
    }
    needs: list[dict] = [];
    other: list[dict] = [];
    for r in incoming {
        rid: str = (r["_jac_id"] or "") as str;
        ent: dict = merged_ent(rid);
        entry: dict = {"request": r};
        if is_zero_match(ent) {
            other = other + [entry];
        } else {
            needs = needs + [entry];
        }
    }
    for e in extra {
        rid: str = ((e["request"] or {})["_jac_id"] or "") as str;
        ent: dict = merged_ent(rid);
        if is_zero_match(ent) {
            other = other + [e];
        } else {
            needs = needs + [e];
        }
    }
    checking_now: int = auto_total - auto_done;
    if len(needs) == 0 and len(other) == 0 {
        return <span hidden={True} />;
    }
    return
        <div className="flex flex-col gap-3">
            {auto_running and checking_now > 0 and
                <p role="status" className="text-caption text-muted-foreground">
                    {"Checking " + str(checking_now) + (" ask" if checking_now == 1 else " asks") + " against your people…"}
                </p>}
            {if len(needs) > 0 {
                <section aria-label={title} className="flex flex-col gap-3">
                    <h2 className="text-eyebrow text-muted-foreground">{title}</h2>
                    <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                        {for e in needs {
                            <AskRow
                                key={(e["request"] or {})["_jac_id"] as str}
                                req={e["request"] as dict}
                                status={friend_status(merged_ent((e["request"] or {})["_jac_id"] as str))}
                                onOpen={onOpen}
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
    asker: str = "@" + ((req["from_handle"] or "") as str);
    n: int = (reply["match_count"] or 0) as int;

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
                    <h2 className="text-subhead font-medium">{ask_line(req)}</h2>
                    {req["about_line"] and <p className="text-body-sm text-muted-foreground">{"About them: " + (req["about_line"] as str)}</p>}
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
                            {"No strong or medium match in your network. " + asker + " sees a count of 0 — no names."}
                        </p>
                    } elif reply_id {
                        <div className="flex flex-col gap-2 rounded-md border border-border-strong bg-secondary pt-3 pb-3 pl-3 pr-3">
                            <p className="text-body font-medium">{"You have " + match_phrase(reply) + " in your network."}</p>
                            <div className="flex flex-col gap-0.5">
                                <span className="text-eyebrow text-muted-foreground">Why it fits</span>
                                <p className="text-caption text-ink-muted">Cirql checked your people on this phone; nothing leaves it until you approve.</p>
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
                        <p className="text-caption text-muted-foreground">{"Approve to ask your contact. " + asker + " still sees only the count until they say yes."}</p>
                        <div className="flex gap-2">
                            <Button className="flex-1" disabled={busy} onClick={handle_approve}>Approve</Button>
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
                            {"Your contact said yes. Reveal grants their card read-only to " + asker + " — that card only."}
                        </p>
                        <div className="flex gap-2">
                            <Button className="flex-1" disabled={busy} onClick={handle_reveal}>Reveal card</Button>
                            <Button variant="secondary" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "revealed" {
                        <p className="rounded-md bg-success/10 pt-3 pb-3 pl-3 pr-3 text-body-sm text-success-text">
                            {"Card granted read-only to " + asker + ". The three-way intro is drafted on their phone."}
                        </p>
                    } elif status == "declined" {
                        <p className="text-body-sm text-muted-foreground">{"Declined. " + asker + " is not told why."}</p>
                    }}
                    {if can_decline and busy {
                        <span role="status" className="text-caption text-muted-foreground">Working…</span>
                    }}
                </section>
            }}
        </div>;
}
