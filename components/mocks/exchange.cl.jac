"""Mocks for the Exchange + GapFinder + PublishCard — SOH-172. OWNER: Person B.

Exact report shapes from the live walkers (gaps.sv.jac, exchange.sv.jac,
cards.sv.jac; contracts/walkers.md v1.1 + the SOH-205 change log):
  GapFinder        -> [{ kind, why_needed, suggested_need }]   ([] = no gap)
  PostRequest      -> [IntroRequest] | [{ error: "no_card" }]
  ListMyRequests   -> [{ request: IntroRequest, replies: [ReplyView] }]
  ListIncomingRequests -> [IntroRequest]  (others', not declined/expired/answered by me)
  ReplyToRequest / ApproveReply -> [ReplyView]
  OptIn            -> [{ reply: ReplyView, opt_in_draft }]
  Reveal           -> [{ reply: ReplyView, revealed_card_handle }]
  ClaimReveal      -> [{ person: Person, card: Card, intro_draft }]
  DeclineRequest / DeclineReply -> ["declined"]
ReplyView = { _jac_id, request_id, from_handle, match_count, strength, status }
— never a match identity.

SOH-229: `from_name`, `goal_text`, `need_key` are seeded here ahead of the
real walker (read defensively everywhere, empty until it lands).

Module-level MX state lets ONE browser under `?mock=1` click the whole loop:
the dev-only "act as a friend" toggle makes the user's own open requests show
up in their incoming list too, answered as the mock friend `sam-ruiz-9c1d`.
One seeded incoming ask (from `jordan-lee-3f2a`) is always there.
Need text containing "#none" -> the friend has 0 matches. A goal whose text
contains "#nogap" -> GapFinder reports [].
"""

import from .goals { mock_goal_text }
import from .capture { mock_remember_person }

glob MY_HANDLE: str = "rowan-kiln",
     FRIEND_HANDLE: str = "sam-ruiz-9c1d",
     MX: dict[str, any] = {"reqs": [], "replies": [], "n": 0, "as_friend": False, "seeded": False, "card": False};

def _seed() -> None {
    if MX["seeded"] {
        return;
    }
    MX["seeded"] = True;
    MX["reqs"] = [
        {
            "_jac_id": "mock-req-jordan",
            "need": "a plant manager at a Midwest foundry open to piloting a heat-recovery retrofit",
            "from_handle": "jordan-lee-3f2a",
            "from_name": "Jordan Lee",
            "goal_text": "Pilot a heat-recovery retrofit with a Midwest foundry by December",
            "need_key": "",
            "about_line": "Mechanical engineering senior building a heat-pump retrofit kit",
            "status": "open",
            "created_at": "2026-09-26T17:40:00Z",
            "expires_at": "2026-10-03T17:40:00Z"
        }
    ];
}

def _next_id(prefix: str) -> str {
    MX["n"] = (MX["n"] as int) + 1;
    return prefix + str(MX["n"]);
}

def _req(rid: str) -> dict | None {
    for r in MX["reqs"] as list[dict] {
        if r["_jac_id"] == rid {
            return r;
        }
    }
    return None;
}

def _reply(reply_id: str) -> dict | None {
    for r in MX["replies"] as list[dict] {
        if r["_jac_id"] == reply_id {
            return r;
        }
    }
    return None;
}

def _view(r: dict) -> dict {
    return {
        "_jac_id": r["_jac_id"],
        "request_id": r["request_id"],
        "from_handle": r["from_handle"],
        "match_count": r["match_count"],
        "strength": r["strength"],
        "status": r["status"]
    };
}

"""Same derivation as exchange.sv.jac `derive_status` (minus expiry)."""
def _derive(req: dict, replies: list[dict]) -> str {
    if req["status"] == "declined" {
        return "declined";
    }
    statuses: list[str] = [];
    for r in replies {
        statuses = statuses + [r["status"] as str];
    }
    if "revealed" in statuses {
        return "revealed";
    }
    if "opted_in" in statuses {
        return "opted_in";
    }
    if "approved" in statuses {
        return "approved";
    }
    if len(statuses) > 0 {
        return "replied";
    }
    return "open";
}

