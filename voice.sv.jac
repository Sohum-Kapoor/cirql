"""Voice — server-side ElevenLabs speech-to-text (SOH-168).

OWNER: Person A. See contracts/walkers.md for the exact report shape. Rules
this file must obey (AGENTS.md):
  - The ElevenLabs key never ships to the client — it is read here, from
    `os.environ.get("ELEVENLABS_API_KEY", "")`, server-side only, and never
    logged (not even on a non-2xx response).
  - `Transcribe` does NOT create a `Note`. The client already owns that step
    (`Capture(text=transcript, kind="debrief")`, per contracts/walkers.md) —
    this walker only turns audio into text (and a file on disk) and hands
    both back.
  - Client audio is `audio/mp4` (AAC, Safari/iOS WKWebView) or
    `audio/webm;codecs=opus` (Chrome); ElevenLabs' `scribe_v1` accepts both —
    never transcode.
  - A missing key does not lose the note: `error: "no_key"` and an empty
    transcript still come back with `audio_ref` set, so the client still has
    the saved audio and can retry once a key exists, or let the user type.
  - `:priv` (own root, JWT required). No `by llm` anywhere in this module —
    this is a plain REST call to ElevenLabs, not a byLLM model.

`save_audio` and `parse_stt` are plain `def`s (not walkers) specifically so
`voice.test.jac` can call them directly with no network and no server —
extension mapping, the 15 MB cap, and the base64 round-trip are all
deterministic and don't need `ElevenLabs` or a running `jac start`.
"""

import base64;
import os;
import requests;
import from uuid { uuid4 }

# ---------------------------------------------------------------- helpers

glob MAX_AUDIO_BYTES: int = 15 * 1024 * 1024;   # 15 MB cap

"""Pick a file extension from the mime type the client sent. `audio/webm`
arrives as `audio/webm;codecs=opus` — matched by prefix, not equality."""
def ext_for_mime(mime: str) -> str {
    if mime == "audio/mp4" {
        return ".m4a";
    }
    if mime.startswith("audio/webm") {
        return ".webm";
    }
    if mime == "audio/wav" {
        return ".wav";
    }
    if mime == "audio/mpeg" {
        return ".mp3";
    }
    return ".bin";
}

"""Read `body[key]` as a string; missing key or a None value is "". Avoids
`dict.get(key, default)` (E1054 on some dict shapes — AGENTS.md gotcha),
same idiom as `imports.sv.jac`'s `row_str`."""
def body_str(body: dict[str, any], key: str) -> str {
    if key in body {
        val = body[key];
        if val is None {
            return "";
        }
        return str(val);
    }
    return "";
}

"""Decode `audio_b64`, cap it at `MAX_AUDIO_BYTES`, and write it to
`uploads/<root_id>/<uuid>.<ext>` (relative to the cwd; directories created
as needed). Returns `{ audio_ref: str, error: str }` — `audio_ref` is ""
and `error` is `"too_large"` (over the cap) or `"bad_audio"` (unparsable
base64) on failure; `error` is "" and `audio_ref` is the relative path on
success. Never raises."""
def save_audio(root_id: str, audio_b64: str, mime: str) -> dict[str, str] {
    try {
        raw = base64.b64decode(audio_b64, validate=False);
    } except Exception {
        return {"audio_ref": "", "error": "bad_audio"};
    }

    if len(raw) > MAX_AUDIO_BYTES {
        return {"audio_ref": "", "error": "too_large"};
    }

    ext = ext_for_mime(mime);
    dir_path = os.path.join("uploads", root_id);
    os.makedirs(dir_path, exist_ok=True);
    filename = f"{str(uuid4())}{ext}";
    full_path = os.path.join(dir_path, filename);

    with open(full_path, "wb") as f {
        f.write(raw);
    }

    return {"audio_ref": full_path, "error": ""};
}

"""Turn an ElevenLabs speech-to-text HTTP response into
`{ transcript: str, error: str }`. 2xx -> `transcript = body["text"]` (or ""
if the key is somehow missing), `error` "". Non-2xx -> transcript "",
`error = f"stt_{status}"`. Never raises, never logs the response body (it
carries no secret, but keep the shape symmetric with the walker, which
never logs the key)."""
def parse_stt(status: int, body: dict[str, any]) -> dict[str, str] {
    if status >= 200 and status < 300 {
        return {"transcript": body_str(body, "text"), "error": ""};
    }
    return {"transcript": "", "error": f"stt_{status}"};
}

# ---------------------------------------------------------------- walker

walker:priv Transcribe {
    """Decode + save the audio, then POST it to ElevenLabs `scribe_v1`.
    Reports exactly one entry: `{ transcript, audio_ref, duration_ms, error }`
    (contracts/walkers.md). `duration_ms` is always 0 (unknown — ElevenLabs'
    `scribe_v1` response used here doesn't carry it)."""
    has audio_b64: str;
    has mime: str = "audio/mp4";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        root_id = jid(root);
        saved = save_audio(root_id, self.audio_b64, self.mime);

        if saved["error"] {
            report {
                "transcript": "", "audio_ref": "",
                "duration_ms": 0, "error": saved["error"]
            };
            disengage;
        }

        audio_ref = saved["audio_ref"] as str;

        api_key = os.environ.get("ELEVENLABS_API_KEY", "");
        if not api_key {
            # Note: the audio itself is still saved at audio_ref — nothing
            # is lost, the client can retry once a key exists or let the
            # user type the note instead.
            report {
                "transcript": "", "audio_ref": audio_ref,
                "duration_ms": 0, "error": "no_key"
            };
            disengage;
        }

        try {
            with open(audio_ref, "rb") as f {
                raw = f.read();
            }
        } except Exception {
            report {
                "transcript": "", "audio_ref": audio_ref,
                "duration_ms": 0, "error": "read_failed"
            };
            disengage;
        }

        filename = os.path.basename(audio_ref);

        try {
            resp = requests.post(
                "https://api.elevenlabs.io/v1/speech-to-text",
                headers={"xi-api-key": api_key},
                files={"file": (filename, raw, self.mime)},
                data={"model_id": "scribe_v1"},
                timeout=60
            );
        } except Exception {
            report {
                "transcript": "", "audio_ref": audio_ref,
                "duration_ms": 0, "error": "stt_network"
            };
            disengage;
        }

        body: dict[str, any] = {};
        try {
            body = resp.json() as dict[str, any];
        } except Exception {
            body = {};
        }

        parsed = parse_stt(resp.status_code, body);
        report {
            "transcript": parsed["transcript"], "audio_ref": audio_ref,
            "duration_ms": 0, "error": parsed["error"]
        };
    }
}
