"""The Exchange (SOH-205) — redacted request -> friend's local score -> approve
-> opt-in -> reveal Card -> requester claims + draft.

OWNER: Person A. Report shapes: contracts/walkers.md (Exchange, v1.1). Idioms
reused verbatim from gate.sv.jac (proven with three real accounts).

Ownership (there is no cross-root write):
  - The requester owns each IntroRequest (root.shared -> Exchange -Posted->
    IntroRequest), granted ConnectPerm so friends read it and attach RepliedTo.
  - The friend owns each IntroReply, hung under root.shared (SOH-205: the
    requester must find it by traversal from a root it can traverse; an edge
    a friend adds onto the requester's node is NOT found by a typed traversal
    after a restart or on another worker), allow_root'ed read-only to the
    requester only. The RepliedTo edge is still attached; nothing reads it.
  - The friend's private half (`match_person_id`, `revealed_card_id`) lives on
    a ReplyPrivate under the FRIEND's root: root.shared is enumerable and jobj
    never authorizes, so nothing identity-bearing sits on the shared node.
    Every report builds a ReplyView dict.
  - Traversals of shared containers (root.shared, Exchange, CardDirectory)
    are UNTYPED then type-filtered; see cards.sv.jac listed_cards().
  - Request status is derived by the requester on read; reply status is
    written only by the friend.
  - The only graph object that crosses accounts is the Card granted at Reveal.
Nothing sends. Nothing reads `Knows.last_contact` to lower anything.
"""

import from jaclang { JacRuntime as Jac }
import from uuid { UUID }
import from llm { llm }
import from datetime { datetime, timedelta }
import from schema {
    Me, Person, Knows, Fact, FactAbout, Intent, IntentAbout, Note, Asserts,
    AssertsIntent, Card, Owns, FromCard, Exchange, IntroRequest, IntroReply,
    Posted, RepliedTo, ReplyPrivate, ClaimedIntro
}
import from cards { listed_cards, list_card, handle_taken }
import from scoring { score_against_need }
import from onboard { handle_from_name, jid_suffix }


# ---------------------------------------------------------------- LLM (ClaimReveal only)

def draft_intro(
    requester_about: str,
    need: str,
    friend_handle: str,
    card_name: str,
    card_headline: str,
    card_about: str,
    requester_name: str
) -> str by llm(temperature=0.4);
sem draft_intro = "Write a three-way intro email under 120 words, written by the friend (friend_handle) from the friend to both people, addressing them by name (requester_name and card_name), and why the need fits, plainly. No flattery, no superlatives, no subject line, never a placeholder like [Name].";
sem draft_intro.requester_about = "What the requester says about themselves.";
sem draft_intro.need = "What the requester is looking for.";
sem draft_intro.friend_handle = "Handle of the mutual friend who is making the intro and signs the email.";
sem draft_intro.card_name = "Name of the person being introduced.";
sem draft_intro.card_headline = "Their one-line headline.";
sem draft_intro.card_about = "What their card says about them.";
sem draft_intro.requester_name = "Display name of the requester being introduced to card_name.";

def intro_template(requester_about: str, need: str, friend_handle: str, card_name: str, card_headline: str, requester_name: str) -> str {
    who = card_name;
    if card_headline {
        who = f"{card_name} ({card_headline})";
    }
    me_line = requester_about.strip().rstrip(".") or "a friend of mine";
    return (
        f"Hi {card_name} and {requester_name}, connecting you two. "
        f"{who}, meet {requester_name}: {me_line}. "
        f"{requester_name} is looking for {need}, and I thought of you. "
        f"I'll let you two take it from here. - {friend_handle}"
    );
}

# ---------------------------------------------------------------- helpers

def now_iso() -> str {
    return datetime.now().isoformat();
}

"""Root id (dash-less hex) of whoever created node n."""
def owner_root(n: object) -> str {
    return str(getattr(n, "__jac__").root).replace("-", "");
}

def err(code: str) -> dict[str, str] {
    return {"error": code};
}

def my_me() -> Me | None {
    found = [root --> [?:Me]];
    if found {
        return found[0];
    }
    return None;
}

