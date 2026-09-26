"""Mocks for the person sheet + Today list — SOH-207 / SOH-187. OWNER: Person B.

Exact contract shapes (contracts/walkers.md): `PersonDetail(person_id)`,
`Brief(person_id, voice)`, `ListPromises()`, `CompletePromise(promise_id, done)`,
`DraftFollowUp(person_id, intent)`, `Forget(id)`. Each returns the walker's
report LIST. Same pseudonymous people as the GoalRank mock (mock-person-maya,
-dev, -lena, -sam). State (promise done flags, forgotten people) lives in the
MOCK_PERSON glob so a tick or a Forget survives across calls under `?mock=1`.
"""

glob MOCK_PERSON: dict[str, any] = {"done": {}, "gone": []};

glob _PEOPLE: dict[str, any] = {
         "mock-person-maya": {
             "name": "Maya Chen", "org": "Stripe Climate", "title": "Carbon removal lead",
             "how_met": "worked together at Stripe", "label": "known", "strength": "strong",
             "reason": "Runs Stripe's climate purchasing and said she knows pre-seed hardware funds.",
             "opener": "Maya — which climate hardware funds would you ask first?"
         },
         "mock-person-dev": {
             "name": "Dev Okafor", "org": "Great Lakes Angels", "title": "Associate",
             "how_met": "spring pitch night", "label": "known", "strength": "medium",
             "reason": "Screens energy deals for an angel group that writes pre-seed checks.",
             "opener": ""
         },
         "mock-person-lena": {
             "name": "Lena Park", "org": "Campus Energy Club", "title": "President",
             "how_met": "Ross climate panel", "label": "route", "strength": "medium",
             "reason": "Knows two climate VCs from the club's speaker series.",
             "opener": ""
         },
         "mock-person-sam": {
             "name": "Sam Ruiz", "org": "Ruiz Castings", "title": "Plant manager",
             "how_met": "", "label": "cold", "strength": "weak",
             "reason": "Operates the kind of plant Kiln Labs targets.",
             "opener": ""
         }
     };

glob _PROMISES: list[dict[str, any]] = [
         {"id": "mock-promise-maya", "to": "mock-person-maya", "text": "Send Maya the Kiln Labs one-pager", "due": "2026-09-28", "span": "I said I'd send Maya the one-pager this weekend."},
         {"id": "mock-promise-dev", "to": "mock-person-dev", "text": "Intro Dev to the Rivian battery team", "due": "", "span": "Told Dev I'd intro him to the Rivian battery folks."},
         {"id": "mock-promise-lena", "to": "mock-person-lena", "text": "Speak at the club's October meetup", "due": "2026-10-15", "span": "Agreed to speak at Lena's October meetup."}
     ];

def _person(pid: str) -> dict[str, any] | None {
    if pid in (MOCK_PERSON["gone"] as list[str]) {
        return None;
    }
    p: any = _PEOPLE[pid];
    if not p {
        return None;
    }
    return {"_jac_id": pid, "name": p["name"], "org": p["org"], "title": p["title"], "status": "confirmed"};
}

def _is_done(prid: str) -> bool {
    return bool((MOCK_PERSON["done"] as dict)[prid]);
}

def _promise_node(pr: dict[str, any]) -> dict[str, any] {
    return {"_jac_id": pr["id"], "text": pr["text"], "due": pr["due"], "done": _is_done(pr["id"] as str)};
}

def _facts(pid: str) -> list[dict[str, any]] {
    if pid == "mock-person-maya" {
        return [
            {"fact": {"_jac_id": "mock-fact-maya-2", "text": "Leads carbon removal purchasing at Stripe Climate", "observed_at": "2026-09-23T18:40:00Z", "valid_to": "", "status": "reported", "source_kind": "web", "source_url": "https://stripe.com/climate"}, "age_days": 3, "source_note_id": "", "span": "Carbon removal lead, Stripe Climate"},
            {"fact": {"_jac_id": "mock-fact-maya-1", "text": "Worked together at Stripe", "observed_at": "2026-07-12T16:10:00Z", "valid_to": "", "status": "confirmed", "source_kind": "reported", "source_url": ""}, "age_days": 76, "source_note_id": "mock-note-maya", "span": "Maya Chen — worked together at Stripe."}
        ];
    }
    return [
        {"fact": {"_jac_id": "mock-fact-" + pid, "text": "Works at " + (_PEOPLE[pid]["org"] as str), "observed_at": "2026-09-12T19:00:00Z", "valid_to": "", "status": "reported", "source_kind": "reported", "source_url": ""}, "age_days": 14, "source_note_id": "mock-note-" + pid, "span": "Works at " + (_PEOPLE[pid]["org"] as str) + "."}
    ];
}

