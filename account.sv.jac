"""Account (SOH-226) — in-app account deletion, App Store guideline 5.1.1(v).

OWNER: Person A. Report shape: contracts/walkers.md (SOH-226 block).
`DeleteAccount` is `:priv` (own root only, JWT required). No `by llm`.

## Investigation: what the installed runtime actually offers

This venv has NO `jac-scale` / `jaseci` package installed at all (pinned in
AGENTS.md, but `pip list` shows only `jaclang 0.16.7`, `jac-client 0.3.25`,
`byllm 0.6.19` — `[plugins.scale.microservices] enabled = false` in
`jac.toml` means we never needed jac-scale's user store). So the runtime
serving `/user/register`, `/user/login`, `/user/info`, `PUT /user/username`,
`PUT /user/password` is plain jaclang's own
`jaclang.runtimelib.server.UserManager` — one SQLite file at
`<base_path>/.jac/data/main.db`, table
`users(username PRIMARY KEY, password_hash, token UNIQUE, root_id)`.

Its PUBLIC surface (`create_user`, `authenticate`, `validate_token`,
`get_root_id`, `get_user`, `user_exists`, `update_username`,
`update_password`, `close`) has:
- no `delete_user` / `remove_user` — a row can never be erased from a
  walker, only mutated;
- no lookup from `root_id` back to `username` — a walker only ever has its
  own `root`, never the caller's username or plaintext password;
- `update_password`/`update_username` both re-verify the CURRENT
  username/password before writing, which a walker never has (only a valid
  JWT, already consumed by the HTTP layer before the walker runs).

So none of the four PUT/POST auth endpoints can be driven from inside a
walker as-is. What a walker CAN reach: `Jac.get_user_manager(base_path)` —
the exact factory `JacAPIServer.postinit` itself calls to build the live
server's `user_manager` — and `Jac.get_base_path_dir()`, which
`JacTestClient`/`jac start` both set to the SAME `base_path` the running
server was constructed with. That gets a `UserManager` wired to the real,
live SQLite file, but its public methods still can't do an unverified
write. Below we open our OWN `sqlite3` connection to that same file (same
path-resolution rule `UserManager.postinit` uses, same
`hashlib.sha256(...).hexdigest()` password-hash scheme `update_password`
uses) and run one UPDATE — this is the safest equivalent the runtime
allows: rotate the password to a random 32-byte secret (so login as this
account fails forever), rename the username to `deleted-<8 hex>` (so the
old username/email is free to re-register), and — one step further than
`PUT /user/password` bothers with — rotate the `token` column too, so the
bearer token the caller is already holding stops validating on the very
next call instead of only decaying by JWT expiry.

`identity_removed` is therefore always `false` (no API removes the row);
`identity_disabled` is `true` only when a users-table row for this root was
actually found and rewritten.
"""

import os;
import hashlib;
import secrets;
import sqlite3;
import from uuid { uuid4 }
import from jaclang { JacRuntime as Jac }
import from lifecycle { delete_my_data, empty_deleted }

# ---------------------------------------------------------------- helpers

"""Same path rule as `UserManager.postinit` (jaclang.runtimelib.server):
`JAC_DATA_PATH` env override, else the runtime's own base_path, then
`.jac/data/main.db` under it. `Jac.get_context().base_path_dir` (the live
request context's OWN base_path, set verbatim from whatever `base_path`
the server/`JacTestClient` was constructed with) is tried first — the same
idiom `server.impl.jac` itself uses to resolve a project root from inside
request handling. `Jac.get_base_path_dir()` is only the process-wide seed
value used to BOOTSTRAP a context, and can differ from it (e.g. it passes
through an `isdir(...) else dirname(...)` fallback at `set_base_path`
time, before a not-yet-created data directory exists — a `JacTestClient`
harness hits exactly that case)."""
def _account_db_path() -> str {
    ctx = Jac.get_context();
    ctx_base = ctx.base_path_dir if ctx is not None else None;
    base = os.environ.get("JAC_DATA_PATH") or ctx_base or Jac.get_base_path_dir() or os.getcwd();
    return os.path.join(base, ".jac", "data", "main.db");
}

"""Rotate the users-table row for `root_id` to a random password, a random
token, and a `deleted-<hex>` username, in one UPDATE. True only when a row
for this root was found and rewritten (false: no db file yet, no matching
row, or a write error — the caller's graph is still wiped either way)."""
def _disable_identity(root_id: str) -> bool {
    db_path = _account_db_path();
    if not os.path.isfile(db_path) {
        return False;
    }
    try {
        conn = sqlite3.connect(db_path);
    } except Exception {
        return False;
    }
    try {
        new_username = f"deleted-{uuid4().hex[:8]}";
        tries = 0;
        while tries < 5 {
            cur = conn.execute(
                "SELECT 1 FROM users WHERE username = ?", (new_username,)
            );
            if cur.fetchone() is None {
                break;
            }
            new_username = f"deleted-{uuid4().hex[:8]}";
            tries += 1;
        }
        new_password = secrets.token_urlsafe(32);
        new_hash = hashlib.sha256(new_password.encode()).hexdigest();
        new_token = secrets.token_urlsafe(32);
        cur = conn.execute(
            "UPDATE users SET username = ?, password_hash = ?, token = ? WHERE root_id = ?",
            (new_username, new_hash, new_token, root_id)
        );
        conn.commit();
        return cur.rowcount > 0;
    } except Exception {
        return False;
    } finally {
        conn.close();
    }
}

# ---------------------------------------------------------------- walker

walker:priv DeleteAccount {
    """App Store 5.1.1(v): in-app account deletion. Only runs when
    `confirm == "DELETE"`; otherwise reports zero counts and `ok: false`,
    touching nothing. On confirm: wipes every node the caller owns (same
    logic as `DeleteMyData`, `lifecycle.delete_my_data()`), then disables
    the auth identity the safest way this runtime allows (see module
    docstring). `identity_removed` is always `false` (no API removes the
    row); `identity_disabled` reflects whether a row was actually found
    and rewritten."""
    has confirm: str = "";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        if self.confirm != "DELETE" {
            report {
                "ok": False,
                "deleted": empty_deleted(),
                "identity_removed": False,
                "identity_disabled": False
            };
            disengage;
        }
        root_id = jid(root);
        result = delete_my_data();
        disabled = _disable_identity(root_id);
        # ok only when BOTH halves happened: a wiped graph with a still-working
        # login is a partial deletion the caller must be told about (Codex review).
        report {
            "ok": bool(result["ok"]) and disabled,
            "deleted": result["deleted"],
            "identity_removed": False,
            "identity_disabled": disabled
        };
    }
}
