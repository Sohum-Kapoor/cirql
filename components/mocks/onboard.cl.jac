"""Mock for `OnboardMe(about: str, name: str = "")` — SOH-164/SOH-227. OWNER: Person B.

Returns EXACTLY the contract shape (contracts/walkers.md, v1.1):
{ me, interests, goals, intents, card, note_id }. Exactly one goal is active.
Pseudonymous demo persona: a student founder raising a climate-tech pre-seed.
`name` (the signup step 1 field), when non-empty, wins over the demo persona's
name — mirrors OnboardMe's real "name wins" rule. Delete this file when OnboardMe
no longer needs a mock fallback under ?mock=1.
"""

def:pub mock_onboardme(about: str, name: str = "") -> dict {
    now: str = "2026-09-26T16:05:00Z";
    display_name: str = name.strip() or "Rowan Vale";
    return {
        "me": {
            "_jac_id": "mock-me-rowan",
            "name": display_name,
            "about": about
        },
        "interests": [
            {"_jac_id": "mock-int-1", "topic": "thermal energy storage"},
            {"_jac_id": "mock-int-2", "topic": "industrial decarbonization"},
            {"_jac_id": "mock-int-3", "topic": "hardware startups"},
            {"_jac_id": "mock-int-4", "topic": "climate policy"}
        ],
        "goals": [
            {
                "_jac_id": "mock-goal-raise",
                "text": "Raise a $750k pre-seed for Kiln Labs by December",
                "created_at": now,
                "active": True
            },
            {
                "_jac_id": "mock-goal-pilot",
                "text": "Land a first pilot with a Midwest manufacturer",
                "created_at": now,
                "active": False
            }
        ],
        "intents": [
            {
                "_jac_id": "mock-intent-1",
                "kind": "need",
                "text": "Intros to climate-tech pre-seed investors",
                "expires_at": "2026-12-31T00:00:00Z",
                "source_kind": "self"
            },
            {
                "_jac_id": "mock-intent-2",
                "kind": "offer",
                "text": "Can help student founders with hardware prototyping",
                "expires_at": "",
                "source_kind": "self"
            }
        ],
        "card": {
            "_jac_id": "mock-card-rowan",
            "handle": "rowan-kiln",
            "headline": "Founder, Kiln Labs: thermal batteries for small factories",
            "about": "Student founder building low-cost thermal storage so small manufacturers can run on cheap off-peak power.",
            "looking_for": [
                "Pre-seed investors in climate hardware",
                "Plant managers open to a pilot"
            ],
            "can_offer": [
                "Hardware prototyping advice",
                "Intros to the campus energy club"
            ],
            "links": ["https://example.com/kiln-labs"],
            "contact_pref": "Email first, then a 20-minute call",
            "visibility": "link",
            "updated_at": now
        },
        "note_id": "mock-note-about-me"
    };
}
