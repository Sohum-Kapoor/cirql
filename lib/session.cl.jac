"""Per-tab-session UI memory (SOH-213). OWNER: Person B.

sessionStorage: survives a reload of this tab, gone when the tab/app closes —
"remember for the session". Every access is guarded (Safari private mode and some
WKWebView configs throw); unreadable -> the default.

Keys: cirql.tab (home | asks | people), cirql.cap_kind (voice | guided | paste).
"""

glob:pub TAB_KEY: str = "cirql.tab",
     CAP_KIND_KEY: str = "cirql.cap_kind",
     TABS: list[str] = ["home", "asks", "people"],
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

"""The remembered home tab, "home" by default."""
def:pub session_tab() -> str {
    v: str = _get(TAB_KEY);
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

"""Logout: the next account starts on Home / Voice."""
def:pub clear_session_ui() -> None {
    try {
        sessionStorage.removeItem(TAB_KEY);  # jac:ignore[W2001]
        sessionStorage.removeItem(CAP_KIND_KEY);  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}
