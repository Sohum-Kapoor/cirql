"""Requester side of the Exchange — "Your asks" on home, the request detail,
and the reveal card. OWNER: Person B.

Data is ListMyRequests: [{ request: IntroRequest, replies: [ReplyView] }].
A ReplyView carries a count, a strength and the FRIEND's handle — never who
the match is. Nothing about the matched person renders until ClaimReveal
returned their Card (`claims[reply_id]`), which only happens after the friend
approved, the contact opted in and the friend revealed.
"""

import from ..ui.button { Button }
import from .common { StatusChip, StepTrack, DraftBlock, req_label, req_active }
import from ...lib.text { short_date }
import from ...lib.utils { cn }

glob _RANK: dict[str, int] = {"declined": 0, "pending": 1, "approved": 2, "opted_in": 3, "revealed": 4};

def _reply_rank(r: dict) -> int {
    return ((_RANK[r["status"]] or 0) as int) * 100 + ((r["match_count"] or 0) as int);
}

"""The most advanced reply (then most matches); {} when none."""
def:pub best_reply(replies: list[dict]) -> dict {
    best: dict = {};
    for r in replies {
        if not best["_jac_id"] or _reply_rank(r) > _reply_rank(best) {
            best = r;
        }
    }
    return best;
}

def:pub match_phrase(r: dict) -> str {
    n: int = (r["match_count"] or 0) as int;
    if n == 0 {
        return "no strong match";
    }
    return str(n) + " " + (r["strength"] as str) + (" match" if n == 1 else " matches");
}

"""One line under the need: where the ask stands, with no identity."""
def:pub req_summary(status: str, replies: list[dict], claimed: bool) -> str {
    best: dict = best_reply(replies);
    if status == "declined" {
        return "You withdrew this ask.";
    }
    if status == "expired" {
        return "Expired with no card shared.";
    }
    if status == "revealed" {
        return "The card arrived." if claimed else "Card shared — opening it…";
    }
    if not best["_jac_id"] {
        return "Waiting for friends' agents to check their own graphs…";
    }
    via: str = "@" + (best["from_handle"] as str);
    if (best["match_count"] or 0) == 0 {
        return via + " checked: no strong match yet.";
    }
    head: str = via + " has " + match_phrase(best);
    if status == "replied" {
        return head + " — waiting for them to approve.";
    }
    if status == "approved" {
        return head + " — waiting for the contact to opt in.";
    }
    if status == "opted_in" {
        return head + " — the contact said yes; waiting for the card.";
    }
    return head + ".";
}

def:pub RequestRow(item: dict, claimed: bool, onOpen: Callable[[str], None]) -> JsxElement {
    req: dict = (item["request"] or {}) as dict;
    replies: list[dict] = (item["replies"] or []) as list[dict];
    status: str = (req["status"] or "open") as str;
    rid: str = (req["_jac_id"] or "") as str;

    def handle_open(e: MouseEvent) {
        onOpen(rid);
    }

    return
        <li>
            <button
                type="button"
                className={cn(
                    "flex w-full flex-col gap-1.5 pt-3 pb-3 pl-3 pr-3 text-left transition-colors hover:bg-muted",
                    "opacity-60" if status == "declined" or status == "expired" else ""
                )}
                onClick={handle_open}
            >
                <div className="flex items-start justify-between gap-2">
                    <span className="line-clamp-2 min-w-0 text-sm font-medium">{req["need"] as str}</span>
                    <StatusChip status={status} label={req_label(status)} />
                </div>
                <span className="text-xs text-muted-foreground">{req_summary(status, replies, claimed)}</span>
            </button>
        </li>;
}

def:pub RequestsSection(mine: list[dict], claims: dict, onOpen: Callable[[str], None]) -> JsxElement {
    if len(mine) == 0 {
        return <span hidden={True} />;
    }
    return
        <section aria-label="Your asks" className="flex flex-col gap-2">
            <h2 className="text-sm font-medium">Your asks</h2>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-md border">
                {for item in mine {
                    <RequestRow
                        key={(item["request"] or {})["_jac_id"] as str}
                        item={item}
                        claimed={_any_claimed(item, claims)}
                        onOpen={onOpen}
                    />
                }}
            </ul>
        </section>;
}

