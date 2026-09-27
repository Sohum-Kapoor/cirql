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
    has blocked_handles: list[str] = [];  # Exchange handles whose requests/replies I never see
}

node Person {
    has name: str;
    has org: str = "";
    has title: str = "";
    has status: str = "confirmed";   # confirmed | proposed (after import, before swipe-confirm)
    # SOH-215..220 (product completeness, 2026-09-26 20:00). All optional, all own-root.
    has email: str = "";             # contact details the user captured or imported; never crosses accounts
    has phone: str = "";
    has links: list[str] = [];       # personal site, GitHub, papers, company bio (Enrich fills from grounding)
    has location: str = "";          # city / region as captured
    has identity_tokens: list[str] = [];  # blinded HMAC tokens (name|org, email, phone, canonical url); the only thing about a person that may be compared across accounts
    has archived: bool = False;      # soft delete: hidden from lists and rankings, restorable
}

node Circle {
    has name: str;                   # a group the user names ("Michigan robotics", "family"); never a score
    has created_at: str = "";
}

node Event {
    has name: str;                   # where people were met ("JacHacks 2026", "Detroit hardware meetup")
    has date: str = "";              # ISO date if known
    has location: str = "";
    has created_at: str = "";
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
    has ranked_at: str = "";         # ISO; set by GoalRank on every rebuild (SOH-212 staleness)
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
    has interests: list[str] = [];   # SOH-179 (interests): owner's own public list; distinct from private Interest nodes, never copied automatically
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

edge HasCircle: Me --> Circle {}

edge InCircle: Person --> Circle {}

edge HasEvent: Me --> Event {}

edge MetAt: Person --> Event {
    has source_note: str = "";       # jid of the Note that placed them there, when known
}

edge PromiseTo: Promise --> Person {}

edge Proposes: Introduction --> Person {}   # exactly two per Introduction

edge RelevantTo: Person --> Goal {
    """Materialized by GoalRank. Rebuilt when the goal changes; deleted when it closes."""
    has reason: str = "";
    has strength: str = "weak";      # strong | medium | weak (one enum project-wide, SOH-160 2026-09-26)
    has evidence: list[str] = [];    # jids of Facts/Intents/Notes/Cards; GoalRank rebuilds {id,kind,observed_at,span} at report time
    has opener: str = "";            # drafted opener, cached so GoalRank can be pre-warmed
    has label: str = "cold";         # known | route | cold
    # SOH-226 ranking stability: this ONE candidate is only re-sent to the
    # model when something about THEM or the goal changed since ranked_at
    # (see goals.sv.jac `stale_trigger`); otherwise strength/reason/opener/
    # label above are kept verbatim across a GoalRank rebuild.
    has ranked_at: str = "";           # ISO; when THIS edge's strength was last (re-)computed
    has ranked_goal_text: str = "";    # snapshot of Goal.text as of ranked_at (detects an edited goal)
    has prev_strength: str = "";       # strength before the most recent change; "" if unchanged this pass
    has change_reason: str = "";       # "new note on Sep 27" | "goal edited" | "re-ranked on request"; "" if unchanged
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
    has audience: str = "everyone";   # everyone | friends (SOH friend-gated exchange)
    has goal_text: str = "";          # SOH-229: requester's goal as a noun phrase; "" when not tied to a goal
}

node IntroReply {
    """Lives under root.shared (so the requester finds it by traversal), OWNED by
    the friend, allow_root'ed read-only to the requester. Nothing identity-bearing
    here: anyone can enumerate root.shared and jobj never authorizes."""
    has request_id: str;
    has from_handle: str;
    has match_count: int = 0;
    has strength: str = "weak";      # strong | medium | weak  (the friend's relationship to the match)
    has status: str = "pending";     # pending | approved | opted_in | revealed | declined
    has revealed_card_handle: str = "";  # set at Reveal only; ClaimReveal finds the Card by it in the CardDirectory
    has match_tokens: list[str] = [];  # blinded identity tokens of the top match; hashes only, never a name
}

node ReplyPrivate {
    """The friend's private half of an IntroReply, under the FRIEND's root only."""
    has reply_id: str;
    has match_person_id: str = "";
    has revealed_card_id: str = "";
    has why: str = "";  # SOH-205 polish: friend-private "why it fits" text; NEVER in ReplyView, never crosses to the requester
}

node ClaimedIntro {
    """SOH-211: the requester's record of one ClaimReveal, under the REQUESTER's root only.
    A second ClaimReveal on the same reply reports this stored draft instead of drafting again."""
    has reply_id: str;
    has person_id: str = "";
    has intro_draft: str = "";
}

edge Posted: Exchange --> IntroRequest {}

edge RepliedTo: IntroReply --> IntroRequest {}

node CardDirectory {
    """One, under root.shared. Lists every Card published with visibility=link so get_card can find it by handle."""
    has name: str = "main";
}

edge Lists: CardDirectory --> Card {}

node CardListing {
    """SOH-211: a public pointer, owned by the Card's owner and granted ReadPerm to everyone,
    hung off the CardDirectory. Carries only the handle and the Card's id, never Card fields.
    Needed because a traversal silently skips targets the caller cannot read, so a
    handshake_only (revoked) Card is invisible through `[dir -->]` to everyone but its owner."""
    has handle: str;
    has card_id: str;
}

node HandshakeOffer {
    """One per scan, under root.shared. Carries two handles and a status; never a name from anyone's graph."""
    has from_handle: str;
    has to_handle: str;
    has status: str = "offered";     # offered | accepted | declined | expired
    has created_at: str = "";
    has expires_at: str = "";
}

# ---------------------------------------------------------------- Merge (SOH-195)

node MergeRecord {
    """Under root. One per `MergePeople` call - the removed person's own
    fields plus a description of every edge that call re-pointed, so
    `UndoMerge` can recreate the person and move the edges back."""
    has kept_id: str;
    has removed_name: str = "";
    has removed_org: str = "";
    has removed_title: str = "";
    has removed_status: str = "";
    has moved: list[str] = [];
    has created_at: str = "";
    has undone: bool = False;
}

# ---------------------------------------------------------------- Agent inbox (SOH-223)

node AgentAction {
    """One proposal RunAgent found in the caller's own graph. Nothing sends:
    approving performs an in-app step at most (PostRequest, ReplyToRequest,
    CompletePromise) and otherwise only stores the edited draft."""
    has kind: str;                   # new_match | ask_network | route | promise_due | follow_up | reconnect | answer_ask
    has title: str;
    has why: str;
    has evidence: list[str] = [];    # jids of the caller's own Facts/Intents/Promises/Notes/Goals; never empty
    has person_id: str = "";
    has goal_id: str = "";
    has request_id: str = "";
    has draft: str = "";
    has payload_json: str = "";
    has status: str = "open";        # open | approved | dismissed | snoozed | stale
    has created_at: str = "";
    has resolved_at: str = "";
    has source_walker: str = "";
    has dedup_key: str = "";
    has approval_source: str = "";   # "" | in_app | agent:warm_path_found
}

node AgentRun {
    """One per RunAgent call, under Me. Throttles model-backed steps (one per
    account per 10 minutes) and remembers RelevantTo strengths so new_match
    only fires when a strength rose."""
    has ran_at: str;
    has reason: str;
    has model_backed: bool = False;
    has strengths_json: str = "";    # {"<person_id>|<goal_id>": "strong|medium|weak"}
}

edge HasAction: Me --> AgentAction {}

edge HasAgentRun: Me --> AgentRun {}