def card_of(me: Me) -> Card | None {
    found = [me ->:Owns:-> [?:Card]];
    if found {
        return found[0];
    }
    return None;
}

def my_card() -> Card | None {
    me = my_me();
    if me is None {
        return None;
    }
    return card_of(me as Me);
}

"""Get-or-create the one Exchange under root.shared (ConnectPerm container)."""
def get_exchange() -> Exchange {
    found = [x for x in [root.shared -->] if isinstance(x, Exchange)];
    if found {
        return found[0];
    }
    ex = (root.shared ++> Exchange(name="main"))[0];
    grant(ex, level=ConnectPerm);
    return ex;
}

"""Every IntroRequest under EVERY Exchange in root.shared, deduped by jid.
get_exchange() can race and leave two Exchanges; readers must see both."""
def all_requests() -> list[IntroRequest] {
    seen: list[str] = [];
    out: list[IntroRequest] = [];
    for ex in [x for x in [root.shared -->] if isinstance(x, Exchange)] {
        for req in [x for x in [ex -->] if isinstance(x, IntroRequest)] {
            k = jid(req);
            if k not in seen {
                seen.append(k);
                out.append(req);
            }
        }
    }
    return out;
}

"""jobj that never raises; resolves ANY node and NEVER authorizes."""
def load(some_id: str) -> object {
    try {
        return jobj(some_id);
    } except Exception {
        return None;
    }
}

def readable(n: object) -> bool {
    return bool(Jac.check_read_access(getattr(n, "__jac__")));  # jac:ignore[E1053]
}

"""Every IntroReply under root.shared the caller can READ (their own, or
allow_root'ed to them). Readability is checked before any field is touched."""
def shared_replies() -> list[IntroReply] {
    out: list[IntroReply] = [];
    seen: list[str] = [];
    for r in [x for x in [root.shared -->] if isinstance(x, IntroReply)] {
        k = jid(r);
        if k not in seen and readable(r) {
            seen.append(k);
            out.append(r);
        }
    }
    return out;
}

"""The redacted reply shape. Never includes match_person_id, revealed_card_id
or revealed_card_handle."""
def view(r: IntroReply) -> dict[str, object] {
    return {
        "_jac_id": jid(r),
        "request_id": r.request_id,
        "from_handle": r.from_handle,
        "match_count": r.match_count,
        "strength": r.strength,
        "status": r.status
    };
}

"""A shared IntroReply OWNED by the caller, by id; None if unknown or not mine."""
def my_reply(reply_id: str) -> IntroReply | None {
    n = load(reply_id);
    if isinstance(n, IntroReply) and owner_root(n) == jid(root) {
        return n as IntroReply;
    }
    return None;
}

"""The caller's private half of one of their replies (own root only)."""
def my_private(reply_id: str) -> ReplyPrivate | None {
    for p in [root --> [?:ReplyPrivate]] {
        if p.reply_id == reply_id {
            return p;
        }
    }
    return None;
}

def my_person(person_id: str) -> Person | None {
    me = my_me();
    if me is None {
        return None;
    }
    for p in [(me as Me) ->:Knows:->] {
        if jid(p) == person_id {
            return p;
        }
    }
    return None;
}

"""SOH-211: a request is closed once the requester declined it or it is past
`expires_at` (same two rules derive_status applies). Every Exchange
transition after ReplyToRequest refuses a closed request."""
def request_closed(req: IntroRequest) -> bool {
    if req.status == "declined" or req.status == "expired" {
        return True;
    }
    if req.expires_at and req.expires_at < now_iso() {
        return True;
    }
    return False;
}

"""request_closed() for the request a reply answers; False if it can't be read
(the caller's own not_found/forbidden checks handle that)."""
def reply_request_closed(reply: IntroReply) -> bool {
    rq = load(reply.request_id);
    if isinstance(rq, IntroRequest) and readable(rq) {
        return request_closed(rq as IntroRequest);
    }
    return False;
}

"""The requester's stored ClaimReveal for this reply (own root only)."""
def my_claim(reply_id: str) -> ClaimedIntro | None {
    for c in [root --> [?:ClaimedIntro]] {
        if c.reply_id == reply_id {
            return c;
        }
    }
    return None;
}

