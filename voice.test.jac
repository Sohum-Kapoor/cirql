"""Tests for voice.sv.jac (SOH-168).

Annex to voice.sv.jac — run with `jac test voice.sv.jac`. Deterministic only:
no network, no ElevenLabs call. `save_audio`/`parse_stt`/`ext_for_mime` are
plain `def`s exactly so this file can exercise extension mapping, the 15 MB
cap, and the base64-to-disk round-trip without a server or a model. The one
walker test (`Transcribe` with no key) is likewise deterministic: it forces
`ELEVENLABS_API_KEY` empty so the walker returns `error: "no_key"` before it
would ever reach the network.

`save_audio` writes real files under `uploads/<root_id>/` relative to the
cwd (per contracts/walkers.md) — `uploads/` is gitignored; these tests don't
clean up after themselves (same posture as other suites' persisted-root
graph nodes, see `jac-testing`), the files are small and harmless.
"""

import from voice { save_audio, parse_stt, ext_for_mime, Transcribe, MAX_AUDIO_B64_CHARS }
import base64;
import os;

# ---------------------------------------------------------------- ext_for_mime

test "ext_for_mime maps known mimes and falls back to .bin" {
    assert ext_for_mime("audio/mp4") == ".m4a";
    assert ext_for_mime("audio/webm;codecs=opus") == ".webm";
    assert ext_for_mime("audio/webm") == ".webm";
    assert ext_for_mime("audio/wav") == ".wav";
    assert ext_for_mime("audio/mpeg") == ".mp3";
    assert ext_for_mime("application/octet-stream") == ".bin";
    assert ext_for_mime("") == ".bin";
}

# ---------------------------------------------------------------- save_audio

test "save_audio base64-round-trips small audio to a file that exists" {
    raw = b"fake-m4a-bytes-for-a-test";
    b64 = base64.b64encode(raw).decode("ascii");

    result = save_audio("voicetestroot1", b64, "audio/mp4");

    assert result["error"] == "";
    audio_ref = result["audio_ref"];
    assert audio_ref != "";
    assert audio_ref.endswith(".m4a");
    assert audio_ref.startswith(os.path.join("uploads", "voicetestroot1"));
    assert os.path.exists(audio_ref), f"expected a file at {audio_ref}";

    with open(audio_ref, "rb") as f {
        on_disk = f.read();
    }
    assert on_disk == raw, "decoded bytes on disk must match the original audio";
}

test "save_audio caps at 15 MB" {
    too_big = b"x" * (15 * 1024 * 1024 + 1);
    b64 = base64.b64encode(too_big).decode("ascii");

    result = save_audio("voicetestroot2", b64, "audio/webm;codecs=opus");

    assert result["error"] == "too_large";
    assert result["audio_ref"] == "";
}

test "save_audio at exactly the 15 MB cap is not rejected" {
    exactly_cap = b"y" * (15 * 1024 * 1024);
    b64 = base64.b64encode(exactly_cap).decode("ascii");

    result = save_audio("voicetestroot3", b64, "audio/wav");

    assert result["error"] == "";
    assert result["audio_ref"].endswith(".wav");
}

test "save_audio reports bad_base64 on non-strict base64 (SOH-211)" {
    result = save_audio("voicetestroot4", "not-valid-base64!!!", "audio/mp4");
    assert result["error"] == "bad_base64";
    assert result["audio_ref"] == "";
    # validate=True: characters outside the alphabet are rejected, not skipped
    assert save_audio("voicetestroot4", "QUJD*REVG", "audio/mp4")["error"] == "bad_base64";
}

test "save_audio rejects an over-long base64 string before decoding (SOH-211)" {
    before = set(os.listdir("uploads")) if os.path.exists("uploads") else set();
    result = save_audio("voicetestroot5", "!" * (MAX_AUDIO_B64_CHARS + 1), "audio/mp4");
    after = set(os.listdir("uploads")) if os.path.exists("uploads") else set();
    # "!" is not base64: too_large (not bad_base64) proves the length check ran first.
    assert result["error"] == "too_large", result;
    assert result["audio_ref"] == "";
    assert after == before;
}

# ---------------------------------------------------------------- parse_stt

test "parse_stt(200, ...) returns the transcript with no error" {
    out = parse_stt(200, {"text": "hi"});
    assert out["transcript"] == "hi";
    assert out["error"] == "";
}

test "parse_stt(401, ...) returns stt_401 with no transcript" {
    out = parse_stt(401, {});
    assert out["transcript"] == "";
    assert out["error"] == "stt_401";
}

test "parse_stt on a 2xx body missing 'text' returns an empty transcript, no error" {
    out = parse_stt(200, {});
    assert out["transcript"] == "";
    assert out["error"] == "";
}

# ---------------------------------------------------------------- Transcribe walker

test "Transcribe with no ElevenLabs key reports no_key but still saves the audio" {
    os.environ["ELEVENLABS_API_KEY"] = "";

    raw = b"fake-audio-for-the-no-key-path";
    b64 = base64.b64encode(raw).decode("ascii");

    result = root spawn Transcribe(audio_b64=b64, mime="audio/mp4");
    assert len(result.reports) == 1;
    out = result.reports[0];

    assert out["error"] == "no_key";
    assert out["transcript"] == "";
    assert out["duration_ms"] == 0;
    assert out["audio_ref"] != "", "audio must still be saved even with no key";
    audio_ref = out["audio_ref"] as str;
    assert os.path.exists(audio_ref);
}
