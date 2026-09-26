"""Mock for `GoalRank(goal_id: str)` — SOH-169. OWNER: Person B.

Returns EXACTLY the contract shape (contracts/walkers.md, v1.1 — strength is
strong|medium|weak), best-first, 4 rows. Pseudonymous demo people only.
`days_since_contact` is display only. Delete this file when GoalRank is live.
"""

def:pub mock_goalrank(goal_id: str) -> list[dict] {
    return [
        {
            "person": {
                "_jac_id": "mock-person-maya",
                "name": "Maya Chen",
                "org": "Stripe Climate",
                "title": "Carbon removal lead",
                "status": "confirmed"
            },
            "label": "known",
            "strength": "strong",
            "reason": "Runs Stripe's climate purchasing and said she knows pre-seed hardware funds.",
            "evidence": [
                {
                    "id": "mock-fact-maya-1",
                    "kind": "fact",
                    "observed_at": "2026-09-26T16:10:00Z",
                    "span": "Maya Chen — worked together at Stripe."
                }
            ],
            "days_since_contact": 3,
            "opener": "Maya — I'm raising a pre-seed for Kiln Labs. Which climate hardware funds would you ask first?"
        },
        {
            "person": {
                "_jac_id": "mock-person-dev",
                "name": "Dev Okafor",
                "org": "Great Lakes Angels",
                "title": "Associate",
                "status": "confirmed"
            },
            "label": "known",
            "strength": "medium",
            "reason": "Screens energy deals for an angel group that writes pre-seed checks.",
            "evidence": [
                {
                    "id": "mock-note-dev",
                    "kind": "note",
                    "observed_at": "2026-09-12T19:00:00Z",
                    "span": "Dev mentioned his group is looking at more energy deals."
                }
            ],
            "days_since_contact": 14,
            "opener": "Dev — you mentioned your group wants more energy deals. Could I send a two-page Kiln Labs memo?"
        },
        {
            "person": {
                "_jac_id": "mock-person-lena",
                "name": "Lena Park",
                "org": "Campus Energy Club",
                "title": "President",
                "status": "confirmed"
            },
            "label": "route",
            "strength": "medium",
            "reason": "Knows two climate VCs from the club's speaker series.",
            "evidence": [
                {
                    "id": "mock-intent-lena",
                    "kind": "intent",
                    "observed_at": "2026-09-20T15:30:00Z",
                    "span": "Lena offered to connect founders with speaker-series VCs."
                }
            ],
            "days_since_contact": 6,
            "opener": "Lena — would either of the speaker-series VCs be open to a 20-minute Kiln Labs call?"
        },
        {
            "person": {
                "_jac_id": "mock-person-sam",
                "name": "Sam Ruiz",
                "org": "Ruiz Castings",
                "title": "Plant manager",
                "status": "confirmed"
            },
            "label": "cold",
            "strength": "weak",
            "reason": "Operates the kind of plant Kiln Labs targets; a pilot story helps the raise.",
            "evidence": [
                {
                    "id": "mock-card-sam",
                    "kind": "card",
                    "observed_at": "2026-08-30T12:00:00Z",
                    "span": "Looking for: ways to cut peak-hour energy costs"
                }
            ],
            "days_since_contact": None,
            "opener": "Sam — your card mentions peak-hour energy costs. Could I show you what a thermal battery would save?"
        }
    ];
}
