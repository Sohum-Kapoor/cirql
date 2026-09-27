"""Shared Exchange bits — status chip, step track, draft block, poller. OWNER: Person B.

Statuses are exactly what exchange.sv.jac emits:
  request (derived on read): open | replied | approved | opted_in | revealed | declined | expired
  reply (written by the friend): pending | approved | opted_in | revealed | declined
Drafts are text + Copy only. Nothing here sends.
"""

import from react { useEffect }
import from ..ui.badge { Badge }
import from ..ui.button { Button }
import from ...lib.utils { cn }
import from ...lib.toast { toast }
import from ...lib.text { join_with }

glob REQ_LABEL: dict[str, str] = {
         "open": "Asked",
         "replied": "Friend replied",
         "approved": "Friend approved",
         "opted_in": "Contact said yes",
         "revealed": "Card shared",
         "declined": "Withdrawn",
         "expired": "Expired"
     },
     REPLY_LABEL: dict[str, str] = {
         "new": "New",
         "checking": "Checking…",
         "pending": "Needs your OK",
         "approved": "Approved",
         "opted_in": "Contact said yes",
         "revealed": "Card shared",
         "declined": "Declined"
     },
     REQ_STEPS: list[str] = ["open", "replied", "approved", "opted_in", "revealed"],
     STEP_NAMES: list[str] = ["Asked", "Replied", "Approved", "Opted in", "Revealed"];

def:pub req_label(status: str) -> str {
    return (REQ_LABEL[status] or status) as str;
}

def:pub reply_label(status: str) -> str {
    return (REPLY_LABEL[status] or status) as str;
}

"""Is this request still moving (worth polling)?"""
def:pub req_active(status: str) -> bool {
    return status in ["open", "replied", "approved", "opted_in"];
}

def _chip_variant(status: str) -> str {
    if status == "revealed" {
        return "success";
    }
    if status == "declined" or status == "expired" {
        return "outline";
    }
    if status == "open" or status == "new" {
        return "outline";
    }
    return "secondary";
}

def:pub StatusChip(status: str, label: str) -> JsxElement {
    return <Badge variant={_chip_variant(status)}>{label}</Badge>;
}

"""Five dots: Asked → Replied → Approved → Opted in → Revealed."""
def:pub StepTrack(status: str) -> JsxElement {
    idx: int = REQ_STEPS.index(status) if status in REQ_STEPS else -1;
    return
        <ol aria-label="Exchange progress" className="flex items-center gap-1">
            {for (i, name) in enumerate(STEP_NAMES) {
                <li key={name} className="flex min-w-0 flex-1 flex-col gap-1">
                    <span
                        aria-hidden="true"
                        className={cn("h-1 rounded-full", "bg-primary" if i <= idx else "bg-border-strong")}
                    />
                    <span
                        className={cn(
                            "truncate text-caption",
                            "font-medium text-foreground" if i == idx else "text-muted-foreground"
                        )}
                        aria-current={"step" if i == idx else "false"}
                    >
                        {name}
                    </span>
                </li>
            }}
        </ol>;
}

"""A drafted message: text, a Copy button, never a Send."""
def:pub DraftBlock(title: str, text: str, note: str = "") -> JsxElement {
    has copied: bool = False;

    async def do_copy -> None {
        ok: bool = True;
        try {
            await navigator.clipboard.writeText(text);  # jac:ignore[E1030]
        } except Exception as e {
            ok = False;
        }
        copied = ok;
        if ok {
            toast("Copied");
        }
    }

    return
        <div className="flex flex-col gap-2 rounded-md border bg-secondary pt-3 pb-3 pl-3 pr-3">
            <div className="flex items-center justify-between gap-2">
                <span className="text-eyebrow text-muted-foreground">{title}</span>
                <Button size="xs" variant="secondary" onClick={do_copy}>{"Copied" if copied else "Copy"}</Button>
            </div>
            <p className="whitespace-pre-wrap text-body-sm">{text}</p>
            {note and <span className="text-caption text-muted-foreground">{note}</span>}
        </div>;
}

