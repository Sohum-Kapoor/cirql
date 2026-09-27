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

def:pub PencilIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <path key="a" d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />,
                <path key="b" d="m15 5 3 3" />
            ]
        );
}

def:pub TrashIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <path key="a" d="M3 6h18" />,
                <path key="b" d="M8 6V4h8v2" />,
                <path key="c" d="M19 6l-1 14H6L5 6" />
            ]
        );
}

def:pub StopIcon(className: str = "") -> JsxElement {
    return _svg(className, [<rect key="a" x="6" y="6" width="12" height="12" rx="2" />]);
}

# SSO brand marks (SOH-237). Brand logos, not stroke glyphs - own <svg>, not
# the currentColor `_svg` helper: Google's "G" is fixed 4-color; Apple is a
# solid currentColor silhouette so it inverts with the button's text color.
def:pub GoogleIcon(className: str = "size-4") -> JsxElement {
    return
        <svg aria-hidden="true" viewBox="0 0 24 24" className={cn("size-4", className)}>
            <path
                key="blue"
                fill="#4285F4"
                d="M23.49 12.27c0-.79-.07-1.54-.19-2.27H12v4.51h6.44c-.28 1.48-1.13 2.73-2.4 3.58v2.98h3.86c2.26-2.08 3.56-5.14 3.56-8.8z"
            />
            <path
                key="green"
                fill="#34A853"
                d="M12 24c3.24 0 5.95-1.08 7.93-2.92l-3.86-2.98c-1.07.72-2.44 1.15-4.07 1.15-3.13 0-5.78-2.11-6.73-4.96H1.29v3.09C3.26 21.3 7.31 24 12 24z"
            />
            <path
                key="yellow"
                fill="#FBBC05"
                d="M5.27 14.29c-.25-.72-.38-1.49-.38-2.29s.14-1.57.38-2.29V6.62H1.29A11.96 11.96 0 0 0 0 12c0 1.94.47 3.78 1.29 5.38l3.98-3.09z"
            />
            <path
                key="red"
                fill="#EA4335"
                d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.7 1.29 6.62l3.98 3.09C6.22 6.86 8.87 4.75 12 4.75z"
            />
        </svg>;
}

def:pub AppleIcon(className: str = "size-4") -> JsxElement {
    return
        <svg
            aria-hidden="true"
            viewBox="0 0 384 512"
            fill="currentColor"
            className={cn("size-4", className)}
        >
            <path
                key="a"
                d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"
            />
        </svg>;
}
