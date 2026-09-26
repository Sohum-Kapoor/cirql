import from "radix-ui" { DropdownMenu as DropdownMenuPrimitive }
import from ...lib.utils { cn }
import from .icons { CheckIcon, ChevronRightIcon }

# jac-shadcn DropdownMenu (`jac add --shadcn dropdown-menu`, nova), restyled
# (SOH-206): popover surface + hairline-strong (DESIGN elevation 3), rounded.md
# items with a surface-2 highlight, 40px touch rows. @hugeicons Tick02Icon /
# ArrowRight01Icon -> inline CheckIcon / ChevronRightIcon.

glob _ITEM: str = "group/dropdown-menu-item relative flex min-h-10 cursor-default select-none items-center gap-2 rounded-sm pl-2.5 pr-2.5 text-body-sm outline-hidden focus:bg-secondary focus:text-foreground data-disabled:pointer-events-none data-disabled:opacity-50 data-inset:pl-8 data-[variant=destructive]:text-destructive data-[variant=destructive]:focus:bg-destructive/10 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
     _PANEL: str = "z-50 min-w-40 overflow-x-hidden overflow-y-auto rounded-md border border-border-strong bg-popover p-1 text-popover-foreground shadow-lg shadow-edge data-open:animate-in";

def:pub DropdownMenu(props: any) -> JsxElement {
    return <DropdownMenuPrimitive.Root data-slot="dropdown-menu" {**props}/>;
}

def:pub DropdownMenuPortal(props: any) -> JsxElement {
    return <DropdownMenuPrimitive.Portal data-slot="dropdown-menu-portal" {**props}/>;
}

def:pub DropdownMenuTrigger(props: any) -> JsxElement {
    return <DropdownMenuPrimitive.Trigger data-slot="dropdown-menu-trigger" {**props}/>;
}

def:pub DropdownMenuContent(props: any) -> JsxElement {
    align = props["align"] or "start";
    sideOffset = props["sideOffset"] or 4;
    return
        <DropdownMenuPrimitive.Portal>
            <DropdownMenuPrimitive.Content
                {**props}
                data-slot="dropdown-menu-content"
                sideOffset={sideOffset}
                align={align}
                className={cn(
                    _PANEL,
                    "max-h-(--radix-dropdown-menu-content-available-height) origin-(--radix-dropdown-menu-content-transform-origin)",
                    props["className"]
                )}
            />
        </DropdownMenuPrimitive.Portal>;
}

def:pub DropdownMenuGroup(props: any) -> JsxElement {
    return <DropdownMenuPrimitive.Group data-slot="dropdown-menu-group" {**props}/>;
}

def:pub DropdownMenuItem(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    return
        <DropdownMenuPrimitive.Item
            {**props}
            data-slot="dropdown-menu-item"
            data-inset={props["inset"]}
            data-variant={variant}
            className={cn(_ITEM, props["className"])}
        />;
}

def:pub DropdownMenuCheckboxItem(props: any) -> JsxElement {
    return
        <DropdownMenuPrimitive.CheckboxItem
            {**props}
            data-slot="dropdown-menu-checkbox-item"
            data-inset={props["inset"]}
            className={cn(_ITEM, "pr-8", props["className"])}
            checked={props["checked"]}
        >
            <span
                className="pointer-events-none absolute right-2 flex items-center justify-center"
                data-slot="dropdown-menu-checkbox-item-indicator"
            >
                <DropdownMenuPrimitive.ItemIndicator>
                    <CheckIcon />
                </DropdownMenuPrimitive.ItemIndicator>
            </span>
            {props["children"]}
        </DropdownMenuPrimitive.CheckboxItem>;
}

def:pub DropdownMenuRadioGroup(props: any) -> JsxElement {
    return <DropdownMenuPrimitive.RadioGroup data-slot="dropdown-menu-radio-group" {**props}/>;
}

def:pub DropdownMenuRadioItem(props: any) -> JsxElement {
    return
        <DropdownMenuPrimitive.RadioItem
            {**props}
            data-slot="dropdown-menu-radio-item"
            data-inset={props["inset"]}
            className={cn(_ITEM, "pr-8", props["className"])}
        >
            <span
                className="pointer-events-none absolute right-2 flex items-center justify-center text-link"
                data-slot="dropdown-menu-radio-item-indicator"
            >
                <DropdownMenuPrimitive.ItemIndicator>
                    <CheckIcon />
                </DropdownMenuPrimitive.ItemIndicator>
            </span>
            {props["children"]}
        </DropdownMenuPrimitive.RadioItem>;
}

def:pub DropdownMenuLabel(props: any) -> JsxElement {
    return
        <DropdownMenuPrimitive.Label
            {**props}
            data-slot="dropdown-menu-label"
            data-inset={props["inset"]}
            className={cn("pt-1.5 pb-1 pl-2.5 pr-2.5 text-eyebrow text-muted-foreground data-inset:pl-8", props["className"])}
        />;
}

def:pub DropdownMenuSeparator(props: any) -> JsxElement {
    return
        <DropdownMenuPrimitive.Separator
            {**props}
            data-slot="dropdown-menu-separator"
            className={cn("-ml-1 -mr-1 mt-1 mb-1 h-px bg-border", props["className"])}
        />;
}

def:pub DropdownMenuShortcut(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <span
            {**attrs}
            data-slot="dropdown-menu-shortcut"
            className={cn("ml-auto text-caption tracking-widest text-muted-foreground", props["className"])}
        />;
}

def:pub DropdownMenuSub(props: any) -> JsxElement {
    return <DropdownMenuPrimitive.Sub data-slot="dropdown-menu-sub" {**props}/>;
}

def:pub DropdownMenuSubTrigger(props: any) -> JsxElement {
    return
        <DropdownMenuPrimitive.SubTrigger
            {**props}
            data-slot="dropdown-menu-sub-trigger"
            data-inset={props["inset"]}
            className={cn(_ITEM, "data-open:bg-secondary", props["className"])}
        >
            {props["children"]}
            <ChevronRightIcon className="ml-auto" />
        </DropdownMenuPrimitive.SubTrigger>;
}

def:pub DropdownMenuSubContent(props: any) -> JsxElement {
    return
        <DropdownMenuPrimitive.SubContent
            {**props}
            data-slot="dropdown-menu-sub-content"
            className={cn(_PANEL, "origin-(--radix-dropdown-menu-content-transform-origin)", props["className"])}
        />;
}
