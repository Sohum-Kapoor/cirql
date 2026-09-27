"""scripts/populate.jac — SOH-221, multi-user population loader (owner B).

For each persona JSON in POP_DIR, pushes the persona through the real walkers
over HTTP (same idiom as seed/load.jac, which stays A's single-user loader):

    register (username + email identity) -> login (username identity)
    -> OnboardMe(about, name) -> SetGoal per goal (first goal ends active)
    -> Capture(text, kind="debrief", how_met) per debrief
    -> PublishCard(visibility="link") -> PostRequest(need, about_line)?
    -> GoalRank(active goal, refresh=True) once

Capture-only mode (POP_CAPTURE_ONLY=1) is for an EXISTING account (Jesse's):
login only (never register), read GetMe/ListGoals/ListPeople, run ONLY the
Captures, then one GoalRank(refresh=True) on the already-active goal. It never
calls OnboardMe, SetGoal, PublishCard or PostRequest, so the account's profile,
goals and card are never overwritten.

    jac run scripts/populate.jac
    POP_ONLY=pop_maya_01,pop_leo_02 jac run scripts/populate.jac
    POP_CAPTURE_ONLY=1 POP_FILES=jesse_extra.json POP_LOGIN=<username> \
        POP_PASSWORD=<pw> jac run scripts/populate.jac

Environment (all optional):
  POP_BASE         http://localhost:8000
  POP_DIR          seed/population
  POP_GLOB         u*.json      (which files in POP_DIR are personas)
  POP_FILES        ""           (comma list of file names; overrides POP_GLOB)
  POP_ONLY         ""           (comma list of usernames to (re)run)
  POP_PASSWORD     pop-pass-2026
  POP_CONCURRENCY  3            (users loaded at once; never more than 3 on the
                                 shared hosted server)
  POP_SLEEP        3            (seconds before each of one user's LLM calls)
  POP_FORCE        0            (1 = load even if the account already has people)
  POP_CAPTURE_ONLY 0            (1 = capture-only mode, see above)
  POP_LOGIN        ""           (capture-only: username or email to log in with)
  POP_RANK         1            (0 = skip the final GoalRank)

Log: one line per call, `<user> PASS|WARN|FAIL <Walker>[#n] (<ms>ms) detail`.
WARN = the call succeeded but returned an empty extraction / no ranking /
an `{error: ...}` report. FAIL = non-2xx or `{"ok": false}`. Exit 1 on any FAIL.
Credentials never appear in the log or in any file.
"""

import requests;
import json;
import os;
import sys;
import time;
import fnmatch;


# ---------------------------------------------------------------- HTTP driver

"""POST /walker/<name> with a bearer token; raises on non-2xx or ok=false
(message carries the response body, never the token)."""
def post(base: str, token: str, name: str, body: dict[str, any]) -> dict[str, any] {
    headers: dict[str, str] = {"Content-Type": "application/json"};
    if len(token) > 0 {
        headers["Authorization"] = f"Bearer {token}";
    }
    resp = requests.post(f"{base}/walker/{name}", headers=headers, json=body, timeout=180);
    if resp.status_code < 200 or resp.status_code >= 300 {
        raise Exception(f"HTTP {resp.status_code}: {resp.text[:300]}");
    }
    payload = resp.json() as dict[str, any];
    ok = payload.get("ok", False) as bool;
    if not ok {
        raise Exception(f"ok=false: {resp.text[:300]}");
    }
    data = payload["data"] as dict[str, any];
    return data;
}


"""Reports list off a walker response (AGENTS.md: data.reports, also
data.result.reports)."""
def reports_of(data: dict[str, any]) -> list[any] {
    if "reports" in data and data["reports"] is not None {
        return data["reports"] as list[any];
    }
    res = data.get("result", {}) as dict[str, any];
    if res is not None and "reports" in res {
        return res["reports"] as list[any];
    }
    return [];
}


def ms_since(t0: float) -> int {
    return int((time.time() - t0) * 1000);
}


"""One log line; returns the level so callers can count it."""
def log(user: str, level: str, call: str, ms: int, detail: str) -> str {
    print(f"{user:<22} {level:<4} {call:<14} ({ms:>6}ms) {detail}", flush=True);
    return level;
}


# ------------------------------------------------------------------ auth

