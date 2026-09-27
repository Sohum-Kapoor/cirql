"""Post-capture confirmation strip — SOH-226.

The one-person case opens the person's sheet directly (see frontend.impl.jac
`capture_done`), so this strip only ever shows for a multi-person Capture:
"Added Priya Nair and Dev Okafor · 2 facts · 1 promise" plus a "View <name>"
button that opens the first person's sheet. The shell auto-dismisses it after
4 s; it can also be dismissed by hand. OWNER: Person B.
"""

import from ..ui.button { Button }
import from ..ui.icons { XIcon }

def:pub CaptureLandedStrip(
    summary: str,
    person_name: str,
    onView: Callable[[], None],
    onDismiss: Callable[[], None]
) -> JsxElement {
    def handle_view(e: MouseEvent) {
        onView();
    }

    def handle_dismiss(e: MouseEvent) {
        onDismiss();
    }

    return
        <div role="status" aria-live="polite" className="flex items-center justify-between gap-2 rounded-lg border bg-card pt-2.5 pb-2.5 pl-3 pr-2 shadow-edge">
            <p className="min-w-0 flex-1 text-body-sm text-foreground">{summary}</p>
            <div className="flex shrink-0 items-center gap-1">
                {person_name and
                    <Button variant="secondary" size="sm" onClick={handle_view}>{"View " + person_name}</Button>}
                <Button variant="ghost" size="icon-sm" aria-label="Dismiss" onClick={handle_dismiss}>
                    <XIcon className="size-3.5" />
                </Button>
            </div>
        </div>;
}