def _any_claimed(item: dict, claims: dict) -> bool {
    for r in (item["replies"] or []) as list[dict] {
        c: dict = (claims[r["_jac_id"]] or {}) as dict;
        if c["card"] {
            return True;
        }
    }
    return False;
}

def _list_block(title: str, items: list[str]) -> JsxElement {
    return
        <div className="flex flex-col gap-1">
            <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{title}</span>
            <ul className="flex flex-col gap-0.5">
                {for (i, s) in enumerate(items) {
                    <li key={str(i)} className="text-sm">{"· " + s}</li>
                }}
            </ul>
        </div>;
}

"""The matched person's own Card + the drafted three-way intro. Rendered only
from a successful ClaimReveal."""
def:pub RevealCard(claim: dict, friend_handle: str) -> JsxElement {
    card: dict = (claim["card"] or {}) as dict;
    person: dict = (claim["person"] or {}) as dict;
    looking: list[str] = (card["looking_for"] or []) as list[str];
    offer: list[str] = (card["can_offer"] or []) as list[str];
    name: str = (card["name"] or person["name"] or "") as str;

    return
        <article aria-label="Revealed card" className="flex flex-col gap-3 rounded-md border border-primary bg-card pt-4 pb-4 pl-3 pr-3">
            <div className="flex flex-col gap-0.5">
                <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                    {"Card granted read-only by @" + friend_handle}
                </span>
                <h3 className="text-base font-semibold tracking-tight">{name}</h3>
                {card["headline"] and <span className="text-sm text-muted-foreground">{card["headline"] as str}</span>}
            </div>
            {card["about"] and <p className="text-sm">{card["about"] as str}</p>}
            {len(looking) > 0 and _list_block("Looking for", looking)}
            {len(offer) > 0 and _list_block("Can offer", offer)}
            {card["contact_pref"] and
                <span className="text-xs text-muted-foreground">{"How to reach them: " + (card["contact_pref"] as str)}</span>}
            <DraftBlock
                title="Three-way intro · draft"
                text={(claim["intro_draft"] or "") as str}
                note="Nothing sends. Copy it into your own email."
            />
            <p className="rounded-md bg-accent pt-2 pb-2 pl-3 pr-3 text-xs text-accent-foreground">
                {"Added to your people — how you met: intro via @" + friend_handle}
            </p>
        </article>;
}

def:pub ReplyLine(r: dict) -> JsxElement {
    status: str = (r["status"] or "pending") as str;
    return
        <li className="flex items-center justify-between gap-2 pt-2 pb-2 pl-3 pr-3 text-sm">
            <span className="min-w-0 truncate">{"@" + (r["from_handle"] as str) + " · " + match_phrase(r)}</span>
            <span className="shrink-0 text-xs text-muted-foreground">{status.replace("_", " ")}</span>
        </li>;
}

