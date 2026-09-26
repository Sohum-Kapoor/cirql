"""SOH-204 — the 9 PM gate: prove or refute the cross-user primitives from
`jac guide jac-sv-multi-user` with real registered accounts.

OWNER: Person A. Throwaway-grade endpoints; the Exchange protocol (SOH-205)
reuses the exact calls proven here:

  - own root id:        jid(root)
  - creator of a node:  str(n.__jac__.root).replace("-", "")
                        (a UUID; jid() form is the dash-less hex)
  - per-user grant:     Jac.allow_root(n, UUID(root_id), ReadPerm)
  - public grant:       grant(n, level=ReadPerm)
  - read by id:         n = jobj(id); then Jac.check_read_access(getattr(n, "__jac__"))
                        (jobj itself NEVER authorizes; the check is ours)
"""

import from jaclang { JacRuntime as Jac }
import from uuid { UUID }
import from schema { Me, Card, Owns, Exchange, IntroRequest, Posted }

"""Get-or-create the one Exchange under root.shared. The Exchange is owned by
whoever created it first, so it is granted ConnectPerm (container) to let
every other user attach IntroRequests under it (guide: container/leaf)."""
def _exchange() -> Exchange {
    found = [root.shared --> [?:Exchange]];
    if found {
        return found[0];
    }
    ex = (root.shared ++> Exchange(name="main"))[0];
    grant(ex, level=ConnectPerm);
    return ex;
}

"""Report the caller's own root id — what another user must be told in order
to allow_root a node to this caller."""
walker:priv GateMyRoot {
    has reports: list[str] = [];

    can go with Root entry {
        report jid(root);
    }
}

"""Post an IntroRequest to the shared Exchange (root.shared -> Exchange
-Posted-> IntroRequest). The leaf is granted ReadPerm so every user reads it
but only the author's walkers mutate it. Reports the request's jid."""
walker:priv GatePostShared {
    has text: str;
    has from_handle: str = "a";
    has reports: list[str] = [];

    can go with Root entry {
        ex = _exchange();
        req = (ex +>:Posted:+> IntroRequest(need=self.text, from_handle=self.from_handle))[0];
        grant(req, level=ReadPerm);
        report jid(req);
    }
}

"""List every IntroRequest reachable from root.shared, with the root id of
the user who posted it (owner_root) — the value an answering user passes to
allow_root to grant a Card back to the requester."""
walker:priv GateListShared {
    has reports: list[dict] = [];

    can go with Root entry {
        for ex in [root.shared --> [?:Exchange]] {
            for r in [ex ->:Posted:-> [?:IntroRequest]] {
                report {
                    "id": jid(r),
                    "need": r.need,
                    "from_handle": r.from_handle,
                    "owner_root": str(getattr(r, "__jac__").root).replace("-", "")
                };
            }
        }
    }
}

"""Create a Card under the caller's Me (get-or-create). to_root -> grant it
read-only to that one user; public -> grant it read-only to every user.
Reports the Card's jid."""
walker:priv GateMakeCard {
    has handle: str;
    has to_root: str = "";
    has public: bool = False;
    has reports: list[str] = [];

    can go with Root entry {
        mes = [root --> [?:Me]];
        if mes {
            me = mes[0];
        } else {
            me = (root ++> Me(name=self.handle))[0];
        }
        card = (me +>:Owns:+> Card(handle=self.handle))[0];
        if self.to_root {
            Jac.allow_root(card, UUID(self.to_root), ReadPerm);  # jac:ignore[E1053]
        }
        if self.public {
            grant(card, level=ReadPerm);
        }
        report jid(card);
    }
}

"""Read a Card by id from the caller's context. Reports its handle, "denied"
if the caller lacks read access, or "not found". enforce=False skips the
access check and reads the field raw — present only so the gate test can
prove that jobj alone does not authorize."""
walker:priv GateReadCard {
    has card_id: str;
    has enforce: bool = True;
    has reports: list[str] = [];

    can go with Root entry {
        try {
            n = jobj(self.card_id);
        } except Exception as e {
            report f"error: {e}";
            return;
        }
        if not isinstance(n, Card) {
            report "not found";
            return;
        }
        can_read = Jac.check_read_access(getattr(n, "__jac__"));  # jac:ignore[E1053]
        if self.enforce and not can_read {
            report "denied";
            return;
        }
        report n.handle;
    }
}
