"""Agent inbox vocabulary — kinds, labels, filters, icons, time words (SOH-224). OWNER: Person B.

AgentAction kinds (SOH-223): new_match | ask_network | route | promise_due |
follow_up | reconnect | answer_ask. Each Approve button says exactly what happens.
Reason-based only: nothing here says "it's been N days" — relationships never decay.
"""

import from ...lib.utils { cn }
import from ...lib.text { due_label }

glob:pub KIND_LABEL: dict[str, str] = {
         "new_match": "New match",
         "ask_network": "Ask your network",
         "route": "Introduction",
         "promise_due": "Promise due",
         "follow_up": "Follow up",
         "reconnect": "Reason to reconnect",
         "answer_ask": "A friend's ask"
     },
     APPROVE_LABEL: dict[str, str] = {
         "new_match": "Got it",
         "ask_network": "Post this ask",
         "route": "Save draft",
         "promise_due": "Mark promise done",
         "follow_up": "Save draft",
         "reconnect": "Save draft",
         "answer_ask": "Open the reply"
     },
     DONE_LABEL: dict[str, str] = {
         "new_match": "Noted",
         "ask_network": "Ask posted",
         "route": "Draft saved",
         "promise_due": "Promise marked done",
         "follow_up": "Draft saved",
         "reconnect": "Draft saved",
         "answer_ask": "Reply opened"
     },
     FILTER_KINDS: dict[str, list[str]] = {
         "asks": ["ask_network", "answer_ask"],
         "routes": ["route"],
         "follow": ["promise_due", "follow_up", "reconnect"],
         "matches": ["new_match"]
     },
     FILTERS: list[list[str]] = [
         ["all", "All"],
         ["asks", "Asks"],
         ["routes", "Introductions"],
         ["follow", "Follow-ups"],
         ["matches", "Matches"]
     ];

def:pub kind_label(kind: str) -> str {
    return (KIND_LABEL[kind] or kind) as str;
}

"""A new_match carrying the edge's cached opener saves it as a draft on approve
(SOH-223 `draft_saved`), so its button says so; without one it is "Got it"."""
def:pub approve_label(kind: str, has_draft: bool = False) -> str {
    if kind == "new_match" and has_draft {
        return "Save draft";
    }
    return (APPROVE_LABEL[kind] or "Approve") as str;
}

"""The resolved row's words for a status the user (or the server) set."""
def:pub resolved_label(kind: str, status: str) -> str {
    if status == "dismissed" {
        return "Dismissed";
    }
    if status == "snoozed" {
        return "Snoozed — back on the next run";
    }
    return (DONE_LABEL[kind] or "Done") as str;
}

def:pub in_filter(kind: str, filt: str) -> bool {
    if filt == "all" {
        return True;
    }
    return kind in ((FILTER_KINDS[filt] or []) as list[str]);
}

"""payload_json -> dict ({} when empty or not JSON)."""
def:pub payload_of(act: dict) -> dict {
    raw: str = (act["payload_json"] or "") as str;
    out: dict = {};
    if not raw {
        return out;
    }
    try {
        out = JSON.parse(raw) as dict;  # jac:ignore[W2001]
    } except Exception as e {
        out = {};
    }
    return out or {};
}

"""For a promise_due action: the due date (weekday-aware, "Due Mon Sep 28")
when its payload carries a `due` ISO, else "Promise open" — never claims a
date that isn't there (SOH-222/223)."""
def:pub promise_due_label(act: dict) -> str {
    due: str = (payload_of(act)["due"] or "") as str;
    label: str = due_label(due);
    return label if label else "Promise open";
}

"""True once a friend-ask entry (`ex.friend[request_id]`) is resolved to zero
matches (nothing left to approve, SOH-222) — the same rule `ApprovalView`
uses to hide its Approve button. No reply yet is NOT zero-match: it stays
counted as "needs your OK" until actually checked (SOH-226)."""
def:pub is_zero_match(ent: dict) -> bool {
    reply: dict = (ent["reply"] or {}) as dict;
    if not reply["_jac_id"] {
        return False;
    }
    n: int = (reply["match_count"] or 0) as int;
    return n == 0;
}

