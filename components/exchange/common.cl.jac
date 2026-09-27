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
