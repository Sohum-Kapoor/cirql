"""Mock for `CaptureImage(image_b64: str, mime: str = "image/jpeg", context: str = "")` — SOH-192.

Returns the `Capture` report shape plus `photo_ref`, `read`, `fallback`, `error`
(brief SOH-192; contract block appended by the server branch). Any photo reads
as one badge (built through the paste mock, so the person lands in the mock
people list); a photo under 2 KB stands in for "no name found" and returns
`error: "no_person"` with empty lists.
"""

import from .capture { mock_capture }

def:pub mock_capture_image(image_b64: str, mime: str) -> dict {
    read: dict = {
        "name": "Kofi Mensah",
        "org": "DTE Energy",
        "title": "Grid planner",
        "email": "kofi@example.com",
        "phone": "",
        "links": [],
        "raw_text": "KOFI MENSAH / Grid planner / DTE Energy / kofi@example.com"
    };
    if len(image_b64) < 2700 {
        return {
            "note_id": "mock-note-photo-empty",
            "people": [],
            "facts": [],
            "intents": [],
            "promises": [],
            "ties": [],
            "photo_ref": "uploads/mock.jpg",
            "read": {"name": "", "org": "", "title": "", "email": "", "phone": "", "links": [], "raw_text": ""},
            "fallback": False,
            "error": "no_person"
        };
    }
    out: dict = mock_capture("Kofi Mensah — DTE Energy grid planner, met at the badge table", "paste");
    out["photo_ref"] = "uploads/mock.jpg";
    out["read"] = read;
    out["fallback"] = False;
    out["error"] = "";
    return out;
}
