import from "class-variance-authority" { cva }
import from "radix-ui" { Slot }
import from ...lib.utils { cn }

# jac-shadcn Button, restyled to docs/design/linear-DESIGN.md (SOH-206):
#   default   -> button-primary   (lavender, hover primary-hover, pressed primary-focus)
#   secondary -> button-secondary (surface-1 + hairline)
#   outline   -> button-secondary on a transparent fill (sits on cards)
#   ghost     -> button-tertiary  (no fill; surface lift on hover)
#   link      -> link emphasis    (lavender text)
#   chip      -> evidence / source pill (aria-expanded = open)
# Sizes: default 40px (DESIGN: CTAs >= 40px tap height), lg 44px; `row` is a
# full-width list row (goal options, asks) with no fixed height.
# SOH-226: one shared transition-property list (color + transform) so a hover
# color change and the active-press scale never fight over `transition-property`
# (two separate `transition-*` utilities would just have one silently win).
glob _buttonVariants: any = cva(
         "group/button inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded-md border border-transparent bg-clip-padding text-button outline-none select-none transition-[color,background-color,border-color,box-shadow,transform] duration-100 focus-visible:ring-2 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/30 active:scale-[0.98] disabled:active:scale-100 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
         {
             "variants": {
                 "variant": {
                     "default": "bg-primary text-primary-foreground hover:bg-primary-hover active:bg-primary-focus",
                     "secondary": "border-border bg-card text-foreground shadow-edge hover:bg-secondary aria-expanded:bg-secondary",
                     "outline": "border-border bg-transparent text-foreground hover:border-border-strong hover:bg-secondary aria-expanded:bg-secondary",
                     "ghost": "bg-transparent text-foreground hover:bg-secondary aria-expanded:bg-secondary",
                     "destructive": "border-destructive/30 bg-destructive/10 text-destructive hover:bg-destructive/15 focus-visible:ring-destructive/30",
                     "link": "h-auto rounded-xs border-0 p-0 text-link underline-offset-4 hover:underline",
                     "chip": "rounded-full border-border bg-transparent font-normal text-muted-foreground hover:bg-secondary hover:text-foreground aria-expanded:border-border-strong aria-expanded:bg-secondary aria-expanded:text-foreground"
                 },
                 "size": {
                     "default": "h-10 px-3.5",
                     "xs": "h-7 gap-1 px-2.5 text-caption [&_svg:not([class*='size-'])]:size-3",
                     "sm": "h-8 gap-1 px-3 [&_svg:not([class*='size-'])]:size-3.5",
                     "lg": "h-11 px-4",
                     "chip": "h-6 gap-1 px-2 text-caption",
                     "row": "h-auto w-full flex-col items-stretch justify-start gap-1.5 rounded-none px-4 pt-3 pb-3 text-left font-normal whitespace-normal",
                     "inline": "h-auto p-0",
                     "icon": "size-10",
                     "icon-xs": "size-7 [&_svg:not([class*='size-'])]:size-3.5",
                     "icon-sm": "size-8",
                     "icon-lg": "size-11"
                 }
             },
             "defaultVariants": {"variant": "default", "size": "default"}
         }
     ),
     _buttonExcludeKeys: list[str] = [
         "className",
         "variant",
         "size",
         "asChild",
         "children"
     ];

def:pub Button(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    size = props["size"] or "default";
    asChild = props["asChild"] or False;

    restProps = {};
    for key in Object.keys(props) {  # jac:ignore[W6001]
        if key not in _buttonExcludeKeys {
            restProps[key] = props[key];
        }
    }

    computedClass = cn(
        _buttonVariants.call(
            None, {"variant": variant, "size": size, "className": props["className"]}
        )
    );

    if asChild {
        return
            <Slot.Root
                data-slot="button"
                data-variant={variant}
                data-size={size}
                className={computedClass}
                {**restProps}
            >
                {props["children"]}
            </Slot.Root>;
    }

    return
        <button
            data-slot="button"
            data-variant={variant}
            data-size={size}
            className={computedClass}
            {**restProps}
        >
            {props["children"]}
        </button>;
}

def:pub buttonVariants -> any {
    return _buttonVariants;
}