def _intents(pid: str) -> list[dict[str, any]] {
    if pid == "mock-person-maya" {
        return [
            {"intent": {"_jac_id": "mock-intent-maya", "kind": "offer", "text": "Intros to climate hardware funds", "expires_at": "2027-03-01T00:00:00Z", "source_kind": "reported"}, "expired": False, "source_note_id": "mock-note-maya", "span": "Maya said she'd happily intro founders to the climate hardware funds she buys alongside."},
            {"intent": {"_jac_id": "mock-intent-maya-old", "kind": "need", "text": "A summer intern for MRV analysis", "expires_at": "2026-08-31T00:00:00Z", "source_kind": "reported"}, "expired": True, "source_note_id": "mock-note-maya", "span": "She was hunting for a summer intern to help with MRV."}
        ];
    }
    return [];
}

def _promises(pid: str) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for pr in _PROMISES {
        if pr["to"] == pid {
            out.append({"promise": _promise_node(pr), "source_note_id": "mock-note-" + pid, "span": pr["span"]});
        }
    }
    return out;
}

def:pub mock_person_detail(person_id: str) -> list[dict[str, any]] {
    person: dict[str, any] | None = _person(person_id);
    if person is None {
        return [{"error": "not_found"}];
    }
    p: any = _PEOPLE[person_id];
    rel: any = None;
    if p["label"] != "cold" {
        rel = {"goal_id": "mock-goal-raise", "goal_text": "Raise a $750k pre-seed for Kiln Labs by December", "label": p["label"], "strength": p["strength"], "reason": p["reason"], "opener": p["opener"]};
    }
    return [{
        "person": person,
        "how_met": p["how_met"],
        "knows_status": "confirmed",
        "last_contact": "2026-09-23T18:40:00Z",
        "relevance": rel,
        "facts": _facts(person_id),
        "intents": _intents(person_id),
        "promises": _promises(person_id),
        "notes": [
            {"note": {"_jac_id": "mock-note-" + person_id, "text": "Coffee with " + (p["name"] as str) + " after the panel.", "kind": "debrief", "captured_at": "2026-09-23T18:40:00Z", "audio_ref": ""}, "span": p["name"]}
        ],
        "reported_by": [],
        "card_handle": "maya-c" if person_id == "mock-person-maya" else ""
    }];
}

def:pub mock_brief(person_id: str, voice: bool = True) -> list[dict[str, any]] {
    person: dict[str, any] | None = _person(person_id);
    if person is None {
        return [{"error": "not_found"}];
    }
    p: any = _PEOPLE[person_id];
    owed: str = "nothing open";
    for pr in _PROMISES {
        if pr["to"] == person_id and not _is_done(pr["id"] as str) {
            owed = pr["text"] as str;
        }
    }
    text: str = (p["name"] as str) + ", " + (p["title"] as str) + " at " + (p["org"] as str) + ". You met at " + ((p["how_met"] or "an event") as str) + ". You promised: " + owed + ".";
    return [{
        "person_id": person_id, "text": text, "audio_b64": "", "mime": "",
        "based_on": [], "fallback": True, "voice_error": "no_key" if voice else ""
    }];
}

def:pub mock_list_promises() -> list[dict[str, any]] {
    open_rows: list[dict[str, any]] = [];
    done_rows: list[dict[str, any]] = [];
    for pr in _PROMISES {
        row: dict[str, any] = {"promise": _promise_node(pr), "to": _person(pr["to"] as str), "source_note_id": "mock-note-" + (pr["to"] as str), "span": pr["span"]};
        if _is_done(pr["id"] as str) {
            done_rows.append(row);
        } else {
            open_rows.append(row);
        }
    }
    return open_rows + done_rows;
}

def:pub mock_complete_promise(promise_id: str, done: bool = True) -> list[dict[str, any]] {
    for pr in _PROMISES {
        if pr["id"] == promise_id {
            (MOCK_PERSON["done"] as dict)[promise_id] = done;
            return [_promise_node(pr)];
        }
    }
    return [{"error": "not_found"}];
}

def:pub mock_draft_follow_up(person_id: str, intent: str = "") -> list[dict[str, any]] {
    person: dict[str, any] | None = _person(person_id);
    if person is None {
        return [{"error": "not_found"}];
    }
    first: str = (person["name"] as str).split(" ")[0];
    return [{
        "person_id": person_id,
        "draft": "Hi " + first + " — great catching up last week. Following up on what we talked about; happy to send over anything useful.",
        "based_on": [],
        "fallback": True
    }];
}

def:pub mock_forget(id: str) -> list[dict[str, any]] {
    if _person(id) is None {
        return [{"error": "not_found"}];
    }
    MOCK_PERSON["gone"] = (MOCK_PERSON["gone"] as list[str]) + [id];
    return [{
        "deleted": "person", "id": id,
        "retracted": {"facts": 1, "intents": 0, "promises": 0, "edges": 2, "introductions_canceled": 0, "relevant_to": 1}
    }];
}
