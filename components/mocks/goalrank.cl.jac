"""Mock for `GoalRank(goal_id: str)` — SOH-169. OWNER: Person B.

Returns EXACTLY the contract shape (contracts/walkers.md, v1.1 — strength is
strong|medium|weak), best-first. Pseudonymous demo people only.
`days_since_contact` is display only. Different rows per goal so a goal switch
is visible under `?mock=1`:
  - mock-goal-raise: 4 rows (investors first); mock-goal-pilot: 3 rows (plants first)
  - a goal whose text contains "#empty" -> []; "#partial" -> the walker's
    deterministic-fallback shape (reason "Ranking unavailable right now; …")
  - any other goal: 2 generic rows that quote the goal text.
"""

import from .goals { mock_goal_text }

def:pub mock_goalrank(goal_id: str) -> list[dict[str, any]] {
    if goal_id == "mock-goal-pilot" {
        return _pilot_rows();
    }
    if goal_id == "mock-goal-raise" {
        return _raise_rows();
    }
    text: str = mock_goal_text(goal_id);
    if "#empty" in text {
        return [];
    }
    if "#partial" in text {
        return _partial_rows();
    }
    if "#many" in text {
        return _raise_rows() + _many_extra_rows();
    }
    return _generic_rows(text);
}

def _person(pid: str, name: str, org: str, title: str) -> dict[str, any] {
    return {"_jac_id": pid, "name": name, "org": org, "title": title, "status": "confirmed"};
}

def _ev(eid: str, kind: str, observed_at: str, span: str) -> dict[str, any] {
    return {"id": eid, "kind": kind, "observed_at": observed_at, "span": span};
}

def _pilot_rows() -> list[dict[str, any]] {
    return [
        {
            "person": _person("mock-person-sam", "Sam Ruiz", "Ruiz Castings", "Plant manager"),
            "label": "cold",
            "strength": "strong",
            "reason": "His card says he wants to cut peak-hour energy costs — exactly what a pilot would test.",
            "evidence": [
                _ev("mock-card-sam", "card", "2026-08-30T12:00:00Z", "Looking for: ways to cut peak-hour energy costs")
            ],
            "days_since_contact": None,
            "opener": "Sam — your card mentions peak-hour energy costs. Could I show you what a thermal battery would save?"
        },
        {
            "person": _person("mock-person-lena", "Lena Park", "Campus Energy Club", "President"),
            "label": "route",
            "strength": "medium",
            "reason": "Ran the club's plant tour series and knows two facilities managers in Ann Arbor.",
            "evidence": [
                _ev("mock-note-lena-tour", "note", "2026-09-20T15:30:00Z", "Lena set up the club's plant tours with two Ann Arbor facilities managers."),
                _ev("mock-intent-lena", "intent", "2026-09-20T15:30:00Z", "Lena offered to connect founders with speaker-series VCs.")
            ],
            "days_since_contact": 6,
            "opener": "Lena — would one of the plant-tour facilities managers take a 15-minute call about a pilot?"
        },
        {
            "person": _person("mock-person-dev", "Dev Okafor", "Great Lakes Angels", "Associate"),
            "label": "known",
            "strength": "weak",
            "reason": "Sees manufacturing deals, but nothing in your notes ties him to a plant.",
            "evidence": [],
            "days_since_contact": 14,
            "opener": ""
        }
    ];
}

def _partial_rows() -> list[dict[str, any]] {
    return [
        {
            "person": _person("mock-person-maya", "Maya Chen", "Stripe Climate", "Carbon removal lead"),
            "label": "known",
            "strength": "medium",
            "reason": "Ranking unavailable right now; ordered by the evidence in your notes.",
            "evidence": [
                _ev("mock-fact-maya-1", "fact", "2026-09-26T16:10:00Z", "Maya Chen — worked together at Stripe.")
            ],
            "days_since_contact": 3,
            "opener": "Hi Maya Chen, I was thinking about what you mentioned about Maya Chen — worked together at Stripe.."
        },
        {
            "person": _person("mock-person-dev", "Dev Okafor", "Great Lakes Angels", "Associate"),
            "label": "known",
            "strength": "weak",
            "reason": "Ranking unavailable right now; ordered by the evidence in your notes.",
            "evidence": [],
            "days_since_contact": 14,
            "opener": ""
        }
    ];
}

def _generic_rows(goal_text: str) -> list[dict[str, any]] {
    return [
        {
            "person": _person("mock-person-lena", "Lena Park", "Campus Energy Club", "President"),
            "label": "route",
            "strength": "medium",
            "reason": "Hosts a speaker series that keeps bringing in people who'd help with “" + goal_text + "”.",
            "evidence": [
                _ev("mock-intent-lena", "intent", "2026-09-20T15:30:00Z", "Lena offered to connect founders with speaker-series VCs.")
            ],
            "days_since_contact": 6,
            "opener": "Lena — is anyone from the speaker series a fit for what I'm working on next?"
        },
        {
            "person": _person("mock-person-maya", "Maya Chen", "Stripe Climate", "Carbon removal lead"),
            "label": "known",
            "strength": "weak",
            "reason": "Only her role lines up; nothing in your notes says more yet.",
            "evidence": [],
            "days_since_contact": 3,
            "opener": ""
        }
    ];
}

"""SOH-213: two more rows so a goal ending in #many ranks six (the Home
preview shows five + "See all (6)")."""
def _many_extra_rows() -> list[dict[str, any]] {
    return [
        {
            "person": _person("mock-person-priya", "Priya Raman", "Michigan Ross", "MBA candidate"),
            "label": "route",
            "strength": "weak",
            "reason": "Runs the Ross energy club's investor night.",
            "evidence": [
                _ev("mock-note-priya", "note", "2026-09-18T20:00:00Z", "Priya said the investor night still has two demo slots.")
            ],
            "days_since_contact": 8,
            "opener": ""
        },
        {
            "person": _person("mock-person-omar", "Omar Haddad", "DTE Energy", "Grid analyst"),
            "label": "cold",
            "strength": "weak",
            "reason": "Models industrial peak load; a useful sanity check on the pitch numbers.",
            "evidence": [],
            "days_since_contact": None,
            "opener": ""
        }
    ];
}

def _raise_rows() -> list[dict[str, any]] {
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
                },
                {
                    "id": "mock-intent-maya",
                    "kind": "intent",
                    "observed_at": "2026-09-23T18:40:00Z",
                    "span": "Maya said she'd happily intro founders to the climate hardware funds she buys alongside."
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
