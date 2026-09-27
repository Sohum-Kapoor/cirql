"""Mocks for the person sheet + Today list — SOH-207 / SOH-187 / SOH-222. OWNER: Person B.

Exact contract shapes (contracts/walkers.md): `PersonDetail(person_id)`,
`Brief(person_id, voice)`, `ListPromises()`, `CompletePromise(promise_id, done)`,
`DraftFollowUp(person_id, intent)`, `Forget(id)`,
`UpdatePerson(person_id, name, org, title, how_met, email, phone, location, links)`,
`ArchivePerson(person_id)`. Each returns the walker's report LIST. Same
pseudonymous people as the GoalRank mock (mock-person-maya, -dev, -lena, -sam).
State (promise done flags, forgotten/archived people, edited fields) lives in
the MOCK_PERSON glob so a tick, an edit, an Archive or a Forget survives across
calls under `?mock=1`.
"""

glob MOCK_PERSON: dict[str, any] = {"done": {}, "gone": [], "archived": [], "overrides": {}};

glob _PEOPLE: dict[str, any] = {
         "mock-person-maya": {
             "name": "Maya Chen", "org": "Stripe Climate", "title": "Carbon removal lead",
             "how_met": "worked together at Stripe", "label": "known", "strength": "strong",
             "reason": "Runs Stripe's climate purchasing and said she knows pre-seed hardware funds.",
             "opener": "Maya — which climate hardware funds would you ask first?",
             "email": "maya.chen@stripeclimate.example", "phone": "+1 415 555 0148",
             "location": "San Francisco, CA",
             "links": ["https://stripe.com/climate", "https://maya-chen.example"]
         },
         "mock-person-dev": {
             "name": "Dev Okafor", "org": "Great Lakes Angels", "title": "Associate",
             "how_met": "spring pitch night", "label": "known", "strength": "medium",
             "reason": "Screens energy deals for an angel group that writes pre-seed checks.",
             "opener": "",
             "email": "", "phone": "", "location": "Ann Arbor, MI", "links": []
         },
         "mock-person-lena": {
             "name": "Lena Park", "org": "Campus Energy Club", "title": "President",
             "how_met": "Ross climate panel", "label": "route", "strength": "medium",
             "reason": "Knows two climate VCs from the club's speaker series.",
             "opener": "",
             "email": "lena.park@umich.example", "phone": "", "location": "", "links": []
         },
         "mock-person-sam": {
             "name": "Sam Ruiz", "org": "Ruiz Castings", "title": "Plant manager",
             "how_met": "", "label": "cold", "strength": "weak",
             "reason": "Operates the kind of plant Kiln Labs targets.",
             "opener": "",
             "email": "", "phone": "+1 313 555 0199", "location": "Detroit, MI", "links": []
         }
     };

"""The stored edit overlay for a person, or {}."""
def _overrides(pid: str) -> dict {
    return ((MOCK_PERSON["overrides"] as dict)[pid] or {}) as dict;
}

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
    over: dict = _overrides(pid);
    name: str = (over["name"] or p["name"]) as str;
    org: str = (over["org"] or p["org"]) as str;
    title: str = (over["title"] or p["title"]) as str;
    email: str = (over["email"] or p["email"] or "") as str;
    phone: str = (over["phone"] or p["phone"] or "") as str;
    location: str = (over["location"] or p["location"] or "") as str;
    links: list[str] = (over["links"] or p["links"] or []) as list[str];
    archived: bool = pid in (MOCK_PERSON["archived"] as list[str]);
    return {
        "_jac_id": pid, "name": name, "org": org, "title": title, "status": "confirmed",
        "email": email, "phone": phone, "location": location, "links": links, "archived": archived
    };
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
    over: dict = _overrides(person_id);
    how_met: str = (over["how_met"] or p["how_met"]) as str;
    rel: any = None;
    if p["label"] != "cold" {
        rel = {"goal_id": "mock-goal-raise", "goal_text": "Raise a $750k pre-seed for Kiln Labs by December", "label": p["label"], "strength": p["strength"], "reason": p["reason"], "opener": p["opener"]};
    }
    return [{
        "person": person,
        "how_met": how_met,
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

"""UpdatePerson(person_id, name, org, title, how_met, email, phone, location, links)
mock (SOH-222): only NON-EMPTY (stripped) args overwrite a field, `links`
overwrites only when the caller sent a non-empty list — same "leave the rest
alone" rule `edits.sv.jac`'s `UpdatePerson` uses today for name/org/title/how_met.
Persists in MOCK_PERSON["overrides"] so the edit survives a re-render or a
Today-list refresh under `?mock=1`."""
def:pub mock_update_person(
    person_id: str, name: str, org: str, title: str, how_met: str,
    email: str, phone: str, location: str, links: list[str]
) -> list[dict[str, any]] {
    if _person(person_id) is None {
        return [{"error": "not_found"}];
    }
    over: dict = {**_overrides(person_id)};
    if name.strip() {
        over["name"] = name.strip();
    }
    if org.strip() {
        over["org"] = org.strip();
    }
    if title.strip() {
        over["title"] = title.strip();
    }
    if how_met.strip() {
        over["how_met"] = how_met.strip();
    }
    if email.strip() {
        over["email"] = email.strip();
    }
    if phone.strip() {
        over["phone"] = phone.strip();
    }
    if location.strip() {
        over["location"] = location.strip();
    }
    if len(links) > 0 {
        over["links"] = links;
    }
    all_over: dict = {**(MOCK_PERSON["overrides"] as dict)};
    all_over[person_id] = over;
    MOCK_PERSON["overrides"] = all_over;
    updated: dict[str, any] | None = _person(person_id);
    if updated is None {
        return [{"error": "not_found"}];
    }
    return [updated];
}

"""ArchivePerson(person_id) mock (SOH-222): soft delete — `Person.archived = true`,
hidden from lists/rankings, restorable; never touches facts/intents/promises/
edges (unlike Forget)."""
def:pub mock_archive_person(person_id: str) -> list[dict[str, any]] {
    if _person(person_id) is None {
        return [{"error": "not_found"}];
    }
    already: list[str] = MOCK_PERSON["archived"] as list[str];
    if person_id not in already {
        MOCK_PERSON["archived"] = already + [person_id];
    }
    updated: dict[str, any] | None = _person(person_id);
    if updated is None {
        return [{"error": "not_found"}];
    }
    return [updated];
}