"""Register username+email identities. True if newly created."""
def register(base: str, username: str, email: str, password: str) -> bool {
    body: dict[str, any] = {
        "identities": [
            {"type": "username", "value": username},
            {"type": "email", "value": email}
        ],
        "credential": {"type": "password", "password": password}
    };
    resp = requests.post(f"{base}/user/register", json=body, timeout=60);
    return resp.status_code >= 200 and resp.status_code < 300;
}


"""Log in with the given identity type; returns the token or ""."""
def login_as(base: str, id_type: str, value: str, password: str) -> str {
    body: dict[str, any] = {
        "identity": {"type": id_type, "value": value},
        "credential": {"type": "password", "password": password}
    };
    resp = requests.post(f"{base}/user/login", json=body, timeout=60);
    if resp.status_code < 200 or resp.status_code >= 300 {
        return "";
    }
    payload = resp.json() as dict[str, any];
    data = payload.get("data", {}) as dict[str, any];
    if data is None {
        return "";
    }
    return str(data.get("token", "") or "");
}


"""Username identity first (AGENTS.md), then email."""
def login(base: str, value: str, password: str) -> str {
    token = login_as(base, "username", value, password);
    if token == "" {
        token = login_as(base, "email", value, password);
    }
    return token;
}


# ------------------------------------------------------------ per-user steps

def count_people(base: str, token: str) -> int {
    data = post(base, token, "ListPeople", {});
    return len(reports_of(data));
}


def active_goal(base: str, token: str) -> dict[str, any] {
    data = post(base, token, "ListGoals", {});
    for g in reports_of(data) {
        gd = g as dict[str, any];
        if gd.get("active", False) as bool {
            return gd;
        }
    }
    return {};
}


def goal_count(base: str, token: str) -> int {
    data = post(base, token, "ListGoals", {});
    return len(reports_of(data));
}


"""One Capture; returns the log level."""
def do_capture(base: str, token: str, user: str, idx: int, text: str, how_met: str) -> str {
    t0 = time.time();
    try {
        body: dict[str, any] = {"text": text, "kind": "debrief"};
        if len(how_met) > 0 {
            body["how_met"] = how_met;
        }
        data = post(base, token, "Capture", body);
        reps = reports_of(data);
        if len(reps) == 0 {
            return log(user, "WARN", f"Capture#{idx}", ms_since(t0), "no report");
        }
        r = reps[0] as dict[str, any];
        people = r.get("people", []) as list[any];
        facts = r.get("facts", []) as list[any];
        intents = r.get("intents", []) as list[any];
        promises = r.get("promises", []) as list[any];
        ties = r.get("ties", []) as list[any];
        amb = 0;
        for p in people {
            pd = p as dict[str, any];
            if len(pd.get("ambiguous_with", []) as list[any]) > 0 {
                amb += 1;
            }
        }
        detail = (
            f"people={len(people)} facts={len(facts)} intents={len(intents)} "
            f"promises={len(promises)} ties={len(ties)} ambiguous={amb}"
        );
        if len(people) + len(facts) + len(intents) + len(promises) + len(ties) == 0 {
            return log(user, "WARN", f"Capture#{idx}", ms_since(t0), "EMPTY extraction");
        }
        return log(user, "PASS", f"Capture#{idx}", ms_since(t0), detail);
    } except Exception as e {
        return log(user, "FAIL", f"Capture#{idx}", ms_since(t0), str(e));
    }
}


"""GoalRank(refresh=True); returns (level, ranking list)."""
def do_rank(base: str, token: str, user: str, goal_id: str) -> tuple[str, list[any]] {
    t0 = time.time();
    try {
        data = post(base, token, "GoalRank", {"goal_id": goal_id, "refresh": True});
        reps = reports_of(data);
        if len(reps) == 0 {
            return (log(user, "WARN", "GoalRank", ms_since(t0), "no candidates ranked"), reps);
        }
        top: list[str] = [];
        for item in reps[:3] {
            it = item as dict[str, any];
            person = it.get("person", {}) as dict[str, any];
            top.append(f"{person.get('name', '?')}/{it.get('label', '?')}/{it.get('strength', '?')}");
        }
        return (log(user, "PASS", "GoalRank", ms_since(t0), f"n={len(reps)} top: {', '.join(top)}"), reps);
    } except Exception as e {
        return (log(user, "FAIL", "GoalRank", ms_since(t0), str(e)), []);
    }
}


