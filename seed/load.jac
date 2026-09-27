"""seed/load.jac — SOH-175.

Signs in (registering if needed) and pushes seed/seed.example.json through the
real walkers — OnboardMe, SetGoal, Capture, GoalRank — over HTTP, so seed data
takes the same provenance path as real data. Owner A (seed/load.jac is A's per
AGENTS.md); does not touch seed/seed.example.json (owner B's file).

Run against a live `jac start main.jac` server:

    jac run seed/load.jac

Configuration is read from the environment (all optional, defaults below):
  SEED_FILE     seed/seed.example.json
  SEED_BASE     http://localhost:8000
  SEED_USERNAME demo
  SEED_EMAIL    demo@example.com
  SEED_PASSWORD demo-pass-123
  SEED_SLEEP    7      (seconds between LLM-backed Capture calls)
  SEED_RANK     1      (set 0 to skip the final GoalRank pre-warm)

Reports come back as `data.reports` (AGENTS.md gotchas). Login must use the
username identity, never email (AGENTS.md gotchas).
"""

import requests;
import json;
import os;
import time;
import sys;

"""POST /walker/<name> with a bearer token. Raises on a non-2xx HTTP status
or on a top-level {"ok": false} response — either way the raised message
carries the response body, never the token."""
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

with entry {
    seed_file = os.environ.get("SEED_FILE", "seed/seed.example.json") as str;
    base = os.environ.get("SEED_BASE", "http://localhost:8000") as str;
    username = os.environ.get("SEED_USERNAME", "demo") as str;
    email = os.environ.get("SEED_EMAIL", "demo@example.com") as str;
    password = os.environ.get("SEED_PASSWORD", "demo-pass-123") as str;
    sleep_s = float(os.environ.get("SEED_SLEEP", "7") as str);
    rank_flag = os.environ.get("SEED_RANK", "1") as str;
    do_rank = rank_flag != "0";

    started_at = time.time();
    ok = True;

    print(f"== seed/load.jac == base={base} user={username} file={seed_file}");

    f = open(seed_file, "r");
    raw = f.read() as str;
    f.close();
    seed = json.loads(raw) as dict[str, any];

    about_me = seed["about_me"] as str;
    debriefs = seed["debriefs"] as list[str];
    seed_goals = seed["goals"] as list[str];

    # ---------------------------------------------------------- register

    print("-- register --");
    reg_body: dict[str, any] = {
        "identities": [
            {"type": "username", "value": username},
            {"type": "email", "value": email}
        ],
        "credential": {"type": "password", "password": password}
    };
    reg_resp = requests.post(f"{base}/user/register", json=reg_body, timeout=60);
    if reg_resp.status_code >= 200 and reg_resp.status_code < 300 {
        print(f"  registered new account {username}");
    } else {
        print(f"  register skipped (already exists, most likely): HTTP {reg_resp.status_code}");
    }

    # ------------------------------------------------------------ login

    print("-- login --");
    login_body: dict[str, any] = {
        "identity": {"type": "username", "value": username},
        "credential": {"type": "password", "password": password}
    };
    login_resp = requests.post(f"{base}/user/login", json=login_body, timeout=60);
    if login_resp.status_code < 200 or login_resp.status_code >= 300 {
        print(f"  login FAILED: HTTP {login_resp.status_code}: {login_resp.text}");
        sys.exit(1);
    }
    login_payload = login_resp.json() as dict[str, any];
    login_data = login_payload["data"] as dict[str, any];
    token = login_data["token"] as str;
    print(f"  logged in as {username}");

    # -------------------------------------------------------- OnboardMe

    print("-- OnboardMe --");
    try {
        onboard_data = post(base, token, "OnboardMe", {"about": about_me});
        onboard_reports = onboard_data["reports"] as list[dict[str, any]];
        if len(onboard_reports) > 0 {
            first = onboard_reports[0];
            interests = first["interests"] as list[dict[str, any]];
            goals_out = first["goals"] as list[dict[str, any]];
            intents_out = first["intents"] as list[dict[str, any]];
            card = first["card"] as dict[str, any];
            handle = card["handle"] as str;
            print(
                f"  interests={len(interests)} goals={len(goals_out)} "
                f"intents={len(intents_out)} card_handle={handle}"
            );
        } else {
            print("  OnboardMe returned no reports");
            ok = False;
        }
    } except Exception as e {
        print(f"  OnboardMe FAILED: {str(e)}");
        ok = False;
    }

    # ---------------------------------------------------------- SetGoal

    print("-- SetGoal --");
    active_goal_id = "";
    for g in seed_goals {
        try {
            sg_data = post(base, token, "SetGoal", {"text": g});
            sg_reports = sg_data["reports"] as list[dict[str, any]];
            if len(sg_reports) > 0 {
                goal_obj = sg_reports[0];
                gid = goal_obj["_jac_id"] as str;
                active_goal_id = gid;
                print(f"  '{g}' -> {gid}");
            } else {
                print(f"  SetGoal('{g}') returned no reports");
                ok = False;
            }
        } except Exception as e {
            print(f"  SetGoal('{g}') FAILED: {str(e)}");
            ok = False;
        }
    }

    # ---------------------------------------------------------- Capture

    print("-- Capture --");
    for d in debriefs {
        time.sleep(sleep_s);
        try {
            cap_data = post(base, token, "Capture", {"text": d, "kind": "debrief"});
            cap_reports = cap_data["reports"] as list[dict[str, any]];
            if len(cap_reports) == 0 {
                print("  Capture returned no reports");
                ok = False;
                continue;
            }
            r = cap_reports[0];
            note_id = r["note_id"] as str;
            people = r["people"] as list[dict[str, any]];
            facts = r["facts"] as list[dict[str, any]];
            intents_c = r["intents"] as list[dict[str, any]];
            promises = r["promises"] as list[dict[str, any]];
            ties = r["ties"] as list[dict[str, any]];
            total = len(people) + len(facts) + len(intents_c) + len(promises) + len(ties);
            if total == 0 {
                print(f"  note_id={note_id} EMPTY extraction (quota exhausted?), continuing");
            } else {
                print(
                    f"  note_id={note_id} people={len(people)} facts={len(facts)} "
                    f"intents={len(intents_c)} promises={len(promises)} ties={len(ties)}"
                );
            }
        } except Exception as e {
            print(f"  Capture FAILED: {str(e)}");
            ok = False;
        }
    }

    # --------------------------------------------------------- GoalRank

    if do_rank and active_goal_id != "" {
        print("-- GoalRank --");
        try {
            rank_data = post(base, token, "GoalRank", {"goal_id": active_goal_id});
            rank_reports = rank_data["reports"] as list[dict[str, any]];
            if len(rank_reports) == 0 {
                print("  no candidates ranked");
            }
            top3 = rank_reports[:3];
            for item in top3 {
                person = item["person"] as dict[str, any];
                pname = person["name"] as str;
                label = item["label"] as str;
                strength = item["strength"] as str;
                print(f"  {pname} · {label} · {strength}");
            }
        } except Exception as e {
            print(f"  GoalRank FAILED: {str(e)}");
            ok = False;
        }
    } elif not do_rank {
        print("-- GoalRank skipped (SEED_RANK=0) --");
    } else {
        print("-- GoalRank skipped (no active goal) --");
    }

    # ---------------------------------------------------------- summary

    print("-- summary --");
    try {
        people_data = post(base, token, "ListPeople", {});
        people_all = people_data["reports"] as list[dict[str, any]];
        print(f"  people: {len(people_all)}");
    } except Exception as e {
        print(f"  ListPeople FAILED: {str(e)}");
        ok = False;
    }

    try {
        goals_data = post(base, token, "ListGoals", {});
        goals_all = goals_data["reports"] as list[dict[str, any]];
        active_text = "";
        for gr in goals_all {
            is_active = gr.get("active", False) as bool;
            if is_active {
                active_text = gr["text"] as str;
            }
        }
        print(f"  goals: {len(goals_all)} (active: {active_text})");
    } except Exception as e {
        print(f"  ListGoals FAILED: {str(e)}");
        ok = False;
    }

    elapsed = time.time() - started_at;
    print(f"-- done in {elapsed:.1f}s --");

    if not ok {
        sys.exit(1);
    }
}