def derive_status(req: IntroRequest, replies: list[IntroReply], now: str) -> str {
    if req.status == "declined" {
        return "declined";
    }
    statuses = [r.status for r in replies];
    derived = "open";
    if "revealed" in statuses {
        derived = "revealed";
    } elif "opted_in" in statuses {
        derived = "opted_in";
    } elif "approved" in statuses {
        derived = "approved";
    } elif len(statuses) > 0 {
        derived = "replied";
    }
    if derived != "revealed" and req.expires_at and req.expires_at < now {
        return "expired";
    }
    return derived;
}

# ---------------------------------------------------------------- requester side

walker:priv PostRequest {
    """Post a need to the shared Exchange under the caller's Card handle.
    `ttl_days` is a dev/test knob (default 7; 0 posts an already-expiring request)."""
    has need: str;
    has about_line: str = "";
    has ttl_days: int = 7;
    has reports: list[object] = [];

    can go with Root entry {
        card = my_card();
        if card is None {
            report err("no_card");
            return;
        }
        c = card as Card;
        now = datetime.now();
        ex = get_exchange();
        req = (ex +>:Posted:+> IntroRequest(
            need=self.need,
            from_handle=c.handle,
            about_line=self.about_line,
            status="open",
            created_at=now.isoformat(),
            expires_at=(now + timedelta(days=self.ttl_days)).isoformat()
        ))[0];
        grant(req, level=ConnectPerm);
        report req;
    }
}

walker:priv ListMyRequests {
    """The caller's own requests with redacted replies; derives and stores status."""
    has reports: list[object] = [];

    can go with Root entry {
        me_root = jid(root);
        now = now_iso();
        visible = shared_replies();
        for req in all_requests() {
            if owner_root(req) != me_root {
                continue;
            }
            rid = jid(req);
            replies = [r for r in visible if r.request_id == rid];
            req.status = derive_status(req, replies, now);
            report {"request": req, "replies": [view(r) for r in replies]};
        }
    }
}

walker:priv DeclineRequest {
    """Requester withdraws their own request. No reason field anywhere."""
    has request_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        req = load(self.request_id);
        if not isinstance(req, IntroRequest) {
            report err("not_found");
            return;
        }
        if owner_root(req) != jid(root) {
            report err("forbidden");
            return;
        }
        (req as IntroRequest).status = "declined";
        report "declined";
    }
}