"""Full persona load (or capture-only). Returns one summary row."""
def load_user(cfg: dict[str, any], path: str) -> dict[str, any] {
    base = cfg["base"] as str;
    sleep_s = cfg["sleep"] as float;
    capture_only = cfg["capture_only"] as bool;
    started = time.time();
    levels: list[str] = [];

    f = open(path, "r");
    persona = json.loads(f.read()) as dict[str, any];
    f.close();

    username = str(persona.get("username", "") or "");
    email = str(persona.get("email", "") or "");
    name = str(persona.get("name", "") or "");
    password = cfg["password"] as str;
    user = username if username != "" else os.path.basename(path);
    row: dict[str, any] = {
        "user": user, "people_before": 0, "people": 0, "goals": 0,
        "request": "n", "pass": 0, "warn": 0, "fail": 0, "secs": 0.0,
        "active_goal": "", "ranking": []
    };

    # ---- auth
    token = "";
    t0 = time.time();
    if capture_only {
        login_id = cfg["login"] as str;
        user = "capture-only";
        row["user"] = user;
        if login_id == "" {
            levels.append(log(user, "FAIL", "login", 0, "POP_LOGIN not set"));
        } else {
            token = login(base, login_id, password);
        }
    } else {
        created = register(base, username, email, password);
        levels.append(log(user, "PASS", "register", ms_since(t0), "new account" if created else "exists, skipped"));
        t0 = time.time();
        token = login_as(base, "username", username, password);
    }
    if token == "" {
        levels.append(log(user, "FAIL", "login", ms_since(t0), "no token"));
        row["fail"] = 1;
        return row;
    }
    levels.append(log(user, "PASS", "login", ms_since(t0), ""));

    # ---- before
    active: dict[str, any] = {};
    try {
        row["people_before"] = count_people(base, token);
        if capture_only {
            me_data = post(base, token, "GetMe", {});
            me_reps = reports_of(me_data);
            me_name = "";
            if len(me_reps) > 0 {
                me_name = str((me_reps[0] as dict[str, any]).get("name", ""));
            }
            active = active_goal(base, token);
            log(user, "PASS", "GetMe", 0, f"name={me_name} people={row['people_before']} active_goal={active.get('text', '(none)')}");
        }
    } except Exception as e {
        levels.append(log(user, "FAIL", "ListPeople", 0, str(e)));
    }

    force = cfg["force"] as bool;
    already = (row["people_before"] as int) > 0 and not capture_only;
    if already and not force {
        log(user, "PASS", "skip", 0, f"already has {row['people_before']} people (POP_FORCE=1 to reload)");
    } else {
        if not capture_only {
            # ---- OnboardMe
            time.sleep(sleep_s);
            t0 = time.time();
            try {
                body: dict[str, any] = {"about": persona["about_me"]};
                if name != "" {
                    body["name"] = name;
                }
                ob = reports_of(post(base, token, "OnboardMe", body));
                if len(ob) == 0 {
                    levels.append(log(user, "WARN", "OnboardMe", ms_since(t0), "no report"));
                } else {
                    o = ob[0] as dict[str, any];
                    n_int = len(o.get("interests", []) as list[any]);
                    n_goal = len(o.get("goals", []) as list[any]);
                    n_int2 = len(o.get("intents", []) as list[any]);
                    card = o.get("card", {}) as dict[str, any];
                    levels.append(log(
                        user, "PASS", "OnboardMe", ms_since(t0),
                        f"interests={n_int} goals={n_goal} intents={n_int2} handle={card.get('handle', '')}"
                    ));
                }
            } except Exception as e {
                levels.append(log(user, "FAIL", "OnboardMe", ms_since(t0), str(e)));
            }

            # ---- SetGoal, reversed so goals[0] ends up active
            goals = persona.get("goals", []) as list[str];
            for g in reversed(goals) {
                t0 = time.time();
                try {
                    sg = reports_of(post(base, token, "SetGoal", {"text": g}));
                    if len(sg) == 0 {
                        levels.append(log(user, "WARN", "SetGoal", ms_since(t0), "no report"));
                    } else {
                        levels.append(log(user, "PASS", "SetGoal", ms_since(t0), g[:60]));
                    }
                } except Exception as e {
                    levels.append(log(user, "FAIL", "SetGoal", ms_since(t0), str(e)));
                }
            }
        }

        # ---- Capture
        debriefs = persona.get("debriefs", []) as list[any];
        i = 0;
        for d in debriefs {
            i += 1;
            text = "";
            how_met = "";
            if isinstance(d, str) {
                text = d as str;
            } else {
                dd = d as dict[str, any];
                text = str(dd.get("text", ""));
                how_met = str(dd.get("how_met", "") or "");
            }
            time.sleep(sleep_s);
            levels.append(do_capture(base, token, user, i, text, how_met));
        }

        if not capture_only {
            # ---- PublishCard
            card_in = persona.get("card", {}) as dict[str, any];
            t0 = time.time();
            try {
                body2: dict[str, any] = {
                    "headline": card_in.get("headline", ""),
                    "about": card_in.get("about", ""),
                    "looking_for": card_in.get("looking_for", []),
                    "can_offer": card_in.get("can_offer", []),
                    "visibility": "link",
                    "name": name
                };
                pc = reports_of(post(base, token, "PublishCard", body2));
                first = (pc[0] if len(pc) > 0 else {}) as dict[str, any];
                if "error" in first {
                    levels.append(log(user, "WARN", "PublishCard", ms_since(t0), f"error={first['error']}"));
                } else {
                    levels.append(log(user, "PASS", "PublishCard", ms_since(t0), f"handle={first.get('handle', '')}"));
                }
            } except Exception as e {
                levels.append(log(user, "FAIL", "PublishCard", ms_since(t0), str(e)));
            }

            # ---- PostRequest (only personas that carry one)
            req = persona.get("request", None);
            if req is not None {
                rq = req as dict[str, any];
                t0 = time.time();
                try {
                    pr = reports_of(post(base, token, "PostRequest", {"need": rq["need"], "about_line": rq["about_line"]}));
                    firstr = (pr[0] if len(pr) > 0 else {}) as dict[str, any];
                    if "error" in firstr or len(pr) == 0 {
                        levels.append(log(user, "WARN", "PostRequest", ms_since(t0), str(firstr)));
                    } else {
                        row["request"] = "y";
                        levels.append(log(user, "PASS", "PostRequest", ms_since(t0), str(rq["need"])[:60]));
                    }
                } except Exception as e {
                    levels.append(log(user, "FAIL", "PostRequest", ms_since(t0), str(e)));
                }
            }
        }

        # ---- GoalRank once, on the active goal
        if cfg["rank"] as bool {
            try {
                active = active_goal(base, token);
            } except Exception as e {
                levels.append(log(user, "FAIL", "ListGoals", 0, str(e)));
            }
            gid = str(active.get("_jac_id", "") or "");
            if gid == "" {
                levels.append(log(user, "WARN", "GoalRank", 0, "no active goal"));
            } else {
                time.sleep(sleep_s);
                (lvl, ranking) = do_rank(base, token, user, gid);
                levels.append(lvl);
                row["ranking"] = ranking;
            }
        }
    }

    # ---- after
    try {
        row["people"] = count_people(base, token);
        row["goals"] = goal_count(base, token);
        if len(active) == 0 {
            active = active_goal(base, token);
        }
        row["active_goal"] = str(active.get("text", "") or "");
    } except Exception as e {
        levels.append(log(user, "FAIL", "summary", 0, str(e)));
    }
    row["pass"] = levels.count("PASS");
    row["warn"] = levels.count("WARN");
    row["fail"] = levels.count("FAIL");
    row["secs"] = time.time() - started;
    return row;
}


