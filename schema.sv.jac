"""Graph schema — the one file both halves depend on.

OWNER: Person A. Changes land on main immediately and are announced in Linear.
Person B never edits this file; request changes via contracts/walkers.md.

See docs/PRD.md §8 for the meaning of every node and edge. Rules that matter:
- Relationships never decay. Facts and Intents have freshness/expiry.
- Relevance is a property of (Person, Goal) — the RelevantTo edge — never of a Person.
- The Card is the only object that ever crosses accounts.
- No edge between two people means UNKNOWN, not "never met".
"""

# ---------------------------------------------------------------- nodes

node Me {
    has name: str;
    has about: str = "";
}

node Person {
    has name: str;
    has org: str = "";
    has title: str = "";
    has status: str = "confirmed";   # confirmed | proposed (after import, before swipe-confirm)
}

node Note {
    has text: str;
    has kind: str;                   # about_me | debrief | paste | import | enrich
    has captured_at: str;
    has audio_ref: str = "";
}

node Fact {
    has text: str;
    has observed_at: str;
    has valid_to: str = "";
    has status: str = "reported";    # reported | confirmed | stale
    has source_kind: str = "reported";   # self | reported | web
    has source_url: str = "";
}

node Interest {
    has topic: str;
}

node Goal {
    has text: str;
    has created_at: str;
    has active: bool = True;
}

node Intent {
    has kind: str;                   # need | offer | open_to
    has text: str;
    has expires_at: str = "";
    has source_kind: str = "reported";   # self | reported
}

node Promise {
    has text: str;
    has due: str = "";
    has done: bool = False;
}

node Introduction {
    has state: str = "proposed";     # proposed | reviewed | awaiting_permission | approved | draft_ready | sent | declined | canceled | expired
    has rationale_a: str = "";
    has rationale_b: str = "";
    has unknowns: str = "";
    has share_preview: str = "";
    has draft: str = "";
    has approval_source: str = "";   # "" | offline | in_app
    has created_at: str = "";
}

node Card {
    """Self-authored. The only object that leaves an account."""
    has handle: str;
    has name: str = "";              # display name; set by OnboardMe from Me.name (SOH-205 needs it on reveal)
    has headline: str = "";
    has about: str = "";
    has looking_for: list[str] = [];
    has can_offer: list[str] = [];
    has links: list[str] = [];
    has contact_pref: str = "";
    has visibility: str = "link";    # link | handshake_only
    has updated_at: str = "";
}

# ---------------------------------------------------------------- edges
# Typed endpoints so traversals infer node types (see `jac guide jac-node-edge-patterns`).

edge Owns: Me --> Card {}

edge Knows: Me --> Person {
    has how_met: str = "";
    has last_contact: str = "";      # ISO-8601; display only; nothing reads it to lower anything
    has status: str = "reported";    # reported | confirmed | proposed
    has source_note: str = "";       # jid of the Note this came from
}

edge Reported: Person --> Person {
    """A tie the user was told about. Never independently confirmed."""
    has source_note: str = "";
    has span: str = "";
}

edge FromCard: Person --> Card {
    has handle: str = "";
    has received_at: str = "";
}

edge Asserts: Note --> Fact {
    has span: str = "";
}

edge AssertsIntent: Note --> Intent {
    has span: str = "";
}

edge AssertsPromise: Note --> Promise {
    has span: str = "";
}

edge Mentions: Note --> Person {
    has span: str = "";
}

edge FactAbout: Fact --> Person {}

edge IntentAbout: Intent --> Person {}

edge HasInterest: Me --> Interest {}

edge HasGoal: Me --> Goal {}

edge HasIntent: Me --> Intent {}

edge PromiseTo: Promise --> Person {}

edge Proposes: Introduction --> Person {}   # exactly two per Introduction

edge RelevantTo: Person --> Goal {
    """Materialized by GoalRank. Rebuilt when the goal changes; deleted when it closes."""
    has reason: str = "";
    has strength: str = "weak";      # strong | medium | weak (one enum project-wide, SOH-160 2026-09-26)
    has evidence: list[str] = [];    # jids of Facts/Intents/Notes/Cards; GoalRank rebuilds {id,kind,observed_at,span} at report time
    has opener: str = "";            # drafted opener, cached so GoalRank can be pre-warmed
    has label: str = "cold";         # known | route | cold
}

# ---------------------------------------------------------------- Exchange (v0.3)
# One Exchange lives under root.shared. Requests carry a need and one line about
# the requester; replies carry a count and a strength and NO identity until Reveal.
# See docs/PRD.md §10 and `jac guide jac-sv-multi-user`.

node Exchange {
    has name: str = "main";
}

node IntroRequest {
    has need: str;
    has from_handle: str;
    has about_line: str = "";
    has status: str = "open";        # open | replied | approved | opted_in | revealed | declined | expired
    has created_at: str = "";
    has expires_at: str = "";
}

node IntroReply {
    has request_id: str;
    has from_handle: str;
    has match_count: int = 0;
    has strength: str = "weak";      # strong | medium | weak  (the friend's relationship to the match)
    has status: str = "pending";     # pending | approved | opted_in | revealed | declined
    has match_person_id: str = "";   # stays on the FRIEND's root; never serialized to the requester
    has revealed_card_id: str = "";  # jid of the Card granted to the requester at Reveal; read server-side by ClaimReveal only
}

edge Posted: Exchange --> IntroRequest {}

edge RepliedTo: IntroReply --> IntroRequest {}
