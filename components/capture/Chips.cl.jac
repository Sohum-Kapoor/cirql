"""Single-select chips (a radiogroup of pill buttons). OWNER: Person B (SOH-209).

36px tap height, wraps at phone width. Selected = the tabs' selected look
(surface-2 lift, strong hairline, ink) plus a check — no new colours.
`clearable`: tapping the selected chip again clears the choice (optional fields).
"""

import from ..ui.icons { CheckIcon }
import from ...lib.utils { cn }

def:pub ChoiceChip(
    value: str,
    label: str,
    selected: bool,
    disabled: bool,
    clearable: bool,
    onPick: Callable[[str], None]
) -> JsxElement {
    def handle_pick(e: MouseEvent) {
        onPick("" if selected and clearable else value);
    }

    return
        <button
            type="button"
            role="radio"
            aria-checked={selected}
            disabled={disabled}
            onClick={handle_pick}
            className={cn(
                "inline-flex h-9 items-center gap-1.5 rounded-full border pl-3 pr-3 text-body-sm outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50",
                "border-border-strong bg-secondary font-medium text-foreground" if selected else "border-border bg-transparent text-muted-foreground hover:bg-secondary hover:text-foreground"
            )}
        >
            {selected and <CheckIcon className="size-3.5 text-link" />}
            <span>{label}</span>
        </button>;
}

def:pub ChipGroup(
    label: str,
    options: list[list[str]],
    value: str,
    onChange: Callable[[str], None],
    disabled: bool = False,
    clearable: bool = True
) -> JsxElement {
    return
        <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-2">
            {for opt in options {
                <ChoiceChip
                    key={opt[0]}
                    value={opt[0]}
                    label={opt[1]}
                    selected={value == opt[0]}
                    disabled={disabled}
                    clearable={clearable}
                    onPick={onChange}
                />
            }}
        </div>;
}
