"""Onboarding step 3 — bring five people; one Continue sends the paste to
Capture. OWNER: Person B.

Stateless: the shell owns `rows` ([{name, how}] x5) and the Capture call.
One Continue: click runs the capture, shows a pending status + skeleton, and
the shell advances to step 4 automatically on success (SOH-232). On failure
the button becomes Retry and the error stays visible. Skip for now is shown
only before the first capture attempt.
"""

import from "..ui.button" { Button }
import from "..ui.input" { Input }
import from "..ui.skeleton" { Skeleton }

"""One (name, how you know them) row: two inputs, no nested card — the flat
list's own `divide-y` draws the hairline between rows (SOH-232). Named
handlers, not lambdas: a lambda inside a `for` slot compiles its body as a
slot child push."""
def:pub PersonRow(
    index: int,
    name: str,
    how: str,
    disabled: bool,
    onRowChange: Callable[[int, str, str], None]
) -> JsxElement {
    def handle_name(e: ChangeEvent) {
        onRowChange(index, "name", e.target.value);
    }

    def handle_how(e: ChangeEvent) {
        onRowChange(index, "how", e.target.value);
    }

    return
        <li className="grid grid-cols-2 gap-2 pt-3 pb-3">
            <Input
                aria-label={"Person " + str(index + 1) + " name"}
                value={name}
                disabled={disabled}
                placeholder={"Name" if index > 0 else "e.g. Maya Chen"}
                onChange={handle_name}
            />
            <Input
                aria-label={"How you know person " + str(index + 1)}
                value={how}
                disabled={disabled}
                placeholder={"How you know them" if index > 0 else "e.g. college roommate"}
                onChange={handle_how}
            />
        </li>;
}

def:pub PeopleStep(
    rows: list[dict],
    pending: bool,
    error: str,
    onRowChange: Callable[[int, str, str], None],
    onCapture: Callable[[], None],
    onSkip: Callable[[], None]
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    def handle_skip(e: MouseEvent) {
        onSkip();
    }

    filled: int = len([r for r in rows if (r["name"] as str).strip()]);
    started: bool = pending or len(error) > 0;
    label: str = "Adding your people…" if pending else ("Retry" if error else "Continue");

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">Bring five people</h2>
                <p className="text-body-sm text-muted-foreground">
                    Who do you already know? A name and one line on how you know them is enough.
                </p>
            </div>
            <ul className="flex flex-col divide-y divide-border">
                {for (i, r) in enumerate(rows) {
                    <PersonRow
                        key={str(i)}
                        index={i}
                        name={r["name"] as str}
                        how={r["how"] as str}
                        disabled={pending}
                        onRowChange={onRowChange}
                    />
                }}
            </ul>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            {pending and
                <div className="flex flex-col gap-2">
                    <span role="status" className="text-caption text-muted-foreground">Adding your people…</span>
                    <div className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                        <Skeleton className="h-4 w-2/3" />
                        <Skeleton className="h-3.5 w-full" />
                    </div>
                </div>}
            <div className="flex flex-col gap-2">
                <Button className="w-full" size="lg" disabled={filled == 0 or pending} onClick={handle_capture}>
                    {label}
                </Button>
                {not started and
                    <Button className="w-full" size="lg" variant="ghost" onClick={handle_skip}>Skip for now</Button>}
            </div>
        </div>;
}
