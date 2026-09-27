"""AboutPanel (SOH-226): "How Cirql works" — plain-sentence explanation of what
Cirql is, what leaves the phone, the exchange flow step by step, and the
product rules that never change. OWNER: Person B.

Mounted inside AppearanceSheet's footer row, below every accordion-style
section (Appearance / My card / Data / Danger zone): the trigger is styled to
sit flush as a plain footer link (no card border) next to Privacy and Send
feedback, but it's still the same disclosure — the content still expands in
place (same pattern person/PersonSheet.cl.jac's PersonSection uses). Fully
self-contained: owns its own open/closed state, calls nothing on the server,
takes no props. `today_build_line()` is exported separately so the footer's
own always-visible version line (outside this accordion) can reuse the same
date logic without a second "Built with…" paragraph inside the collapsed
content.
"""

import from ..ui.collapsible { Collapsible, CollapsibleTrigger, CollapsibleContent }
import from ..ui.button { buttonVariants }
import from ..ui.icons { ChevronRightIcon }
import from ...lib.utils { cn }
import from ...lib.text { today_month_day }

"""The page's <title> ("Cirql"), falling back if it's ever empty."""
def _page_title() -> str {
    t: any = document.title;  # jac:ignore[W2001]
    s: str = String(t);  # jac:ignore[W2001]
    return s or "Cirql";
}

""""Cirql · build Sep 27" — the footer's always-visible version line
(SOH-226/SOH-232), outside any accordion. Short local date, never ISO."""
def:pub today_build_line() -> str {
    return _page_title() + " · build " + today_month_day();
}

def:pub AboutPanel() -> JsxElement {
    return
        <Collapsible className="overflow-hidden rounded-md">
            <CollapsibleTrigger
                className={cn(
                    buttonVariants().call(None, {"variant": "ghost", "size": "row"}),
                    "flex-row items-center justify-between rounded-md pt-2 pb-2 pl-1 pr-1 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50 [&[data-state=open]>span>svg]:rotate-90"
                )}
            >
                <span className="flex items-center gap-1.5 text-body-sm">
                    How Cirql works
                    <ChevronRightIcon className="size-4 text-muted-foreground transition-transform" />
                </span>
            </CollapsibleTrigger>
            <CollapsibleContent>
                <div className="flex flex-col gap-4 border-t border-border pt-3 pb-3 pl-4 pr-4 text-body-sm">
                    <section className="flex flex-col gap-1">
                        <h3 className="text-eyebrow text-muted-foreground">What Cirql is</h3>
                        <p>
                            Cirql is a relationship graph you talk into. Every fact, want, and
                            promise points back at the words you said. Tap a source chip to
                            see them.
                        </p>
                    </section>

                    <section className="flex flex-col gap-1">
                        <h3 className="text-eyebrow text-muted-foreground">What leaves your device</h3>
                        <p>
                            Your notes go to Gemini to be read, and the audio goes to a
                            transcription service. Nothing is sent to any person. Your graph
                            is isolated by construction.
                        </p>
                        <p>
                            Across accounts, the only thing that ever crosses is a card you
                            wrote, granted read-only to one specific person, and, in your
                            friends' asks, a need, one line about you, and your handle. Blinded
                            identity tokens (hashes, not names) let two friends' replies be
                            recognized as the same person without a name crossing.
                        </p>
                    </section>

                    <section className="flex flex-col gap-1">
                        <h3 className="text-eyebrow text-muted-foreground">Asking your network, step by step</h3>
                        <ol className="flex list-decimal flex-col gap-0.5 pl-5">
                            <li>You ask.</li>
                            <li>Cirql searches only your friend's own graph and answers with a count.</li>
                            <li>The friend approves.</li>
                            <li>The contact opts in.</li>
                            <li>A card is revealed to you.</li>
                            <li>You claim it.</li>
                        </ol>
                        <p className="text-muted-foreground">A human taps at every step. Nothing sends.</p>
                    </section>

                    <section className="flex flex-col gap-1">
                        <h3 className="text-eyebrow text-muted-foreground">What never happens</h3>
                        <ul className="flex list-disc flex-col gap-0.5 pl-5">
                            <li>Relationships never decay.</li>
                            <li>Nobody gets a score.</li>
                            <li>Relevance belongs to a goal, not a person.</li>
                            <li>No LinkedIn or platform scraping.</li>
                        </ul>
                    </section>

                    <section className="flex flex-col gap-1">
                        <h3 className="text-eyebrow text-muted-foreground">Your data</h3>
                        <p>
                            Export everything as one JSON file. Archive instead of delete.
                            Delete my data removes everything. A note you delete takes only
                            the claims it alone supported.
                            {" "}
                            <a href="/static/privacy.html" className="underline underline-offset-2 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-sm">Read the privacy page</a>
                        </p>
                    </section>

                    <p className="text-caption text-muted-foreground">
                        Built with Jac (walkers on a graph), Gemini, and ElevenLabs.
                    </p>
                </div>
            </CollapsibleContent>
        </Collapsible>;
}
