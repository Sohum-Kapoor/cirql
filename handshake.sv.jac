"""The QR handshake (SOH-183) — consented two-sided Card exchange across
accounts. Two people scan each other's QR (the QR encodes a Card handle);
each receives the OTHER's self-authored Card as a Person + FromCard edge in
their OWN graph, facts sourced `card:<handle>`. Nobody's graph is read by the
other; only the two Cards cross, each granted read-only to exactly one root,
and only after both sides have acted (or the offer just sits there until one
side accepts/declines/expires).

OWNER: Person A. Report shapes: contracts/walkers.md (SOH-183). Idioms reused
verbatim from gate.sv.jac / exchange.sv.jac: `owner_root`, `readable`, `load`,
`Jac.allow_root`, the shared-node get-or-create pattern.

Design (no container node — one HandshakeOffer per scan, hung directly off
`root.shared`, ambient `grant(..., ReadPerm)` so both parties can read it,
same as gate.sv.jac's GatePostShared/IntroRequest):

  - `OfferHandshake` creates ONE HandshakeOffer(status="offered") and grants
    the caller's own Card read-only to the target's root so the target can
    later read it in `AcceptHandshake`.
  - `AcceptHandshake` materializes the Person/Knows/FromCard/Fact directly in
    the ACCEPTER's own graph (synchronous, immediate) AND posts a reciprocal
    HandshakeOffer(status="accepted") as a signal for the ORIGINAL SENDER,
    since the accepter cannot write the original offer's `status` field (only
    the owner can write their own node). `DeclineHandshake` does the same
    with a "declined" signal for an incoming offer, or flips its own
    outgoing offer's status directly when it owns it.
  - `ListHandshakes` walks every HandshakeOffer touching my handle. A
    "signal" node (status accepted/declined that has a reversed "offered"
    counterpart) is never listed on its own; it only overrides the status of
    the primary offer it answers — this is the "requester derives status
    lazily" idiom from exchange.sv.jac's `derive_status`. A signal I posted
    to DECLINE an incoming offer hides that whole pair from MY OWN list (no
    reason crosses back to me either); the ORIGINAL SENDER's side keeps
    seeing "offered" until it expires — a decline never reaches them at all.
    An "accepted" signal instead surfaces on the ORIGINAL SENDER's outgoing
    entry as status="accepted" and lazily materializes the Person there too
    (first ListHandshakes call after acceptance creates it; later calls
    reuse it — get_or_create, idempotent).

Nothing sends. Nothing reads `Knows.last_contact` to lower anything.
"""

import from jaclang { JacRuntime as Jac }
import from uuid { UUID }
import from datetime { datetime, timedelta }
import from schema {
    Me, Person, Knows, Card, FromCard, Fact, FactAbout, HandshakeOffer
}
import from exchange { owner_root, my_me, card_of, my_card, load, readable, now_iso }
import from cards { listed_cards }
import from identity { fill_contact }

# ---------------------------------------------------------------- helpers

"""Find a Card by handle in the shared CardDirectory, ANY visibility — the
handshake path deliberately does not gate on visibility=="link" the way
get_card does; a handshake_only card is exactly the case this feature exists
for. Reuses `cards.listed_cards()` (SOH-205): an untyped `[root.shared -->]`
traversal filtered by `isinstance`, on purpose — a typed traversal
(`[root.shared --> [?:T]]`, `[dir ->:Lists:->]`) is answered from the
topology index stored on the root that OWNS the origin node, and a user who
only has CONNECT on root.shared/the CardDirectory cannot persist that index,
so after a restart (or on another worker) the typed form silently misses
every edge a non-owner attached. No check_read_access here (that gate is
applied at the specific points the contract calls for — see
AcceptHandshake / ListHandshakes), mirroring get_card's own style of
scanning listed cards' fields directly."""
def find_card_in_directory(handle: str) -> Card | None {
    for c in listed_cards() {
        if c.handle == handle {
            return c;
        }
    }
    return None;
}

