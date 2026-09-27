"""Mocks for the Agent inbox — SOH-224 (server half SOH-223). OWNER: Person B.

Exact report shapes from the SOH-223 contract (SK builds the walkers):
  RunAgent(reason="manual")          -> [{ run_id, ran_at, new, total_open, skipped: [str] }]
  ListAgentActions(status="open", limit=30)
                                     -> [{ action: AgentAction, person: Person | null,
                                           evidence: [{ id, kind, observed_at, span }] }]
  ResolveAgentAction(action_id, decision, edited_draft="")
                                     -> [{ action, result: dict }] | [{ error: "not_found" | "invalid_state" }]
AgentAction = { _jac_id, kind, title, why, evidence: [jid], person_id, goal_id,
  request_id, draft, payload_json, status, created_at, source_walker, dedup_key }
kind: new_match | ask_network | route | promise_due | follow_up | reconnect | answer_ask
status: open | approved | dismissed | snoozed   (final SOH-223 contract; a snoozed action reopens next run)

Module-level AG state so a resolve survives across calls under `?mock=1`. People
are the same pseudonymous mocks the PersonSheet mock knows (mock-person-maya,
-dev, -lena, -sam), so tapping a person opens a real sheet. The seeded
`answer_ask` points at the exchange mock's always-present ask (mock-req-jordan).
Every RunAgent adds the next one or two actions from EXTRA. Approving an
`ask_network` posts the ask into the exchange mock (as SK's walker calls
PostRequest server-side), so it shows under "Your asks".

Dev URL flags (mock only): `agent=empty` -> no actions and RunAgent finds none;
`agent=fail` -> every ResolveAgentAction reports invalid_state (rollback path).
"""

import from .exchange { mock_post_request, mock_reply_to_request }

glob AG: dict[str, any] ={"actions": [], "seeded": False, "runs": 0, "next_extra": 0};

def _flag(name: str) -> bool {
    search: str = String(window.location.search);  # jac:ignore[W2001]
    return ("agent=" + name) in search;
}

def _now_iso() -> str {
    d: any = new(Date);  # jac:ignore[W2001]
    return d.toISOString() as str;
}

"""ISO time `minutes` ago (so created_at looks recent in any demo)."""
def _ago_iso(minutes: int) -> str {
    ms: int = (Date.now() as int) - minutes * 60000;  # jac:ignore[W2001]
    d: any = new(Date, ms);  # jac:ignore[W2001]
    return d.toISOString() as str;
}

def _ev(eid: str, kind: str, observed_at: str, span: str) -> dict {
    return {"id": eid, "kind": kind, "observed_at": observed_at, "span": span};
}

glob _PEOPLE: dict[str, any] = {
         "mock-person-maya": {"name": "Maya Chen", "org": "Stripe Climate", "title": "Carbon removal lead"},
         "mock-person-dev": {"name": "Dev Okafor", "org": "Great Lakes Angels", "title": "Associate"},
         "mock-person-lena": {"name": "Lena Park", "org": "Campus Energy Club", "title": "President"},
         "mock-person-sam": {"name": "Sam Ruiz", "org": "Ruiz Castings", "title": "Plant manager"}
     };

def _person(pid: str) -> dict | None {
    p: any = _PEOPLE[pid];
    if not pid or not p {
        return None;
    }
    return {"_jac_id": pid, "name": p["name"], "org": p["org"], "title": p["title"], "status": "confirmed"};
}

"""One ListAgentActions row: the action node + its evidence list."""
def _row(
    aid: str,
    kind: str,
    title: str,
    why: str,
    evidence: list[dict],
    person_id: str,
    draft: str,
    payload: dict,
    request_id: str,
    source_walker: str,
    minutes_ago: int
) -> dict {
    ids: list[str] = [];
    for e in evidence {
        ids = ids + [e["id"] as str];
    }
    act: dict = {
        "_jac_id": aid,
        "kind": kind,
        "title": title,
        "why": why,
        "evidence": ids,
        "person_id": person_id,
        "goal_id": "mock-goal-raise",
        "request_id": request_id,
        "draft": draft,
        "payload_json": JSON.stringify(payload),  # jac:ignore[W2001]
        "status": "open",
        "created_at": _ago_iso(minutes_ago),
        "source_walker": source_walker,
        "dedup_key": kind + ":" + (person_id or request_id or aid)
    };
    return {"action": act, "person": _person(person_id), "evidence": evidence};
}

