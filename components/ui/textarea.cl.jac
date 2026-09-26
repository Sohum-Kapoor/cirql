import from ...lib.utils { cn }

# jac-shadcn Textarea, restyled to DESIGN.md `text-input` (SOH-206).
def:pub Textarea(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <textarea
            {**attrs}
            data-slot="textarea"
            className={cn(
                "flex field-sizing-content min-h-20 w-full rounded-md border border-input bg-card pt-2 pb-2 pl-3 pr-3 text-body text-foreground outline-none transition-colors placeholder:text-ink-tertiary focus-visible:border-border-strong focus-visible:ring-2 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/30",
                props["className"]
            )}
        />;
}
