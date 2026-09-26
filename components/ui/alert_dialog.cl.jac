import from "radix-ui" { AlertDialog as AlertDialogPrimitive }
import from ...lib.utils { cn }
import from .button { buttonVariants }

# jac-shadcn AlertDialog (`jac add --shadcn alert-dialog`, nova), restyled
# (SOH-206): popover surface, hairline, rounded.lg, overlay token. Action /
# Cancel are the Radix primitives styled with buttonVariants (the generated
# `<Button asChild>` wrapper leaked a stray grid/text-left class list).

def:pub AlertDialog(props: any) -> JsxElement {
    return <AlertDialogPrimitive.Root data-slot="alert-dialog" {**props}/>;
}

def:pub AlertDialogTrigger(props: any) -> JsxElement {
    return <AlertDialogPrimitive.Trigger data-slot="alert-dialog-trigger" {**props}/>;
}

def:pub AlertDialogPortal(props: any) -> JsxElement {
    return <AlertDialogPrimitive.Portal data-slot="alert-dialog-portal" {**props}/>;
}

def:pub AlertDialogOverlay(props: any) -> JsxElement {
    return
        <AlertDialogPrimitive.Overlay
            {**props}
            data-slot="alert-dialog-overlay"
            className={cn("fixed inset-0 isolate z-50 bg-overlay data-open:animate-in", props["className"])}
        />;
}

def:pub AlertDialogContent(props: any) -> JsxElement {
    size = props["size"] or "default";
    return
        <AlertDialogPortal>
            <AlertDialogOverlay/>
            <AlertDialogPrimitive.Content
                {**props}
                data-slot="alert-dialog-content"
                data-size={size}
                className={cn(
                    "group/alert-dialog-content fixed top-1/2 left-1/2 z-50 grid w-[calc(100%-2rem)] max-w-sm -translate-x-1/2 -translate-y-1/2 gap-4 rounded-lg border border-border bg-popover p-4 text-popover-foreground shadow-edge outline-none data-open:animate-in",
                    props["className"]
                )}
            />
        </AlertDialogPortal>;
}

def:pub AlertDialogHeader(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="alert-dialog-header"
            className={cn("flex flex-col gap-1.5 text-left", props["className"])}
        />;
}

def:pub AlertDialogFooter(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="alert-dialog-footer"
            className={cn("grid grid-cols-2 gap-2", props["className"])}
        />;
}

def:pub AlertDialogTitle(props: any) -> JsxElement {
    return
        <AlertDialogPrimitive.Title
            {**props}
            data-slot="alert-dialog-title"
            className={cn("text-subhead font-medium", props["className"])}
        />;
}

def:pub AlertDialogDescription(props: any) -> JsxElement {
    return
        <AlertDialogPrimitive.Description
            {**props}
            data-slot="alert-dialog-description"
            className={cn("text-body-sm text-muted-foreground", props["className"])}
        />;
}

def:pub AlertDialogAction(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    size = props["size"] or "default";
    return
        <AlertDialogPrimitive.Action
            {**props}
            data-slot="alert-dialog-action"
            className={cn(buttonVariants().call(None, {"variant": variant, "size": size}), props["className"])}
        />;
}

def:pub AlertDialogCancel(props: any) -> JsxElement {
    variant = props["variant"] or "outline";
    size = props["size"] or "default";
    return
        <AlertDialogPrimitive.Cancel
            {**props}
            data-slot="alert-dialog-cancel"
            className={cn(buttonVariants().call(None, {"variant": variant, "size": size}), props["className"])}
        />;
}
