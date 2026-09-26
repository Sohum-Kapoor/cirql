"""scripts/demo_check.jac — the whole Cirql demo path over HTTP, one command.

OWNER: Person A (a script, not a client file; drives the same compiled-Jac
HTTP-driver idiom as `seed/load.jac`: register/login, a `post()` helper, env
config, exit codes — see `jac guide` there for precedent). Runs against ANY
live server (local `jac start main.jac` or the hosted tunnel) with two fresh
accounts and prints PASS/WARN/SKIP/FAIL per beat, so C2 (midnight) and the
Sunday rehearsals are one command:

    jac run scripts/demo_check.jac

Configuration is read from the environment (all optional, defaults below):
  DEMO_BASE      http://localhost:8000
  DEMO_PASSWORD  demo-pass-123
  DEMO_SLEEP     3   (seconds slept before each model-backed / by-llm call)
  DEMO_KEEP      1   (reserved knob for a future cleanup step; currently a
                      no-op — every beat always runs, nothing is ever deleted)

Account usernames get a random 6-hex suffix each run so reruns never collide:
`demo-a-<sfx>` / `demo-b-<sfx>`, emails `<username>@example.com`.

Every beat prints `PASS|WARN|SKIP|FAIL <label> (<elapsed>ms) [— detail]` and
the script keeps going after a FAIL — nothing here raises past its own beat's
try/except. `PASS`/`WARN`/`SKIP` are not failures for the exit code; only a
`FAIL` (including any `{"ok": false}` HTTP response, per AGENTS.md/contract)
makes the final exit code 1. WARN marks a result that depends on the Gemini
extraction quota (a deterministic fallback still ran server-side — nothing
here is ever silently skipped for that reason, it is reported). SKIP marks a
beat that could not run because an earlier beat in the same Exchange chain
(no match on B's own root) made it inapplicable — expected, not a failure.

Nothing here sends anything: every walker called is a graph read/write or a
draft-only Exchange step (contracts/walkers.md — "Nothing sends").
"""

import requests;
import json;
import os;
import sys;
import time;
import secrets;


# ---------------------------------------------------------------- HTTP driver

"""POST /walker/<name> with a bearer token. Raises on a non-2xx HTTP status
or on a top-level {"ok": false} response — either way the raised message
carries the response body, never the token (same contract as seed/load.jac's
`post()`)."""
def post(base: str, token: str, name: str, body: dict[str, any]) -> dict[str, any] {
    headers: dict[str, str] = {"Content-Type": "application/json"};
    if len(token) > 0 {
        headers["Authorization"] = f"Bearer {token}";
    }
    resp = requests.post(f"{base}/walker/{name}", headers=headers, json=body, timeout=120);
    if resp.status_code < 200 or resp.status_code >= 300 {
        raise Exception(f"{name}: HTTP {resp.status_code}: {resp.text}");
    }
    payload = resp.json() as dict[str, any];
    ok = payload.get("ok", False) as bool;
    if not ok {
        raise Exception(f"{name}: ok=false: {resp.text}");
    }
    data = payload["data"] as dict[str, any];
    return data;
}

"""`data.reports` as a list of dicts — every walker report (a node or a plain
object) arrives over HTTP as a JSON object with the node's `has` fields plus
`_jac_id` (contracts/walkers.md, wire format note)."""
def reports_of(data: dict[str, any]) -> list[dict[str, any]] {
    return data["reports"] as list[dict[str, any]];
}

def register(base: str, username: str, email: str, password: str) {
    body: dict[str, any] = {
        "identities": [
            {"type": "username", "value": username},
            {"type": "email", "value": email}
        ],
        "credential": {"type": "password", "password": password}
    };
    resp = requests.post(f"{base}/user/register", json=body, timeout=60);
    if resp.status_code < 200 or resp.status_code >= 300 {
        raise Exception(f"register {username}: HTTP {resp.status_code}: {resp.text}");
    }
}

"""Login uses the username identity, never email (AGENTS.md gotcha)."""
def login(base: str, username: str, password: str) -> str {
    body: dict[str, any] = {
        "identity": {"type": "username", "value": username},
        "credential": {"type": "password", "password": password}
    };
    resp = requests.post(f"{base}/user/login", json=body, timeout=60);
    if resp.status_code < 200 or resp.status_code >= 300 {
        raise Exception(f"login {username}: HTTP {resp.status_code}: {resp.text}");
    }
    payload = resp.json() as dict[str, any];
    data = payload["data"] as dict[str, any];
    return data["token"] as str;
}


