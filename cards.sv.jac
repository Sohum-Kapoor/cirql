"""PublishCard + get_card (SOH-178) — the Card is the only object that leaves
an account. PublishCard drafts/updates the caller's own Card in place;
get_card is the ONE public, unauthenticated read, and it emits Card fields
only — never `visibility`, ids, or anything else off the Card node, and never
a `handshake_only` card.

OWNER: Person A. Report shapes: contracts/walkers.md (Tier 1, SOH-178).
Idioms reused verbatim from gate.sv.jac / exchange.sv.jac: root.shared
get-or-create for a container node, `grant`/container-`ConnectPerm`+
leaf-`ReadPerm`, and onboard.sv.jac's `handle_from_name` + `jid_suffix` for a
stable, unique handle (imported, not copied).
"""

import from datetime { datetime }
import from schema { Me, Card, Owns, CardDirectory, Lists, CardListing }
import from onboard { handle_from_name, jid_suffix }
import from reads { owner_root }

def now_iso() -> str {
    return datetime.now().isoformat();
}

"""Get-or-create the one CardDirectory under root.shared. Granted ConnectPerm
(container) so every user's PublishCard can attach a Lists edge to it —
same idiom as exchange.sv.jac's get_exchange()."""
def get_card_directory() -> CardDirectory {
    found = [x for x in [root.shared -->] if isinstance(x, CardDirectory)];
    if found {
        return found[0];
    }
    dir = (root.shared ++> CardDirectory(name="main"))[0];
    grant(dir, level=ConnectPerm);
    return dir;
}

"""Every Card listed under every CardDirectory in root.shared. UNTYPED
traversal then a type filter, on purpose (SOH-205): a typed traversal
(`[dir ->:Lists:->]`, `[root.shared --> [?:T]]`) is answered from the
topology index stored on the root that OWNS the origin node, and a user who
only has CONNECT on that node cannot persist that index -- after a restart
or on another worker the typed walk silently misses every edge a non-owner
added. `[n -->]` walks the persisted edge list itself; the type filter is
a plain isinstance comprehension because `[n -->][?:T]` is compiled into
the SAME indexed path query and misses them too."""
def listed_cards() -> list[Card] {
    out: list[Card] = [];
    seen: list[str] = [];
    for dir in [x for x in [root.shared -->] if isinstance(x, CardDirectory)] {
        for x in [dir -->] {
            if isinstance(x, Card) {
                k = jid(x);
                if k not in seen {
                    seen.append(k);
                    out.append(x);
                }
            } elif isinstance(x, CardListing) {
                # SOH-211: `[dir -->]` skips every Card the caller cannot read
                # (a handshake_only card is revoked), so resolve the owner's
                # public CardListing by id. The listing must be owned by the
                # same root as the Card, or anyone could list anyone's card.
                c = listing_card(x);
                if c is not None {
                    k = jid(c);
                    if k not in seen {
                        seen.append(k);
                        out.append(c as Card);
                    }
                }
            }
        }
    }
    return out;
}

"""The Card a CardListing points at, only when both have the same owner root."""
def listing_card(l: CardListing) -> Card | None {
    try {
        n = jobj(l.card_id);
    } except Exception {
        return None;
    }
    if isinstance(n, Card) and owner_root(n) == owner_root(l) {
        return n as Card;
    }
    return None;
}

"""SOH-211: True when a Card with this `handle`, owned by a root OTHER than
`me_root` (dash-less hex, i.e. `jid(root)`), is already listed in the
CardDirectory. Handles are self-chosen; the first root to list one keeps it."""
def handle_taken(handle: str, me_root: str) -> bool {
    want = handle.strip().lower();
    for c in listed_cards() {
        if c.handle.strip().lower() == want and owner_root(c) != me_root {
            return True;
        }
    }
    return False;
}

"""Attach `card` to the shared CardDirectory (idempotent). Listing is not
granting: get_card still refuses anything but visibility == "link", and the
fields stay closed unless the owner granted them."""
def list_card(card: Card) {
    dir = get_card_directory();
    # Untyped: a typed traversal on the shared directory drops edges other
    # roots attached after a restart (AGENTS.md gotcha) and would re-list.
    if card not in [x for x in [dir -->] if isinstance(x, Card)] {
        dir +>:Lists:+> card;
    }
    cid = jid(card);
    me_root = jid(root);
    for x in [dir -->] {
        if isinstance(x, CardListing) and x.card_id == cid and owner_root(x) == me_root {
            return;
        }
    }
    listing = (dir ++> CardListing(handle=card.handle, card_id=cid))[0];
    grant(listing, level=ReadPerm);
}