walker:priv ClaimReveal {
    """Requester reads the Card granted at Reveal and creates the Person in
    their OWN graph (Knows how_met="intro via <friend>", one Fact sourced to
    the card). No edge to the foreign Card. One `by llm` draft with a
    deterministic fallback. Nothing sends."""
    has reply_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        n = load(self.reply_id);
        if not isinstance(n, IntroReply) {
            report err("not_found");
            return;
        }
        if not readable(n) {
            report err("forbidden");
            return;
        }
        reply = n as IntroReply;
        rq = load(reply.request_id);
        if not isinstance(rq, IntroRequest) {
            report err("not_found");
            return;
        }
        if not readable(rq) {
            report err("forbidden");
            return;
        }
        req = rq as IntroRequest;
        if owner_root(req) != jid(root) {
            report err("forbidden");
            return;
        }
        if reply.status == "declined" {
            report err("reply_declined");
            return;
        }
        if request_closed(req) {
            report err("request_closed");
            return;
        }
        if reply.status != "revealed" or not reply.revealed_card_handle {
            report err("invalid_state");
            return;
        }
        # Handles are self-chosen: only a Card owned by the replying friend,
        # granted to us, and carrying that handle counts.
        friend_root = owner_root(reply);
        found: Card | None = None;
        for cn in listed_cards() {
            if found is None and readable(cn) and owner_root(cn) == friend_root and cn.handle == reply.revealed_card_handle {
                found = cn;
            }
        }
        if found is None {
            report err("not_found");
            return;
        }
        card = found as Card;
        m = my_me();
        if m is None {
            report err("no_card");
            return;
        }
        me = m as Me;
        # SOH-211: a second ClaimReveal on the same reply reports the stored
        # draft; no second model call, no second Person.
        prior = my_claim(self.reply_id);
        if prior is not None {
            pc = prior as ClaimedIntro;
            pp0 = my_person(pc.person_id);
            if pp0 is not None {
                report {"person": pp0 as Person, "card": card, "intro_draft": pc.intro_draft};
                return;
            }
        }
        now = now_iso();

        headline = card.headline or "";
        title = headline;
        org = "";
        if " at " in headline {
            idx = headline.index(" at ");
            title = headline[:idx].strip();
            org = headline[idx + 4:].strip();
        }
        how_met = f"intro via {reply.from_handle}";

        person: Person | None = None;
        for p in [me ->:Knows:->] {
            if p.name == card.name {
                for e in [edge me ->:Knows:-> p] {
                    if e.how_met == how_met {
                        person = p;
                    }
                }
            }
        }
        created = False;
        if person is None {
            person = (me +>:Knows(how_met=how_met, last_contact=now, status="reported", source_note=""):+> Person(
                name=card.name, org=org, title=title, status="confirmed"
            ))[0];
            created = True;
        }
        pp = person as Person;
        if created and card.about {
            fact = (root ++> Fact(
                text=card.about, observed_at=now, source_kind="self", source_url=f"card:{card.handle}"
            ))[0];
            fact +>:FactAbout:+> pp;
        }

        req_card = my_card();
        requester_name = "";
        if req_card is not None and (req_card as Card).name {
            requester_name = (req_card as Card).name;
        } elif me.name and me.name != "me" {
            requester_name = me.name;
        } else {
            requester_name = req.from_handle;
        }

        draft = "";
        try {
            draft = draft_intro(me.about, req.need, reply.from_handle, card.name, headline, card.about, requester_name);
        } except Exception {
            draft = "";
        }
        if not draft or not draft.strip() {
            draft = intro_template(me.about, req.need, reply.from_handle, card.name, headline, requester_name);
        }
        if prior is not None {
            (prior as ClaimedIntro).person_id = jid(pp);
            (prior as ClaimedIntro).intro_draft = draft;
        } else {
            root ++> ClaimedIntro(reply_id=self.reply_id, person_id=jid(pp), intro_draft=draft);
        }
        report {"person": pp, "card": card, "intro_draft": draft};
    }
}

# ---------------------------------------------------------------- friend side

walker:priv ListIncomingRequests {
    """Requests posted by others, not expired, not declined, not yet answered by me."""
    has reports: list[object] = [];

    can go with Root entry {
        me_root = jid(root);
        now = now_iso();
        answered = [r.request_id for r in shared_replies() if owner_root(r) == me_root];
        # Ownership is by root only; handles are self-chosen and spoofable.
        for req in all_requests() {
            if owner_root(req) == me_root {
                continue;
            }
            if req.status == "declined" {
                continue;
            }
            if req.expires_at and req.expires_at < now {
                continue;
            }
            if jid(req) in answered {
                continue;
            }
            report req;
        }
    }
}

walker:priv ReplyToRequest {
    """Score the need against MY graph only; reply with a count and a strength,
    no identity. The reply lives on my root, read-only to the requester."""
    has request_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        n = load(self.request_id);
        if not isinstance(n, IntroRequest) {
            report err("not_found");
            return;
        }
        if not readable(n) {
            report err("forbidden");
            return;
        }
        req = n as IntroRequest;
        rid = jid(req);
        if owner_root(req) == jid(root) {
            report err("invalid_state");
            return;
        }
        me_root = jid(root);
        for r in shared_replies() {
            if owner_root(r) == me_root and r.request_id == rid {
                report err("invalid_state");
                return;
            }
        }
        if req.status == "declined" or (req.expires_at and req.expires_at < now_iso()) {
            report err("invalid_state");
            return;
        }
        m = my_me();
        if m is None {
            report err("no_card");
            return;
        }
        me = m as Me;
        c = card_of(me);
        if c is None {
            report err("no_card");
            return;
        }
        card = c as Card;
        matches = score_against_need(me, req.need, [req.from_handle]);
        kept = [x for x in matches if x["strength"] == "strong" or x["strength"] == "medium"];
        strength = "weak";
        person_id = "";
        why = "No strong match in your graph.";
        if kept {
            strength = str(kept[0]["strength"]);
            person_id = str(kept[0]["person_id"]);
            why = str(kept[0]["why"]);
        }
        reply = (root.shared ++> IntroReply(
            request_id=rid,
            from_handle=card.handle,
            match_count=len(kept),
            strength=strength,
            status="pending"
        ))[0];
        Jac.allow_root(reply, UUID(owner_root(req)), ReadPerm);  # jac:ignore[E1053]
        root ++> ReplyPrivate(reply_id=jid(reply), match_person_id=person_id, why=why);
        reply +>:RepliedTo:+> req;  # kept for the graph view; nothing reads it
        report view(reply);
    }
}

