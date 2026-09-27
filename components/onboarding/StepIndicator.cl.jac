"""Onboarding progress: "Step n of total" plus one thin segment per step. OWNER: Person B.

The step's own heading (each step component's <h2>) is the only visible title;
this shows the position only, never a repeated step name (SOH-232). The step
names still reach assistive tech, one per segment's aria-label.
"""

import from "...lib.utils" { cn }

def:pub StepIndicator(step: int, total: int, labels: list[str]) -> JsxElement {
    return
        <div className="flex flex-col gap-2">
            <span className="text-caption text-muted-foreground tabular-nums">
                {"Step " + str(step) + " of " + str(total)}
            </span>
            <div className="flex gap-1" role="list" aria-label="Onboarding steps">
                {for i in range(total) {
                    <div
                        key={str(i)}
                        role="img"
                        aria-label={(labels[i] if i < len(labels) else ("Step " + str(i + 1))) + (", current step" if i == step - 1 else "")}
                        className={cn(
                            "h-1 flex-1 rounded-full",
                            "bg-primary" if i < step else "bg-border-strong"
                        )}
                    />
                }}
            </div>
        </div>;
}
