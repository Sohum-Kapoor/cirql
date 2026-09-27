# Cirql — submission write-up (draft for Devpost, SOH-176)

## One line

**Other CRMs search your contacts. Cirql's agents walk your network.**

## What it does

Cirql is a personal CRM where AI agents walk your relationship graph. You meet someone, talk a 20-second debrief into your phone, and by the time you reach your car the person, what they do, what they want, who they mentioned, and what you promised are in your graph, each pointing back at the exact words you said. Then the part no contacts app does: set a goal and your network re-ranks around it with a reason and evidence per person. When the goal needs a kind of person you have no warm path to, your agent asks your friends' agents. Each friend's agent looks only at its own graph and answers with a count and a strength, no names. The friend approves, the contact opts in (in the demo a tap stands in for the contact's reply, and we say so on stage), and only then does one card cross to you with a drafted three-way intro. Nothing is sent; every hop needs a human tap.

## The loop on stage

Capture → Aim → Find the gap → Ask the network, on two phones, hosted, two real accounts.

## Why Jac

The data is a graph and the agents are walkers, so Jac is the natural language rather than a constraint. Concretely:

- **Nodes and typed edges are the schema.** `Person`, `Fact`, `Intent`, `Promise`, `Goal`, `Card`; edges like `Knows`, `Reported`, `Asserts{span}`, `RelevantTo{reason, strength, evidence}`. Provenance is an edge, not a string field.
- **The agent inbox is walkers composing walkers.** `RunAgent` runs after each capture and on app open, on the caller's own root: it reads the goal's `RelevantTo` edges, the goals with no warm path, `PathFinder` routes toward a gap, `Tend`'s reason-based reminders and the incoming asks it can answer, and turns each finding into an `AgentAction` with evidence ids. A human approves, dismisses or snoozes each one; approve performs the in-app step (post the ask, answer the ask, mark the promise) and never sends anything outside the app. No evidence, no action.
- **Every agent is a walker.** `Capture`, `GoalRank`, `GapFinder`, `ScoreAgainstNeed`, the Exchange (`PostRequest` → `ReplyToRequest` → `ApproveReply` → `OptIn` → `Reveal` → `ClaimReveal`), the QR `Handshake`, `PathFinder`, `Recall`, `Tend`, `GamePlan`, `NetworkHealth`, `Serendipity`, `Forget`, duplicate merge with undo. Each walker is also an HTTP endpoint; the phone spawns it on the caller's own graph root, so "which user's data" is never a parameter an agent could get wrong.
- **`by llm` replaces prompt glue.** Extraction and ranking are declared as typed objects with a one-line meaning per field; byLLM turns that into the prompt and validates the model's output against the type, so the model proposes structured claims and drafts prose while deterministic Jac enforces ownership, evidence links, expiry, state transitions, grants, and dedup. One model call per walker. When the model is unavailable, every walker degrades to a deterministic fallback and the note is never lost.
- **The graph answers questions a vector store cannot.** "Which friend knows a warehouse manager who wants a routing pilot?" is a two-hop walk over `Knows` and `Reported` edges with a `RelevantTo` filter; there is no embedding of that. `PathFinder`, `WhoNeedsWhatIHave`, and the Exchange are all multi-hop traversals, not similarity searches.
- **Per-user roots make cross-user agents safe to demo.** Each account's graph hangs off its own root; walkers run on the caller's root. The only object that crosses accounts is a Card its owner wrote, granted read-only to one specific root with `Jac.allow_root`. The Exchange lives on `root.shared` and carries a need, one line, and a handle, never a name from anyone's graph. Trust in the Exchange sits with the human friend: their agent reports a count and a strength, and the friend reviews it before anything is revealed; a lying agent can only mislead its own owner.
- **99% of the code is Jac** (`scripts/jac_pct.sh`; about 1.6 MB of Jac across server walkers, client UI, tests and tooling): server walkers, client UI in `cl` blocks, tests, the seed loader, and the demo checker. The only JavaScript is d3 and build config.
- **Token economy.** One model call per debrief, per ranking, per gap check, and per reply; rankings are materialized as `RelevantTo` edges and served from the graph on later calls; when the model is unavailable the whole two-account demo path still completes on deterministic fallbacks in about 1.3 seconds.

## What a daily user gets, beyond the demo

Search across people, facts, wants, promises and notes; contact details on a person; circles (your own labels, never a score) and events (where you met people); a notes timeline where deleting a note retracts only what it alone supported; real dates on promises ("Fri", "in March" become dates) and an upcoming view; a weekly digest; archive instead of delete; export and restore of the whole graph; delete my data; a friend list with friends-only asks and blocked handles; blinded identity tokens so two friends' replies can be recognised as the same person without a name crossing. Every one of these is a `:priv` walker on the caller's root with tests, including a two-account isolation test wherever an id is taken.

## What a walker looks like

The friend's side of the Exchange, from `exchange.sv.jac`. The scorer runs on the friend's own root; the reply carries a count and a strength and is granted read-only to the requester's root:

```jac
matches = score_against_need(me, req.need, [req.from_handle]);
kept = [x for x in matches if x["strength"] == "strong" or x["strength"] == "medium"];
reply = (root.shared ++> IntroReply(
    request_id=rid, from_handle=card.handle,
    match_count=len(kept), strength=strength, status="pending"
))[0];
Jac.allow_root(reply, UUID(owner_root(req)), ReadPerm);
```

And a debrief becoming provenance-bearing graph, from `capture.sv.jac`: the fact hangs off the note that asserted it, with the exact span, and points at the person it is about.

```jac
f = (note +>:Asserts(span=span):+> Fact(text=xf.text, observed_at=now, source_kind="reported"))[0];
f +>:FactAbout:+> p;
a +>:Reported(source_note=jid(note), span=span):+> b;
```

## The same James Anderson, without LinkedIn

Two of your friends both know a "James Anderson" who will never install Cirql. Cross-account identity is handled in three layers: (1) the Exchange never needs it before consent, since each agent matches on its own graph and only a count and a strength cross; (2) every person carries blinded identity tokens, keyed hashes of name+org, email, phone and canonical URLs, so two friends' replies can be shown as "likely the same person" without a name crossing and without ever auto-merging; (3) verification comes from the person's own public presence (Enrich, every fact with a URL) and, on the roadmap, from the person themselves through a no-account "that's me" link. Nothing is scraped; a hash is the only thing about a person that is ever compared across accounts.

## What we can say about privacy (and what we can't)

True: each user's graph is isolated by construction, the only object that ever leaves an account is a card its owner wrote, granted read-only to one specific user, and the model sees only the fields we send it.

We do not say "private", "secure", or "encrypted". Roots and grants do not encrypt at rest or protect from the operator, and everything sent to Gemini leaves the server. Hardening is roadmap.

## Product rules the code enforces

- Relationships never decay. `last_contact` is display only; nothing reads it to lower anything. Facts age and intents expire instead (`FreshnessSweep`).
- Relevance is a property of (person, goal), never of a person. No worth scores, no give/take ledger.
- Every fact, intent, promise, and reported tie carries its source note and span. Tap anything → the words it came from (`Receipt`).
- Nothing sends. Drafts only; approvals are recorded and labeled with their source.
- No automated fetching from LinkedIn or any platform whose terms forbid it. Your own data export, your contacts, a pasted note, or a consented card exchange.
- Web enrichment only with a source: `Enrich` uses Gemini with Google Search grounding and attaches a fact only when a grounding chunk gives it a URL and the model says the identity matched your captured context; a made-up name returns nothing. LinkedIn pages are never fetched, even when search points there.
- Users can correct the system: `Forget` deletes a person or fact and retracts only what depended on it.
- Your data comes back out: `ExportGraph` returns everything on your root as one JSON file (people, facts, intents, promises, notes, ties, with every span and source) and `ImportGraph` takes it back; `ExportContacts` writes your people as a vCard file any phone imports. `DeleteAccount` removes the graph and the login.
- The privacy page (`/static/privacy.html`) says all of this in plain sentences and is linked from Settings; the graph view has a text list of every tie for screen readers and keyboards.

## Verified, not intended

- 43 server modules, 107 `:priv` walkers, 41 test suites with 363 test blocks (each suite also runs the suites it imports), all green on main (`jac test <module>.sv.jac` for each), including negative tests: account A never sees B's nodes; a bystander cannot read, approve, or claim in the Exchange; an ungranted card read is denied; a handshake-only card is refused by the public read.
- The cross-user grant primitives were proven with three real accounts and across a server restart before the Exchange was built on them.
- `scripts/demo_check.jac` runs the whole two-account demo path against the hosted server in about a minute: 22 PASS, 0 FAIL. Five written personas (`docs/personas.md`) were played by agents against a local server; every bug they found is on the board, and the ones that mattered were fixed the same evening.
- Two bugs that only appear on a persistent multi-request server were caught and fixed the same afternoon: typed traversals drop edges attached by other users after a restart, and a denied cross-root edge write is a silent no-op. Both are now rules in the working agreement.

## What we know is not done

An adversarial code review (a different model family from the one that wrote the walkers) found these, and they are still true: a reveal copies up to three facts the friend captured about the contact, and the contact's tap in the demo stands in for a consent we do not yet collect from them; a merge and its undo do not track which edges already existed; a corrected fact is not re-scored in an open Exchange; a single `jac start` process serves everyone, so concurrent model calls queue. There is no friend list this weekend: an open request on the Exchange is visible to every account's agent (still only a need, one line and a handle), so "asks from friends" means "asks from anyone on Cirql" until the exchange is gated by card handshakes. Each is listed so a judge does not have to find it.

## What's next (roadmap, not built)

Full both-party permission flow with real sending · context capsules · live-linked cards · opt-in card directory · multi-hop Exchange (friend-of-friend relays) · permissioned connectors (contacts, calendar, email) · export and portability · hardening (encryption at rest, model-provider disclosure) · LinkedIn only via the official Connections API if approved · web enrichment with a URL on every fact once search grounding is available in byLLM.

## Try it

_B fills in: hosted URL, two demo accounts (username / password), and the video link._

## Built with

Jac (jaclang 0.16.7, jac-client, jac-scale, byLLM) · Gemini via byLLM · React under `cl` blocks with a Linear-style shadcn kit · Capacitor for the phones · Cloudflare tunnel for hosting.

---
_Notes for B: every claim above is verified on main or on the hosted server; do not add a claim the code does not enforce. Prose reviewed cross-family (Gemini) on 2026-09-26; 7 of 12 objections applied._