walker:priv ListMyReplies {
    """Every shared IntroReply OWNED by me (friend side), newest first, with
    its readable request and the friend-private "why it fits" text (from
    ReplyPrivate.why, set at ReplyToRequest). `why` never enters ReplyView and
    never crosses to the requester. Every status included, so a friend who
    reloads mid-flow still sees their in-progress replies."""
    has reports: list[object] = [];

    can go with Root entry {
        me_root = jid(root);
        mine = [r for r in shared_replies() if owner_root(r) == me_root];
        for r in reversed(mine) {
            rq = load(r.request_id);
            if not isinstance(rq, IntroRequest) or not readable(rq) {
                continue;
            }
            why = "";
            priv = my_private(jid(r));
            if priv is not None {
                why = (priv as ReplyPrivate).why;
            }
            report {"request": rq as IntroRequest, "reply": view(r), "why": why};
        }
    }
}

walker:priv ApproveReply {
    """Friend clicks approve on their own pending reply."""
    has reply_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        r = my_reply(self.reply_id);
        if r is None {
            report err("not_found");
            return;
        }
        reply = r as IntroReply;
        if reply_request_closed(reply) {
            report err("request_closed");
            return;
        }
        if reply.status != "pending" {
            report err("invalid_state");
            return;
        }
        reply.status = "approved";
        report view(reply);
    }
}

walker:priv OptIn {
    """Friend records that the matched contact opted in (approved -> opted_in)
    and gets a deterministic opt-in draft to send themselves. Nothing sends."""
    has reply_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        r = my_reply(self.reply_id);
        if r is None {
            report err("not_found");
            return;
        }
        reply = r as IntroReply;
        if reply_request_closed(reply) {
            report err("request_closed");
            return;
        }
        pv = my_private(self.reply_id);
        if reply.status != "approved" or pv is None or not (pv as ReplyPrivate).match_person_id {
            report err("invalid_state");
            return;
        }
        p = my_person((pv as ReplyPrivate).match_person_id);
        if p is None {
            report err("not_found");
            return;
        }
        person = p as Person;
        need = "an intro";
        rq = load(reply.request_id);
        if isinstance(rq, IntroRequest) and readable(rq) {
            need = (rq as IntroRequest).need;
        }
        facts = [f for f in [person <-:FactAbout:<-]];
        basis = "your work";
        if facts {
            basis = facts[0].text.strip().rstrip(".").strip();
        }
        reply.status = "opted_in";
        draft = (
            f"Hi {person.name}, a friend of mine is looking for {need}. "
            f"From what you've told me ({basis}), you'd be a great fit. "
            "Would you be open to an intro? No pressure either way."
        );
        report {"reply": view(reply), "opt_in_draft": draft};
    }
}