def:pub RequestDetail(
    item: dict,
    claims: dict,
    claiming: dict,
    busy: bool,
    error: str,
    onBack: Callable[[], None],
    onCancel: Callable[[str], None],
    onClaim: Callable[[str], None]
) -> JsxElement {
    req: dict = (item["request"] or {}) as dict;
    replies: list[dict] = (item["replies"] or []) as list[dict];
    status: str = (req["status"] or "open") as str;
    rid: str = (req["_jac_id"] or "") as str;
    revealed: list[dict] = [r for r in replies if r["status"] == "revealed"];
    expires: str = short_date((req["expires_at"] or "") as str);
    has confirming: bool = False;

    def handle_back(e: MouseEvent) {
        onBack();
    }

    def ask_cancel(e: MouseEvent) {
        confirming = True;
    }

    def keep(e: MouseEvent) {
        confirming = False;
    }

    def do_cancel(e: MouseEvent) {
        confirming = False;
        onCancel(rid);
    }

    return
        <div className="flex flex-col gap-4 pb-10">
            <header className="flex items-center gap-2">
                <Button size="sm" variant="ghost" onClick={handle_back}>← Home</Button>
            </header>
            {if not rid {
                <p className="text-sm text-muted-foreground">This ask isn't on your list anymore.</p>
            } else {
                <section aria-label="Your ask" className="flex flex-col gap-3 rounded-md border bg-card pt-4 pb-4 pl-3 pr-3">
                    <div className="flex items-start justify-between gap-2">
                        <span className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Your ask</span>
                        <StatusChip status={status} label={req_label(status)} />
                    </div>
                    <h2 className="text-base font-semibold tracking-tight">{req["need"] as str}</h2>
                    {req["about_line"] and <p className="text-sm text-muted-foreground">{"About you: " + (req["about_line"] as str)}</p>}
                    {status != "declined" and status != "expired" and <StepTrack status={status} />}
                    <p className="text-sm">{req_summary(status, replies, len(revealed) > 0 and _any_claimed(item, claims))}</p>
                    <span className="text-xs text-muted-foreground">
                        {"Posted as @" + (req["from_handle"] as str) + (" · expires " + expires if expires and req_active(status) else "")}
                    </span>
                    {len(replies) > 0 and
                        <ul aria-label="Replies" className="flex flex-col divide-y divide-border rounded-md border">
                            {for r in replies {
                                <ReplyLine key={r["_jac_id"] as str} r={r} />
                            }}
                        </ul>}
                    {req_active(status) and
                        <p className="text-xs text-muted-foreground">
                            Friends' agents each check their own graph and answer with a count and a strength — no name — until the friend and their contact both say yes.
                        </p>}
                    {error and <p role="alert" className="text-sm text-destructive/80">{error}</p>}
                    {if req_active(status) and not confirming {
                        <div>
                            <Button size="sm" variant="outline" disabled={busy} onClick={ask_cancel}>Withdraw ask</Button>
                        </div>
                    } elif req_active(status) {
                        <div role="alertdialog" aria-label="Withdraw ask" className="flex flex-col gap-2">
                            <p className="text-sm">Withdraw this ask? Friends stop seeing it. No reason is sent.</p>
                            <div className="flex gap-2">
                                <Button className="flex-1" size="sm" variant="destructive" disabled={busy} onClick={do_cancel}>Withdraw</Button>
                                <Button className="flex-1" size="sm" variant="outline" disabled={busy} onClick={keep}>Keep it</Button>
                            </div>
                        </div>
                    }}
                </section>
                for r in revealed {
                    <RevealSlot
                        key={r["_jac_id"] as str}
                        reply={r}
                        claim={(claims[r["_jac_id"]] or {}) as dict}
                        claiming={True if claiming[r["_jac_id"]] else False}
                        onClaim={onClaim}
                    />
                }
            }}
        </div>;
}

"""One revealed reply: the card once claimed, a loading line while claiming,
or the error with a retry."""
def:pub RevealSlot(reply: dict, claim: dict, claiming: bool, onClaim: Callable[[str], None]) -> JsxElement {
    reply_id: str = reply["_jac_id"] as str;
    friend: str = reply["from_handle"] as str;

    def handle_claim(e: MouseEvent) {
        onClaim(reply_id);
    }

    if claim["card"] {
        return <RevealCard claim={claim} friend_handle={friend} />;
    }
    if claiming {
        return
            <p role="status" className="rounded-md border border-dashed pt-4 pb-4 pl-3 pr-3 text-sm text-muted-foreground">
                {"@" + friend + " shared a card. Adding it to your people and drafting the intro…"}
            </p>;
    }
    return
        <div className="flex flex-col gap-2 rounded-md border border-dashed pt-3 pb-3 pl-3 pr-3">
            <p className="text-sm">{"@" + friend + " shared a card with you."}</p>
            {claim["error"] and <p role="alert" className="text-xs text-destructive/80">{"Couldn't open it (" + (claim["error"] as str) + ")."}</p>}
            <div>
                <Button size="sm" onClick={handle_claim}>Open the card</Button>
            </div>
        </div>;
}