def:pub mock_as_friend() -> bool {
    return True if MX["as_friend"] else False;
}

def:pub mock_set_as_friend(on: bool) -> None {
    MX["as_friend"] = on;
}

def:pub mock_gap_finder(goal_id: str) -> list[dict] {
    text: str = mock_goal_text(goal_id);
    if "#nogap" in text {
        return [];
    }
    if goal_id == "mock-goal-pilot" {
        return [
            {
                "kind": "plant manager at a mid-size foundry",
                "why_needed": "A pilot needs someone who runs a furnace line and can approve a two-week trial.",
                "suggested_need": "an intro to a plant manager at a Midwest foundry open to a two-week thermal-storage pilot"
            }
        ];
    }
    return [
        {
            "kind": "climate-tech VC",
            "why_needed": "A pre-seed round needs at least one lead investor who writes climate hardware checks.",
            "suggested_need": "an intro to a climate-tech VC who takes cold student pitches"
        },
        {
            "kind": "founder who has raised for hardware",
            "why_needed": "Someone who raised for a hardware company can pressure-test the deck and the round size.",
            "suggested_need": "a founder who raised a hardware pre-seed and would review a deck"
        }
    ];
}

def:pub mock_publish_card(name: str, headline: str, about: str) -> dict {
    MX["card"] = True;
    return {
        "_jac_id": "mock-card-rowan",
        "handle": MY_HANDLE,
        "name": name,
        "headline": headline,
        "about": about,
        "looking_for": [],
        "can_offer": [],
        "links": [],
        "contact_pref": "",
        "visibility": "handshake_only",
        "updated_at": "2026-09-26T18:00:00Z"
    };
}

"""An about_line containing "#nocard" reports no_card until PublishCard ran."""
def:pub mock_post_request(need: str, about_line: str) -> dict {
    _seed();
    if "#nocard" in about_line and not MX["card"] {
        return {"error": "no_card"};
    }
    req: dict = {
        "_jac_id": _next_id("mock-req-"),
        "need": need,
        "from_handle": MY_HANDLE,
        "from_name": "",
        "goal_text": "",
        "need_key": "",
        "about_line": about_line,
        "status": "open",
        "created_at": "2026-09-26T18:05:00Z",
        "expires_at": "2026-10-03T18:05:00Z"
    };
    MX["reqs"] = (MX["reqs"] as list[dict]) + [req];
    return {**req};
}

def:pub mock_list_my_requests() -> list[dict] {
    _seed();
    out: list[dict] = [];
    for req in MX["reqs"] as list[dict] {
        if req["from_handle"] != MY_HANDLE {
            continue;
        }
        all_replies: list[dict] = MX["replies"] as list[dict];
        replies: list[dict] = [r for r in all_replies if r["request_id"] == req["_jac_id"]];
        req["status"] = _derive(req, replies);
        out = out + [{"request": {**req}, "replies": [_view(r) for r in replies]}];
    }
    return out;
}

def:pub mock_decline_request(request_id: str) -> str {
    req: dict | None = _req(request_id);
    if req is None {
        return "not_found";
    }
    req["status"] = "declined";
    return "declined";
}

def:pub mock_list_incoming() -> list[dict] {
    _seed();
    answered: list[str] = [];
    for r in MX["replies"] as list[dict] {
        answered = answered + [r["request_id"] as str];
    }
    out: list[dict] = [];
    for req in MX["reqs"] as list[dict] {
        mine: bool = req["from_handle"] == MY_HANDLE;
        if mine and not MX["as_friend"] {
            continue;
        }
        if req["status"] == "declined" or req["_jac_id"] in answered {
            continue;
        }
        out = out + [{**req}];
    }
    return out;
}