walker:priv PublishCard {
    """Get-or-create the caller's Card (via their Me) and publish it. Only
    non-empty arguments overwrite fields; `visibility` is always applied and
    must be "link" or "handshake_only". `link` grants the Card read-only to
    every user and lists it in the shared CardDirectory so get_card can find
    it by handle; `handshake_only` revokes the public grant only — it stays
    LISTED in the directory either way (SOH-183: the missing grant is what
    protects a handshake_only card, not unlisting; a handshake handle needs
    to be found in the directory by the other side of a scan before either
    of them has granted anything). get_card also refuses anything but
    visibility=="link" on its own, so a stale grant can never leak a
    handshake_only card through that path)."""
    has headline: str = "";
    has about: str = "";
    has looking_for: list[str] = [];
    has can_offer: list[str] = [];
    has links: list[str] = [];
    has contact_pref: str = "";
    has visibility: str = "link";
    has name: str = "";
    has reports: list[object] = [];

    can go with Root entry {
        if self.visibility != "link" and self.visibility != "handshake_only" {
            report {"error": "bad_visibility"};
            return;
        }

        existing_me = [root --> [?:Me]];
        if existing_me {
            me = existing_me[0];
        } else {
            me = (root ++> Me(name="me"))[0];
        }

        existing_card = [me ->:Owns:-> [?:Card]];
        if existing_card {
            card = existing_card[0];
        } else {
            handle = handle_from_name(self.name or "me") + "-" + jid_suffix(jid(me));
            card = (me +>:Owns:+> Card(handle=handle))[0];
        }
        if handle_taken(card.handle, jid(root)) {
            report {"error": "handle_taken"};
            return;
        }

        if self.headline {
            card.headline = self.headline;
        }
        if self.about {
            card.about = self.about;
        }
        if self.looking_for {
            card.looking_for = self.looking_for;
        }
        if self.can_offer {
            card.can_offer = self.can_offer;
        }
        if self.links {
            card.links = self.links;
        }
        if self.contact_pref {
            card.contact_pref = self.contact_pref;
        }
        if self.name {
            card.name = self.name;
        }
        card.visibility = self.visibility;
        card.updated_at = now_iso();

        list_card(card);
        if self.visibility == "link" {
            grant(card, level=ReadPerm);
        } else {
            revoke(card);
        }

        report card;
    }
}

def empty_my_card() -> dict[str, object] {
    return {
        "found": False,
        "card": {
            "name": "", "handle": "", "headline": "", "about": "",
            "looking_for": [], "can_offer": [], "links": [], "contact_pref": "",
            "updated_at": "", "visibility": ""
        },
        "handle": ""
    };
}

walker:priv MyCard {
    """SOH-179: the card editor's own-root read. Unlike `get_card`, this
    returns the caller's Card regardless of `visibility` (a `handshake_only`
    card must still be editable by its owner) — and unlike `PublishCard`, it
    never writes anything. Resolution idiom is `PublishCard`'s own:
    `[root --> [?:Me]]` then the Me->Card `Owns` edge, both own-root so the
    typed traversal is safe (AGENTS.md's "typed traversal after a restart"
    gotcha only applies to containers OTHER users attach to, e.g.
    root.shared/CardDirectory — not a caller's own Me/Card). `found: false`
    with empty fields when there is no Me yet or no Card yet."""
    has reports: list[dict[str, object]] = [];

    can go with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report empty_my_card();
            return;
        }
        me = existing_me[0];
        existing_card = [me ->:Owns:-> [?:Card]];
        if not existing_card {
            report empty_my_card();
            return;
        }
        card = existing_card[0];
        report {
            "found": True,
            "card": {
                "name": card.name,
                "handle": card.handle,
                "headline": card.headline,
                "about": card.about,
                "looking_for": card.looking_for,
                "can_offer": card.can_offer,
                "links": card.links,
                "contact_pref": card.contact_pref,
                "updated_at": card.updated_at,
                "visibility": card.visibility
            },
            "handle": card.handle
        };
    }
}

"""The ONE public read. `def:pub` — no JWT required; per `jac guide
jac-sv-auth`, an anonymous caller's `root` IS `root.shared`, but a caller who
DOES send a valid token runs on their own root instead — so this reaches the
CardDirectory through `root.shared` explicitly, never bare `root`, or a
token-holder's own graph would silently shadow the public directory. Returns
a dict of Card fields only — never `visibility`, `_jac_id`, or anything else —
and `found: false` with empty fields when no link-visible card matches."""
def:pub get_card(handle: str) -> dict[str, object] {
    empty: dict[str, object] = {
        "found": False,
        "name": "",
        "handle": "",
        "headline": "",
        "about": "",
        "looking_for": [],
        "can_offer": [],
        "links": [],
        "contact_pref": "",
        "updated_at": ""
    };
    for card in listed_cards() {
        if card.handle == handle and card.visibility == "link" {
            return {
                "found": True,
                "name": card.name,
                "handle": card.handle,
                "headline": card.headline,
                "about": card.about,
                "looking_for": card.looking_for,
                "can_offer": card.can_offer,
                "links": card.links,
                "contact_pref": card.contact_pref,
                "updated_at": card.updated_at
            };
        }
    }
    return empty;
}
