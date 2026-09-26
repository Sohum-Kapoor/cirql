import from ...lib.utils { cn }

# jac-shadcn Skeleton (`jac add --shadcn skeleton`), on the surface-3 step.
def:pub Skeleton(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="skeleton"
            className={cn("animate-pulse rounded-xs bg-muted", props["className"])}
        />;
}