# ---------------------------------------------------------------- reporting

def bump(counts: dict[str, int], status: str) {
    if status == "PASS" {
        counts["PASS"] = counts["PASS"] + 1;
    } elif status == "WARN" {
        counts["WARN"] = counts["WARN"] + 1;
    } elif status == "SKIP" {
        counts["SKIP"] = counts["SKIP"] + 1;
    } else {
        counts["FAIL"] = counts["FAIL"] + 1;
    }
}

def mark(counts: dict[str, int], status: str, label: str, ms: float, detail: str = "") {
    bump(counts, status);
    suffix = f" — {detail}" if len(detail) > 0 else "";
    print(f"{status:<4} {label} ({ms:.0f}ms){suffix}");
}


# ---------------------------------------------------------------- fixed demo text

glob ABOUT_A = (
    "I am Alex, a CS junior at Michigan building accessible robotics. I want "
    "a summer 2027 VC internship in climate tech and feedback from "
    "wheelchair users on our prototype. I can offer intros to robotics "
    "faculty."
);
glob ABOUT_B = (
    "I am Sam, I run a student-founder community in Ann Arbor and know a "
    "lot of early-stage investors. I can offer intros to climate-tech VCs."
);
glob DEBRIEF_A = (
    "Met Maya Okafor at JacHacks. She works on accessible robotics at the "
    "Michigan Robotics lab, knows Arjun Patel from their lab, wants feedback "
    "from wheelchair users on her prototype. I promised to send her our "
    "demo."
);
glob GOAL_TEXT = "Land a summer 2027 climate-tech VC internship";
glob NEED_FALLBACK = "an intro to a climate-tech VC who takes cold student pitches";
glob NO_MATCH_NOTE = "no match on B's root (model unavailable)";


