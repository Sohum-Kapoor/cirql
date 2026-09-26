"""Inline SVG icons for the jac-shadcn primitives (SOH-206). OWNER: Person B.

`jac add --shadcn` wires dialog/sheet/dropdown-menu to @hugeicons/*, which is not
in jac.toml; these stroke icons (currentColor, 24px grid) stand in so no npm
dependency is added. Size comes from the parent (`[&_svg]:size-4`) or className.
"""

import from ...lib.utils { cn }

def _svg(className: any, children: any) -> JsxElement {
    return
        <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className={cn("size-4", className)}
        >
            {children}
        </svg>;
}

def:pub XIcon(className: str = "") -> JsxElement {
    return _svg(className, [<path key="a" d="M18 6 6 18" />, <path key="b" d="m6 6 12 12" />]);
}

def:pub CheckIcon(className: str = "") -> JsxElement {
    return _svg(className, [<path key="a" d="M20 6 9 17l-5-5" />]);
}

def:pub ChevronRightIcon(className: str = "") -> JsxElement {
    return _svg(className, [<path key="a" d="m9 18 6-6-6-6" />]);
}

def:pub ChevronDownIcon(className: str = "") -> JsxElement {
    return _svg(className, [<path key="a" d="m6 9 6 6 6-6" />]);
}

def:pub ChevronLeftIcon(className: str = "") -> JsxElement {
    return _svg(className, [<path key="a" d="m15 18-6-6 6-6" />]);
}

def:pub MoreIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <circle key="a" cx="5" cy="12" r="1" />,
                <circle key="b" cx="12" cy="12" r="1" />,
                <circle key="c" cx="19" cy="12" r="1" />
            ]
        );
}

def:pub MicIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <rect key="a" x="9" y="3" width="6" height="11" rx="3" />,
                <path key="b" d="M5 11a7 7 0 0 0 14 0" />,
                <path key="c" d="M12 18v3" />
            ]
        );
}

def:pub QuoteIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <path key="a" d="M7 7h4v4c0 3-1.5 5-4 6" />,
                <path key="b" d="M14 7h4v4c0 3-1.5 5-4 6" />
            ]
        );
}

def:pub PlusIcon(className: str = "") -> JsxElement {
    return _svg(className, [<path key="a" d="M12 5v14" />, <path key="b" d="M5 12h14" />]);
}
