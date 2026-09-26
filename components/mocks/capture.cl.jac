"""Mock for `Capture(text: str, kind: str)` — SOH-166 / SOH-167. OWNER: Person B.

Returns EXACTLY the contract shape (contracts/walkers.md, v1.1):
{ note_id, people, facts, intents, promises, ties }.

- kind="paste" (onboarding step 3): people derived from the lines of `text`
  ("Name — how you know them.").
- kind="debrief": a fixed, rich extraction of MOCK_DEBRIEF (2 people, one
  ambiguous; 2 facts; 1 intent; 1 promise; 1 tie). Spans are literal substrings
  of MOCK_DEBRIEF, so type/paste that text to see highlighted receipts.
- a debrief containing "#empty" returns the failed-extraction shape (all lists
  empty, note_id still set), like the real walker when Gemini fails.

Every person a mock capture returns is kept in MOCK_STORE so `mock_list_people`
can stand in for ListPeople in mock mode (home refresh after Done).
"""

glob _NL: str = chr(10),
     MOCK_DEBRIEF: str = "Met Priya Raman at the Ross climate panel. She's a partner at Great Lakes Angels and leads their hardware deals. She's looking for student founders working on grid storage. Priya knows Dev from the spring pitch night. Dev just started at Rivian on the battery pack team. I promised to send Priya our deck by Friday.",
     MOCK_STORE: dict = {"people": [], "n": 0};

def _split_line(line: str) -> list[str] {
    seps: list[str] = [" — ", " – ", " - ", ": "];
    for sep in seps {
        if sep in line {
            idx: int = line.index(sep);
            return [line[:idx].strip(), line[idx + len(sep):].strip()];
        }
    }
    return [line.strip().rstrip("."), ""];
}

def _remember(person: dict) -> None {
    kept: list[dict] = MOCK_STORE["people"] as list[dict];
    for p in kept {
        if p["_jac_id"] == person["_jac_id"] {
            return;
        }
    }
    MOCK_STORE["people"] = kept + [person];
}

"""First stored person whose first name is `first`, else None."""
def _find_first_name(first: str) -> dict | None {
    for p in MOCK_STORE["people"] as list[dict] {
        name: str = p["name"] as str;
        if name.split(" ")[0].lower() == first.lower() and name.lower() != first.lower() {
            return p;
        }
    }
    return None;
}

"""Exchange mock (SOH-172): ClaimReveal adds the revealed person to your people."""
def:pub mock_remember_person(person: dict) -> None {
    _remember(person);
}

def:pub mock_list_people() -> list[dict] {
    return MOCK_STORE["people"] as list[dict];
}

def _empty(note_id: str) -> dict {
    return {
        "note_id": note_id,
        "people": [],
        "facts": [],
        "intents": [],
        "promises": [],
        "ties": []
    };
}

def _mock_paste(text: str, note_id: str, now: str) -> dict {
    people: list[dict] = [];
    facts: list[dict] = [];
    n: int = MOCK_STORE["n"] as int;
    for raw in text.split(_NL) {
        line: str = raw.strip();
        if not line {
            continue;
        }
        n = n + 1;
        parts: list[str] = _split_line(line);
        pid: str = "mock-person-" + str(n);
        person: dict = {
            "_jac_id": pid,
            "name": parts[0],
            "org": "",
            "title": "",
            "status": "confirmed"
        };
        _remember(person);
        people = people + [{"person": person, "is_new": True, "ambiguous_with": []}];
        if parts[1] {
            facts = facts + [
                {
                    "fact": {
                        "_jac_id": "mock-fact-" + str(n),
                        "text": parts[1].rstrip("."),
                        "observed_at": now,
                        "valid_to": "",
                        "status": "reported",
                        "source_kind": "self",
                        "source_url": ""
                    },
                    "about": pid,
                    "span": line
                }
            ];
        }
    }
    MOCK_STORE["n"] = n;
    out: dict = _empty(note_id);
    out["people"] = people;
    out["facts"] = facts;
    return out;
}

def _mock_debrief(note_id: str, now: str) -> dict {
    priya: dict = {
        "_jac_id": "mock-person-priya",
        "name": "Priya Raman",
        "org": "Great Lakes Angels",
        "title": "Partner",
        "status": "confirmed"
    };
    dev: dict = {
        "_jac_id": "mock-person-dev",
        "name": "Dev",
        "org": "",
        "title": "",
        "status": "proposed"
    };
    # Like the real walker: a bare first name that matches someone you already
    # know is flagged, not merged. Unknown id -> the review shows nothing.
    known_dev: dict | None = _find_first_name("Dev");
    dev_ambiguous: list[str] = [(known_dev["_jac_id"] as str) if known_dev else "mock-person-unknown"];
    _remember(priya);
    _remember(dev);
    return {
        "note_id": note_id,
        "people": [
            {"person": priya, "is_new": True, "ambiguous_with": []},
            {"person": dev, "is_new": True, "ambiguous_with": dev_ambiguous}
        ],
        "facts": [
            {
                "fact": {
                    "_jac_id": "mock-fact-priya",
                    "text": "Partner at Great Lakes Angels; leads their hardware deals",
                    "observed_at": now,
                    "status": "reported",
                    "source_kind": "reported"
                },
                "about": "mock-person-priya",
                "span": "She's a partner at Great Lakes Angels and leads their hardware deals."
            },
            {
                "fact": {
                    "_jac_id": "mock-fact-dev",
                    "text": "Just started at Rivian on the battery pack team",
                    "observed_at": now,
                    "status": "reported",
                    "source_kind": "reported"
                },
                "about": "mock-person-dev",
                "span": "Dev just started at Rivian on the battery pack team."
            }
        ],
        "intents": [
            {
                "intent": {
                    "_jac_id": "mock-intent-priya",
                    "kind": "need",
                    "text": "Looking for student founders working on grid storage",
                    "expires_at": ""
                },
                "about": "mock-person-priya",
                "span": "She's looking for student founders working on grid storage."
            }
        ],
        "promises": [
            {
                "promise": {
                    "_jac_id": "mock-promise-priya",
                    "text": "Send our deck",
                    "due": "Friday",
                    "done": False
                },
                "to": "mock-person-priya",
                "span": "I promised to send Priya our deck by Friday."
            }
        ],
        "ties": [
            {
                "from": "mock-person-priya",
                "to": "mock-person-dev",
                "span": "Priya knows Dev from the spring pitch night."
            }
        ]
    };
}

def:pub mock_capture(text: str, kind: str) -> dict {
    now: str = "2026-09-26T16:10:00Z";
    note_id: str = "mock-note-" + kind;
    if kind == "paste" {
        return _mock_paste(text, note_id, now);
    }
    if "#empty" in text {
        return _empty(note_id);
    }
    return _mock_debrief(note_id, now);
}
