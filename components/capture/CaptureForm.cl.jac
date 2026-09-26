"""Capture screen — Guided · Paste · Voice; Submit calls Capture. OWNER: Person B.

The shell owns every draft (`guided` dict, paste `text`, `voice` result), the
mode, `pending`, `error` and the Capture call — so nothing typed is lost on a
tab switch, a failed call, or "Try again" from the review. This component only
holds `voice_busy` (tabs and Back lock while the mic is on or transcribing).

Modes (SOH-209 / SOH-168):
  guided — structured form (GuidedForm), composed into prose; kind "debrief"
  paste  — free text (a debrief, notes, an email); kind "paste"
  voice  — record -> Transcribe -> editable transcript; kind "debrief" + audio_ref
"""

import from ..ui.button { Button }
import from ..ui.textarea { Textarea }
import from ..ui.field { Field, FieldLabel, FieldDescription }
import from ..ui.tabs { Tabs, TabsList, TabsTrigger, TabsContent }
import from ..ui.icons { MicIcon, ChevronLeftIcon }
import from .GuidedForm { GuidedForm }
import from .VoiceCapture { VoiceCapture }
import from .PhotoCapture { PhotoCapture }
import from .guided { guided_missing, guided_text }

"""Can this mode submit? "" when yes, else a short reason."""
def:pub capture_blocker(mode: str, text: str, guided: dict, voice: dict) -> str {
    if mode == "guided" {
        return guided_missing(guided) or ("" if guided_text(guided).strip() else "Add who you met.");
    }
    if mode == "voice" {
        return "" if ((voice["text"] or "") as str).strip() else "Record a note first.";
    }
    return "" if text.strip() else "Write something first.";
}

def:pub CaptureForm(
    mode: str,
    text: str,
    guided: dict,
    voice: dict,
    pending: bool,
    error: str,
    onModeChange: Callable[[str], None],
    onTextChange: Callable[[str], None],
    onGuidedField: Callable[[str, any], None],
    onVoice: Callable[[dict], None],
    onSubmit: Callable[[], None],
    onBack: Callable[[], None],
    onPhotoResult: Callable[[dict, str], None] | None = None
) -> JsxElement {
    has voice_busy: bool = False;

    def handle_change(e: ChangeEvent) {
        onTextChange(e.target.value);
    }

    def handle_mode(value: str) -> None {
        onModeChange(value);
    }

    def handle_submit(e: MouseEvent) {
        onSubmit();
    }

    def handle_back(e: MouseEvent) {
        onBack();
    }

    def set_busy(v: bool) -> None {
        voice_busy = v;
    }

    def type_instead() -> None {
        onModeChange("paste");
    }

    locked: bool = pending or voice_busy;
    blocker: str = capture_blocker(mode, text, guided, voice);
    can_submit: bool = not blocker and not locked;

    return
        <div className="flex flex-col gap-5">
            <header className="-ml-2 flex items-center gap-1">
                <Button size="icon" variant="ghost" disabled={locked} onClick={handle_back} aria-label="Back to home">
                    <ChevronLeftIcon className="size-5" />
                </Button>
                <h1 className="text-card-title">Capture</h1>
            </header>
            <Tabs value={mode} onValueChange={handle_mode}>
                <TabsList aria-label="How to capture" className="w-full">
                    <TabsTrigger value="guided" disabled={locked}>Guided</TabsTrigger>
                    <TabsTrigger value="paste" disabled={locked}>Paste</TabsTrigger>
                    <TabsTrigger value="voice" disabled={locked}>
                        <MicIcon className="size-3.5" />
                        Voice
                    </TabsTrigger>
                </TabsList>
                <TabsContent value="guided">
                    <GuidedForm guided={guided} pending={pending} onField={onGuidedField} />
                </TabsContent>
                <TabsContent value="paste">
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
                        <FieldDescription>
                            Write it the way you'd tell a friend, or paste notes or an email. Cirql keeps the original text.
                        </FieldDescription>
                    </Field>
                </TabsContent>
                <TabsContent value="voice">
                    <VoiceCapture voice={voice} pending={pending} onVoice={onVoice} onBusy={set_busy} onTypeInstead={type_instead} />
                </TabsContent>
            </Tabs>
            <PhotoCapture disabled={pending} onResult={onPhotoResult} />
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            <div className="flex flex-col gap-2">
                <Button className="w-full" size="lg" disabled={not can_submit} onClick={handle_submit}>
                    {"Reading your note…" if pending else "Capture"}
                </Button>
                {if pending {
                    <p aria-live="polite" className="text-center text-caption text-muted-foreground">
                        Pulling out people, facts, intents and promises. Nothing is sent to anyone.
                    </p>
                } elif blocker and not voice_busy {
                    <p className="text-center text-caption text-muted-foreground">{blocker}</p>
                }}
            </div>
        </div>;
}
