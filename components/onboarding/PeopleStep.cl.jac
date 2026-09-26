"""Onboarding step 3 — bring five people; Continue sends one paste to Capture. OWNER: Person B.

Stateless: the shell owns `rows` ([{name, how}] x5), the Capture call, and the
returned people count (`captured_count`, -1 until Capture returns).
"""

import from "..ui.button" { Button }
import from "..ui.input" { Input }

"""One (name, how you know them) row. Named handlers, not lambdas: a lambda
inside a `for` slot compiles its body as a slot child push."""
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
        <div className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-3 pr-3 shadow-edge">
            <Input
                aria-label={"Person " + str(index + 1) + " name"}
                value={name}
                disabled={disabled}
                placeholder={"Name" if index > 0 else "Name, e.g. Maya Chen"}
                onChange={handle_name}
            />
            <Input
                aria-label={"How you know person " + str(index + 1)}
                value={how}
                disabled={disabled}
                placeholder={"How you know them" if index > 0 else "How you know them, e.g. worked together at Stripe"}
                onChange={handle_how}
            />
        </div>;
}

def:pub PeopleStep(
    rows: list[dict],
    pending: bool,
    error: str,
    captured_count: int,
    onRowChange: Callable[[int, str, str], None],
    onCapture: Callable[[], None],
    onSkip: Callable[[], None],
    onNext: Callable[[], None]
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    def handle_skip(e: MouseEvent) {
        onSkip();
    }

    def handle_next(e: MouseEvent) {
        onNext();
    }

    filled: int = len([r for r in rows if (r["name"] as str).strip()]);
    captured: bool = captured_count >= 0;

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">Bring five people</h2>
                <p className="text-body-sm text-muted-foreground">
                    Who do you already know? A name and one line on how you know them is enough.
                </p>
            </div>
            <div className="flex flex-col gap-2">
                {for (i, r) in enumerate(rows) {
                    <PersonRow
                        key={str(i)}
                        index={i}
                        name={r["name"] as str}
                        how={r["how"] as str}
                        disabled={pending or captured}
                        onRowChange={onRowChange}
                    />
                }}
            </div>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            {if captured {
                <div className="flex flex-col gap-2">
                    <p role="status" className="rounded-lg bg-success/10 pt-3 pb-3 pl-4 pr-4 text-body-sm text-success-text">
                        <span className="font-medium tabular-nums">{str(captured_count)}</span>
                        {" " + ("person" if captured_count == 1 else "people") + " added to your graph."}
                    </p>
                    <Button className="w-full" size="lg" onClick={handle_next}>Continue</Button>
                </div>
            } else {
                <div className="flex flex-col gap-2">
                    <Button className="w-full" size="lg" disabled={filled == 0 or pending} onClick={handle_capture}>
                        {"Capturing…" if pending else "Continue"}
                    </Button>
                    <Button className="w-full" size="lg" variant="ghost" disabled={pending} onClick={handle_skip}>Skip for now</Button>
                </div>
            }}
        </div>;
}