def _seed_rows() -> list[dict] {
    return [
        _row(
            "7c1e0a94b2d34f6e9a51c0de4b7f2a18", "route",
            "Dev knows someone at Northwind Capital — ask Dev?",
            "Northwind leads climate-hardware pre-seed rounds, and Dev co-invested with their partner last spring.",
            [
                _ev("a41f9e0c7d2b4c58b3e6f1a2d9c07e55", "fact", "2026-09-23T18:40:00Z", "Dev said he co-invested with Priya at Northwind on a battery deal last spring."),
                _ev("5be3d0f2a8c14e7f96b0c3d1e2f4a687", "note", "2026-09-23T18:40:00Z", "Spring pitch night — Dev screens energy deals for Great Lakes Angels.")
            ],
            "mock-person-dev",
            "Hi Dev — hope the fall deal flow is treating you well. You mentioned co-investing with Northwind on that battery deal. Would you be open to introducing me to their climate partner? I'm raising a pre-seed for Kiln Labs (thermal batteries for mid-size plants). Happy to send a two-line blurb you can forward.",
            {"target_org": "Northwind Capital"}, "", "PathFinder", 4
        ),
        _row(
            "e2d94b17c0a6438f8d5e7b21a9c3f046", "ask_network",
            "No warm path to a climate-tech VC — ask your network?",
            "Nobody you know is a climate-tech VC yet, and it's the missing piece for raising a pre-seed round.",
            [
                _ev("0f7a3c9e1b2d4e5f8a6c7b9d0e1f2a3b", "goal", "2026-09-26T13:05:00Z", "Raise a pre-seed round for Kiln Labs by December.")
            ],
            "", "",
            {"kind": "climate-tech VC", "need": "a climate-tech VC who writes pre-seed checks for hardware", "about_line": "Student founder building thermal batteries for mid-size plants"},
            "", "GapFinder", 6
        ),
        _row(
            "3a8f6d2e9b1c4705a2e4d6f8b0c1e397", "promise_due",
            "Send Maya the Kiln Labs one-pager",
            "You told Maya you'd send it this weekend; it's due Sep 28.",
            [
                _ev("mock-promise-maya", "promise", "2026-09-23T18:40:00Z", "I said I'd send Maya the one-pager this weekend.")
            ],
            "mock-person-maya",
            "Hi Maya — as promised, here's the Kiln Labs one-pager. The short version: we store off-peak heat in firebrick and release it on shift. Would love your read on which climate hardware funds would care.",
            {"promise_id": "mock-promise-maya", "due": "2026-09-28"}, "", "Tend", 8
        ),
        _row(
            "b5c7e9a1d3f24b6c8e0a2c4e6a8b0d2f", "answer_ask",
            "Jordan's agent is looking for a plant manager — your network may fit",
            "You know a plant manager at a Midwest foundry; answering shows Jordan a count and a strength, never a name.",
            [
                _ev("mock-card-sam", "card", "2026-08-30T12:00:00Z", "Looking for: ways to cut peak-hour energy costs")
            ],
            "", "", {}, "mock-req-jordan", "WhoNeedsWhatIHave", 10
        ),
        _row(
            "9d2b4f6a8c0e41a3b5d7f9e1c3a5b7d9", "follow_up",
            "Lena offered intros to the speaker-series VCs",
            "She offered at the Ross climate panel, and two of those VCs back pre-seed hardware.",
            [
                _ev("mock-intent-lena", "intent", "2026-09-20T15:30:00Z", "Lena offered to connect founders with speaker-series VCs."),
                _ev("c6e8a0b2d4f64c8e9a1b3d5f7a9c1e3b", "note", "2026-09-20T15:30:00Z", "Ross climate panel — Lena runs the Campus Energy Club speaker series.")
            ],
            "mock-person-lena",
            "Hi Lena — thanks again for the panel. You mentioned you could connect founders with the speaker-series VCs; I'd be grateful for an intro to whoever looks at pre-seed climate hardware. Happy to send a short blurb.",
            {"intent_id": "mock-intent-lena"}, "", "Tend", 14
        ),
        _row(
            "1f3e5a7c9b2d44e6a8c0e2f4b6d8a0c2", "new_match",
            "Maya is now a strong match for raising your pre-seed",
            "A new note says she buys alongside two climate hardware funds.",
            [
                _ev("mock-fact-maya-2", "fact", "2026-09-23T18:40:00Z", "Carbon removal lead, Stripe Climate"),
                _ev("mock-intent-maya", "intent", "2026-09-23T18:40:00Z", "Maya said she'd happily intro founders to the climate hardware funds she buys alongside.")
            ],
            "mock-person-maya", "", {"strength_from": "medium", "strength_to": "strong"}, "", "GoalRank", 18
        ),
        _row(
            "6b8d0f2a4c6e48a0b2d4f6a8c0e2a4b6", "reconnect",
            "Sam's card asks about peak-hour energy costs",
            "That's exactly what your pilot measures — a reason to reach out, not a reminder.",
            [
                _ev("mock-card-sam", "card", "2026-08-30T12:00:00Z", "Looking for: ways to cut peak-hour energy costs")
            ],
            "mock-person-sam",
            "Hi Sam — your card mentions cutting peak-hour energy costs. We're running a small thermal-battery pilot this winter; could I show you what it would save Ruiz Castings on a typical shift?",
            {}, "", "Tend", 25
        ),
        _row(
            "d0a2c4e6b8f04a2c6e8b0d2f4a6c8e0b", "route",
            "Lena knows two facilities managers in Ann Arbor — ask Lena?",
            "A plant pilot needs a facilities manager, and Lena set up the club's plant tours with two of them.",
            [
                _ev("mock-note-lena-tour", "note", "2026-09-20T15:30:00Z", "Lena set up the club's plant tours with two Ann Arbor facilities managers.")
            ],
            "mock-person-lena",
            "Hi Lena — would one of the facilities managers from the plant tours take a 15-minute call about a heat-battery pilot? No pitch deck, just their read on whether it would fit.",
            {"target_org": "Ann Arbor facilities"}, "", "PathFinder", 32
        )
    ];
}

