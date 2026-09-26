"""Onboarding progress: "Step n of total" plus one thin segment per step. OWNER: Person B."""

import from "...lib.utils" { cn }

def:pub StepIndicator(step: int, total: int, label: str) -> JsxElement {
    return
        <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between text-caption text-muted-foreground">
                <span className="text-eyebrow text-foreground">{label}</span>
                <span className="tabular-nums">{str(step) + "/" + str(total)}</span>
            </div>
            <div className="flex gap-1" aria-hidden="true">
                {for i in range(total) {
                    <div
                        key={str(i)}
                        className={cn(
                            "h-1 flex-1 rounded-full",
                            "bg-primary" if i < step else "bg-border-strong"
                        )}
                    />
                }}
            </div>
        </div>;
}
