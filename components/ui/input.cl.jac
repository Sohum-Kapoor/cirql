import from ...lib.utils { cn }

# jac-shadcn Input, restyled to DESIGN.md `text-input` (SOH-206): surface-1,
# body 16px (also stops iOS zoom-on-focus), rounded.md, 8px 12px, 44px tap
# height; focus keeps the surface and adds a 2px primary-focus ring at 50%.
def:pub Input(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <input
            {**attrs}
            data-slot="input"
            className={cn(
                "h-11 w-full min-w-0 rounded-md border border-input bg-card pt-2 pb-2 pl-3 pr-3 text-body text-foreground outline-none transition-colors placeholder:text-ink-tertiary focus-visible:border-border-strong focus-visible:ring-2 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/30 file:inline-flex file:h-6 file:border-0 file:bg-transparent file:text-body-sm file:font-medium file:text-foreground",
                props["className"]
            )}
        />;
}