with entry {
    base = os.environ.get("DEMO_BASE", "http://localhost:8000") as str;
    password = os.environ.get("DEMO_PASSWORD", "demo-pass-123") as str;
    sleep_s = float(os.environ.get("DEMO_SLEEP", "3") as str);
    _ = os.environ.get("DEMO_KEEP", "1") as str;   # reserved, currently a no-op

    sfx = secrets.token_hex(3);
    username_a = f"demo-a-{sfx}";
    username_b = f"demo-b-{sfx}";
    email_a = f"{username_a}@example.com";
    email_b = f"{username_b}@example.com";

    counts: dict[str, int] = {"PASS": 0, "WARN": 0, "SKIP": 0, "FAIL": 0};
    started_at = time.time();

    print(f"== demo_check.jac == base={base} A={username_a} B={username_b}");

    token_a = "";
    token_b = "";

    # ---------------------------------------------------------- 1. register + login

    t0 = time.time();
    try {
        register(base, username_a, email_a, password);
        token_a = login(base, username_a, password);
        mark(counts, "PASS", "register+login A", (time.time() - t0) * 1000);
    } except Exception as e {
        mark(counts, "FAIL", "register+login A", (time.time() - t0) * 1000, str(e));
    }

    t0 = time.time();
    try {
        register(base, username_b, email_b, password);
        token_b = login(base, username_b, password);
        mark(counts, "PASS", "register+login B", (time.time() - t0) * 1000);
    } except Exception as e {
        mark(counts, "FAIL", "register+login B", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 2. A OnboardMe

    a_card_handle = "";
    t0 = time.time();
    try {
        time.sleep(sleep_s);
        data = post(base, token_a, "OnboardMe", {"about": ABOUT_A});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        first = reps[0];
        if "me" not in first or "card" not in first {
            raise Exception(f"missing me/card: {first}");
        }
        interests_out = first["interests"] as list[any];
        goals_out = first["goals"] as list[any];
        intents_out = first["intents"] as list[any];
        card_out = first["card"] as dict[str, any];
        a_card_handle = str(card_out["handle"]);
        empty_extraction = len(interests_out) == 0 and len(goals_out) == 0 and len(intents_out) == 0;
        if empty_extraction {
            mark(counts, "WARN", "OnboardMe A", (time.time() - t0) * 1000, "empty extraction (quota?)");
        } else {
            mark(counts, "PASS", "OnboardMe A", (time.time() - t0) * 1000, f"card={a_card_handle}");
        }
    } except Exception as e {
        mark(counts, "FAIL", "OnboardMe A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 3. B OnboardMe (+ DevMakeCard fallback)

    b_card_handle = "";
    t0 = time.time();
    try {
        time.sleep(sleep_s);
        data = post(base, token_b, "OnboardMe", {"about": ABOUT_B});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        first = reps[0];
        if "me" not in first or "card" not in first {
            raise Exception(f"missing me/card: {first}");
        }
        interests_out = first["interests"] as list[any];
        goals_out = first["goals"] as list[any];
        intents_out = first["intents"] as list[any];
        card_out = first["card"] as dict[str, any];
        b_card_handle = str(card_out["handle"]);
        empty_extraction = len(interests_out) == 0 and len(goals_out) == 0 and len(intents_out) == 0;
        if len(b_card_handle) == 0 {
            made = post(base, token_b, "DevMakeCard", {"handle": f"demo-b-{sfx}", "name": "Sam"});
            made_reps = reports_of(made);
            if len(made_reps) > 0 {
                b_card_handle = str(made_reps[0]["handle"]);
            }
        }
        if empty_extraction {
            mark(counts, "WARN", "OnboardMe B", (time.time() - t0) * 1000, "empty extraction (quota?)");
        } else {
            mark(counts, "PASS", "OnboardMe B", (time.time() - t0) * 1000, f"card={b_card_handle}");
        }
    } except Exception as e {
        mark(counts, "FAIL", "OnboardMe B", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 4. A Capture (debrief)

    t0 = time.time();
    try {
        time.sleep(sleep_s);
        data = post(base, token_a, "Capture", {"text": DEBRIEF_A, "kind": "debrief"});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        r = reps[0];
        if "note_id" not in r {
            raise Exception(f"missing note_id: {r}");
        }
        people_out = r["people"] as list[dict[str, any]];
        facts_out = r["facts"] as list[any];
        intents_out = r["intents"] as list[any];
        promises_out = r["promises"] as list[any];
        ties_out = r["ties"] as list[any];
        if len(people_out) == 0 {
            mark(counts, "WARN", "Capture A", (time.time() - t0) * 1000, "empty extraction (quota?)");
        } else {
            maya_found = False;
            for pe in people_out {
                person_d = pe["person"] as dict[str, any];
                if "name" in person_d and str(person_d["name"]) == "Maya Okafor" {
                    maya_found = True;
                }
            }
            if not maya_found {
                raise Exception(f"Maya Okafor not among extracted people: {people_out}");
            }
            if len(promises_out) == 0 {
                raise Exception("no promise extracted (expected the demo send)");
            }
            mark(
                counts, "PASS", "Capture A", (time.time() - t0) * 1000,
                f"people={len(people_out)} facts={len(facts_out)} "
                f"intents={len(intents_out)} promises={len(promises_out)} ties={len(ties_out)}"
            );
        }
    } except Exception as e {
        mark(counts, "FAIL", "Capture A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 5. B DevAddPerson + DevSeedMatch

    t0 = time.time();
    try {
        dp = post(base, token_b, "DevAddPerson", {"name": "Priya Rao"});
        if len(reports_of(dp)) == 0 {
            raise Exception("DevAddPerson: no reports");
        }
        sm = post(base, token_b, "DevSeedMatch", {
            "name": "Priya Rao",
            "fact": "Priya is a partner at a climate-tech seed fund.",
            "offer": "intros to climate-tech founders and student pitches"
        });
        sm_reps = reports_of(sm);
        if len(sm_reps) == 0 or "person_id" not in sm_reps[0] {
            raise Exception(f"DevSeedMatch: missing person_id: {sm_reps}");
        }
        mark(counts, "PASS", "DevAddPerson+DevSeedMatch B", (time.time() - t0) * 1000);
    } except Exception as e {
        mark(counts, "FAIL", "DevAddPerson+DevSeedMatch B", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 6. A SetGoal + GoalRank

    goal_id = "";
    t0 = time.time();
    try {
        data = post(base, token_a, "SetGoal", {"text": GOAL_TEXT});
        reps = reports_of(data);
        if len(reps) == 0 or "_jac_id" not in reps[0] {
            raise Exception(f"missing goal id: {reps}");
        }
        goal_id = str(reps[0]["_jac_id"]);
        mark(counts, "PASS", "SetGoal A", (time.time() - t0) * 1000, f"goal_id={goal_id}");
    } except Exception as e {
        mark(counts, "FAIL", "SetGoal A", (time.time() - t0) * 1000, str(e));
    }

    t0 = time.time();
    try {
        if len(goal_id) == 0 {
            raise Exception("no goal_id from SetGoal");
        }
        time.sleep(sleep_s);
        data = post(base, token_a, "GoalRank", {"goal_id": goal_id});
        reps = reports_of(data);
        detail = "no candidates ranked";
        if len(reps) > 0 {
            top = reps[0];
            person_d = top["person"] as dict[str, any];
            detail = f"top={person_d['name']} · {top['label']} · {top['strength']}";
        }
        mark(counts, "PASS", "GoalRank A", (time.time() - t0) * 1000, detail);
    } except Exception as e {
        mark(counts, "FAIL", "GoalRank A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 7. A GapFinder

    need = NEED_FALLBACK;
    t0 = time.time();
    try {
        if len(goal_id) == 0 {
            raise Exception("no goal_id");
        }
        time.sleep(sleep_s);
        data = post(base, token_a, "GapFinder", {"goal_id": goal_id});
        reps = reports_of(data);
        if len(reps) == 0 {
            mark(counts, "WARN", "GapFinder A", (time.time() - t0) * 1000, "no gap reported (model unavailable?)");
        } else {
            gap0 = reps[0];
            if "suggested_need" in gap0 and len(str(gap0["suggested_need"])) > 0 {
                need = str(gap0["suggested_need"]);
            }
            mark(counts, "PASS", "GapFinder A", (time.time() - t0) * 1000, f"need={need}");
        }
    } except Exception as e {
        mark(counts, "FAIL", "GapFinder A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 8. A PostRequest

    request_id = "";
    t0 = time.time();
    try {
        data = post(base, token_a, "PostRequest", {"need": need, "about_line": "CS junior building accessible robotics", "audience": "everyone"});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        req = reps[0];
        if "error" in req {
            raise Exception(str(req["error"]));
        }
        request_id = str(req["_jac_id"]);
        mark(counts, "PASS", "PostRequest A", (time.time() - t0) * 1000, f"request_id={request_id}");
    } except Exception as e {
        mark(counts, "FAIL", "PostRequest A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 9. B ListIncomingRequests

    t0 = time.time();
    try {
        if len(request_id) == 0 {
            raise Exception("no request_id from PostRequest");
        }
        data = post(base, token_b, "ListIncomingRequests", {});
        reps = reports_of(data);
        ids = [str(r["_jac_id"]) for r in reps];
        if request_id not in ids {
            raise Exception(f"request {request_id} not in incoming {ids}");
        }
        mark(counts, "PASS", "ListIncomingRequests B", (time.time() - t0) * 1000);
    } except Exception as e {
        mark(counts, "FAIL", "ListIncomingRequests B", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 10. B ReplyToRequest

    reply_id = "";
    match_count = -1;
    t0 = time.time();
    try {
        if len(request_id) == 0 {
            raise Exception("no request_id");
        }
        time.sleep(sleep_s);
        data = post(base, token_b, "ReplyToRequest", {"request_id": request_id});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        rv = reps[0];
        if "error" in rv {
            raise Exception(str(rv["error"]));
        }
        if "match_person_id" in rv {
            raise Exception("match_person_id leaked in ReplyView");
        }
        reply_id = str(rv["_jac_id"]);
        match_count = int(rv["match_count"]);
        if match_count == 0 {
            mark(counts, "WARN", "ReplyToRequest B", (time.time() - t0) * 1000, "match_count == 0");
        } else {
            mark(counts, "PASS", "ReplyToRequest B", (time.time() - t0) * 1000, f"match_count={match_count}");
        }
    } except Exception as e {
        mark(counts, "FAIL", "ReplyToRequest B", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 11. A ListMyRequests

    t0 = time.time();
    try {
        if len(reply_id) == 0 {
            raise Exception("no reply_id");
        }
        data = post(base, token_a, "ListMyRequests", {});
        reps = reports_of(data);
        found_pending = False;
        reply_total = 0;
        for item in reps {
            req_d = item["request"] as dict[str, any];
            if str(req_d["_jac_id"]) == request_id {
                replies = item["replies"] as list[dict[str, any]];
                reply_total = len(replies);
                for rp in replies {
                    if str(rp["_jac_id"]) == reply_id and str(rp["status"]) == "pending" {
                        found_pending = True;
                    }
                }
            }
        }
        if reply_total == 0 {
            mark(counts, "WARN", "ListMyRequests A", (time.time() - t0) * 1000, "0 replies (friends-only audience without a handshake, or B blocked?)");
        } elif not found_pending {
            raise Exception(f"reply not shown pending in ListMyRequests: {reps}");
        } else {
            mark(counts, "PASS", "ListMyRequests A", (time.time() - t0) * 1000);
        }
    } except Exception as e {
        mark(counts, "FAIL", "ListMyRequests A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 12. B ApproveReply, OptIn, Reveal

    exchange_completed = False;
    revealed_handle = "";

    t0 = time.time();
    try {
        if len(reply_id) == 0 {
            raise Exception("no reply_id");
        }
        data = post(base, token_b, "ApproveReply", {"reply_id": reply_id});
        reps = reports_of(data);
        if len(reps) == 0 or "error" in reps[0] {
            raise Exception(f"ApproveReply failed: {reps}");
        }
        mark(counts, "PASS", "ApproveReply B", (time.time() - t0) * 1000);
    } except Exception as e {
        mark(counts, "FAIL", "ApproveReply B", (time.time() - t0) * 1000, str(e));
    }

    opted_in = False;
    t0 = time.time();
    try {
        if len(reply_id) == 0 {
            raise Exception("no reply_id");
        }
        data = post(base, token_b, "OptIn", {"reply_id": reply_id});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        oi = reps[0];
        if "error" in oi {
            if str(oi["error"]) == "invalid_state" and match_count == 0 {
                mark(counts, "SKIP", "OptIn B", (time.time() - t0) * 1000, f"expected invalid_state ({NO_MATCH_NOTE})");
            } else {
                raise Exception(str(oi["error"]));
            }
        } else {
            draft = str(oi["opt_in_draft"]);
            opted_in = True;
            mark(counts, "PASS", "OptIn B", (time.time() - t0) * 1000, draft[:80]);
        }
    } except Exception as e {
        mark(counts, "FAIL", "OptIn B", (time.time() - t0) * 1000, str(e));
    }

    if opted_in {
        t0 = time.time();
        try {
            data = post(base, token_b, "Reveal", {"reply_id": reply_id});
            reps = reports_of(data);
            if len(reps) == 0 {
                raise Exception("no reports");
            }
            rl = reps[0];
            if "error" in rl {
                raise Exception(str(rl["error"]));
            }
            revealed_handle = str(rl["revealed_card_handle"]);
            exchange_completed = True;
            mark(counts, "PASS", "Reveal B", (time.time() - t0) * 1000, f"handle={revealed_handle}");
        } except Exception as e {
            mark(counts, "FAIL", "Reveal B", (time.time() - t0) * 1000, str(e));
        }
    } else {
        mark(counts, "SKIP", "Reveal B", 0.0, NO_MATCH_NOTE);
    }

    # ---------------------------------------------------------- 13. A ClaimReveal + ListPeople both sides

    b_people_final: list[dict[str, any]] = [];

    if exchange_completed {
        b_before: list[dict[str, any]] = [];
        try {
            b_before = reports_of(post(base, token_b, "ListPeople", {}));
        } except Exception {
            b_before = [];
        }

        t0 = time.time();
        try {
            time.sleep(sleep_s);
            data = post(base, token_a, "ClaimReveal", {"reply_id": reply_id});
            reps = reports_of(data);
            if len(reps) == 0 {
                raise Exception("no reports");
            }
            cr = reps[0];
            if "error" in cr {
                raise Exception(str(cr["error"]));
            }
            person_d = cr["person"] as dict[str, any];
            card_d = cr["card"] as dict[str, any];
            if str(person_d["name"]) != "Priya Rao" {
                raise Exception(f"unexpected person name: {person_d['name']}");
            }
            if str(card_d["handle"]) != revealed_handle {
                raise Exception(f"card handle mismatch: {card_d['handle']} != {revealed_handle}");
            }
            mark(counts, "PASS", "ClaimReveal A", (time.time() - t0) * 1000);
        } except Exception as e {
            mark(counts, "FAIL", "ClaimReveal A", (time.time() - t0) * 1000, str(e));
        }

        t0 = time.time();
        try {
            a_people = reports_of(post(base, token_a, "ListPeople", {}));
            names = [str(p["name"]) for p in a_people];
            if "Priya Rao" not in names {
                raise Exception(f"Priya Rao not in A's ListPeople: {names}");
            }
            mark(counts, "PASS", "ListPeople A (Priya)", (time.time() - t0) * 1000);
        } except Exception as e {
            mark(counts, "FAIL", "ListPeople A (Priya)", (time.time() - t0) * 1000, str(e));
        }

        t0 = time.time();
        try {
            b_after = reports_of(post(base, token_b, "ListPeople", {}));
            b_people_final = b_after;
            before_ids = [str(p["_jac_id"]) for p in b_before];
            after_ids = [str(p["_jac_id"]) for p in b_after];
            if before_ids != after_ids {
                raise Exception(f"B's ListPeople changed: {before_ids} -> {after_ids}");
            }
            mark(counts, "PASS", "ListPeople B (unchanged)", (time.time() - t0) * 1000, f"count={len(after_ids)}");
        } except Exception as e {
            mark(counts, "FAIL", "ListPeople B (unchanged)", (time.time() - t0) * 1000, str(e));
        }
    } else {
        mark(counts, "SKIP", "ClaimReveal A", 0.0, NO_MATCH_NOTE);
        mark(counts, "SKIP", "ListPeople A (Priya)", 0.0, NO_MATCH_NOTE);

        t0 = time.time();
        try {
            b_people_final = reports_of(post(base, token_b, "ListPeople", {}));
            mark(counts, "PASS", "ListPeople B", (time.time() - t0) * 1000, f"count={len(b_people_final)}");
        } except Exception as e {
            mark(counts, "FAIL", "ListPeople B", (time.time() - t0) * 1000, str(e));
        }
    }

    # ---------------------------------------------------------- 14. Isolation: A Receipt on a B person id

    t0 = time.time();
    try {
        if len(b_people_final) == 0 {
            raise Exception("no B person id known to test isolation with");
        }
        target_id = str(b_people_final[0]["_jac_id"]);
        data = post(base, token_a, "Receipt", {"id": target_id});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        rc = reps[0];
        if "error" not in rc or str(rc["error"]) != "not_found" {
            raise Exception(f"expected not_found, got {rc}");
        }
        mark(counts, "PASS", "Receipt A on B's person (isolation)", (time.time() - t0) * 1000);
    } except Exception as e {
        mark(counts, "FAIL", "Receipt A on B's person (isolation)", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- 15. A ListPromises + Recall

    t0 = time.time();
    try {
        reps = reports_of(post(base, token_a, "ListPromises", {}));
        mark(counts, "PASS", "ListPromises A", (time.time() - t0) * 1000, f"count={len(reps)}");
    } except Exception as e {
        mark(counts, "FAIL", "ListPromises A", (time.time() - t0) * 1000, str(e));
    }

    t0 = time.time();
    try {
        time.sleep(sleep_s);
        data = post(base, token_a, "Recall", {"question": "who wants feedback from wheelchair users?"});
        reps = reports_of(data);
        if len(reps) == 0 {
            raise Exception("no reports");
        }
        rc = reps[0];
        if "insufficient" not in rc {
            raise Exception(f"missing insufficient field: {rc}");
        }
        mark(counts, "PASS", "Recall A", (time.time() - t0) * 1000, f"insufficient={rc['insufficient']}");
    } except Exception as e {
        mark(counts, "FAIL", "Recall A", (time.time() - t0) * 1000, str(e));
    }

    # ---------------------------------------------------------- summary

    elapsed = time.time() - started_at;
    print("-- summary --");
    print(
        f"PASS={counts['PASS']} WARN={counts['WARN']} SKIP={counts['SKIP']} "
        f"FAIL={counts['FAIL']} total_time={elapsed:.1f}s"
    );
    print(f"accounts: A={username_a} B={username_b}");

    if counts["FAIL"] > 0 {
        sys.exit(1);
    }
}
