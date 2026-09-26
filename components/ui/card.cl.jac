import from ...lib.utils { cn }

# jac-shadcn Card, restyled to DESIGN.md `feature-card` (SOH-206): surface-1,
# 1px hairline, rounded.lg 12px, top-edge highlight. Interior padding is 16px
# (the phone gutter) rather than the desktop 24px.
def:pub Card(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    size = props["size"] or "default";
    return
        <div
            {**attrs}
            data-slot="card"
            data-size={size}
            className={cn(
                "group/card flex flex-col gap-4 overflow-hidden rounded-lg border border-border bg-card pt-4 pb-4 text-body-sm text-card-foreground shadow-edge has-data-[slot=card-footer]:pb-0 data-[size=sm]:gap-3 data-[size=sm]:pt-3 data-[size=sm]:pb-3 data-[size=sm]:has-data-[slot=card-footer]:pb-0",
                props["className"]
            )}
        />;
}

def:pub CardHeader(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="card-header"
            className={cn(
                "group/card-header @container/card-header grid auto-rows-min items-start gap-1 pl-4 pr-4 group-data-[size=sm]/card:pl-3 group-data-[size=sm]/card:pr-3 has-data-[slot=card-action]:grid-cols-[1fr_auto] has-data-[slot=card-description]:grid-rows-[auto_auto]",
                props["className"]
            )}
        />;
}

def:pub CardTitle(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="card-title"
            className={cn(
                "text-subhead font-medium group-data-[size=sm]/card:text-body",
                props["className"]
            )}
        />;
}

def:pub CardDescription(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="card-description"
            className={cn("text-body-sm text-muted-foreground", props["className"])}
        />;
}

def:pub CardAction(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="card-action"
            className={cn(
                "col-start-2 row-span-2 row-start-1 self-start justify-self-end",
                props["className"]
            )}
        />;
}

def:pub CardContent(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="card-content"
            className={cn(
                "pl-4 pr-4 group-data-[size=sm]/card:pl-3 group-data-[size=sm]/card:pr-3",
                props["className"]
            )}
        />;
}

def:pub CardFooter(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="card-footer"
            className={cn(
                "flex items-center border-t bg-secondary/50 p-4 group-data-[size=sm]/card:p-3",
                props["className"]
            )}
        />;
}