"""What each RunAgent finds next (cycled: 2, then 1, then 2 …)."""
def _extra_rows() -> list[dict] {
    return [
        _row(
            "4e6a8c0e2b4d46f8a0c2e4a6b8d0f2a4", "new_match",
            "Dev moved up for raising your pre-seed",
            "Your latest note says Great Lakes Angels is opening a climate sidecar.",
            [
                _ev("8a0c2e4f6b8d40a2c4e6f8b0d2a4c6e8", "fact", "2026-09-26T16:10:00Z", "Dev said Great Lakes Angels is opening a climate sidecar fund this fall.")
            ],
            "mock-person-dev", "", {"strength_from": "medium", "strength_to": "strong"}, "", "GoalRank", 0
        ),
        _row(
            "c2e4a6b8d0f24c6e8a0b2d4f6a8c0e2d", "follow_up",
            "Dev asked for your deck after pitch night",
            "He asked to see the deck once the pilot numbers were in — they are now.",
            [
                _ev("f4a6c8e0b2d44f6a8c0e2a4b6d8f0a2c", "intent", "2026-09-26T16:10:00Z", "Dev: send me the deck once you have pilot numbers.")
            ],
            "mock-person-dev",
            "Hi Dev — the pilot numbers are in (18% peak-hour savings on the test line). Here's the updated deck you asked for. Would love 20 minutes when you have them.",
            {}, "", "Tend", 0
        ),
        _row(
            "a8c0e2f4b6d84a0c2e4f6a8b0d2c4e6f", "route",
            "Maya knows the Stripe Climate hardware lead — ask Maya?",
            "Stripe's hardware purchases need a pilot partner, and Maya sits next to the person who picks them.",
            [
                _ev("mock-fact-maya-1", "fact", "2026-07-12T16:10:00Z", "Maya Chen — worked together at Stripe.")
            ],
            "mock-person-maya",
            "Hi Maya — would you be up for introducing me to whoever leads hardware purchases at Stripe Climate? A two-line blurb is below if it helps.",
            {"target_org": "Stripe Climate"}, "", "PathFinder", 0
        )
    ];
}

def _seed() -> None {
    if AG["seeded"] {
        return;
    }
    AG["seeded"] = True;
    AG["actions"] = [] if _flag("empty") else _seed_rows();
}

def _find(aid: str) -> dict | None {
    for row in AG["actions"] as list[dict] {
        if (row["action"] or {})["_jac_id"] == aid {
            return row;
        }
    }
    return None;
}

def _open_count() -> int {
    n: int = 0;
    for row in AG["actions"] as list[dict] {
        if (row["action"] or {})["status"] == "open" {
            n = n + 1;
        }
    }
    return n;
}

"""ListFriends() -> [{ handle, person, since }] (SOH-218) for the ask sheet's
audience toggle. Kept here (the one mock module SOH-224 owns): one friend, the
exchange mock's friend handle; `friends=0` in the URL -> no friends."""
def:pub mock_list_friends() -> list[dict] {
    search: str = String(window.location.search);  # jac:ignore[W2001]
    if "friends=0" in search {
        return [];
    }
    return [{"handle": "sam-ruiz-9c1d", "person": _person("mock-person-sam"), "since": "2026-09-26T15:00:00Z"}];
}

