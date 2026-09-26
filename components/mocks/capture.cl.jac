"""Mock for `Capture(text: str, kind: str)` — SOH-166. OWNER: Person B.

Returns EXACTLY the contract shape (contracts/walkers.md, v1.1):
{ note_id, people, facts, intents, promises, ties }. People are derived from the
lines of `text` ("Name — how you know them.") so the onboarding flow feels real.
Delete this file when Capture is live.
"""

glob _NL: str = chr(10);

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

def:pub mock_capture(text: str, kind: str) -> dict {
    now: str = "2026-09-26T16:10:00Z";
    note_id: str = "mock-note-" + kind;
    people: list[dict] = [];
    facts: list[dict] = [];
    n: int = 0;
    for raw in text.split(_NL) {
        line: str = raw.strip();
        if not line {
            continue;
        }
        n = n + 1;
        parts: list[str] = _split_line(line);
        pid: str = "mock-person-" + str(n);
        people = people + [
            {
                "person": {
                    "_jac_id": pid,
                    "name": parts[0],
                    "org": "",
                    "title": "",
                    "status": "confirmed"
                },
                "is_new": True,
                "ambiguous_with": []
            }
        ];
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
    return {
        "note_id": note_id,
        "people": people,
        "facts": facts,
        "intents": [],
        "promises": [],
        "ties": []
    };
}