"""Worker: loads its slice of files one after another."""
def worker(cfg: dict[str, any], paths: list[str]) -> list[dict[str, any]] {
    rows: list[dict[str, any]] = [];
    for p in paths {
        try {
            rows.append(load_user(cfg, p));
        } except Exception as e {
            print(f"{os.path.basename(p):<22} FAIL load           (     0ms) {str(e)}", flush=True);
            rows.append({"user": os.path.basename(p), "people_before": 0, "people": 0, "goals": 0,
                         "request": "n", "pass": 0, "warn": 0, "fail": 1, "secs": 0.0,
                         "active_goal": "", "ranking": []});
        }
    }
    return rows;
}


def row_key(r: dict[str, any]) -> str {
    return str(r["user"]);
}


def pick_files(cfg: dict[str, any]) -> list[str] {
    d = cfg["dir"] as str;
    names: list[str] = [];
    files_env = cfg["files"] as str;
    if files_env != "" {
        names = [n.strip() for n in files_env.split(",") if n.strip() != ""];
    } else {
        names = sorted([n for n in os.listdir(d) if fnmatch.fnmatch(n, cfg["glob"] as str)]);
    }
    only = cfg["only"] as list[str];
    out: list[str] = [];
    for n in names {
        p = os.path.join(d, n);
        if len(only) > 0 {
            f = open(p, "r");
            uname = str((json.loads(f.read()) as dict[str, any]).get("username", ""));
            f.close();
            if uname not in only {
                continue;
            }
        }
        out.append(p);
    }
    return out;
}


