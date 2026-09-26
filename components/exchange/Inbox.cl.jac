"""Friend side of the Exchange — "Asks from friends" on home and the approval
card. OWNER: Person B.

`incoming` is ListIncomingRequests ([IntroRequest], others' asks this user has
not answered). Once answered, a request leaves that list, so the shell keeps
the in-progress reply for this session in `friend[request_id]`:
  { request, reply: ReplyView | {}, draft, revealed_handle, error, busy }
The reply's count and strength come from this user's own graph only
(ReplyToRequest). Every step is a click by this user; nothing sends.
"""

import from ..ui.button { Button }
import from .common { StatusChip, DraftBlock, reply_label }
import from .Requests { match_phrase }
import from ...lib.utils { cn }

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

def:pub AskRow(req: dict, status: str, onOpen: Callable[[str], None]) -> JsxElement {
    rid: str = req["_jac_id"] as str;

    def handle_open(e: MouseEvent) {
        onOpen(rid);
    }

    return
        <li>
            <button
                type="button"
                className={cn(
                    "flex w-full flex-col gap-1.5 pt-3 pb-3 pl-3 pr-3 text-left transition-colors hover:bg-muted",
                    "opacity-60" if status == "declined" or status == "revealed" else ""
                )}
                onClick={handle_open}
            >
                <div className="flex items-start justify-between gap-2">
                    <span className="min-w-0 text-sm">{"A friend's agent is looking for " + (req["need"] as str) + "."}</span>
                    <StatusChip status={status} label={reply_label(status)} />
                </div>
                {req["about_line"] and <span className="text-xs text-muted-foreground">{req["about_line"] as str}</span>}
                <span className="text-xs text-muted-foreground">{"from @" + (req["from_handle"] as str)}</span>
            </button>
        </li>;
}

def:pub AsksSection(incoming: list[dict], friend: dict, onOpen: Callable[[str], None]) -> JsxElement {
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
    if len(incoming) == 0 and len(extra) == 0 {
        return <span hidden={True} />;
    }
    return
        <section aria-label="Asks from friends" className="flex flex-col gap-2">
            <h2 className="text-sm font-medium">Asks from friends</h2>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-md border">
                {for r in incoming {
                    <AskRow
                        key={r["_jac_id"] as str}
                        req={r}
                        status={friend_status((friend[r["_jac_id"]] or {}) as dict)}
                        onOpen={onOpen}
                    />
                }}
                {for e in extra {
                    <AskRow
                        key={(e["request"] or {})["_jac_id"] as str}
                        req={e["request"] as dict}
                        status={friend_status(e)}
                        onOpen={onOpen}
                    />
                }}
            </ul>
        </section>;
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
            <header className="flex items-center gap-2">
                <Button size="sm" variant="ghost" onClick={handle_back}>← Home</Button>
            </header>
            {if not rid {
                <p className="text-sm text-muted-foreground">This ask isn't available anymore.</p>
            } else {
                <section aria-label="Ask from a friend" className="flex flex-col gap-3 rounded-md border bg-card pt-4 pb-4 pl-3 pr-3">
                    <div className="flex items-start justify-between gap-2">
                        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{"Ask from " + asker}</span>
                        <StatusChip status={status} label={reply_label(status)} />
                    </div>
                    <h2 className="text-base font-semibold tracking-tight">{"A friend's agent is looking for " + (req["need"] as str) + "."}</h2>
                    {req["about_line"] and <p className="text-sm text-muted-foreground">{"About them: " + (req["about_line"] as str)}</p>}
                    {if status == "new" or status == "checking" {
                        if busy {
                            <p role="status" className="animate-pulse rounded-md bg-muted pt-3 pb-3 pl-3 pr-3 text-sm text-muted-foreground">
                                Checking your graph on this phone…
                            </p>
                        } else {
                            <div>
                                <Button size="sm" onClick={handle_check}>Check my network</Button>
                            </div>
                        }
                    } elif reply_id and n == 0 {
                        <p className="rounded-md bg-muted pt-3 pb-3 pl-3 pr-3 text-sm">
                            {"No strong or medium match in your network. " + asker + " sees a count of 0 — no names."}
                        </p>
                    } elif reply_id {
                        <div className="flex flex-col gap-2 rounded-md bg-accent pt-3 pb-3 pl-3 pr-3 text-accent-foreground">
                            <p className="text-sm font-medium">{"You have " + match_phrase(reply) + " in your network."}</p>
                            <div className="flex flex-col gap-0.5">
                                <span className="text-[11px] font-medium uppercase tracking-wide opacity-70">Why it fits</span>
                                <p className="text-xs">Cirql checked your graph on this phone; nothing leaves it until you approve.</p>
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
                        <p role="alert" className="text-sm text-destructive/80">{ask["error"] as str}</p>
                    }}
                    {if status == "pending" and n > 0 {
                        <p className="text-xs text-muted-foreground">{"Approve to ask your contact. " + asker + " still sees only the count until they say yes."}</p>
                        <div className="flex gap-2">
                            <Button className="flex-1" size="sm" disabled={busy} onClick={handle_approve}>Approve</Button>
                            <Button size="sm" variant="outline" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "approved" {
                        <p className="text-xs text-muted-foreground">
                            Approved. Next your contact says yes or no. For this demo, the button below stands in for their reply.
                        </p>
                        <div className="flex gap-2">
                            <Button className="flex-1" size="sm" disabled={busy} onClick={handle_opt_in}>Contact opted in (stand-in)</Button>
                            <Button size="sm" variant="outline" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "opted_in" {
                        <p className="text-xs text-muted-foreground">
                            {"Your contact said yes. Reveal grants their card read-only to " + asker + " — that card only."}
                        </p>
                        <div className="flex gap-2">
                            <Button className="flex-1" size="sm" disabled={busy} onClick={handle_reveal}>Reveal card</Button>
                            <Button size="sm" variant="outline" disabled={busy} onClick={handle_decline}>Decline</Button>
                        </div>
                    } elif status == "revealed" {
                        <p className="rounded-md bg-accent pt-3 pb-3 pl-3 pr-3 text-sm text-accent-foreground">
                            {"Card granted read-only to " + asker + ". The three-way intro is drafted on their phone."}
                        </p>
                    } elif status == "declined" {
                        <p className="text-sm text-muted-foreground">{"Declined. " + asker + " is not told why."}</p>
                    }}
                    {if can_decline and busy {
                        <span role="status" className="text-xs text-muted-foreground">Working…</span>
                    }}
                </section>
            }}
        </div>;
}