"""A friend-ask entry's status word: the reply's own status once one exists,
"checking" while a check is in flight, else "new" (not yet looked at)."""
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

"""Up to `cap` incoming-ask ids that haven't been checked yet (no reply,
not mid-check): the client-side scan the Inbox used to run on its own
(SOH-222) — moved here so the shell drives it through the SAME `friend_check`
call a manually-opened ask uses, never a second parallel path (SOH-226:
two code paths calling ReplyToRequest independently is exactly how the badge
and the visible "Needs your OK" list drifted apart)."""
def:pub pick_unchecked(incoming: list[dict], friend: dict, cap: int) -> list[str] {
    out: list[str] = [];
    for r in incoming {
        if len(out) >= cap {
            return out;
        }
        rid: str = (r["_jac_id"] or "") as str;
        if not rid {
            continue;
        }
        ent: dict = (friend[rid] or {}) as dict;
        if friend_status(ent) != "new" {
            continue;
        }
        out = out + [rid];
    }
    return out;
}

"""Every incoming ask (already `covered`-filtered by the caller) plus any of
this session's in-progress `friend` replies that have left `incoming`, split
into `needs` ("Needs your OK": counts toward the Inbox badge) and `other`
(checked, count-0 — nothing left to approve, SOH-222). `covered` are request
ids an open `answer_ask` AgentAction already represents on its own card;
excluded from both buckets here so the same ask is never counted twice
across AgentInbox and this list (SOH-226) — this is the ONE place both the
badge and the "Needs your OK" section compute from."""
def:pub split_asks(incoming: list[dict], friend: dict, covered: list[str]) -> dict {
    ids: list[str] = [];
    needs: list[dict] = [];
    other: list[dict] = [];
    for r in incoming {
        rid: str = (r["_jac_id"] or "") as str;
        if not rid or rid in covered {
            continue;
        }
        ids = ids + [rid];
        ent: dict = (friend[rid] or {}) as dict;
        entry: dict = {"request": r};
        if is_zero_match(ent) {
            other = other + [entry];
        } else {
            needs = needs + [entry];
        }
    }
    for rid in Object.keys(friend) {  # jac:ignore[W2001]
        if rid in ids or rid in covered {
            continue;
        }
        ent: dict = friend[rid] as dict;
        if not ent["request"] {
            continue;
        }
        st: str = friend_status(ent);
        if st == "revealed" or st == "declined" {
            continue;
        }
        if is_zero_match(ent) {
            other = other + [ent];
        } else {
            needs = needs + [ent];
        }
    }
    return {"needs": needs, "other": other};
}

"""What the Inbox badge counts for friends' asks (SOH-226): the `needs`
bucket only — never count-0, never stale/dismissed/snoozed, never a request
an open `answer_ask` AgentAction (`covered`) already represents."""
def:pub asks_needing_count(incoming: list[dict], friend: dict, covered: list[str]) -> int {
    needs: list[dict] = (split_asks(incoming, friend, covered)["needs"] or []) as list[dict];
    return len(needs);
}

"""Rough "just now" / "4 min ago" / "3 h ago" / "2 d ago" for `ms` elapsed."""
def:pub ago_words(ms: int) -> str {
    if ms < 0 {
        return "";
    }
    mins: int = int(ms / 60000);
    if mins < 1 {
        return "just now";
    }
    if mins < 60 {
        return str(mins) + " min ago";
    }
    hours: int = int(mins / 60);
    if hours < 24 {
        return str(hours) + " h ago";
    }
    return str(int(hours / 24)) + " d ago";
}

"""Elapsed ms since an ISO timestamp (-1 when it doesn't parse)."""
def:pub since_iso(iso: str) -> int {
    if not iso {
        return -1;
    }
    t: any = Date.parse(iso);  # jac:ignore[W2001]
    if isNaN(t) {  # jac:ignore[W2001]
        return -1;
    }
    return (Date.now() as int) - (t as int);  # jac:ignore[W2001]
}