with entry:__main__ {
    only_env = os.environ.get("POP_ONLY", "") as str;
    cfg: dict[str, any] = {
        "base": (os.environ.get("POP_BASE", "http://localhost:8000") as str).rstrip("/"),
        "dir": os.environ.get("POP_DIR", "seed/population"),
        "glob": os.environ.get("POP_GLOB", "u*.json"),
        "files": os.environ.get("POP_FILES", ""),
        "only": [o.strip() for o in only_env.split(",") if o.strip() != ""],
        "password": os.environ.get("POP_PASSWORD", "pop-pass-2026"),
        "sleep": float(os.environ.get("POP_SLEEP", "3") as str),
        "force": os.environ.get("POP_FORCE", "0") == "1",
        "capture_only": os.environ.get("POP_CAPTURE_ONLY", "0") == "1",
        "login": os.environ.get("POP_LOGIN", ""),
        "rank": os.environ.get("POP_RANK", "1") != "0"
    };
    conc = max(1, min(3, int(os.environ.get("POP_CONCURRENCY", "3") as str)));
    paths = pick_files(cfg);
    mode = "capture-only" if cfg["capture_only"] as bool else "full";
    print(f"== populate == base={cfg['base']} files={len(paths)} concurrency={conc} mode={mode}", flush=True);

    t_start = time.time();
    slices: list[list[str]] = [paths[k::conc] for k in range(conc)];
    futures = [flow worker(cfg, s) for s in slices if len(s) > 0];
    rows: list[dict[str, any]] = [];
    for fu in futures {
        got = (wait fu) as list[dict[str, any]];
        rows.extend(got);
    }
    wall = time.time() - t_start;

    rows = sorted(rows, key=row_key);
    print("");
    print("== summary ==");
    print(f"{'user':<22} {'people':>13} {'goals':>5} {'req':>3} {'pass':>4} {'warn':>4} {'fail':>4} {'secs':>6}");
    tp = 0;
    tw = 0;
    tf = 0;
    reqs = 0;
    for r in rows {
        ppl = f"{r['people_before']}->{r['people']}";
        print(f"{r['user']:<22} {ppl:>13} {r['goals']:>5} {r['request']:>3} {r['pass']:>4} {r['warn']:>4} {r['fail']:>4} {r['secs']:>6.0f}");
        tp += r["pass"] as int;
        tw += r["warn"] as int;
        tf += r["fail"] as int;
        if r["request"] == "y" {
            reqs += 1;
        }
    }
    print(f"users={len(rows)} requests_posted={reqs} PASS={tp} WARN={tw} FAIL={tf} wall={wall:.0f}s");

    if cfg["capture_only"] as bool {
        for r in rows {
            print("");
            print(f"active goal: {r['active_goal']}");
            print(f"people: {r['people_before']} -> {r['people']}");
            print("GoalRank top 8:");
            n = 0;
            for item in r["ranking"] as list[any] {
                n += 1;
                it = item as dict[str, any];
                person = it.get("person", {}) as dict[str, any];
                print(f"  {n}. {person.get('name', '?')} | {it.get('label', '')} | {it.get('strength', '')} | {it.get('reason', '')}");
                if n >= 8 {
                    break;
                }
            }
            print("full ranking (name label strength):");
            n = 0;
            for item in r["ranking"] as list[any] {
                n += 1;
                it = item as dict[str, any];
                person = it.get("person", {}) as dict[str, any];
                print(f"  {n}. {person.get('name', '?')} {it.get('label', '')} {it.get('strength', '')}");
            }
        }
    }

    if tf > 0 {
        sys.exit(1);
    }
}
