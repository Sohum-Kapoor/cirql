"""Appearance sheet: Light / Dark / System (SOH-206). OWNER: Person B.

Opened from the home header's overflow menu. The choice is applied to <html> and
persisted immediately (lib/theme); System removes the override and follows the
OS. Owns only the selected mode; the caller owns `open`.
"""

import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody }
import from ..ui.tabs { Tabs, TabsList, TabsTrigger }
import from ...lib.theme { stored_theme, set_theme }
import from .DataPanel { DataPanel }
import from .AboutPanel { AboutPanel }

def:pub AppearanceSheet(
    open: bool,
    onOpenChange: Callable[[bool], None],
    onDeleted: Callable[[], None] | None = None
) -> JsxElement {
    has mode: str = stored_theme();

    def change(value: str) -> None {
        mode = value;
        set_theme(value);
    }

    def deleted() {
        if onDeleted {
            onDeleted();
        }
    }

    return
        <Sheet open={open} onOpenChange={onOpenChange}>
            <SheetContent aria-label="Appearance">
                <SheetHeader>
                    <SheetTitle>Appearance</SheetTitle>
                    <SheetDescription>System follows your phone. Your choice is kept on this device.</SheetDescription>
                </SheetHeader>
                <SheetBody>
                    <Tabs value={mode} onValueChange={change}>
                        <TabsList aria-label="Theme" className="w-full">
                            <TabsTrigger value="light">Light</TabsTrigger>
                            <TabsTrigger value="dark">Dark</TabsTrigger>
                            <TabsTrigger value="system">System</TabsTrigger>
                        </TabsList>
                    </Tabs>
                    <DataPanel onDeleted={deleted} />
                    <AboutPanel />
                </SheetBody>
            </SheetContent>
        </Sheet>;
}
