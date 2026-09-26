"""Capture screen — write (or paste) what happened; Submit calls Capture. OWNER: Person B.

Stateless: the shell owns `text`, `kind` (debrief | paste), `pending`, `error`
and the Capture call. The mic is a visible placeholder for voice capture
(SOH-168) — disabled and labelled "soon", never a fake working control.
"""

import from "..ui.button" { Button }
import from "..ui.textarea" { Textarea }
import from "..ui.field" { Field, FieldLabel, FieldDescription }
import from ...lib.utils { cn }

glob _SEG_BASE: str = "flex-1 rounded-[5px] pt-1 pb-1 pl-3 pr-3 text-sm font-medium transition-colors disabled:opacity-50",
     _SEG_ON: str = "bg-background text-foreground shadow-sm ring-1 ring-border",
     _SEG_OFF: str = "text-muted-foreground hover:text-foreground";

def:pub CaptureForm(
    text: str,
    kind: str,
    pending: bool,
    error: str,
    onTextChange: Callable[[str], None],
    onKindChange: Callable[[str], None],
    onSubmit: Callable[[], None],
    onBack: Callable[[], None]
) -> JsxElement {
    def handle_change(e: ChangeEvent) {
        onTextChange(e.target.value);
    }

    def handle_debrief(e: MouseEvent) {
        onKindChange("debrief");
    }

    def handle_paste(e: MouseEvent) {
        onKindChange("paste");
    }

    def handle_submit(e: MouseEvent) {
        onSubmit();
    }

    def handle_back(e: MouseEvent) {
        onBack();
    }

    can_submit: bool = len(text.strip()) > 0 and not pending;
    hint: str = (
        "Write it the way you'd tell a friend. Cirql keeps the note and shows where every detail came from."
        if kind == "debrief"
        else "Paste notes, an email, or a list — one person per line works. Cirql keeps the original text."
    );

    return
        <div className="flex flex-col gap-4">
            <header className="flex items-center gap-2">
                <Button size="sm" variant="ghost" disabled={pending} onClick={handle_back} aria-label="Back to home">
                    {"← Back"}
                </Button>
                <h1 className="text-base font-semibold tracking-tight">Capture</h1>
            </header>
            <div className="flex items-center gap-2">
                <div role="group" aria-label="Note kind" className="flex flex-1 gap-1 rounded-md border bg-muted pt-0.5 pb-0.5 pl-0.5 pr-0.5">
                    <button
                        type="button"
                        aria-pressed={kind == "debrief"}
                        disabled={pending}
                        className={cn(_SEG_BASE, _SEG_ON if kind == "debrief" else _SEG_OFF)}
                        onClick={handle_debrief}
                    >
                        Debrief
                    </button>
                    <button
                        type="button"
                        aria-pressed={kind == "paste"}
                        disabled={pending}
                        className={cn(_SEG_BASE, _SEG_ON if kind == "paste" else _SEG_OFF)}
                        onClick={handle_paste}
                    >
                        Paste
                    </button>
                </div>
                <button
                    type="button"
                    disabled={True}
                    aria-label="Voice capture — coming soon"
                    title="Voice capture is coming soon"
                    className="inline-flex h-8 shrink-0 cursor-not-allowed items-center gap-1 rounded-md border border-dashed pl-2 pr-2 text-xs text-muted-foreground"
                >
                    <svg
                        aria-hidden="true"
                        viewBox="0 0 24 24"
                        width="14"
                        height="14"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                    >
                        <rect x="9" y="3" width="6" height="11" rx="3" />
                        <path d="M5 11a7 7 0 0 0 14 0" />
                        <path d="M12 18v3" />
                    </svg>
                    <span>Voice · soon</span>
                </button>
            </div>
            <Field>
                <FieldLabel htmlFor="capture-text" className="sr-only">Your note</FieldLabel>
                <Textarea
                    id="capture-text"
                    rows={9}
                    value={text}
                    onChange={handle_change}
                    disabled={pending}
                    placeholder="What happened? Who did you meet, what did they say, what did you promise?"
                />
                <FieldDescription>{hint}</FieldDescription>
            </Field>
            {error and <p role="alert" className="text-sm text-destructive/80">{error}</p>}
            <Button className="w-full" disabled={not can_submit} onClick={handle_submit}>
                {"Reading your note…" if pending else "Capture"}
            </Button>
            {pending and
                <p aria-live="polite" className="text-center text-xs text-muted-foreground">
                    Pulling out people, facts, intents and promises. Nothing is sent to anyone.
                </p>}
        </div>;
}
