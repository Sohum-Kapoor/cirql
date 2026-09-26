import from "radix-ui" { Dialog as SheetPrimitive }
import from ...lib.utils { cn }
import from .button { buttonVariants }
import from .icons { XIcon }

# jac-shadcn Sheet (`jac add --shadcn sheet`, nova), restyled (SOH-206):
# popover surface + hairline, rounded.xl top corners on the bottom sheet (the
# phone default here), a grab bar, safe-area bottom padding, overlay token.
# @hugeicons Cancel01Icon -> inline XIcon (no new npm dependency). The close
# control is a plain <button> styled with buttonVariants: Radix `asChild` needs
# a ref-forwarding child and the Jac Button is not one.

def:pub Sheet(props: any) -> JsxElement {
    return <SheetPrimitive.Root data-slot="sheet" {**props}/>;
}

def:pub SheetTrigger(props: any) -> JsxElement {
    return <SheetPrimitive.Trigger data-slot="sheet-trigger" {**props}/>;
}

def:pub SheetClose(props: any) -> JsxElement {
    return <SheetPrimitive.Close data-slot="sheet-close" {**props}/>;
}

def:pub SheetPortal(props: any) -> JsxElement {
    return <SheetPrimitive.Portal data-slot="sheet-portal" {**props}/>;
}

def:pub SheetOverlay(props: any) -> JsxElement {
    return
        <SheetPrimitive.Overlay
            {**props}
            data-slot="sheet-overlay"
            className={cn("fixed inset-0 z-50 bg-overlay data-open:animate-in", props["className"])}
        />;
}

def:pub SheetContent(props: any) -> JsxElement {
    side = props["side"] or "bottom";
    # default shown; only an explicit False hides it (`is None` misses JS undefined)
    showCloseButton = props["showCloseButton"] is not False;  # jac:ignore[W2075]
    return
        <SheetPortal>
            <SheetOverlay/>
            <SheetPrimitive.Content
                {**props}
                data-slot="sheet-content"
                data-side={side}
                className={cn(
                    "fixed z-50 flex flex-col gap-4 border-border bg-popover text-body-sm text-popover-foreground shadow-edge outline-none data-open:animate-in",
                    "data-[side=bottom]:inset-x-0 data-[side=bottom]:bottom-0 data-[side=bottom]:mx-auto data-[side=bottom]:max-h-[85svh] data-[side=bottom]:w-full data-[side=bottom]:max-w-md data-[side=bottom]:overflow-y-auto data-[side=bottom]:rounded-t-xl data-[side=bottom]:border-t data-[side=bottom]:border-l data-[side=bottom]:border-r data-[side=bottom]:pb-[max(16px,env(safe-area-inset-bottom))] data-[side=bottom]:data-open:animate-sheet-in",
                    "data-[side=top]:inset-x-0 data-[side=top]:top-0 data-[side=top]:border-b",
                    "data-[side=left]:inset-y-0 data-[side=left]:left-0 data-[side=left]:h-full data-[side=left]:w-3/4 data-[side=left]:border-r data-[side=left]:sm:max-w-sm",
                    "data-[side=right]:inset-y-0 data-[side=right]:right-0 data-[side=right]:h-full data-[side=right]:w-3/4 data-[side=right]:border-l data-[side=right]:sm:max-w-sm",
                    props["className"]
                )}
            >
                {side == "bottom" and
                    <div aria-hidden="true" className="mx-auto mt-2 h-1 w-9 shrink-0 rounded-full bg-border-strong" />}
                {props["children"]}
                {showCloseButton and
                    <SheetPrimitive.Close data-slot="sheet-close" asChild={True}>
                        <button
                            type="button"
                            className={cn(
                                buttonVariants().call(None, {"variant": "ghost", "size": "icon-sm"}),
                                "absolute top-3 right-3 text-muted-foreground"
                            )}
                        >
                            <XIcon />
                            <span className="sr-only">Close</span>
                        </button>
                    </SheetPrimitive.Close>}
            </SheetPrimitive.Content>
        </SheetPortal>;
}

def:pub SheetHeader(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="sheet-header"
            className={cn("flex flex-col gap-1 pt-2 pl-4 pr-12", props["className"])}
        />;
}

def:pub SheetBody(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="sheet-body"
            className={cn("flex flex-col gap-3 pl-4 pr-4", props["className"])}
        />;
}

def:pub SheetFooter(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="sheet-footer"
            className={cn("mt-auto flex flex-col gap-2 pl-4 pr-4", props["className"])}
        />;
}

def:pub SheetTitle(props: any) -> JsxElement {
    return
        <SheetPrimitive.Title
            {**props}
            data-slot="sheet-title"
            className={cn("text-card-title text-foreground", props["className"])}
        />;
}

def:pub SheetDescription(props: any) -> JsxElement {
    return
        <SheetPrimitive.Description
            {**props}
            data-slot="sheet-description"
            className={cn("text-body-sm text-muted-foreground", props["className"])}
        />;
}