"""A Person under `me` already linked to a Card with this handle — checked
two ways: the normal FromCard edge, or (fallback, when the cross-root edge
attach failed at runtime because only ReadPerm was granted, never
ConnectPerm) the marker `card:<handle>` stashed on the Knows edge's
source_note. Keeps get_or_create_person_from_card idempotent either way."""
def find_person_by_card_handle(me: Me, handle: str) -> Person | None {
    marker = f"card:{handle}";
    for p in [me ->:Knows:->] {
        for e in [edge p ->:FromCard:->] {
            if e.handle == handle {
                return p;
            }
        }
        for e in [edge me ->:Knows:-> p] {
            if e.source_note == marker {
                return p;
            }
        }
    }
    return None;
}

"""Get-or-create the Person in `me`'s own graph for a handshake counterpart's
Card: Knows(how_met="handshake", status="confirmed") + best-effort FromCard
edge (may fail cross-root — only ReadPerm was granted, not ConnectPerm; the
handle is then stashed on the Knows edge's source_note instead) + one Fact
sourced `card:<handle>` when `card.about` is non-empty. Idempotent: a second
call for the same card returns the existing Person, never a duplicate."""
def get_or_create_person_from_card(me: Me, card: Card, now: str) -> Person {
    existing = find_person_by_card_handle(me, card.handle);
    if existing is not None {
        return existing;
    }

    headline = card.headline or "";
    title = headline;
    org = "";
    if " at " in headline {
        idx = headline.index(" at ");
        title = headline[:idx].strip();
        org = headline[idx + 4:].strip();
    }

    person = (me +>:Knows(how_met="handshake", last_contact=now, status="confirmed", source_note=""):+> Person(
        name=card.name, org=org, title=title, status="confirmed"
    ))[0];
    fill_contact(person, "", "", list(card.links));  # SOH-215

    try {
        person +>:FromCard(handle=card.handle, received_at=now):+> card;
    } except Exception { }
    # A denied edge_write (ReadPerm on the target, not ConnectPerm) is a
    # SILENT no-op here — the runtime logs a warning but raises nothing, so
    # try/except alone can't tell success from failure. Verify directly
    # (untyped traversal from `person`, which I own, so this is reliable)
    # before deciding whether the fallback marker is needed.
    attached = False;
    for x in [person -->] {
        if isinstance(x, Card) and jid(x) == jid(card) {
            attached = True;
        }
    }
    if not attached {
        for e in [edge me ->:Knows:-> person] {
            e.source_note = f"card:{card.handle}";
        }
    }

    if card.about {
        fact = (root ++> Fact(
            text=card.about, observed_at=now, source_kind="self", source_url=f"card:{card.handle}"
        ))[0];
        fact +>:FactAbout:+> person;
    }
    return person;
}

"""A `HandshakeOffer` whose status is accepted/declined and which answers a
still-"offered" reversed counterpart is a pure signal — it is never listed as
its own entry, only used to derive the primary offer's status."""
def is_signal(o: HandshakeOffer, all_offers: list[HandshakeOffer]) -> bool {
    if o.status != "accepted" and o.status != "declined" {
        return False;
    }
    for r in all_offers {
        if jid(r) == jid(o) {
            continue;
        }
        if r.from_handle == o.to_handle and r.to_handle == o.from_handle and r.status == "offered" {
            return True;
        }
    }
    return False;
}

"""The reciprocal accepted/declined signal answering primary offer `o`, if
any (posted by whoever is `o.to_handle`, addressed back to `o.from_handle`)."""
def find_signal_for(o: HandshakeOffer, all_offers: list[HandshakeOffer]) -> HandshakeOffer | None {
    for r in all_offers {
        if r.from_handle == o.to_handle and r.to_handle == o.from_handle and (r.status == "accepted" or r.status == "declined") {
            return r;
        }
    }
    return None;
}

