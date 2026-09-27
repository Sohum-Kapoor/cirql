"""Mocks for the notes timeline — SOH-222 (client, brief C notes).

Exact contract shapes (contracts/walkers.md): `ListNotes(limit, before, kind)`,
`DeleteNote(note_id)`. 8 notes over 4 days (Today / Yesterday / Sep 24 / Sep 22),
newest first. Reuses the pseudonymous people from `mocks/person.cl.jac`
(mock-person-maya, -dev, -lena, -sam) so tapping a chip opens the same sheet.
Deleted ids live in MOCK_NOTES so a delete survives across calls under `?mock=1`.
"""

glob MOCK_NOTES: dict[str, any] = {"gone": []};

glob _NOTES: list[dict[str, any]] = [
         {
             "id": "mock-note-1", "captured_at": "2026-09-26T09:15:00Z", "kind": "debrief",
             "audio_ref": "",
             "text": "Caught up with Maya over coffee. She's still running carbon removal purchasing at Stripe Climate and offered to intro me to the climate hardware funds she buys alongside. I said I'd send her the Kiln Labs one-pager this weekend.",
             "people": [{"id": "mock-person-maya", "name": "Maya Chen"}],
             "counts": {"facts": 1, "intents": 1, "promises": 1}
         },
         {
             "id": "mock-note-2", "captured_at": "2026-09-26T08:02:00Z", "kind": "about_me",
             "audio_ref": "",
             "text": "About me: building Kiln Labs, pre-seed, targeting climate hardware manufacturers. Looking for warm intros to pre-seed climate funds and to plant operators who'd pilot the kiln.",
             "people": [],
             "counts": {"facts": 0, "intents": 2, "promises": 0}
         },
         {
             "id": "mock-note-3", "captured_at": "2026-09-25T19:40:00Z", "kind": "paste",
             "audio_ref": "",
             "text": "Dev Okafor, Associate at Great Lakes Angels. Screens energy deals for an angel group that writes pre-seed checks.",
             "people": [{"id": "mock-person-dev", "name": "Dev Okafor"}],
             "counts": {"facts": 1, "intents": 0, "promises": 0}
         },
         {
             "id": "mock-note-4", "captured_at": "2026-09-25T11:05:00Z", "kind": "paste",
             "audio_ref": "",
             "text": "Badge photo: Lena Park, President at Campus Energy Club. lena@campusenergy.org, Ross climate panel badge.",
             "people": [{"id": "mock-person-lena", "name": "Lena Park"}],
             "counts": {"facts": 2, "intents": 0, "promises": 0}
         },
         {
             "id": "mock-note-5", "captured_at": "2026-09-24T17:20:00Z", "kind": "debrief",
             "audio_ref": "",
             "text": "Toured Sam's casting plant. Told him I'd send over the kiln retrofit spec once it's ready.",
             "people": [{"id": "mock-person-sam", "name": "Sam Ruiz"}],
             "counts": {"facts": 1, "intents": 0, "promises": 1}
         },
         {
             "id": "mock-note-6", "captured_at": "2026-09-24T09:00:00Z", "kind": "import",
             "audio_ref": "",
             "text": "Imported 12 contacts from a conference badge scan CSV export.",
             "people": [],
             "counts": {"facts": 0, "intents": 0, "promises": 0}
         },
         {
             "id": "mock-note-7", "captured_at": "2026-09-22T20:10:00Z", "kind": "debrief",
             "audio_ref": "",
             "text": "Kickoff conversation about the climate hardware search with both Lena and Dev on a call. Lena said the Campus Energy Club's speaker series brought in two climate VCs last spring and she still has their emails. Dev screens energy deals for Great Lakes Angels and thinks a pre-seed check is realistic once we have a plant pilot lined up. Both agreed to keep an eye out for warm intros to plant operators too.",
             "people": [{"id": "mock-person-lena", "name": "Lena Park"}, {"id": "mock-person-dev", "name": "Dev Okafor"}],
             "counts": {"facts": 2, "intents": 1, "promises": 0}
         },
         {
             "id": "mock-note-8", "captured_at": "2026-09-22T10:30:00Z", "kind": "paste",
             "audio_ref": "",
             "text": "Market research note: three regional casting plants are the likeliest early pilots for the kiln retrofit.",
             "people": [],
             "counts": {"facts": 1, "intents": 0, "promises": 0}
         }
     ];

def _gone() -> list[str] {
    return MOCK_NOTES["gone"] as list[str];
}

def _preview(text: str) -> str {
    if len(text) <= 160 {
        return text;
    }
    return text[0:160] + "…";
}

def _row(n: dict[str, any]) -> dict[str, any] {
    return {
        "note": {
            "_jac_id": n["id"], "text": n["text"], "kind": n["kind"],
            "captured_at": n["captured_at"], "audio_ref": n["audio_ref"]
        },
        "people": n["people"],
        "counts": n["counts"],
        "text_preview": _preview(n["text"] as str)
    };
}

"""ListNotes(limit, before, kind) -> report rows, newest first."""
def:pub mock_list_notes(limit: int, before: str, kind: str) -> list[dict[str, any]] {
    gone: list[str] = _gone();
    out: list[dict[str, any]] = [];
    for n in _NOTES {
        nid: str = n["id"] as str;
        if nid in gone {
            continue;
        }
        if kind and (n["kind"] as str) != kind {
            continue;
        }
        if before and not ((n["captured_at"] as str) < before) {
            continue;
        }
        out = out + [_row(n)];
        if len(out) >= limit {
            break;
        }
    }
    return out;
}

"""DeleteNote(note_id) -> [{ deleted, kept_people: int }] | [{ error: "not_found" }].
`kept_people` is a COUNT (matches notes.sv.jac, SOH-219) — the mentioned people
are never deleted, only their count is reported."""
def:pub mock_delete_note(note_id: str) -> list[dict[str, any]] {
    gone: list[str] = _gone();
    if note_id in gone {
        return [{"error": "not_found"}];
    }
    found: dict[str, any] | None = None;
    for n in _NOTES {
        if (n["id"] as str) == note_id {
            found = n;
        }
    }
    if found is None {
        return [{"error": "not_found"}];
    }
    n2 = found as dict[str, any];
    MOCK_NOTES["gone"] = gone + [note_id];
    kept: int = len(n2["people"] as list[dict[str, any]]);
    return [{"deleted": n2["counts"], "kept_people": kept}];
}
