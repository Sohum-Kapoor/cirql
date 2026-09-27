"""Global toast stack (SOH-226, POLISH-PLAN item 6 / FEEL-AUDIT #15). OWNER: Person B.

Mount ONCE at the shell root (`frontend.cl.jac` — `<Toaster />` as the last
child of `<main>`; `fixed` positioning means it doesn't need to be a layout
sibling). Every other component calls `toast()` from `../../lib/toast.cl.jac`;
this file only renders whatever that module-level store currently holds and
never talks to a screen directly.

Bridging: `lib/toast.cl.jac`'s store is a plain `glob` (not reactive — see
`jac-cl-components`), so this component polls it on a short interval and
mirrors changes into its own `has` state, the same idiom `frontend.cl.jac`'s
RANK_ROWS/publish_rank() and `components/exchange/common.cl.jac`'s `Poller`
already use. The same interval also drives auto-dismiss (3.5 s, `DEFAULT_
DURATION_MS`) by calling `dismiss()` once a toast's age passes its duration —
centralising the timer here means an individual toast never needs its own
`setTimeout`.

Position: fixed, bottom-centre, ABOVE the bottom tab bar
(`components/nav/TabBar.cl.jac`'s `<nav>` is `h-14` = 56px plus
`env(safe-area-inset-bottom)`), so a toast never covers Capture. Max 3 visible
(`lib/toast.cl.jac`'s `MAX_TOASTS`); `role="status" aria-live="polite"` so
assistive tech announces new toasts without stealing focus. `prefers-reduced-
motion` is handled globally in `assets/main.css`, not per-component.

`window.__cirqlToast` is a dev-only hook (verify via `jac browse eval`) wired
in the mount effect — never a production entry point (other components should
import `toast` directly).
"""

import from react { useEffect }
import from .icons { XIcon, CheckIcon }
import from ...lib.toast { snapshot, dismiss, toast, DEFAULT_DURATION_MS }
import from ...lib.utils { cn }

glob POLL_MS: int = 200;

"""Border/dot accent per kind — everything else (surface, text) stays the same
popover token so the stack reads as one system, not three different alerts."""
def _kind_accent(kind: str) -> str {
    if kind == "success" {
        return "text-success-text";
    }
    if kind == "error" {
        return "text-destructive";
    }
    return "text-muted-foreground";
}

def:pub ToastRow(item: dict, onDismiss: Callable[[str], None], onUndo: Callable[[str, Callable[[], None]], None]) -> JsxElement {
    tid: str = (item["id"] or "") as str;
    message: str = (item["message"] or "") as str;
    kind: str = (item["kind"] or "info") as str;
    undo: any = item["undo"];

    def handle_close(e: MouseEvent) {
        onDismiss(tid);
    }

    def handle_undo(e: MouseEvent) {
        onUndo(tid, undo as Callable[[], None]);
    }

    return
        <div
            key={tid}
            data-slot="toast"
            data-kind={kind}
            className="animate-in pointer-events-auto flex w-full items-center gap-2 rounded-lg border border-border bg-popover pt-2.5 pb-2.5 pl-3.5 pr-2.5 text-body-sm text-popover-foreground shadow-edge shadow-lg"
        >
            {kind == "success" and <CheckIcon className={cn("size-4 shrink-0", _kind_accent(kind))} />}
            <span className="flex-1 leading-snug">{message}</span>
            {undo and
                <button
                    type="button"
                    onClick={handle_undo}
                    className="shrink-0 rounded-sm pt-1 pb-1 pl-2 pr-2 text-button text-link outline-none transition-transform hover:underline focus-visible:ring-2 focus-visible:ring-ring/50 active:scale-[0.98]"
                >
                    Undo
                </button>}
            <button
                type="button"
                aria-label="Dismiss"
                onClick={handle_close}
                className="shrink-0 rounded-sm p-1 text-muted-foreground outline-none transition-transform hover:text-foreground hover:bg-secondary focus-visible:ring-2 focus-visible:ring-ring/50 active:scale-[0.98]"
            >
                <XIcon className="size-3.5" />
            </button>
        </div>;
}

def:pub Toaster() -> JsxElement {
    has items: list[dict] = [];

    useEffect(lambda {
        (window as any).__cirqlToast = toast;  # jac:ignore[W2001]
        return lambda { (window as any).__cirqlToast = None; };  # jac:ignore[W2001]
    }, []);

    useEffect(lambda {
        iv = setInterval(lambda {
            fresh: list[dict] = snapshot();
            now: int = Date.now() as int;  # jac:ignore[W2001]
            for t in fresh {
                created: int = (t["created_at"] or 0) as int;
                dur: int = (t["duration_ms"] or DEFAULT_DURATION_MS) as int;
                if now - created >= dur {
                    dismiss(t["id"] as str);
                }
            }
            items = snapshot();
        }, POLL_MS);
        return lambda { clearInterval(iv); };
    }, []);

    def handle_dismiss(tid: str) {
        dismiss(tid);
        items = snapshot();
    }

    def handle_undo(tid: str, undo: Callable[[], None]) {
        if undo {
            undo();
        }
        dismiss(tid);
        items = snapshot();
    }

    if len(items) == 0 {
        return <div data-slot="toaster" aria-hidden="true" className="hidden" />;
    }

    return
        <div
            data-slot="toaster"
            role="status"
            aria-live="polite"
            className="pointer-events-none fixed inset-x-0 bottom-[calc(3.5rem+env(safe-area-inset-bottom)+12px)] z-30 mx-auto flex w-full max-w-md flex-col-reverse gap-2 pl-4 pr-4"
        >
            {for t in items {
                <ToastRow key={(t["id"] or "") as str} item={t} onDismiss={handle_dismiss} onUndo={handle_undo} />
            }}
        </div>;
}