"""Have I (my_handle) already posted a response (accepted or declined) to an
offer from `their_handle`? Used so AcceptHandshake/DeclineHandshake refuse a
second response to the same incoming offer — the ORIGINAL offer's own
status field never changes when the RECIPIENT responds (only the owner can
write it), so that check alone isn't enough to catch a repeat."""
def find_my_signal(my_handle: str, their_handle: str) -> HandshakeOffer | None {
    for o in [x for x in [root.shared -->] if isinstance(x, HandshakeOffer)] {
        if o.from_handle == my_handle and o.to_handle == their_handle and (o.status == "accepted" or o.status == "declined") {
            return o;
        }
    }
    return None;
}

# ---------------------------------------------------------------- walkers

walker:priv OfferHandshake {
    """Offer a handshake to a Card handle found in the shared CardDirectory
    (any visibility). Grants my own Card read-only to the target's root so
    they can read it once they act. Idempotent per (me, to_handle, "offered")."""
    has to_handle: str;
    has reports: list[object] = [];

    can go with Root entry {
        m = my_me();
        if m is None {
            report {"error": "no_card"};
            return;
        }
        me = m as Me;
        c = card_of(me);
        if c is None {
            report {"error": "no_card"};
            return;
        }
        my_card_node = c as Card;
        target = find_card_in_directory(self.to_handle);
        if target is None {
            report {"error": "not_found"};
            return;
        }
        if self.to_handle == my_card_node.handle {
            report {"error": "self"};
            return;
        }

        me_root = jid(root);
        for o in [x for x in [root.shared -->] if isinstance(x, HandshakeOffer)] {
            if owner_root(o) == me_root and o.from_handle == my_card_node.handle and o.to_handle == self.to_handle and o.status == "offered" {
                report {"offer_id": jid(o), "to_handle": o.to_handle, "status": o.status};
                return;
            }
        }

        Jac.allow_root(my_card_node, UUID(owner_root(target)), ReadPerm);  # jac:ignore[E1053]

        now_dt = datetime.now();
        offer = (root.shared ++> HandshakeOffer(
            from_handle=my_card_node.handle,
            to_handle=self.to_handle,
            status="offered",
            created_at=now_dt.isoformat(),
            expires_at=(now_dt + timedelta(days=7)).isoformat()
        ))[0];
        grant(offer, level=ReadPerm);
        report {"offer_id": jid(offer), "to_handle": self.to_handle, "status": offer.status};
    }
}

walker:priv ListHandshakes {
    """Every HandshakeOffer touching my handle, signals folded into their
    primary offer's status (see module docstring)."""
    has reports: list[object] = [];

    can go with Root entry {
        m = my_me();
        if m is None {
            return;
        }
        me = m as Me;
        c = card_of(me);
        if c is None {
            return;
        }
        my_handle = (c as Card).handle;
        if not my_handle {
            return;
        }
        now = now_iso();

        all_offers = [o for o in [x for x in [root.shared -->] if isinstance(x, HandshakeOffer)] if readable(o)];
        for o in all_offers {
            if o.from_handle != my_handle and o.to_handle != my_handle {
                continue;
            }
            if is_signal(o, all_offers) {
                continue;
            }
            if o.expires_at and o.expires_at < now {
                continue;
            }

            direction = "outgoing" if o.from_handle == my_handle else "incoming";
            counterpart = o.to_handle if direction == "outgoing" else o.from_handle;
            status = o.status;
            person_id = "";

            signal = find_signal_for(o, all_offers);
            if signal is not None {
                if signal.status == "accepted" {
                    status = "accepted";
                    counterpart_card = find_card_in_directory(counterpart);
                    if counterpart_card is not None and readable(counterpart_card) {
                        person = get_or_create_person_from_card(me, counterpart_card as Card, now);
                        person_id = jid(person);
                    }
                } elif signal.status == "declined" {
                    if direction == "incoming" {
                        # I declined this one myself — hide the whole pair.
                        continue;
                    }
                    # direction == "outgoing": the offerer keeps seeing
                    # "offered" until it expires; no reason ever crosses.
                }
            }

            report {
                "offer_id": jid(o),
                "from_handle": o.from_handle,
                "to_handle": o.to_handle,
                "status": status,
                "direction": direction,
                "person_id": person_id
            };
        }
    }
}

