"""Device-only edits for fields no walker can write yet. OWNER: Person B (SOH-209).

`UpdatePerson` (name/org/title/how_met) and `UpdatePromise` (text/due) are
"Needs A" on SOH-166 — not on main. Until they land, an edit is kept here, in
localStorage under `cirql-local-edits`, keyed by the node's jid (globally unique,
so two accounts on one device never collide), and overlaid on whatever the
server reports at render time. The UI says "Saved on this device until the
server update lands" wherever such an edit shows; nothing pretends it reached
the server. When the walkers land, components/api.cl.jac flips
UPDATE_PERSON_LIVE / UPDATE_PROMISE_LIVE and this overlay becomes a no-op.

Every localStorage access is guarded (Safari private mode / some WKWebViews throw).
"""

glob _KEY: str = "cirql-local-edits",
     _CACHE: dict = {"loaded": False, "data": {}};

def _load() -> dict {
    if _CACHE["loaded"] {
        return _CACHE["data"] as dict;
    }
    data: dict = {};
    try {
        raw: any = localStorage.getItem(_KEY);  # jac:ignore[W2001]
        if raw {
            data = JSON.parse(raw as str) as dict;  # jac:ignore[W2001]
        }
    } except Exception as e {
        data = {};
    }
    _CACHE["data"] = data or {};
    _CACHE["loaded"] = True;
    return _CACHE["data"] as dict;
}

def _save(data: dict) -> None {
    _CACHE["data"] = data;
    _CACHE["loaded"] = True;
    try {
        localStorage.setItem(_KEY, JSON.stringify(data));  # jac:ignore[W2001]
    } except Exception as e {
        return;
    }
}

"""The stored overlay for (kind, id), or {} — kind is "person" | "promise"."""
def:pub local_get(kind: str, node_id: str) -> dict {
    bucket: dict = (_load()[kind] or {}) as dict;
    return (bucket[node_id] or {}) as dict;
}

"""Merge `fields` into the overlay for (kind, id)."""
def:pub local_put(kind: str, node_id: str, fields: dict) {
    data: dict = {**_load()};
    bucket: dict = {**((data[kind] or {}) as dict)};
    cur: dict = {**((bucket[node_id] or {}) as dict)};
    for k in list(fields.keys()) {
        cur[k] = fields[k];
    }
    bucket[node_id] = cur;
    data[kind] = bucket;
    _save(data);
}

"""Drop the overlay for (kind, id) — e.g. after the node is forgotten."""
def:pub local_drop(kind: str, node_id: str) {
    data: dict = {**_load()};
    bucket: dict = {**((data[kind] or {}) as dict)};
    bucket[node_id] = None;
    data[kind] = bucket;
    _save(data);
}

"""Copy of `item` (a reported Person / Promise dict) with its overlay applied.
Returns the input unchanged when there is no overlay (no copy, cheap)."""
def:pub local_view(kind: str, item: any) -> any {
    if not item {
        return item;
    }
    over: dict = local_get(kind, (item["_jac_id"] or "") as str);
    keys: list = list(over.keys());
    if len(keys) == 0 {
        return item;
    }
    out: dict = {**(item as dict)};
    for k in keys {
        if k != "how_met" {
            out[k] = over[k];
        }
    }
    out["local_edit"] = True;
    return out;
}

"""The how-met overlay for a person, or `fallback`."""
def:pub local_how_met(person_id: str, fallback: str) -> str {
    over: dict = local_get("person", person_id);
    return (over["how_met"] or fallback) as str;
}

"""True when (kind, id) has an overlay (the UI shows the on-device note)."""
def:pub has_local(kind: str, node_id: str) -> bool {
    return len(list(local_get(kind, node_id).keys())) > 0;
}

"""GoalRank rows with each row's person overlaid (display only)."""
def:pub local_rows(rows: list[dict]) -> list[dict] {
    out: list[dict] = [];
    for row in rows {
        p: any = row["person"];
        if p and has_local("person", (p["_jac_id"] or "") as str) {
            r2: dict = {**row};
            r2["person"] = local_view("person", p);
            out = out + [r2];
        } else {
            out = out + [row];
        }
    }
    return out;
}
