"""Mocks for Transcribe, ApplyCorrection and Forget — SOH-168 / SOH-209. OWNER: Person B.

Shapes are exactly contracts/walkers.md (change log: SOH-168 voice.sv.jac,
SOH-184 noted.sv.jac, SOH-188 forget.sv.jac). Used under `?mock=1` only.
"""

import from .capture { mock_forget_person }

glob MOCK_TRANSCRIPT: str = "Met Dana Lee at the MHacks career fair. She's a PM at Rivian working on battery supply chains, and she's teaching a guest lecture at UMich next week. She wants to see the Kiln Labs demo. I promised to send her the deck by Friday.",
     _SEQ: dict = {"n": 0};

def _next_id(prefix: str) -> str {
    _SEQ["n"] = (_SEQ["n"] as int) + 1;
    return prefix + str(_SEQ["n"]);
}

"""Transcribe(audio_b64, mime) -> { transcript, audio_ref, duration_ms, error }."""
def:pub mock_transcribe(audio_b64: str, mime: str) -> dict {
    ext: str = ".m4a" if mime.startswith("audio/mp4") else ".webm";
    return {
        "transcript": MOCK_TRANSCRIPT,
        "audio_ref": "uploads/mock/" + _next_id("clip-") + ext,
        "duration_ms": 0,
        "error": ""
    };
}

"""ApplyCorrection(person_id, text, replace_fact_id, kind) -> { fact } | { intent } | { error }."""
def:pub mock_apply_correction(person_id: str, text: str, replace_fact_id: str, kind: str) -> dict {
    now: str = "2026-09-26T18:30:00Z";
    if kind == "fact" {
        return {
            "fact": {
                "_jac_id": _next_id("mock-fact-c"),
                "text": text,
                "observed_at": now,
                "valid_to": "",
                "status": "confirmed",
                "source_kind": "self",
                "source_url": ""
            }
        };
    }
    if kind == "need" or kind == "offer" or kind == "open_to" {
        return {
            "intent": {
                "_jac_id": _next_id("mock-intent-c"),
                "kind": kind,
                "text": text,
                "expires_at": "2026-12-25T18:30:00",
                "source_kind": "self"
            }
        };
    }
    return {"error": "bad_kind"};
}

"""Forget(id) -> { deleted, id, retracted } | { error: "not_found" }."""
def:pub mock_forget(some_id: str) -> dict {
    kind: str = "";
    if some_id.startswith("mock-person") {
        mock_forget_person(some_id);
        kind = "person";
    } elif some_id.startswith("mock-fact") {
        kind = "fact";
    } elif some_id.startswith("mock-intent") {
        kind = "intent";
    } elif some_id.startswith("mock-promise") {
        kind = "promise";
    } else {
        return {"error": "not_found"};
    }
    return {
        "deleted": kind,
        "id": some_id,
        "retracted": {"facts": 0, "intents": 0, "promises": 0, "edges": 1, "introductions_canceled": 0, "relevant_to": 0}
    };
}
