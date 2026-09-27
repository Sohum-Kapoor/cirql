"""Launch-time render cache (SOH-236). OWNER: Person B.

localStorage, one key per slice, all prefixed `cirql.cache.` so `clear_cache()`
(logout / account switch) wipes every one of them in a single pass without
touching `lib/session.cl.jac`'s per-tab keys or the `cirql.onboarding`
snapshot. Every access is guarded (Safari private mode and some WKWebView
configs throw on any localStorage call) — a cache miss/failure just means the
launch screen renders nothing cached and waits for the live load, same as
before this existed.
"""

glob:pub CACHE_PREFIX: str = "cirql.cache.";

def:pub cache_get(key: str) -> any {
    out: any = None;
    try {
        v: any = localStorage.getItem(CACHE_PREFIX + key);  # jac:ignore[W2001]
        if v {
            out = JSON.parse(v as str);  # jac:ignore[W2001]
        }
    } except Exception as e {
        out = None;
    }
    return out;
}

def:pub cache_set(key: str, value: any) -> None {
    try {
        localStorage.setItem(CACHE_PREFIX + key, JSON.stringify(value));  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}

"""Wipe every `cirql.cache.*` key — logout, and switching to a different
account on the same browser."""
def:pub clear_cache() -> None {
    try {
        n: int = localStorage.length;  # jac:ignore[W2001]
        stale: list[str] = [];
        i: int = 0;
        while i < n {
            k: any = localStorage.key(i);  # jac:ignore[W2001]
            if k and (k as str).startswith(CACHE_PREFIX) {
                stale = stale + [k as str];
            }
            i = i + 1;
        }
        for k in stale {
            localStorage.removeItem(k);  # jac:ignore[W2001]
        }
    } except Exception as e {
        return;
    }
}