"""ms an ISO timestamp parses to (-1 when it doesn't parse)."""
def _parse_ms(iso: str) -> int {
    if not iso {
        return -1;
    }
    t: any = Date.parse(iso);  # jac:ignore[W2001]
    if isNaN(t) {  # jac:ignore[W2001]
        return -1;
    }
    return t as int;  # jac:ignore[W2001]
}

glob:pub INBOX_SEEN_KEY: str = "cirql.inbox_seen_ms";

"""When the Inbox tab was last opened this session (sessionStorage, guarded —
Safari private mode and some WKWebView configs throw), or 0 on a first-ever
visit (so every open proposal reads as "new" the first time)."""
def:pub load_inbox_seen_ms() -> int {
    out: int = 0;
    try {
        v: any = sessionStorage.getItem(INBOX_SEEN_KEY);  # jac:ignore[W2001]
        if v {
            out = int(v as str);
        }
    } except Exception as e {
        out = 0;
    }
    return out;
}

"""Marks "now" as the last time the Inbox was opened, for the NEXT open."""
def:pub mark_inbox_seen_now() -> None {
    try {
        sessionStorage.setItem(INBOX_SEEN_KEY, str(Date.now() as int));  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}

"""How many of `rows` (open AgentActions, "What Cirql found") were created
after `seen_ms` — the "N new" line's number, SOH-226: same array the found-
count uses, never a walker-reported "new this run" that can drift from what
"What Cirql found N" actually shows."""
def:pub new_since_seen(rows: list[dict], seen_ms: int) -> int {
    n: int = 0;
    for r in rows {
        act: dict = (r["action"] or {}) as dict;
        c: int = _parse_ms((act["created_at"] or "") as str);
        if c > seen_ms {
            n = n + 1;
        }
    }
    return n;
}

def _svg(className: str, children: any) -> JsxElement {
    return
        <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
            className={cn("size-3.5", className)}
        >
            {children}
        </svg>;
}

"""One small stroke icon per kind (ink-subtle; color stays scarce)."""
def:pub KindIcon(kind: str, className: str = "") -> JsxElement {
    if kind == "new_match" {
        return _svg(className, [<path key="a" d="M3 17l6-6 4 4 8-8" />, <path key="b" d="M15 7h6v6" />]);
    }
    if kind == "ask_network" {
        return
            _svg(
                className,
                [
                    <path key="a" d="M4 10v4a1 1 0 0 0 1 1h2l6 4V5L7 9H5a1 1 0 0 0-1 1z" />,
                    <path key="b" d="M17 9a4 4 0 0 1 0 6" />
                ]
            );
    }
    if kind == "route" {
        return
            _svg(
                className,
                [
                    <circle key="a" cx="6" cy="6" r="2.5" />,
                    <circle key="b" cx="18" cy="18" r="2.5" />,
                    <path key="c" d="M8.5 6H15a3 3 0 0 1 0 6H9a3 3 0 0 0 0 6h6.5" />
                ]
            );
    }
    if kind == "promise_due" {
        return _svg(className, [<circle key="a" cx="12" cy="12" r="9" />, <path key="b" d="m8 12 3 3 5-6" />]);
    }
    if kind == "answer_ask" {
        return
            _svg(
                className,
                [
                    <path key="a" d="M4 13h4l1.5 3h5L16 13h4" />,
                    <path key="b" d="M5.5 5h13L21 13v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-5z" />
                ]
            );
    }
    if kind == "reconnect" {
        return
            _svg(
                className,
                [
                    <path key="a" d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1" />,
                    <path key="b" d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" />
                ]
            );
    }
    # follow_up (and anything new): a reply arrow
    return _svg(className, [<path key="a" d="M9 14 4 9l5-5" />, <path key="b" d="M4 9h10a6 6 0 0 1 6 6v4" />]);
}

"""The agent mark for the inbox header: a small spark."""
def:pub AgentIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <path key="a" d="M12 3v4M12 17v4M3 12h4M17 12h4" />,
                <path key="b" d="m6.5 6.5 2 2M15.5 15.5l2 2M17.5 6.5l-2 2M8.5 15.5l-2 2" />
            ]
        );
}