walker:priv AcceptHandshake {
    """Accept an offer addressed to me: materialize the Person/Knows/
    FromCard/Fact in MY graph immediately, grant my Card back to the
    offerer's root, and post a reciprocal "accepted" signal (I cannot write
    their offer's own status field)."""
    has offer_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        m = my_me();
        if m is None {
            report {"error": "no_card"};
            return;
        }
        me = m as Me;
        c = card_of(me);
        if c is None {
            report {"error": "no_card"};
            return;
        }
        my_handle = (c as Card).handle;

        n = load(self.offer_id);
        if not isinstance(n, HandshakeOffer) {
            report {"error": "not_found"};
            return;
        }
        if not readable(n) {
            report {"error": "not_found"};
            return;
        }
        offer = n as HandshakeOffer;
        if offer.to_handle != my_handle {
            report {"error": "not_found"};
            return;
        }
        if offer.status != "offered" {
            report {"error": "invalid_state"};
            return;
        }
        if find_my_signal(my_handle, offer.from_handle) is not None {
            # I already accepted or declined this pair — the original offer's
            # own status field never changed (I don't own it), so that check
            # alone would let a second AcceptHandshake through.
            report {"error": "invalid_state"};
            return;
        }

        their_handle = offer.from_handle;
        found_card = find_card_in_directory(their_handle);
        if found_card is None {
            report {"error": "not_found"};
            return;
        }
        their_card = found_card as Card;
        if not readable(their_card) {
            report {"error": "forbidden"};
            return;
        }

        now = now_iso();
        person = get_or_create_person_from_card(me, their_card, now);

        Jac.allow_root(c as Card, UUID(owner_root(their_card)), ReadPerm);  # jac:ignore[E1053]

        reciprocal = (root.shared ++> HandshakeOffer(
            from_handle=my_handle,
            to_handle=their_handle,
            status="accepted",
            created_at=now,
            expires_at=offer.expires_at
        ))[0];
        grant(reciprocal, level=ReadPerm);

        report {"person": person, "card": their_card};
    }
}

walker:priv DeclineHandshake {
    """Decline either: an offer addressed to me (posts a reciprocal
    "declined" signal — no reason crosses; my own ListHandshakes then hides
    the pair, the offerer keeps seeing "offered" until it expires), or my own
    outgoing offer (I own it, so I flip its status directly)."""
    has offer_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        m = my_me();
        if m is None {
            report {"error": "no_card"};
            return;
        }
        me = m as Me;
        c = card_of(me);
        if c is None {
            report {"error": "no_card"};
            return;
        }
        my_handle = (c as Card).handle;

        n = load(self.offer_id);
        if not isinstance(n, HandshakeOffer) {
            report {"error": "not_found"};
            return;
        }
        if not readable(n) {
            report {"error": "not_found"};
            return;
        }
        offer = n as HandshakeOffer;
        now = now_iso();

        if offer.to_handle == my_handle and offer.status == "offered" and find_my_signal(my_handle, offer.from_handle) is None {
            reciprocal = (root.shared ++> HandshakeOffer(
                from_handle=my_handle,
                to_handle=offer.from_handle,
                status="declined",
                created_at=now,
                expires_at=offer.expires_at
            ))[0];
            grant(reciprocal, level=ReadPerm);
            report "declined";
            return;
        }

        if owner_root(offer) == jid(root) {
            offer.status = "declined";
            report "declined";
            return;
        }

        report {"error": "invalid_state"};
    }
}