def:pub mock_reply_to_request(request_id: str) -> dict {
    req: dict | None = _req(request_id);
    if req is None {
        return {"error": "not_found"};
    }
    none: bool = "#none" in (req["need"] as str);
    reply: dict = {
        "_jac_id": _next_id("mock-reply-"),
        "request_id": request_id,
        "from_handle": FRIEND_HANDLE if req["from_handle"] == MY_HANDLE else MY_HANDLE,
        "match_count": 0 if none else 1,
        "strength": "weak" if none else "strong",
        "status": "pending"
    };
    MX["replies"] = (MX["replies"] as list[dict]) + [reply];
    return _view(reply);
}

def _advance(reply_id: str, want: str, next_status: str) -> dict {
    r: dict | None = _reply(reply_id);
    if r is None {
        return {"error": "not_found"};
    }
    if r["status"] != want {
        return {"error": "invalid_state"};
    }
    r["status"] = next_status;
    return r;
}

def:pub mock_approve_reply(reply_id: str) -> dict {
    r: dict = _advance(reply_id, "pending", "approved");
    if r["error"] {
        return r;
    }
    return _view(r);
}

def:pub mock_opt_in(reply_id: str) -> dict {
    r: dict = _advance(reply_id, "approved", "opted_in");
    if r["error"] {
        return r;
    }
    req: dict | None = _req(r["request_id"] as str);
    need: str = (req["need"] as str) if req is not None else "an intro";
    return {
        "reply": _view(r),
        "opt_in_draft": "Hi Priya Raman, a friend of mine is looking for " + need + ". From what you've told me (Priya is a partner at a climate-tech seed fund), you'd be a great fit. Would you be open to an intro? No pressure either way."
    };
}

def:pub mock_reveal(reply_id: str) -> dict {
    r: dict = _advance(reply_id, "opted_in", "revealed");
    if r["error"] {
        return r;
    }
    r["revealed_card_handle"] = "priya-raman-7b21";
    return {"reply": _view(r), "revealed_card_handle": "priya-raman-7b21"};
}

def:pub mock_decline_reply(reply_id: str) -> str {
    r: dict | None = _reply(reply_id);
    if r is None {
        return "not_found";
    }
    r["status"] = "declined";
    return "declined";
}

def:pub mock_claim_reveal(reply_id: str) -> dict {
    r: dict | None = _reply(reply_id);
    if r is None {
        return {"error": "not_found"};
    }
    if r["status"] != "revealed" {
        return {"error": "invalid_state"};
    }
    req: dict | None = _req(r["request_id"] as str);
    need: str = (req["need"] as str) if req is not None else "an intro";
    person: dict = {
        "_jac_id": "mock-person-priya-rao",
        "name": "Priya Rao",
        "org": "Northwind Climate Fund",
        "title": "Partner",
        "status": "confirmed"
    };
    mock_remember_person(person);
    return {
        "person": person,
        "card": {
            "_jac_id": "mock-card-priya",
            "handle": "priya-raman-7b21",
            "name": "Priya Rao",
            "headline": "Partner at Northwind Climate Fund",
            "about": "Seed-stage investor in climate hardware. Takes student pitches on Fridays.",
            "looking_for": ["Hardware founders with a pilot customer", "Grid storage teams"],
            "can_offer": ["Pre-seed checks up to $500k", "Intros to industrial pilot partners"],
            "links": ["https://example.com/northwind"],
            "contact_pref": "Email, with a one-page summary",
            "visibility": "handshake_only",
            "updated_at": "2026-09-26T18:20:00Z"
        },
        "intro_draft": "Hi Rowan and Priya, connecting you two. Priya is a partner at Northwind Climate Fund and backs climate hardware at seed. Rowan is a student founder building thermal batteries for small factories and is looking for " + need + ". I thought of you right away, Priya. I'll let you two take it from here. - " + (r["from_handle"] as str)
    };
}
