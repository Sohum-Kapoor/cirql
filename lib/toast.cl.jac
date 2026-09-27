"""Global toast store (SOH-226, POLISH-PLAN item 6). OWNER: Person B.

`toast(message, kind, undo)` is the one entry point every other client component
should call on save / copy / dismiss / archive / delete so the app stops hard-
cutting between states with no confirmation (FEEL-AUDIT #15). It can be called
from anywhere — this file talks to no specific screen.

The store itself is a module `glob`, which is NOT reactive (`jac-cl-components`:
"glob is NOT reactive - anything that changes belongs in has"). `components/ui/
toaster.cl.jac` is the one component that mirrors this store into its own `has`
state, polling on an interval — the same module-glob-mirrored-into-has idiom
`frontend.cl.jac`'s RANK_ROWS/publish_rank() and `components/exchange/common
.cl.jac`'s Poller already use for cheap module-state -> React bridging, chosen
over a subscribe/listener callback list because a `has` field must only ever be
written from inside its own component (writing another component's `has` from
here would not be a stable reference across renders).

Each toast is a dict: { id, message, kind, created_at, duration_ms, undo }.
kind: "info" | "success" | "error". `undo`, when given, is called once and the
toast is dismissed immediately after (no double-fire on repeat taps).
"""

glob _TOASTS: list[dict[str, any]] = [];
glob _NEXT_ID: int = 1;
glob:pub TOAST_KINDS: list[str] = ["info", "success", "error"];
glob:pub DEFAULT_DURATION_MS: int = 3500;
glob:pub MAX_TOASTS: int = 3;

# jac check has no type for a module `glob` read back inside a `def` in this
# compiler version (isolated `jac check`, confirmed with a 4-line repro): every
# arithmetic/subscript/comprehension use of `_TOASTS`/`_NEXT_ID` below is flagged
# Unknown/E1055/E1053, but it runs correctly (`jac-cl-js-interop`'s "correct at
# runtime, jac build succeeds" note for browser-global reads applies here too).
# Suppressed per line rather than widened to `any`, which would lose real typing
# for every CALLER of `snapshot()`/`toast()`.

def _cap(items: list[dict[str, any]]) -> list[dict[str, any]] {
    if len(items) <= MAX_TOASTS {
        return items;
    }
    start: int = len(items) - MAX_TOASTS;
    return items[start:];
}

"""Queue a toast. `undo`, if given, renders an Undo button that calls it once."""
def:pub toast(message: str, kind: str = "info", undo: Callable[[], None] | None = None) -> None {
    if not message {
        return;
    }
    tid: str = "t" + str(_NEXT_ID);  # jac:ignore[E1055]
    _NEXT_ID = _NEXT_ID + 1;  # jac:ignore[E1055]
    item: dict[str, any] = {
        "id": tid,
        "message": message,
        "kind": kind if kind in TOAST_KINDS else "info",
        "created_at": Date.now() as int,  # jac:ignore[W2001]
        "duration_ms": DEFAULT_DURATION_MS,
        "undo": undo
    };
    _TOASTS = _cap(_TOASTS + [item]);  # jac:ignore[E1055,E1053]
}

"""Remove one toast (auto-dismiss, or a manual close tap)."""
def:pub dismiss(tid: str) {
    _TOASTS = [t for t in _TOASTS if t["id"] != tid];  # jac:ignore[E1053]
}

"""A fresh copy of the current toasts, oldest first. Never the same list
reference back-to-back, so a polling caller can always tell "changed" from
"same" without a deep-equality check."""
def:pub snapshot() -> list[dict[str, any]] {
    return list(_TOASTS);  # jac:ignore[E1053]
}
