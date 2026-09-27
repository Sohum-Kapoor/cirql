"""Voice capture — record, transcribe, check the transcript. OWNER: Person B (SOH-168).

Tap to record, tap to stop (capped at 3 minutes). MediaRecorder picks
`audio/mp4` when the browser supports it (Safari / iOS WKWebView), else
`audio/webm;codecs=opus` (Chrome). On stop the blob is base64'd
(FileReader.readAsDataURL, prefix stripped) and sent to `Transcribe`; the
transcript lands in an editable box ("fix names before Cirql reads it") and the
shell submits `Capture(text, "debrief", audio_ref)`.

The recorder and stream live in a module `glob` (not reactive, survives
re-renders); `phase` / `elapsed` are this component's UI state. The shell owns
the result (`voice` = { text, audio_ref, error, mime }) so it survives a tab
switch or "Try again". While recording or transcribing, `onBusy(True)` lets the
form lock the tabs; unmounting releases the mic.

`?mock=1`: no microphone — a fake 2 s recording and a canned transcript
(`?mock=1&mic=denied` shows the permission-denied state).
"""

import from react { useEffect }
import from ..ui.button { Button }
import from ..ui.textarea { Textarea }
import from ..ui.icons { MicIcon, StopIcon }
import from ..api { transcribe, mocks_on }
import from ...lib.utils { cn }

glob:pub MAX_MS: int = 180000;
glob:pub MIC_TIMEOUT_MS: int = 6000;
glob _REC: dict = {"rec": None, "stream": None, "chunks": [], "mime": "", "t0": 0, "fake": False, "stopping": False};

def _now() -> int {
    return Date.now() as int;  # jac:ignore[W2001]
}

"""audio/mp4 when supported (iOS / Safari), else webm/opus, else "" (browser default)."""
def:pub pick_mime() -> str {
    mime: str = "";
    try {
        mr: any = window.MediaRecorder;  # jac:ignore[W2001,E1030]
        if not mr {
            return "";
        }
        if mr.isTypeSupported("audio/mp4") {
            mime = "audio/mp4";
        } elif mr.isTypeSupported("audio/webm;codecs=opus") {
            mime = "audio/webm;codecs=opus";
        } elif mr.isTypeSupported("audio/webm") {
            mime = "audio/webm";
        }
    } except Exception as e {
        mime = "";
    }
    return mime;
}

"""`getUserMedia` raced against a timeout (SOH-232): some browsers neither
resolve nor reject the permission prompt (a dismissed system dialog, a stuck
policy check), which used to leave "Starting the mic…" on screen forever with
every control disabled. Whichever settles first wins; the timeout branch
rejects so the caller's single catch handles both cases the same way."""
async def get_mic(timeout_ms: int) -> any {
    stream: any = None;
    stream = await new(Promise, lambda(resolve: any, reject: any) {  # jac:ignore[W2001]
        timer: any = setTimeout(lambda { reject.call(None, new(Error, "mic_timeout")); }, timeout_ms);  # jac:ignore[W2001,E1053]
        navigator.mediaDevices.getUserMedia({"audio": True}).then(  # jac:ignore[W2001,E1030]
            lambda(s: any) { clearTimeout(timer); resolve.call(None, s); },  # jac:ignore[W2001,E1053]
            lambda(err: any) { clearTimeout(timer); reject.call(None, err); }  # jac:ignore[W2001,E1053]
        );
    });
    return stream;
}

def:pub voice_supported() -> bool {
    ok: bool = False;
    try {
        md: any = navigator.mediaDevices;  # jac:ignore[W2001,E1030]
        mr: any = window.MediaRecorder;  # jac:ignore[W2001,E1030]
        ok = bool(md and md.getUserMedia and mr);
    } except Exception as e {
        ok = False;
    }
    return ok;
}

