import from "radix-ui" { Tabs as TabsPrimitive }
import from "class-variance-authority" { cva }
import from ...lib.utils { cn }

# jac-shadcn Tabs (`jac add --shadcn tabs`, nova), restyled to DESIGN.md
# `pricing-tab-default` / `pricing-tab-selected` (SOH-206): a pill track;
# unselected = ink-subtle on no fill, selected = surface-2 lift + ink. 36px
# track (DESIGN: pill tabs >= 36px tap height).
glob _tabsListVariants: any = cva(
         "group/tabs-list inline-flex w-fit items-center justify-center text-muted-foreground group-data-vertical/tabs:h-fit group-data-vertical/tabs:flex-col",
         {
             "variants": {
                 "variant": {
                     "default": "h-10 gap-1 rounded-full border border-border bg-background p-1",
                     "line": "gap-1 rounded-none bg-transparent"
                 }
             },
             "defaultVariants": {"variant": "default"}
         }
     );

def:pub Tabs(props: any) -> JsxElement {
    orientation = props["orientation"] or "horizontal";
    return
        <TabsPrimitive.Root
            {**props}
            data-slot="tabs"
            data-orientation={orientation}
            className={cn("group/tabs flex gap-3 data-horizontal:flex-col", props["className"])}
        />;
}

def:pub TabsList(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    return
        <TabsPrimitive.List
            {**props}
            data-slot="tabs-list"
            data-variant={variant}
            className={cn(_tabsListVariants.call(None, {"variant": variant}), props["className"])}
        />;
}

def:pub TabsTrigger(props: any) -> JsxElement {
    return
        <TabsPrimitive.Trigger
            {**props}
            data-slot="tabs-trigger"
            className={cn(
                "relative inline-flex h-full flex-1 items-center justify-center gap-1.5 whitespace-nowrap rounded-full border border-transparent pl-3.5 pr-3.5 text-button text-muted-foreground outline-none transition-colors hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 group-data-vertical/tabs:w-full group-data-vertical/tabs:justify-start [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
                "data-active:border-border data-active:bg-secondary data-active:text-foreground",
                "group-data-[variant=line]/tabs-list:rounded-none group-data-[variant=line]/tabs-list:data-active:border-transparent group-data-[variant=line]/tabs-list:data-active:bg-transparent",
                "after:absolute after:opacity-0 after:transition-opacity group-data-horizontal/tabs:after:inset-x-0 group-data-horizontal/tabs:after:bottom-[-5px] group-data-horizontal/tabs:after:h-0.5 after:bg-foreground group-data-[variant=line]/tabs-list:data-active:after:opacity-100",
                props["className"]
            )}
        />;
}

def:pub TabsContent(props: any) -> JsxElement {
    # SOH-226: Radix only mounts the active TabsContent (no forceMount here),
    # so switching tabs always mounts a fresh DOM node - `animate-tab-in`
    # (assets/main.css, a 150ms fade; no data-state gate needed) plays on
    # every mount without needing to track a "just switched" flag.
    return
        <TabsPrimitive.Content
            {**props}
            data-slot="tabs-content"
            className={cn("flex-1 text-body-sm outline-none animate-tab-in", props["className"])}
        />;
}

def:pub tabsListVariants -> any {
    return _tabsListVariants;
}
