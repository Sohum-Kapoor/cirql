"""Capture screen — write (or paste) what happened; Submit calls Capture. OWNER: Person B.

Stateless: the shell owns `text`, `kind` (debrief | paste), `pending`, `error`
and the Capture call. The mic is a visible placeholder for voice capture
(SOH-168) — disabled and labelled "soon", never a fake working control.
"""

import from "..ui.button" { Button }
import from "..ui.textarea" { Textarea }
import from "..ui.field" { Field, FieldLabel, FieldDescription }
import from "..ui.tabs" { Tabs, TabsList, TabsTrigger, TabsContent }
import from "..ui.icons" { MicIcon, ChevronLeftIcon }
import from .PhotoCapture { PhotoCapture }

def:pub CaptureForm(
    text: str,
    kind: str,
    pending: bool,
    error: str,
    onTextChange: Callable[[str], None],
    onKindChange: Callable[[str], None],
    onSubmit: Callable[[], None],
    onBack: Callable[[], None],
    onPhotoResult: Callable[[dict, str], None] | None = None
) -> JsxElement {
    def handle_change(e: ChangeEvent) {
        onTextChange(e.target.value);
    }

    def handle_kind(value: str) -> None {
        onKindChange(value);
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

    def note_field() -> JsxElement {
        return
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
            </Field>;
    }

    return
        <div className="flex flex-col gap-5">
            <header className="-ml-2 flex items-center gap-1">
                <Button size="icon" variant="ghost" disabled={pending} onClick={handle_back} aria-label="Back to home">
                    <ChevronLeftIcon className="size-5" />
                </Button>
                <h1 className="text-card-title">Capture</h1>
            </header>
            <Tabs value={kind} onValueChange={handle_kind}>
                <div className="flex flex-wrap items-start gap-2">
                    <TabsList aria-label="Note kind" className="min-w-40 flex-1">
                        <TabsTrigger value="debrief" disabled={pending}>Debrief</TabsTrigger>
                        <TabsTrigger value="paste" disabled={pending}>Paste</TabsTrigger>
                    </TabsList>
                    <Button
                        variant="outline"
                        size="sm"
                        disabled={True}
                        aria-label="Voice capture — coming soon"
                        title="Voice capture is coming soon"
                        className="h-10 border-dashed border-border-strong text-muted-foreground"
                    >
                        <MicIcon className="size-3.5" />
                        <span className="text-caption">Voice · soon</span>
                    </Button>
                    <PhotoCapture disabled={pending} onResult={onPhotoResult} />
                </div>
                <TabsContent value="debrief">{note_field()}</TabsContent>
                <TabsContent value="paste">{note_field()}</TabsContent>
            </Tabs>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            <Button className="w-full" size="lg" disabled={not can_submit} onClick={handle_submit}>
                {"Reading your note…" if pending else "Capture"}
            </Button>
            {pending and
                <p aria-live="polite" className="text-center text-caption text-muted-foreground">
                    Pulling out people, facts, intents and promises. Nothing is sent to anyone.
                </p>}
        </div>;
}
