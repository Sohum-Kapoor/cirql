"""Scan a badge (SOH-192): a hidden `<input type="file" accept="image/*"
capture="environment">` behind a shadcn Button. The picked photo (under 10 MB)
is read as base64 with FileReader and sent to `CaptureImage`; the result goes to
`onResult(result, note_text)`, the same review path a text Capture takes.
Nothing is sent to anyone; the photo is kept as the note's source.
"""

import from ..ui.button { Button }
import from ..api { capture_image }

glob MAX_BYTES: int = 10 * 1024 * 1024;

"""A FileReader data URL -> (mime, base64) as a dict."""
def split_data_url(url: str) -> dict {
    parts: list[str] = url.split(",");
    head: str = parts[0] if len(parts) > 1 else "";
    kind: str = head.split(";")[0];
    mime: str = kind[5:] if kind.startswith("data:") else "";
    return {"mime": mime, "b64": parts[1] if len(parts) > 1 else ""};
}

"""Resolve the file's data URL (FileReader wrapped in a Promise)."""
def read_as_data_url(file: any) -> any {
    return new(Promise, lambda(resolve: any, reject: any) {
        reader: any = new(FileReader);  # jac:ignore[W2001,E1053]
        reader.onload = lambda { resolve.call(None, reader.result); };
        reader.onerror = lambda { reject.call(None, reader.error); };
        reader.readAsDataURL(file);
    });
}

def:pub PhotoCapture(
    disabled: bool = False,
    onResult: Callable[[dict, str], None] | None = None,
    onBusyChange: Callable[[bool], None] | None = None
) -> JsxElement {
    has busy: bool = False,
        message: str = "",
        fileRef: Ref[any] = Ref();

    def set_busy(v: bool) -> None {
        busy = v;
        if onBusyChange {
            onBusyChange(v);
        }
    }

    def open_picker(e: MouseEvent) {
        if fileRef.current {
            fileRef.current.click();
        }
    }

    async def handle_file(e: ChangeEvent) -> None {
        input_el: any = e.target;
        files: any = input_el.files;
        file: any = files[0] if files and (files.length as int) > 0 else None;
        input_el.value = "";
        if not file {
            return;
        }
        if file.size > MAX_BYTES {
            message = "That photo is over 10 MB — try a smaller one.";
            return;
        }
        message = "";
        set_busy(True);
        url: any = None;
        out: dict = {};
        try {
            url = await read_as_data_url(file);
            parts: dict = split_data_url(str(url));
            mime: str = (parts["mime"] or file.type or "image/jpeg") as str;
            out = await capture_image(parts["b64"] as str, mime);
        } except Exception as err {
            set_busy(False);
            message = "Couldn't read that photo. " + str(err);
            return;
        }
        set_busy(False);
        if out["error"] == "no_person" {
            message = "No name found on that photo — try again or type it.";
            return;
        }
        if out["error"] {
            message = "Couldn't read that photo (" + str(out["error"]) + ") — try again or type it.";
            return;
        }
        read: dict = (out["read"] or {}) as dict;
        note: str = "Badge photo: " + ((read["raw_text"] or read["name"] or "") as str);
        if onResult {
            onResult(out, note);
        }
    }

    return
        <div className="relative">
            <input
                ref={fileRef}
                type="file"
                accept="image/*"
                capture="environment"
                className="sr-only"
                tabIndex={-1}
                aria-hidden="true"
                onChange={handle_file}
            />
            <Button
                variant="outline"
                size="sm"
                disabled={disabled or busy}
                onClick={open_picker}
                aria-label="Scan a badge or business card"
                className="h-10"
            >
                <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="size-3.5">
                    <path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z" />
                    <circle cx="12" cy="13" r="3" />
                </svg>
                <span className="text-caption">{"Reading…" if busy else "Scan a badge"}</span>
            </Button>
            {busy and <p aria-live="polite" className="absolute top-full right-0 z-10 mt-1 w-max rounded-md border bg-popover pt-1.5 pb-1.5 pl-2.5 pr-2.5 text-caption text-muted-foreground shadow-edge">Reading the badge…</p>}
            {message and <p role="alert" className="absolute top-full right-0 z-10 mt-1 w-64 max-w-[calc(100vw_-_32px)] rounded-md border bg-popover pt-1.5 pb-1.5 pl-2.5 pr-2.5 text-caption text-destructive shadow-edge">{message}</p>}
        </div>;
}