"""Stop the tracks (the OS mic indicator goes off) and forget the recorder."""
def release_mic() {
    stream: any = _REC["stream"];
    if stream {
        for t in stream.getTracks() {
            t.stop();
        }
    }
    rec: any = _REC["rec"];
    if rec and rec.state == "recording" {
        try {
            rec.stop();
        } except Exception as e {
            rec = None;
        }
    }
    _REC["rec"] = None;
    _REC["stream"] = None;
    _REC["chunks"] = [];
    _REC["fake"] = False;
    _REC["stopping"] = False;
}

"""Stop the recorder and resolve with the recorded Blob."""
async def stop_to_blob() -> any {
    rec: any = _REC["rec"];
    mime: str = (_REC["mime"] or "") as str;
    blob: any = None;
    blob = await new(Promise, lambda(resolve: any, reject: any) {  # jac:ignore[W2001]
        rec.onstop = lambda(e: any) {
            opts: dict = {"type": mime} if mime else {};
            resolve.call(None, new(Blob, _REC["chunks"], opts));  # jac:ignore[W2001,E1053]
        };
        rec.stop();
    });
    return blob;
}

"""Blob -> bare base64 (the data-URL prefix stripped)."""
async def blob_to_b64(blob: any) -> str {
    url: str = "";
    url = await new(Promise, lambda(resolve: any, reject: any) {  # jac:ignore[W2001,E1001]
        fr: any = new(FileReader);  # jac:ignore[W2001,E1053]
        fr.onloadend = lambda(e: any) { resolve.call(None, fr.result); };
        fr.onerror = lambda(e: any) { reject.call(None, fr.error); };
        fr.readAsDataURL(blob);
    });
    cut: int = url.index(",") if "," in url else -1;
    return url[cut + 1:] if cut >= 0 else "";
}

def _noop() {
    return;
}

def:pub mmss(ms: int) -> str {
    s: int = int(ms / 1000);
    m: int = int(s / 60);
    r: int = s - m * 60;
    return str(m) + ":" + (("0" + str(r)) if r < 10 else str(r));
}

"""A short, plain message for Transcribe's `error` (the audio is kept when audio_ref is set)."""
def:pub voice_error_text(code: str, has_audio: bool) -> str {
    kept: str = " Your recording is saved with the note." if has_audio else "";
    if code == "no_key" {
        return "Transcription isn't set up on this server." + kept + " Type what happened below.";
    }
    if code == "too_large" {
        return "That recording is too long to send (15 MB max). Record a shorter one, or type it below.";
    }
    if code.startswith("stt_") {
        return "Transcription failed (" + code[4:] + ")." + kept + " Type what happened below, or record again.";
    }
    if code == "empty" {
        return "Nothing was recorded. Check the microphone and try again, or type it below.";
    }
    return "Couldn't transcribe that (" + code + ")." + kept + " Type what happened below.";
}

