import from "class-variance-authority" { cva }
import from "radix-ui" { Slot }
import from ...lib.utils { cn }

# jac-shadcn Badge, restyled to DESIGN.md `status-badge` (SOH-206): caption type,
# pill, 2px 8px. Lavender stays scarce: only `default` (emphasis) uses it.
#   secondary -> status-badge exactly (surface-2, ink-muted)
#   default   -> emphasis (lavender tint, link ink)
#   outline   -> hairline, ink-subtle
#   success   -> semantic-success tint (the only other hue)
glob _badgeVariants: any = cva(
         "group/badge inline-flex h-5 w-fit shrink-0 items-center justify-center gap-1 overflow-hidden whitespace-nowrap rounded-full border border-transparent pt-0.5 pb-0.5 pl-2 pr-2 text-caption font-medium transition-colors focus-visible:ring-2 focus-visible:ring-ring/50 [&>svg]:pointer-events-none [&>svg]:size-3!",
         {
             "variants": {
                 "variant": {
                     "default": "bg-primary/15 text-link",
                     "secondary": "bg-secondary text-ink-muted",
                     "outline": "border-border text-muted-foreground",
                     "success": "bg-success/15 text-success-text",
                     "destructive": "bg-destructive/10 text-destructive",
                     "ghost": "text-muted-foreground",
                     "link": "text-link underline-offset-4 hover:underline"
                 }
             },
             "defaultVariants": {"variant": "default"}
         }
     );

def:pub Badge(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    variant = props["variant"] or "default";
    asChild = props["asChild"] or False;

    variantsFn = _badgeVariants;
    computedClass = cn(variantsFn.call(None, {"variant": variant}), props["className"]);

    if asChild {
        return
            <Slot.Root
                {**props}
                data-slot="badge"
                data-variant={variant}
                className={computedClass}
            />;
    }

    return
        <span
            {**attrs}
            data-slot="badge"
            data-variant={variant}
            className={computedClass}
        />;
}

def:pub badgeVariants -> any {
    return _badgeVariants;
}
