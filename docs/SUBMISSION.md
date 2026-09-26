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
- **Every agent is a walker.** `Capture`, `GoalRank`, `GapFinder`, `ScoreAgainstNeed`, the Exchange (`PostRequest` → `ReplyToRequest` → `ApproveReply` → `OptIn` → `Reveal` → `ClaimReveal`), the QR `Handshake`, `PathFinder`, `Recall`, `Tend`, `GamePlan`, `NetworkHealth`, `Serendipity`, `Forget`, duplicate merge with undo. Each walker is also an HTTP endpoint; the phone spawns it on the caller's own graph root, so "which user's data" is never a parameter an agent could get wrong.
- **`by llm` replaces prompt glue.** Extraction and ranking are declared as typed objects with a one-line meaning per field; byLLM turns that into the prompt and validates the model's output against the type, so the model proposes structured claims and drafts prose while deterministic Jac enforces ownership, evidence links, expiry, state transitions, grants, and dedup. One model call per walker. When the model is unavailable, every walker degrades to a deterministic fallback and the note is never lost.
- **Per-user roots make cross-user agents safe to demo.** Each account's graph hangs off its own root; walkers run on the caller's root. The only object that crosses accounts is a Card its owner wrote, granted read-only to one specific root with `Jac.allow_root`. The Exchange lives on `root.shared` and carries a need, one line, and a handle, never a name from anyone's graph.
- **98% of the code is Jac** (`scripts/jac_pct.sh`; about 21,000 lines of Jac across server walkers, client UI, tests and tooling): server walkers, client UI in `cl` blocks, tests, the seed loader, and the demo checker. The only JavaScript is d3 and build config.
- **Token economy.** One model call per debrief, per ranking, per gap check, and per reply; rankings are materialized as `RelevantTo` edges and served from the graph on later calls; when the model is unavailable the whole two-account demo path still completes on deterministic fallbacks in about 1.3 seconds.

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

## What we can say about privacy (and what we can't)

True: each user's graph is isolated by construction, the only object that ever leaves an account is a card its owner wrote, granted read-only to one specific user, and the model sees only the fields we send it.

We do not say "private", "secure", or "encrypted". Roots and grants do not encrypt at rest or protect from the operator, and everything sent to Gemini leaves the server. Hardening is roadmap.

## Product rules the code enforces

- Relationships never decay. `last_contact` is display only; nothing reads it to lower anything. Facts age and intents expire instead (`FreshnessSweep`).
- Relevance is a property of (person, goal), never of a person. No worth scores, no give/take ledger.
- Every fact, intent, promise, and reported tie carries its source note and span. Tap anything → the words it came from (`Receipt`).
- Nothing sends. Drafts only; approvals are recorded and labeled with their source.
- No automated fetching from LinkedIn or any platform whose terms forbid it. Your own data export, your contacts, a pasted note, or a consented card exchange.
- Users can correct the system: `Forget` deletes a person or fact and retracts only what depended on it.

## Verified, not intended

- 26 server modules, 26 test suites, 431 test runs (each suite also runs the suites it imports), all green on main (`jac test <module>.sv.jac` for each), including negative tests: account A never sees B's nodes; a bystander cannot read, approve, or claim in the Exchange; an ungranted card read is denied; a handshake-only card is refused by the public read.
- The cross-user grant primitives were proven with three real accounts and across a server restart before the Exchange was built on them.
- `scripts/demo_check.jac` runs the whole two-account demo path against the hosted server in about a minute: 18 PASS, 0 FAIL.
- Two bugs that only appear on a persistent multi-request server were caught and fixed the same afternoon: typed traversals drop edges attached by other users after a restart, and a denied cross-root edge write is a silent no-op. Both are now rules in the working agreement.

## What's next (roadmap, not built)

Full both-party permission flow with real sending · context capsules · live-linked cards · opt-in card directory · multi-hop Exchange (friend-of-friend relays) · permissioned connectors (contacts, calendar, email) · export and portability · hardening (encryption at rest, model-provider disclosure) · LinkedIn only via the official Connections API if approved · web enrichment with a URL on every fact once search grounding is available in byLLM.

## Try it

_B fills in: hosted URL, two demo accounts (username / password), and the video link._

## Built with

Jac (jaclang 0.16.7, jac-client, jac-scale, byLLM) · Gemini via byLLM · React under `cl` blocks with a Linear-style shadcn kit · Capacitor for the phones · Cloudflare tunnel for hosting.

---
_Notes for B: every claim above is verified on main or on the hosted server; do not add a claim the code does not enforce. Prose reviewed cross-family (Gemini) on 2026-09-26; 7 of 12 objections applied._