def:pub VoiceCapture(
    voice: dict,
    pending: bool,
    onVoice: Callable[[dict], None],
    onBusy: Callable[[bool], None],
    onTypeInstead: Callable[[], None]
) -> JsxElement {
    has phase: str = "idle",
        elapsed: int = 0;

    # Unmount (tab switch, back): release the mic.
    useEffect(lambda {
        return lambda { release_mic(); };
    }, []);

    has_result: bool = bool(voice["text"] or voice["audio_ref"] or voice["error"]);

    async def finish -> None {
        if _REC["stopping"] {
            return;
        }
        _REC["stopping"] = True;
        phase = "transcribing";
        b64: str = "";
        mime: str = "";
        out: dict = {};
        blob: any = None;
        try {
            if _REC["fake"] {
                b64 = "bW9jaw==";
                mime = "audio/mp4";
            } else {
                blob = await stop_to_blob();
                mime = ((blob.type or _REC["mime"]) or "audio/webm") as str;
                if not blob or (blob.size as int) == 0 {
                    release_mic();
                    onBusy(False);
                    phase = "idle";
                    onVoice({"text": "", "audio_ref": "", "error": "empty", "mime": mime});
                    return;
                }
                if (blob.size as int) > 11000000 {
                    # ~11 MB raw ≈ Transcribe's 15 MB base64 cap: don't upload what the server will refuse.
                    release_mic();
                    onBusy(False);
                    phase = "idle";
                    onVoice({"text": "", "audio_ref": "", "error": "too_large", "mime": mime});
                    return;
                }
                b64 = await blob_to_b64(blob);
            }
            release_mic();
            out = await transcribe(b64, mime);
        } except Exception as e {
            release_mic();
            onBusy(False);
            phase = "idle";
            onVoice({"text": "", "audio_ref": "", "error": "failed", "mime": mime});
            return;
        }
        onBusy(False);
        phase = "idle";
        onVoice({
            "text": (out["transcript"] or "") as str,
            "audio_ref": (out["audio_ref"] or "") as str,
            "error": (out["error"] or "") as str,
            "mime": mime
        });
    }

    # Elapsed clock while recording; auto-stop at the 3-minute cap.
    useEffect(lambda {
        if phase != "recording" {
            return _noop;
        }
        iv: any = setInterval(lambda {  # jac:ignore[W2001]
            ms: int = _now() - (_REC["t0"] as int);
            elapsed = ms;
            if ms >= MAX_MS {
                finish();
            }
        }, 250);
        return lambda { clearInterval(iv); };  # jac:ignore[W2001,E1053]
    }, [phase]);

    async def start -> None {
        stream: any = None;
        rec: any = None;
        mime: str = "";
        if mocks_on() {
            search: str = String(window.location.search);  # jac:ignore[W2001]
            if "mic=denied" in search {
                phase = "denied";
                return;
            }
            _REC["fake"] = True;
            _REC["stopping"] = False;
            _REC["t0"] = _now();
            elapsed = 0;
            phase = "recording";
            onBusy(True);
            setTimeout(lambda { finish(); }, 2000);  # jac:ignore[W2001]
            return;
        }
        if not voice_supported() {
            phase = "unsupported";
            return;
        }
        phase = "starting";
        onBusy(True);
        try {
            stream = await get_mic(MIC_TIMEOUT_MS);
        } except Exception as e {
            # Rejected, denied, no device, or timed out (SOH-232): one message,
            # one recovery path — never leave the disabled/"starting" state.
            onBusy(False);
            phase = "denied";
            return;
        }
        mime = pick_mime();
        try {
            rec = new(MediaRecorder, stream, {"mimeType": mime}) if mime else new(MediaRecorder, stream);  # jac:ignore[W2001,E1053]
        } except Exception as e {
            rec = new(MediaRecorder, stream);  # jac:ignore[W2001,E1053]
            mime = "";
        }
        _REC["stream"] = stream;
        _REC["rec"] = rec;
        _REC["mime"] = mime or (rec.mimeType or "");
        _REC["chunks"] = [];
        _REC["fake"] = False;
        _REC["stopping"] = False;
        rec.ondataavailable = lambda(ev: any) {
            if ev.data and (ev.data.size as int) > 0 {
                _REC["chunks"] = (_REC["chunks"] as list) + [ev.data];
            }
        };
        rec.start(1000);
        _REC["t0"] = _now();
        elapsed = 0;
        phase = "recording";
    }

    def handle_start(e: MouseEvent) {
        start();
    }

    def handle_stop(e: MouseEvent) {
        finish();
    }

    def handle_again(e: MouseEvent) {
        phase = "idle";
        onVoice({"text": "", "audio_ref": "", "error": "", "mime": ""});
    }

    def handle_type(e: MouseEvent) {
        onTypeInstead();
    }

    def handle_text(e: ChangeEvent) {
        nv: dict = {**voice};
        nv["text"] = e.target.value;
        onVoice(nv);
    }

    # ---- transcript review
    if has_result and phase == "idle" {
        err: str = (voice["error"] or "") as str;
        return
            <div className="flex flex-col gap-3">
                {err and
                    <p role="alert" className="rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-3 pr-3 text-body-sm text-muted-foreground">
                        {voice_error_text(err, bool(voice["audio_ref"]))}
                    </p>}
                <div className="flex flex-col gap-1">
                    <label htmlFor="voice-transcript" className="text-eyebrow text-muted-foreground">
                        {"Type what happened" if err and not voice["text"] else "Check the transcript: fix names before Cirql reads it"}
                    </label>
                    <Textarea
                        id="voice-transcript"
                        rows={8}
                        value={(voice["text"] or "") as str}
                        disabled={pending}
                        placeholder="Who did you meet, what did you talk about, what did you promise?"
                        onChange={handle_text}
                    />
                </div>
                <div className="flex items-center justify-between gap-2">
                    <span className="text-caption text-muted-foreground">
                        {"Audio kept with the note as its receipt." if voice["audio_ref"] else ""}
                    </span>
                    <Button size="sm" variant="outline" disabled={pending} onClick={handle_again}>
                        <MicIcon />
                        Record again
                    </Button>
                </div>
            </div>;
    }

    # ---- no mic / no permission / timed out (SOH-232: one message, tabs and
    # Back re-enabled the moment onBusy(False) ran above; nothing stays locked).
    if phase == "denied" or phase == "unsupported" {
        msg: str = (
            "This browser can't record audio here."
            if phase == "unsupported"
            else "Couldn't start the microphone. Check permissions, or type your note instead."
        );
        return
            <div className="flex flex-col gap-3">
                <p role="alert" className="rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-3 pr-3 text-body-sm">{msg}</p>
                <div className="flex gap-2">
                    {phase != "unsupported" and
                        <Button variant="secondary" className="flex-1" onClick={handle_start}>Try again</Button>}
                    <Button variant="ghost" className="flex-1" onClick={handle_type}>Type it instead</Button>
                </div>
            </div>;
    }

    recording: bool = phase == "recording";
    busy: bool = phase == "starting" or phase == "transcribing";
    # One name for the action (SOH-232): the button's aria-label and this
    # visible status agree ("Start recording" / "Stop recording"); "Tap to
    # record" stays as the helper caption below instead of standing in for it.
    status: str = (
        mmss(elapsed) + " / " + mmss(MAX_MS)
        if recording
        else ("Transcribing…" if phase == "transcribing" else ("Starting the mic…" if phase == "starting" else "Start recording"))
    );

    return
        <div className="flex flex-col items-center gap-6 rounded-lg border bg-card pt-10 pb-6 pl-4 pr-4 shadow-edge">
            <div className="relative flex size-24 items-center justify-center">
                {recording and
                    <span aria-hidden="true" className="absolute inset-0 rounded-full bg-destructive/25 motion-safe:animate-ping" />}
                {recording and
                    <span aria-hidden="true" className="absolute -inset-2 rounded-full border-2 border-destructive/40 motion-safe:animate-pulse" />}
                <button
                    type="button"
                    aria-label={"Stop recording" if recording else "Start recording"}
                    aria-pressed={recording}
                    disabled={busy or pending}
                    onClick={handle_stop if recording else handle_start}
                    className={cn(
                        "relative flex size-20 items-center justify-center rounded-full text-primary-foreground outline-none transition-colors focus-visible:ring-2 focus-visible:ring-ring/50 disabled:opacity-50",
                        "bg-destructive" if recording else "bg-primary hover:bg-primary-hover active:bg-primary-focus"
                    )}
                >
                    {recording and <StopIcon className="size-7" />}
                    {not recording and <MicIcon className="size-8" />}
                </button>
            </div>
            <p aria-live="polite" className="text-body font-medium tabular-nums">{status}</p>
            <p className="text-center text-caption text-muted-foreground">
                {
                    "Tap stop when you're done. Up to 3 minutes."
                    if recording
                    else "Tap to record. Say who you met, how, what you talked about, and anything you promised. Up to 3 minutes."
                }
            </p>
        </div>;
}