"""RunAgent(reason) -> [{ run_id, ran_at, new, total_open, skipped }]."""
def:pub mock_run_agent(reason: str) -> list[dict] {
    _seed();
    AG["runs"] = (AG["runs"] as int) + 1;
    added: int = 0;
    # Like the walker: every snoozed action reopens at the start of a run (counts as new).
    reopened: list[dict] = [];
    for r in AG["actions"] as list[dict] {
        if (r["action"] or {})["status"] == "snoozed" {
            na: dict = {**(r["action"] as dict)};
            na["status"] = "open";
            nr: dict = {**r};
            nr["action"] = na;
            reopened = reopened + [nr];
            added = added + 1;
        } else {
            reopened = reopened + [r];
        }
    }
    AG["actions"] = reopened;
    fresh_added: int = 0;
    if not _flag("empty") {
        extras: list[dict] = _extra_rows();
        want: int = 2 if (AG["runs"] as int) % 2 == 1 else 1;
        while fresh_added < want and (AG["next_extra"] as int) < len(extras) {
            row: dict = extras[AG["next_extra"] as int];
            act: dict = {**(row["action"] as dict)};
            act["created_at"] = _now_iso();
            fresh: dict = {**row};
            fresh["action"] = act;
            AG["actions"] = [fresh] + (AG["actions"] as list[dict]);
            AG["next_extra"] = (AG["next_extra"] as int) + 1;
            fresh_added = fresh_added + 1;
            added = added + 1;
        }
    }
    skipped: list[str] = ["serendipity"];
    return [
        {
            "run_id": "run-" + str(AG["runs"]) + "-" + reason,
            "ran_at": _now_iso(),
            "new": added,
            "total_open": _open_count(),
            "skipped": skipped
        }
    ];
}

"""ListAgentActions(status, limit) -> [{ action, person, evidence }], newest first."""
def:pub mock_list_agent_actions(status: str, limit: int) -> list[dict] {
    _seed();
    out: list[dict] = [];
    for row in AG["actions"] as list[dict] {
        if ((row["action"] or {})["status"] == status or status == "all") and len(out) < limit {
            out = out + [row];
        }
    }
    return out;
}

"""ResolveAgentAction(action_id, decision, edited_draft) -> [{ action, result }] | [{ error }]."""
def:pub mock_resolve_agent_action(action_id: str, decision: str, edited_draft: str) -> list[dict] {
    _seed();
    row: dict | None = _find(action_id);
    if row is None {
        return [{"error": "not_found"}];
    }
    act: dict = {**((row as dict)["action"] as dict)};
    if act["status"] not in ["open", "snoozed"] or decision not in ["approve", "dismiss", "snooze"] or _flag("fail") {
        return [{"error": "invalid_state"}];
    }
    kind: str = act["kind"] as str;
    result: dict = {};
    if decision == "approve" {
        act["status"] = "approved";
        act["approval_source"] = "in_app";
        if edited_draft {
            act["draft"] = edited_draft;
        }
        if kind == "promise_due" {
            result = {"step": "CompletePromise", "promise": {"_jac_id": "mock-promise-maya", "done": True}};
        } elif kind in ["route", "follow_up", "reconnect", "new_match"] {
            result = {"step": "draft_saved", "draft": act["draft"]};
        } elif kind == "answer_ask" {
            # SOH-223 amendment: the walker runs ReplyToRequest -> { step: "replied", reply }.
            reply: dict = mock_reply_to_request(act["request_id"] as str);
            if reply["error"] {
                return [{"action": row["action"], "result": {"error": reply["error"]}}];
            }
            result = {"step": "replied", "reply": reply};
        } elif kind == "ask_network" {
            # SOH-223: approve posts the ask server-side (PostRequest, audience
            # "everyone") with the confirmed need; the about line is the payload's.
            pl: dict = {};
            try {
                pl = JSON.parse((act["payload_json"] or "{}") as str) as dict;  # jac:ignore[W2001]
            } except Exception as e {
                pl = {};
            }
            posted: dict = mock_post_request((edited_draft or pl["need"] or act["title"]) as str, (pl["about_line"] or "") as str);
            if posted["error"] {
                return [{"action": row["action"], "result": {"error": posted["error"]}}];
            }
            act["request_id"] = posted["_jac_id"];
            result = {"step": "posted", "request": posted};
        }
    } elif decision == "dismiss" {
        act["status"] = "dismissed";
        result = {"step": "dismissed"};
    } else {
        act["status"] = "snoozed";
        result = {"step": "snoozed"};
    }
    fresh: dict = {**(row as dict)};
    fresh["action"] = act;
    rows: list[dict] = [];
    for r in AG["actions"] as list[dict] {
        rows = rows + [fresh if (r["action"] or {})["_jac_id"] == action_id else r];
    }
    AG["actions"] = rows;
    return [{"action": act, "result": result}];
}
