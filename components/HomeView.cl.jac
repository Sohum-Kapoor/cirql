"""Logged-in home: Capture action + the people you know. Stateless. OWNER: Person B."""

import from ".ui.button" { Button }
import from "..lib.text" { join_with }
sv import from ..schema { Person }

def:pub HomeView(
    people: list[Person],
    status: str,
    onRefresh: Callable[[], None],
    onLogout: Callable[[], None],
    onCapture: Callable[[], None]
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    def handle_refresh(e: MouseEvent) {
        onRefresh();
    }

    def handle_logout(e: MouseEvent) {
        onLogout();
    }

    return
        <div className="flex flex-col gap-4">
            <header className="flex items-center justify-between gap-2">
                <h1 className="text-base font-semibold tracking-tight">Cirql</h1>
                <div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={handle_refresh}>Refresh</Button>
                    <Button size="sm" variant="outline" onClick={handle_logout}>Log out</Button>
                </div>
            </header>
            <Button className="w-full" size="lg" onClick={handle_capture}>Capture a conversation</Button>
            <section className="flex flex-col gap-2">
                <div className="flex items-baseline justify-between">
                    <h2 className="text-sm font-medium">People you know</h2>
                    <span className="text-xs tabular-nums text-muted-foreground">{str(len(people))}</span>
                </div>
                {if len(people) == 0 {
                    <p className="rounded-md border border-dashed pt-4 pb-4 pl-3 pr-3 text-sm text-muted-foreground">
                        {"No one yet — "}
                        <button
                            type="button"
                            className="font-medium text-primary underline-offset-4 hover:underline"
                            onClick={handle_capture}
                        >
                            capture a conversation
                        </button>
                        {" to start."}
                    </p>
                } else {
                    <ul className="flex flex-col divide-y divide-border rounded-md border">
                        {for (idx, p) in enumerate(people) {
                            <li key={str(idx)} className="flex flex-col pt-2 pb-2 pl-3 pr-3">
                                <span className="text-sm">{p.name}</span>
                                {(p.title or p.org) and
                                    <span className="text-xs text-muted-foreground">
                                        {join_with([s for s in [p.title, p.org] if s], ", ")}
                                    </span>}
                            </li>
                        }}
                    </ul>
                }}
            </section>
            {status and <p className="text-xs text-muted-foreground">{status}</p>}
        </div>;
}
