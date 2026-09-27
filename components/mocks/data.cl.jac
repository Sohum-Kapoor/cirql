"""Mocks for the settings data panel (SOH-222): export, archived people,
delete-my-data. OWNER: Person B.

Shapes match the brief (contracts/walkers.md has `ExportGraph()`; `ListArchived`,
`RestorePerson`, `DeleteMyData` are on a parallel server branch not yet
contracted — these mirror the brief's exact shapes so the panel renders
identically once the live walkers land). State lives in MOCK_DATA so a Restore
or a Delete survives across calls under `?mock=1`, same idiom as
`mocks/person.cl.jac`'s MOCK_PERSON.
"""

glob MOCK_DATA: dict[str, any] = {"archived": ["mock-archived-priya", "mock-archived-tom"], "deleted": False};

glob _ARCHIVED: dict[str, any] = {
         "mock-archived-priya": {"name": "Priya Nair", "org": "Northline Robotics", "title": "Ops lead"},
         "mock-archived-tom": {"name": "Tom Reyes", "org": "", "title": "Freelance welder"}
     };

def _archived_person(pid: str) -> dict[str, any] {
    p: any = _ARCHIVED[pid];
    return {"_jac_id": pid, "name": p["name"], "org": p["org"], "title": p["title"], "status": "confirmed", "archived": True};
}

"""ExportGraph() -> the caller's whole graph as one JSON dict (contracts/walkers.md).
A small, representative shape — enough for the panel to show counts and for a
downloaded file to be real JSON."""
def:pub mock_export_graph() -> dict[str, any] {
    return {
        "exported_at": "2026-09-26T20:00:00Z",
        "me": {"id": "mock-me", "name": "You", "about": "Building Kiln Labs."},
        "goals": [{"id": "mock-goal-1", "text": "Raise a pre-seed round for Kiln Labs", "active": True}],
        "card": {
            "id": "mock-card-1", "handle": "you", "name": "You", "headline": "Founder, Kiln Labs",
            "about": "Building Kiln Labs.", "looking_for": "climate hardware investors",
            "can_offer": "manufacturing ops advice", "links": [], "contact_pref": "email",
            "visibility": "handshake_only", "updated_at": "2026-09-26T18:00:00Z"
        },
        "people": [
            {"id": "mock-person-maya", "name": "Maya Chen", "org": "Stripe Climate", "title": "Carbon removal lead", "status": "confirmed"},
            {"id": "mock-person-dev", "name": "Dev Okafor", "org": "Great Lakes Angels", "title": "Associate", "status": "confirmed"}
        ],
        "knows": [
            {"from": "mock-me", "to": "mock-person-maya", "status": "confirmed", "how_met": "worked together at Stripe", "source_note": "mock-note-1", "span": "", "last_contact": "2026-09-20T10:00:00Z"}
        ],
        "reported": [],
        "facts": [
            {"id": "mock-fact-1", "about": "mock-person-maya", "text": "Leads carbon removal purchasing at Stripe", "observed_at": "2026-09-10T00:00:00Z", "valid_to": "", "status": "confirmed", "source_kind": "self", "source_url": "", "source_note": "mock-note-1", "span": "Maya leads carbon removal purchasing at Stripe."}
        ],
        "intents": [],
        "promises": [
            {"id": "mock-promise-maya", "to": "mock-person-maya", "text": "Send Maya the Kiln Labs one-pager", "due": "2026-09-28", "source_note": "mock-note-1", "span": "I said I'd send Maya the one-pager this weekend."}
        ],
        "notes": [
            {"id": "mock-note-1", "kind": "debrief", "text": "Caught up with Maya about Stripe's climate purchasing.", "captured_at": "2026-09-10T00:00:00Z", "audio_ref": ""}
        ],
        "counts": {"people": 2, "facts": 1, "intents": 0, "promises": 1, "notes": 1},
        "truncated": False
    };
}

"""ExportContacts() -> the caller's active people as one VERSION:3.0 vCard
file (contracts/walkers.md). A small, representative shape matching the two
people in `mock_export_graph` above — enough for the panel to show a count
and for a downloaded file to be a real .vcf."""
def:pub mock_export_contacts() -> dict[str, any] {
    vcf: str = (
        "BEGIN:VCARD\r\n" +
        "VERSION:3.0\r\n" +
        "N:Chen;Maya;;;\r\n" +
        "FN:Maya Chen\r\n" +
        "ORG:Stripe Climate\r\n" +
        "TITLE:Carbon removal lead\r\n" +
        "NOTE:Met via worked together at Stripe\r\n" +
        "END:VCARD\r\n" +
        "BEGIN:VCARD\r\n" +
        "VERSION:3.0\r\n" +
        "N:Okafor;Dev;;;\r\n" +
        "FN:Dev Okafor\r\n" +
        "ORG:Great Lakes Angels\r\n" +
        "TITLE:Associate\r\n" +
        "END:VCARD\r\n"
    );
    return {"vcf": vcf, "count": 2};
}

"""ListArchived() -> [Person] (archived == True)."""
def:pub mock_list_archived() -> list[dict[str, any]] {
    ids: list[str] = MOCK_DATA["archived"] as list[str];
    return [_archived_person(pid) for pid in ids];
}

"""RestorePerson(person_id) -> [Person] (remaining archived people)."""
def:pub mock_restore_person(person_id: str) -> list[dict[str, any]] {
    ids: list[str] = MOCK_DATA["archived"] as list[str];
    left: list[str] = [pid for pid in ids if pid != person_id];
    MOCK_DATA["archived"] = left;
    return [_archived_person(pid) for pid in left];
}

"""DeleteMyData(confirm) -> { deleted: {...counts}, ok } | { error: "confirm_mismatch" }."""
def:pub mock_delete_my_data(confirm: str) -> dict[str, any] {
    if confirm != "DELETE" {
        return {"error": "confirm_mismatch"};
    }
    MOCK_DATA["deleted"] = True;
    return {
        "deleted": {"people": 6, "facts": 14, "intents": 3, "promises": 2, "notes": 9, "goals": 1, "cards": 1, "circles": 2, "events": 1},
        "ok": True
    };
}

"""Mock DeleteAccount: same gate as DeleteMyData, plus the identity flags."""
def:pub mock_delete_account(confirm: str) -> dict[str, any] {
    base: dict[str, any] = mock_delete_my_data(confirm);
    if base["error"] {
        return base;
    }
    return {"ok": confirm == "DELETE", "deleted": base["deleted"], "identity_removed": False, "identity_disabled": confirm == "DELETE"};
}