walker:priv Reveal {
    """Friend reveals the matched person's Card to the requester only
    (opted_in -> revealed). If the person has no Card, the friend's
    card-on-them is created here from the friend's own notes (Person fields
    and up to three Fact texts) with visibility handshake_only, attached via
    FromCard. The Card is allow_root'ed read-only to the requester's root."""
    has reply_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        r = my_reply(self.reply_id);
        if r is None {
            report err("not_found");
            return;
        }
        reply = r as IntroReply;
        if reply_request_closed(reply) {
            report err("request_closed");
            return;
        }
        pv = my_private(self.reply_id);
        if reply.status != "opted_in" or pv is None {
            report err("invalid_state");
            return;
        }
        priv = pv as ReplyPrivate;
        p = my_person(priv.match_person_id);
        if p is None {
            report err("not_found");
            return;
        }
        person = p as Person;
        rq = load(reply.request_id);
        if not isinstance(rq, IntroRequest) {
            report err("not_found");
            return;
        }
        if not readable(rq) {
            report err("forbidden");
            return;
        }
        req_owner = owner_root(rq);
        me_root = jid(root);
        now = now_iso();
        card: Card | None = None;
        for c in [person ->:FromCard:-> [?:Card]] {
            if owner_root(c) == me_root {
                card = c;
            }
        }
        if card is None {
            handle = handle_from_name(person.name) + "-" + jid_suffix(jid(person));
            parts = [x for x in [person.title.strip(), person.org.strip()] if x];
            headline = " at ".join(parts);
            texts = [f.text for f in [person <-:FactAbout:<-]][:3];
            card = (person +>:FromCard(handle=handle, received_at=now):+> Card(
                handle=handle,
                name=person.name,
                headline=headline,
                about=" ".join(texts),
                visibility="handshake_only",
                updated_at=now
            ))[0];
        }
        cc = card as Card;
        Jac.allow_root(cc, UUID(req_owner), ReadPerm);  # jac:ignore[E1053]
        list_card(cc);
        priv.revealed_card_id = jid(cc);
        reply.revealed_card_handle = cc.handle;
        reply.status = "revealed";
        report {"reply": view(reply), "revealed_card_handle": cc.handle};
    }
}

walker:priv DeclineReply {
    """Friend declines their own reply. No reason crosses the boundary."""
    has reply_id: str;
    has reports: list[object] = [];

    can go with Root entry {
        r = my_reply(self.reply_id);
        if r is None {
            report err("not_found");
            return;
        }
        (r as IntroReply).status = "declined";
        report "declined";
    }
}

# ---------------------------------------------------------------- dev-only

walker:priv DevMakeCard {
    """DEV/TEST ONLY: get-or-create the caller's Me and its Card (via Owns),
    for when OnboardMe's LLM is unavailable. Reports the Card."""
    has handle: str;
    has name: str;
    has reports: list[object] = [];

    can go with Root entry {
        if handle_taken(self.handle, jid(root)) {
            report err("handle_taken");
            return;
        }
        m = my_me();
        if m is None {
            me = (root ++> Me(name=self.name))[0];
        } else {
            me = m as Me;
        }
        c = card_of(me);
        if c is None {
            card = (me +>:Owns:+> Card(handle=self.handle, name=self.name, updated_at=now_iso()))[0];
        } else {
            card = c as Card;
        }
        report card;
    }
}

walker:priv DevSeedMatch {
    """DEV/TEST ONLY: attach to an existing Person (by name) in the caller's
    graph one Fact and one offer Intent, each asserted by a debrief Note with
    a span, so the scorer has evidence without an LLM Capture."""
    has name: str;
    has fact: str;
    has offer: str;
    has reports: list[object] = [];

    can go with Root entry {
        m = my_me();
        if m is None {
            report err("not_found");
            return;
        }
        me = m as Me;
        target: Person | None = None;
        for p in [me ->:Knows:->] {
            if p.name == self.name {
                target = p;
            }
        }
        if target is None {
            report err("not_found");
            return;
        }
        person = target as Person;
        now = now_iso();
        note = (root ++> Note(text=f"{self.fact} {self.offer}", kind="debrief", captured_at=now))[0];
        fact = (note +>:Asserts(span=self.fact):+> Fact(text=self.fact, observed_at=now))[0];
        fact +>:FactAbout:+> person;
        intent = (note +>:AssertsIntent(span=self.offer):+> Intent(kind="offer", text=self.offer))[0];
        intent +>:IntentAbout:+> person;
        report {"person_id": jid(person), "note_id": jid(note)};
    }
}
