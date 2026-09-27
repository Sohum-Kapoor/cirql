"""Bottom tab bar — Home · Inbox · People + the Capture action (SOH-213; the Asks
tab became Inbox in SOH-224: agent suggestions + friends' asks + your asks). OWNER: Person B.

Fixed to the bottom, safe-area aware (`padding-bottom: env(safe-area-inset-bottom)`).
Linear style: hairline top border, ink-subtle icons, the active tab in ink with a
medium-weight label; every target is >= 44px tall.

Capture is the bar's trailing primary action rather than a full-width button
stacked above the bar: at 375px three tabs cannot flank a centered action
symmetrically, and a stacked button doubles the fixed chrome (~124px vs 56px).
The trailing slot keeps Capture one tap away on every tab, under the thumb.

At `lg:` and up (SOH-234) the bottom bar is replaced by a fixed left rail,
~14rem wide, icons + labels stacked vertically Linear-style, with Capture as
the rail's primary button. Below `lg:` nothing here changes — the two navs
are `lg:hidden` / `hidden lg:flex` toggles of the same markup, so the phone
stays pixel-identical.
"""

import from ..ui.button { Button }
import from ..ui.icons { MicIcon }
import from ...lib.utils { cn }

def _svg(className: str, children: any) -> JsxElement {
    return
        <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
            className={cn("size-5", className)}
        >
            {children}
        </svg>;
}

def:pub HomeIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <path key="a" d="M3 10.5 12 3l9 7.5" />,
                <path key="b" d="M5 9.5V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.5" />
            ]
        );
}

def:pub InboxIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <path key="a" d="M4 13h4l1.5 3h5L16 13h4" />,
                <path key="b" d="M5.5 5h13L21 13v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-5z" />
            ]
        );
}

def:pub PeopleIcon(className: str = "") -> JsxElement {
    return
        _svg(
            className,
            [
                <circle key="a" cx="9" cy="8" r="3.5" />,
                <path key="b" d="M2.5 20c.8-3.4 3.3-5.5 6.5-5.5s5.7 2.1 6.5 5.5" />,
                <path key="c" d="M16 4.8a3.5 3.5 0 0 1 0 6.4" />,
                <path key="d" d="M18 14.8c1.8.7 3 2.5 3.5 5.2" />
            ]
        );
}

def:pub TabButton(
    value: str,
    label: str,
    active: bool,
    badge: int,
    onPick: Callable[[str], None],
    children: any = None
) -> JsxElement {
    def handle(e: MouseEvent) {
        onPick(value);
    }

    badge_text: str = ("9+" if badge > 9 else str(badge)) if badge > 0 else "";
    return
        <button
            type="button"
            data-tab={value}
            aria-current={"page" if active else None}
            aria-label={label + (" (" + badge_text + " new)" if badge_text else "")}
            onClick={handle}
            className={cn(
                "relative flex min-h-12 min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-md outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring/50",
                "text-foreground" if active else "text-muted-foreground hover:text-foreground"
            )}
        >
            <span className="relative">
                {children}
                {badge_text and
                    <span
                        aria-hidden="true"
                        className="absolute -top-1.5 -right-2.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-primary pl-1 pr-1 text-[10px] font-semibold leading-none tabular-nums text-primary-foreground ring-2 ring-background"
                    >
                        {badge_text}
                    </span>}
            </span>
            <span className={cn("text-[11px] leading-tight", "font-medium" if active else "")}>{label}</span>
        </button>;
}

def:pub RailButton(
    value: str,
    label: str,
    active: bool,
    badge: int,
    onPick: Callable[[str], None],
    children: any = None
) -> JsxElement {
    def handle(e: MouseEvent) {
        onPick(value);
    }

    badge_text: str = ("9+" if badge > 9 else str(badge)) if badge > 0 else "";
    return
        <button
            type="button"
            data-tab={value}
            aria-current={"page" if active else None}
            aria-label={label + (" (" + badge_text + " new)" if badge_text else "")}
            onClick={handle}
            className={cn(
                "flex w-full items-center gap-3 rounded-md px-3 py-2 text-body-sm outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring/50",
                "bg-accent text-foreground font-medium" if active else "text-muted-foreground hover:bg-accent/50 hover:text-foreground"
            )}
        >
            {children}
            <span className="flex-1 text-left">{label}</span>
            {badge_text and
                <span
                    aria-hidden="true"
                    className="flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-semibold leading-none tabular-nums text-primary-foreground"
                >
                    {badge_text}
                </span>}
        </button>;
}

"""The `lg:` left rail on its own (SOH-234 follow-up): Capture, Review, Request
and Ask are full-page views with no bottom tab bar of their own, so they render
this directly (instead of the full `TabBar`) to pick up the rail at `lg:`
without adding the phone bottom bar those views intentionally don't have.
Identical markup to the rail half of `TabBar` below, kept in sync by hand
since a shared render is more risk than the duplication is at ~25 lines."""
def:pub DesktopRail(
    tab: str,
    onTab: Callable[[str], None],
    onCapture: Callable[[], None],
    inbox_badge: int = 0
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    return
        <nav
            aria-label="Main"
            className="hidden lg:fixed lg:inset-y-0 lg:left-0 lg:z-20 lg:flex lg:w-56 lg:flex-col lg:gap-4 lg:border-r lg:bg-background lg:p-4"
        >
            <div className="px-3 pt-1 text-subhead font-semibold">Cirql</div>
            <div className="flex flex-col gap-1">
                <RailButton value="home" label="Home" active={tab == "home"} badge={0} onPick={onTab}>
                    <HomeIcon />
                </RailButton>
                <RailButton value="inbox" label="Inbox" active={tab == "inbox"} badge={inbox_badge} onPick={onTab}>
                    <InboxIcon />
                </RailButton>
                <RailButton value="people" label="People" active={tab == "people"} badge={0} onPick={onTab}>
                    <PeopleIcon />
                </RailButton>
            </div>
            <Button className="mt-2 w-full justify-center rounded-lg" aria-label="Capture a conversation" onClick={handle_capture}>
                <MicIcon className="size-4" />
                Capture
            </Button>
        </nav>;
}

def:pub TabBar(
    tab: str,
    onTab: Callable[[str], None],
    onCapture: Callable[[], None],
    inbox_badge: int = 0
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    return
        <div>
            <nav
                aria-label="Main"
                className="fixed inset-x-0 bottom-0 z-20 border-t bg-background/90 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden"
            >
                <div className="mx-auto flex h-14 w-full max-w-md items-center gap-1 pl-4 pr-4">
                    <TabButton value="home" label="Home" active={tab == "home"} badge={0} onPick={onTab}>
                        <HomeIcon />
                    </TabButton>
                    <TabButton value="inbox" label="Inbox" active={tab == "inbox"} badge={inbox_badge} onPick={onTab}>
                        <InboxIcon />
                    </TabButton>
                    <TabButton value="people" label="People" active={tab == "people"} badge={0} onPick={onTab}>
                        <PeopleIcon />
                    </TabButton>
                    <Button size="lg" className="ml-1 rounded-lg" aria-label="Capture a conversation" onClick={handle_capture}>
                        <MicIcon className="size-4" />
                        Capture
                    </Button>
                </div>
            </nav>
            <DesktopRail tab={tab} onTab={onTab} onCapture={onCapture} inbox_badge={inbox_badge} />
        </div>;
}
