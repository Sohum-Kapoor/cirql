"""Mocks for the card editor's read/write pair (SOH-179). OWNER: Person B.

`PublishCard` (full form, not the narrow `publish_card` in components/api.cl.jac)
and `get_card` are BOTH already live (cards.sv.jac, SOH-178) — these only back
the `?mock=1` dev toggle, same idiom every other wrapper in components/api.cl.jac
uses. Delete this file if that toggle is ever dropped for the card editor.
"""

glob _MOCK_HANDLE: str = "rowan-vale-7f3a";

glob _MOCK_CARD: dict = {
    "id": "mock-card-1",
    "handle": _MOCK_HANDLE,
    "name": "Rowan Vale",
    "headline": "Building Kiln Labs — thermal storage for factories",
    "about": "Raising a pre-seed for hardware that stores industrial waste heat. Always happy to swap notes with other student founders.",
    "looking_for": ["a climate-tech VC who takes cold student pitches", "a founder who has raised for hardware"],
    "can_offer": ["intros into decarbonization pilots", "feedback on hardware pitch decks"],
    "links": ["kilnlabs.com"],
    "contact_pref": "email: rowan@kilnlabs.com",
    "visibility": "link",
    "updated_at": "2026-09-26T18:00:00Z"
};

"""The owner's own card, as the editor would read it (mirrors ExportGraph's
`card` field, contracts/walkers.md SOH-210: adds `visibility`, `get_card`
never returns). `None` before the first save (contract shape: `card: {...} |
null`)."""
def:pub mock_my_card() -> dict | None {
    return {**_MOCK_CARD};
}

"""PublishCard(...) -> Card. Overwrites every field with whatever the editor
sent (the mock always applies every arg — the real walker only overwrites
non-empty ones, but the editor always sends its whole form state)."""
def:pub mock_publish_card_full(
    headline: str, about: str, looking_for: list[str], can_offer: list[str],
    links: list[str], contact_pref: str, visibility: str, name: str
) -> dict {
    _MOCK_CARD["headline"] = headline;
    _MOCK_CARD["about"] = about;
    _MOCK_CARD["looking_for"] = looking_for;
    _MOCK_CARD["can_offer"] = can_offer;
    _MOCK_CARD["links"] = links;
    _MOCK_CARD["contact_pref"] = contact_pref;
    _MOCK_CARD["visibility"] = visibility;
    if name {
        _MOCK_CARD["name"] = name;
    }
    _MOCK_CARD["updated_at"] = "2026-09-26T18:10:00Z";
    return {**_MOCK_CARD};
}

"""get_card(handle) -> Card fields only, never `visibility` — refuses a
handshake_only card exactly like the live def:pub does."""
def:pub mock_get_card(handle: str) -> dict {
    empty: dict = {
        "found": False, "name": "", "handle": "", "headline": "", "about": "",
        "looking_for": [], "can_offer": [], "links": [], "contact_pref": "", "updated_at": ""
    };
    if handle != _MOCK_CARD["handle"] or _MOCK_CARD["visibility"] != "link" {
        return empty;
    }
    return {
        "found": True,
        "name": _MOCK_CARD["name"],
        "handle": _MOCK_CARD["handle"],
        "headline": _MOCK_CARD["headline"],
        "about": _MOCK_CARD["about"],
        "looking_for": _MOCK_CARD["looking_for"],
        "can_offer": _MOCK_CARD["can_offer"],
        "links": _MOCK_CARD["links"],
        "contact_pref": _MOCK_CARD["contact_pref"],
        "updated_at": _MOCK_CARD["updated_at"]
    };
}