"""SOH-229: the friend-name-aware ask copy + the client-side grouping key.
`from_name`/`goal_text`/`need_key` are read defensively off an IntroRequest
row — the server adds them; until it does (or when it doesn't recognize a
caller), every function here falls back to the handle and skips the goal
line entirely, never guessing.
"""

glob NEED_STOPWORDS: list[str] = ["a", "an", "the", "who", "someone", "that", "for", "in", "and", "with", "of", "to"];

"""The first word of a name, "" when blank."""
def:pub first_name(name: str) -> str {
    n: str = (name or "").strip();
    if not n {
        return "";
    }
    for w in n.split(" ") {
        if w {
            return w;
        }
    }
    return "";
}

"""The requester's display word: their first name when known, else their handle."""
def:pub asker_label(from_name: str, from_handle: str) -> str {
    fn: str = first_name(from_name);
    if fn {
        return fn;
    }
    return "@" + (from_handle or "");
}

"""Lower-cases only the first letter, so a need that reads as its own
sentence ("An investor…") folds into the middle of another one."""
def:pub lower_lead(s: str) -> str {
    if not s {
        return s;
    }
    return s[0:1].lower() + s[1:];
}

"""`need` ready to sit mid-sentence: trailing period dropped, leading letter lowered."""
def:pub need_sentence(need: str) -> str {
    n: str = (need or "").strip();
    if n.endswith(".") {
        n = n[0:len(n) - 1];
    }
    return lower_lead(n);
}

"""SOH-229 title: "<First name> is looking for <need>." — "@handle" when no name."""
def:pub ask_title(from_name: str, from_handle: str, need: str) -> str {
    return asker_label(from_name, from_handle) + " is looking for " + need_sentence(need) + ".";
}

"""SOH-229 second line: only rendered when the requester's own goal text is known."""
def:pub goal_approved_line(from_name: str, from_handle: str, goal_text: str) -> str {
    if not goal_text {
        return "";
    }
    return asker_label(from_name, from_handle) + " approved this ask from their goal '" + goal_text + "'.";
}

"""SOH-229 footer under an expanded ask: only meaningful once a name is known."""
def:pub handle_caption(from_name: str, from_handle: str) -> str {
    fn: str = first_name(from_name);
    if not fn {
        return "";
    }
    return "@" + (from_handle or "") + " is " + fn + "'s Cirql handle.";
}

glob _NEED_CHARS: str = "abcdefghijklmnopqrstuvwxyz0123456789 ";

def _identity_str(s: str) -> str {
    return s;
}

def _need_tokens(need: str) -> list[str] {
    lower: str = (need or "").lower();
    buf: str = "";
    for ch in lower {
        buf = buf + (ch if ch in _NEED_CHARS else " ");
    }
    out: list[str] = [];
    for tok in buf.split(" ") {
        if tok and tok not in NEED_STOPWORDS {
            out = out + [tok];
        }
    }
    return sorted(out, key=_identity_str);
}

"""SOH-229 grouping key: the server's own `need_key` when present, else the
same normalize-and-sort a client can do alone (lowercase, strip punctuation,
drop stopwords, sort tokens, join)."""
def:pub need_group_key(req: dict) -> str {
    given: str = (req["need_key"] or "") as str;
    if given {
        return given;
    }
    return join_with(_need_tokens((req["need"] or "") as str), " ");
}

"""Calls `onTick` every `ms` while mounted (skips while the tab is hidden).
Mount it only while polling is wanted; unmounting clears the interval. The
latest `onTick` is kept in a ref so re-renders never reset the timer."""
def:pub Poller(ms: int, onTick: Callable[[], None]) -> JsxElement {
    has latest: Ref[any] = Ref(None);
    latest.current = onTick;

    useEffect(lambda {
        iv = setInterval(lambda {
            if not document.hidden and latest.current {  # jac:ignore[E1030]
                latest.current.call(None);
            }
        }, ms);
        return lambda { clearInterval(iv); };
    }, []);

    return <span hidden={True} />;
}
