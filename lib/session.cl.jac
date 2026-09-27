"""Per-tab-session UI memory (SOH-213). OWNER: Person B.

sessionStorage: survives a reload of this tab, gone when the tab/app closes —
"remember for the session". Every access is guarded (Safari private mode and some
WKWebView configs throw); unreadable -> the default.

Keys: cirql.tab (home | inbox | people; a stored "asks" from before SOH-224 reads
as "inbox"), cirql.cap_kind (voice | guided | paste), cirql.agent_run (the last
RunAgent report, JSON: { ran_at, new, total_open, ms } — `ms` is the client clock
when it finished, so "ran N min ago" never trusts server time). SOH-236:
cirql.agent_run moved to localStorage (survives a reload/new tab, not just this
one) so reopening the app right after a run still shows "ran N min ago" instead
of re-running immediately; still cleared on logout.
"""

glob:pub TAB_KEY: str = "cirql.tab",
     CAP_KIND_KEY: str = "cirql.cap_kind",
     AGENT_RUN_KEY: str = "cirql.agent_run",
     TABS: list[str] = ["home", "inbox", "people"],
     CAP_KINDS: list[str] = ["voice", "guided", "paste"];

def _get(key: str) -> str {
    out: str = "";
    try {
        v: any = sessionStorage.getItem(key);  # jac:ignore[W2001]
        if v {
            out = v as str;
        }
    } except Exception as e {
        out = "";
    }
    return out;
}

def _put(key: str, value: str) -> None {
    try {
        sessionStorage.setItem(key, value);  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}

"""Same guarded shape as `_get`/`_put`, against localStorage (SOH-236: the
agent-run timestamp needs to survive a reload/new tab, not just this one)."""
def _get_local(key: str) -> str {
    out: str = "";
    try {
        v: any = localStorage.getItem(key);  # jac:ignore[W2001]
        if v {
            out = v as str;
        }
    } except Exception as e {
        out = "";
    }
    return out;
}

def _put_local(key: str, value: str) -> None {
    try {
        localStorage.setItem(key, value);  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}

"""The remembered home tab, "home" by default."""
def:pub session_tab() -> str {
    v: str = _get(TAB_KEY);
    if v == "asks" {
        return "inbox";
    }
    return v if v in TABS else "home";
}

def:pub save_tab(tab: str) -> None {
    if tab in TABS {
        _put(TAB_KEY, tab);
    }
}

"""The last-used capture mode, "voice" by default."""
def:pub session_cap_kind() -> str {
    v: str = _get(CAP_KIND_KEY);
    return v if v in CAP_KINDS else "voice";
}

def:pub save_cap_kind(kind: str) -> None {
    if kind in CAP_KINDS {
        _put(CAP_KIND_KEY, kind);
    }
}

"""The last agent run: { ran_at, new, total_open, ms } or {}. SOH-236:
localStorage, not sessionStorage — a reopened tab still remembers it."""
def:pub session_agent_run() -> dict {
    raw: str = _get_local(AGENT_RUN_KEY);
    out: dict = {};
    if not raw {
        return out;
    }
    try {
        out = JSON.parse(raw) as dict;  # jac:ignore[W2001]
    } except Exception as e {
        out = {};
    }
    return out or {};
}

def:pub save_agent_run(run: dict) -> None {
    _put_local(AGENT_RUN_KEY, JSON.stringify(run));  # jac:ignore[W2001]
}

"""The client clock in ms (what `last_run.ms` is measured in)."""
def:pub now_ms() -> int {
    return Date.now() as int;  # jac:ignore[W2001]
}

"""Milliseconds since the last agent run this session (-1 = never)."""
def:pub agent_run_age_ms() -> int {
    run: dict = session_agent_run();
    if not run["ms"] {
        return -1;
    }
    return (Date.now() as int) - (run["ms"] as int);  # jac:ignore[W2001]
}

"""Logout: the next account starts on Home / Voice, with no agent run on record."""
def:pub clear_session_ui() -> None {
    try {
        sessionStorage.removeItem(TAB_KEY);  # jac:ignore[W2001]
        sessionStorage.removeItem(CAP_KIND_KEY);  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
    try {
        localStorage.removeItem(AGENT_RUN_KEY);  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}
