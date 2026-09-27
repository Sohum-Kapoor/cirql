"""Settings sheet (SOH-206/226): account header, then Appearance / My card /
Data / Danger zone, then a flat footer row. OWNER: Person B.

Opened from the home header's overflow menu. The header carries identity (an
initials avatar, the card's name, and its handle as a muted line — the
runtime exposes no email accessor, `@jac/runtime`'s own exports are just
`jacLogin`/`jacSignup`/`jacLogout`/`jacIsLoggedIn`, so email is omitted
rather than guessed at). Sections below are eyebrow-headed cards in a fixed
order (Danger zone's own eyebrow lives inside `DataPanel`, which now renders
Data's two export cards and the merged Danger zone card together — same
shared delete/export state, SOH-226). The footer sits OUTSIDE every section:
"How Cirql works" (still `AboutPanel`'s own collapsible, just restyled flush
so its trigger reads as a plain row here), a Privacy link, a feedback mailto,
and the version/build line, always visible (not buried in the collapsed
content any more).

Owns only the selected theme mode and the header's own card read; the caller
owns `open`.
"""

import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody }
import from ..ui.tabs { Tabs, TabsList, TabsTrigger }
import from ..ui.skeleton { Skeleton }
import from ..ui.avatar { Avatar }
import from ..ui.icons { ChevronRightIcon }
import from ...lib.theme { stored_theme, set_theme }
import from ..card.CardEditor { CardEditor }
import from ..api_card { my_card }
import from .DataPanel { DataPanel }
import from .AboutPanel { AboutPanel, today_build_line }

glob _FEEDBACK_MAILTO: str = "mailto:hello@cirql.app";

"""The card's own name, or a call-to-action when nobody's set one yet (the
placeholder is literally "me" until the card editor's first save)."""
def _display_name(name: str) -> str {
    return name if (name and name != "me") else "Add your name";
}

def:pub SettingsHeader(name: str, handle: str) -> JsxElement {
    return
        <div className="flex items-center gap-3 pb-1">
            <Avatar name={name} size="lg" />
            <div className="flex min-w-0 flex-col">
                <span className="truncate text-card-title font-medium">{_display_name(name)}</span>
                {handle and <span className="truncate text-caption text-muted-foreground">{"@" + handle}</span>}
            </div>
        </div>;
}

def:pub SettingsFooterLink(label: str, href: str) -> JsxElement {
    return
        <a
            href={href}
            className="flex items-center justify-between gap-2 rounded-md pt-2 pb-2 pl-1 pr-1 text-body-sm outline-none transition-colors hover:bg-secondary focus-visible:ring-2 focus-visible:ring-ring/50"
        >
            {label}
            <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />
        </a>;
}

def:pub AppearanceSheet(
    open: bool,
    onOpenChange: Callable[[bool], None],
    onDeleted: Callable[[], None] | None = None
) -> JsxElement {
    has mode: str = stored_theme(),
        header_loaded: bool = False,
        card_name: str = "",
        card_handle: str = "";

    def change(value: str) -> None {
        mode = value;
        set_theme(value);
    }

    def deleted() {
        if onDeleted {
            onDeleted();
        }
    }

    async def load_header -> None {
        card: dict | None = await my_card();
        if card is not None {
            card_name = (card["name"] or "") as str;
            card_handle = (card["handle"] or "") as str;
        }
        header_loaded = True;
    }

    async can with entry {
        await load_header();
    }

    return
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent aria-label="Settings">
                <SheetHeader>
                    <SheetTitle className="sr-only">Settings</SheetTitle>
                    <SheetDescription className="sr-only">Your account, appearance, and data.</SheetDescription>
                    {if not header_loaded {
                        <div role="status" aria-label="Loading your account" className="flex items-center gap-3 pb-1">
                            <Skeleton className="size-12 shrink-0 rounded-full" />
                            <Skeleton className="h-5 w-32" />
                        </div>
                    } else {
                        <SettingsHeader name={card_name} handle={card_handle} />
                    }}
                </SheetHeader>
                <SheetBody>
                    <h3 className="text-eyebrow text-muted-foreground">Appearance</h3>
                    <Tabs value={mode} onValueChange={change}>
                        <TabsList aria-label="Theme" className="w-full">
                            <TabsTrigger value="light">Light</TabsTrigger>
                            <TabsTrigger value="dark">Dark</TabsTrigger>
                            <TabsTrigger value="system">System</TabsTrigger>
                        </TabsList>
                    </Tabs>
                    <p className="text-caption text-muted-foreground">
                        System follows your phone. Your choice is kept on this device.
                    </p>

                    <h3 className="text-eyebrow text-muted-foreground">My card</h3>
                    <CardEditor />

                    <h3 className="text-eyebrow text-muted-foreground">Data</h3>
                    <DataPanel onDeleted={deleted} />

                    <div className="flex flex-col gap-0.5 border-t border-border pt-3">
                        <AboutPanel />
                        <SettingsFooterLink label="Privacy" href="/static/privacy.html" />
                        <SettingsFooterLink label="Send feedback" href={_FEEDBACK_MAILTO} />
                        <p className="pt-1 pl-1 text-caption text-muted-foreground">{today_build_line()}</p>
                    </div>
                </SheetBody>
            </SheetContent>
        </Sheet>;
}
