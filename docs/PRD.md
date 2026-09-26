# Cirql — PRD v0.3 (merged)

**JacHacks UMich · September 26–27, 2026 · Team of 2 · Working name: Cirql**
**Status:** Merged from PRD v0.1 (product vision), the feature-list session, and the "Tether" PRD (Jesse, Sept 26). Supersedes v0.2. Lives at `docs/PRD.md` in the repo.

**How to read this:** Part A is what exists at noon Sunday, ranked. Part B is the roadmap: what we say when a judge asks "what's next?" Nothing in Part B is a build commitment this weekend. Hour estimates assume two people who learned Jac this morning; pad them.

---

## 1. Vision

A private relationship memory that lives on your phone. You capture people the moment you meet them, mostly by talking. Agents walk your network instead of searching it: they reorganize it around what you're trying to do right now, they notice when the goal needs someone you have no path to, and then your agent asks your friends' agents — with a person approving every step and no one's graph ever read by anyone else's agent. Every suggestion comes with receipts. Nothing is scraped from platforms that forbid it, relationships never decay, and nobody gets a worth score.

**One-liner for judges:** *Other CRMs search your contacts. Cirql's agents walk your network.*

**The product loop, four steps, one story:**
1. **Capture** — a 30-second voice memo after you meet someone becomes people, facts, and promises in your graph, each pointing back at the memo.
2. **Aim** — set a goal ("summer 2027 VC internship"); the graph re-ranks around it with a reason per person.
3. **Find the gap** — the agent notices the goal needs a kind of person you have no warm path to ("you don't know anyone in climate VC").
4. **Ask the network** — your agent posts a redacted request; your friends' agents each search *their own* graph; the friend approves, the contact opts in, and only then are cards exchanged and an intro drafted.

**The three questions** (kept from v0.1): Remember (who is this person to me?), Connect (who in my network should meet, and why now?), Grow (who could help with a goal, and what's a legitimate next step?).

The graph is centered on the user for navigation but contains real person-to-person ties. It is not a hub-and-spoke address book.

## 2. What success means by noon Sunday, in order

1. **It's live.** Hosted backend, hosted website, app installed on two phones with two real accounts. A judge can open the URL.
2. **One story on stage, no feature tour.** Goal → ranked list → voice debrief → new person lands with facts and a promise → gap alert → "Ask my network" → second phone gets an approval card ("a friend's agent is looking for climate-tech VC; you have 1 strong match — approve?") → approve, contact opts in → first phone gets the card and a drafted three-way intro. Close: "No agent ever read another person's graph. A human approved every step. Everything here is walkers on a graph in Jac."
3. **Jac visibly does the graph work.** ≥40% Jac. Walkers for every agent, per-user roots for the accounts, `grant`/`allow_root` for the one shared node, UI in `cl`. "Why Jac?" gets a real answer: the data is a graph, the agents are walkers, `by llm` replaces prompt glue, per-user roots make cross-user agents safe to demo.
4. **Prize posture:** Agentic AI (1st $1,000 / 2nd $600) is the target. Best Mobile through Jac ($200) and Best Jaclang / Best JacHammer ($200 each) come along if 1–3 land. Best of Google via Gemini as the LLM. Best of ElevenLabs only if the call-in debrief agent ships (Tier 2); speech-to-text alone won't win it.

## 3. Non-goals and rejected ideas

Stated here so nobody relitigates them at 2 AM.

| Rejected | Why |
|---|---|
| Automated LinkedIn (or any TOS-prohibited) scraping | LinkedIn's User Agreement forbids automated access; hiQ ended under a permanent injunction for breaching it. Judges will ask. Replaced by §12: the user's own LinkedIn data export, phone contacts, paste-anything, public-web enrichment with sources, and consented card exchange. |
| Relationship decay — `warmth` with a 30-day half-life on the Knows edge (Tether §Hero 1) | Silence is not evidence of a damaged friendship. **Facts** have freshness and expiry; **relationships** don't decay. Days-since-contact is shown on a card and may break ties *within one goal's ranking*; it is never a property of the relationship and never lowers anything. |
| Facts as bare strings on the Person (`Person.facts: list[str]`) | Kills receipts. Facts are nodes with `source_note` and span. |
| Give/take ledger, "who reaches out first" | A ranking of a person's worth. We rank a person's *relevance to a goal*, never the person. |
| Automatic sending of introductions | Drafts only. Approval is recorded and labeled with its source. In the demo, a click stands in for the contact's reply and we say so. |
| Privacy claims beyond what the code enforces | See §13. Per-user roots + explicit grants give isolation by construction; they do not give encryption or protection from the operator. |
| Team-of-4 scope (Tether's 40 person-hours) | We are two. Tether's own rule: a team of 3 skips every Stretch item. A team of 2 cuts into its MVP; §7 is the cut. |

## 4. Principles

1. **Reduce maintenance.** Accept natural speech, pasted text, and permitted imports; ask only when ambiguity changes a result.
2. **Treat people as people.** No sales stages on a person. Prospect/introduced/engaged states live inside a goal, never on the person.
3. **Keep facts and possibilities separate.** Knowing someone, sharing context, and "these two might benefit from meeting" are three edge types with three different looks.
4. **Show why and why now.** Every recommendation cites the note, its date, and what's unknown.
5. **Benefit both sides.** Similarity is a signal; complementary need/offer, willingness, and timing decide.
6. **Relevance is a property of (person, goal). Worth is not a property of anything.** `RelevantTo` edges are rebuilt when the goal changes and deleted when it closes.
7. **The only thing that crosses accounts is a card its owner wrote.** An agent never reads another user's graph; it only answers requests about its owner's own graph, and only with a redacted reply until every person involved has said yes.
8. **A human approves every hop.** Nothing moves someone toward a new person without a click from the person whose relationship it is.
9. **Let users correct the system.** Names, facts, ties, and suggestions are editable; deletion retracts derived claims.
10. **Respect attention.** Few suggestions, each with a dismiss and a "not now." Requests expire; either side can decline without the other learning why.

## 5. Users and journeys

**User 0 is us.** Two students who run events and recruiting pipelines, meeting 30+ new people a month, with real goals (an internship, a first check, a hire, a jazz group to sit in with). The judges' question "who did you build this for?" is answered by handing them the phone.

**Job to be done (Tether's phrasing, kept):** "When I'm working toward something, show me who in my network matters for it, what I owe them, and how to reach the people I don't know yet."

### J0 — Onboarding (three-minute target)
1. Sign up with email.
2. Talk or paste an about-me. Becomes `Me`, `Interest`, `Goal`, and self-asserted `Intent` nodes, plus a drafted `Card`.
3. **Your card** — headline, what I do, interests, looking for, can offer, links, how to reach me. Drafted from the about-me, edited and owned by the user. It's the only object that ever leaves the account, and it's what gets revealed at the end of an Exchange.
4. Bring people: LinkedIn data-export CSV, phone contacts, vCard/CSV, or five names and how you know them. Bulk import proposes `how_met` from the export's fields × your history; you confirm by swipe, never by form.
5. First recall before any work: "For your goal, here's who you already know and why."

### J1 — Aim: set a goal, watch the network reorganize
`GoalRank` walks known people, scores relevance with a reason and evidence per person, writes `RelevantTo` edges (`known | route | cold`). The ranked list shows the top people worth contacting this week, each with a one-line reason citing the memo it came from, days since last contact, and a drafted opener that mentions one specific thing from your last conversation. Change the goal; the ranking rebuilds. Close it; the edges go away.

### J2 — Capture a real encounter
You say: "Met Maya at JacHacks. She works on accessible robotics, knows Arjun from their lab, wants feedback from wheelchair users, I promised to send our demo." `Capture` stores the note first, then proposes Maya, a Fact, a need, a reported tie Maya→Arjun, and a Promise, each pointing at the note's span. Ambiguous identity is preserved as a second `proposed` person, never guessed.

### J3 — Find the gap
`GapFinder` reads the goal's `RelevantTo` edges and the goal text and asks: does this goal need a kind of person for whom there is no `known` or `route` entry? If so it raises a **gap alert** ("No warm path to climate-tech VC") with an *Ask my network* button. Missing links stay missing; the app does not manufacture closeness.

### J4 — Ask the network (the Exchange)
1. **Request:** your agent posts an `IntroRequest` to the shared Exchange: the need plus one line about you. No names from your graph go out.
2. **Local search:** each friend's agent runs `ScoreAgainstNeed` on *its own root only* — the same need/offer scorer the intra-graph Matchmaker uses.
3. **Redacted reply:** "1 match, relationship: strong." No identity attached.
4. **Friend approves:** the friend sees an approval card — the request, the match, why it fits — and clicks. Nothing moves without it.
5. **Contact opts in:** the friend's agent drafts a double-opt-in note to the contact. In the demo a click stands in for the reply, and we say so.
6. **Reveal and intro:** the matched person's own card is granted to the requester (`allow_root`, that one node, read-only), a three-way intro is drafted, and the requester's graph gets a new `Person` + `Knows{how_met="intro via <friend>"}`.

Rules said out loud in the demo: an agent never reads another user's graph; every step that moves someone toward a new person needs a human approval; requests expire after 7 days; either side can decline without the other learning why.

**Fallback (9 PM gate):** if cross-user grants fight us past 9 PM, the same `ScoreAgainstNeed` scorer runs inside one graph and the second act is the intra-graph **Matchmaker** card (two of your own contacts with complementary need/offer, rationale per side, unknowns, share preview, draft). That is a shipped feature, not a simulation, and we say which one we're showing.

### J5 — Consented exchange in person (Tier 1)
Both scan a QR; each receives the other's self-authored card as a `Person` + `FromCard`, facts sourced `card:<handle>`. "Here's what I noted" sends someone the card you keep on them so they can correct it.

### J6 — Tend (Tier 2)
Reason-based, not timer-based: an open promise, a person newly relevant to a goal, an intent about to expire, a stated life event.

## 6. Demo script (2:00, two phones, website on the projector)

| t | Beat | On screen |
|---|---|---|
| 0:00 | "I met 40 people last month. I remember maybe 10. And my contacts app has no idea I'm trying to land a VC internship." | Home: today's promises, one goal |
| 0:15 | The network | Projector: ~30 seeded people drawn live |
| 0:25 | Tap mic, 20-second memo about a judge or mentor met today, with their OK (pre-recorded file as backup) | New node, facts attach with source chips, a promise appears |
| 0:50 | Set the goal "summer 2027 VC internship" | Ranked list rebuilds; projector graph re-clusters; each card: reason, days since contact, drafted opener |
| 1:15 | Gap alert: "No warm path to climate-tech VC." Tap *Ask my network* | Request posted; no names leave the phone |
| 1:25 | Teammate's phone: "A friend's agent is looking for climate-tech VC. You have 1 strong match. Approve?" Approve → tap the contact's opt-in | First phone: the matched person's card arrives, a three-way intro is drafted, a new edge appears |
| 1:50 | "No agent ever read another person's graph. A human approved every step. Everything here is walkers on a graph in Jac." | Tap an edge → the note span it came from |

Backups: pre-recorded memo file (room noise), pre-warmed LLM calls and cached GoalRank results (latency), 2-minute screen recording (Wi-Fi). Rehearse three times with a timer.

## 7. Feature ranking

Single ordered list. Tier boundaries are where the demo stops working. Hours are for two people new to Jac.

### Tier 0 — the demo doesn't exist without these (~27 h)

| # | Feature | Required behavior | Acceptance | Hrs |
|---|---|---|---|---|
| 1 | Graph schema + per-user persistence | `server/schema.jac` (done, passes `jac check`); `walker:priv` endpoints; isolation negative test | A walker from account A never returns a node from B | 2 |
| 2 | Auth + onboarding | `jacSignup`/`jacLogin`; about-me → `Me`, `Interest`, `Goal`, self `Intent`s, drafted `Card` | Scrubbed hot.md → 1 Me, ≥5 Interests, ≥1 Goal, a Card; rerun doesn't duplicate | 3 |
| 3 | Capture (text) + paste-anything | Note stored first; typed extraction → Person/Fact/Intent/Promise/Reported with `source_note` + span | J2 example yields all five, all pointing at the note | 4 |
| 4 | Voice capture | MediaRecorder in the webview → ElevenLabs STT (server-side call) → #3 | 25-second memo lands as a Note with transcript + `audio_ref`. Cut to text at C1 if behind | 1.5 |
| 5 | GoalRank + ranked list | Score known people vs. active goal with reason + evidence; `RelevantTo` materialized, rebuilt on change, deleted on close; days-since-contact shown, never scored; drafted opener per card | Same title alone doesn't rank high; a matching Intent does | 4 |
| 6 | GapFinder + gap alert | From the goal's RelevantTo set: which needed kind of person has no `known`/`route`? Raise an alert with *Ask my network* | "No warm path to climate-tech VC" on the seed data; no alert when a route exists | 2 |
| 7 | ScoreAgainstNeed + Introduction state machine | The one need/offer scorer, run over the caller's own root; deterministic exclusions first (dismissed, expired, `proposed` people); `Introduction` node with `proposed → reviewed → awaiting_permission → approved → draft_ready → sent` (+ declined/canceled/expired); `sent` unreachable this weekend | Complementary need↔offer scores high; shared employer alone doesn't | 3 |
| 8 | Exchange (cross-user) | Shared `Exchange` node (`root.shared`); `IntroRequest{need, from_handle, status, expires}`; friend's agent scores locally and posts a redacted `IntroReply{match_count, strength}`; approval → contact opt-in (click) → `allow_root(card, requester_root, ReadPerm)` → draft. **9 PM gate:** not working across accounts → Matchmaker (#7 in one graph) is the second act | Two accounts complete J4 end to end; the requester's root never contains a node from the friend's graph other than the granted card | 6 |
| 9 | Approval / intro cards | Gap alert; request card; friend's approval card (request, match, why); requester's reveal card + drafted intro; state chip; decline / not now | C2: full demo path on two phones | 3 |
| 10 | Mobile shell + hosting + live web | Capacitor target from the same `cl` bundle; backend hosted (Hammer sandbox first, VM fallback); HTTPS | App on two phones hits the hosted backend; URL opens on a laptop. PWA fallback Sun 8:00 | 3 (may balloon) |
| 11 | Seed data, video, Devpost, README | Pseudonymized seed (committed) + real (gitignored) + Jac loader; 2-minute video; writeup | Partial submission by 9:00 AM Sunday | 3 |

### Tier 1 — first additions, in order (pick top-down)

| # | Feature | Required behavior | Hrs |
|---|---|---|---|
| 12 | My card editor + public card page | Edit the drafted card; public page at `/card/<handle>` rendering only card fields; QR. `link` vs `handshake_only` visibility (`grant` vs `allow_root`) | 2 |
| 13 | Import all connections | LinkedIn data-export CSV, phone contacts, vCard → `Person(status=proposed)` with org/title; proposed `how_met` | 2 |
| 14 | "Sort your people" swipe confirm | Confirm/skip/edit proposed people; bulk-confirm by cluster | 3 |
| 15 | Enrich walker | Gemini + Search grounding; every Fact carries `source_url`; identity validated before attaching | 3 |
| 16 | Graph view | d3-force in `cl`; recorded solid / context thin / proposed dashed; size = goal relevance; website primary, phone secondary | 4 |
| 17 | QR handshake (J5) | Both scan; each gets the other's card as a `Person` + `FromCard` | 3 |
| 18 | "Here's what I noted" | Share your card-on-them for correction; corrections come back `self` | 2 |
| 19 | Receipts | Tap anything → the note span, clip, URL, or card it came from | 1.5 |
| 20 | Promise ledger | Today list + per-person; mark done | 1 |
| 21 | Forget | Delete a person/fact; retract solely-supported claims; invalidate RelevantTo/Introductions | 1 |
| 22 | Ask-your-graph | NL question → bounded traversal → answer with citations; "insufficient evidence" allowed | 3 |
| 23 | Fact freshness + intent expiry | Facts age; intents expire/reconfirm; stale facts flagged in explanations; card edits refresh intents | 1.5 |
| 24 | Card/badge photo | Gemini vision → Person | 2 |

### Tier 2 — differentiators, only after Tier 1 #12–#19

| # | Feature | Hrs |
|---|---|---|
| 25 | Call-in debrief: ElevenLabs conversational agent asks follow-ups, posts to Capture. The ElevenLabs prize play | 4 |
| 26 | PathFinder: warmest *evidenced* route; "no known route" allowed; shared employer is context, never a route | 3 |
| 27 | Duplicate merge: propose, confirm, undo | 3 |
| 28 | Reason-based tending (J6) | 2 |
| 29 | Pre-event game plan from a guest list | 3 |
| 30 | Broadcast an ask, and the reverse | 2 |
| 31 | Voice brief before a meeting (ElevenLabs TTS) | 2 |
| 32 | Network health: bridges, weak ties, echo-chamber share — of the user's own network, never a per-person score | 3 |
| 33 | Serendipity nudges | 3 |

### Tier 3 — stretch
Network replay slider · Name trainer · Organizer mode (attendees opt in; Matchmaker pairs the room; Community Favorite play).

### Part B — roadmap
Full both-party permission flow with real sending · Context capsules · Live-linked cards · Opt-in card directory · Multi-hop Exchange (friend-of-friend relays) · Permissioned connectors (contacts, calendar, email) · Small-gathering suggestions · Export/portability · Privacy hardening (encryption at rest, model-provider disclosure) · LinkedIn via the official Connections API only if approved · First-class relationship-assertion nodes.

## 8. Graph model

`server/schema.jac` is the source of truth (it type-checks). Summary:

**Nodes:** `Me`, `Person{name, org, title, status}`, `Note{text, kind, captured_at, audio_ref}`, `Fact{text, observed_at, valid_to, status, source_kind, source_url}`, `Interest`, `Goal{text, created_at, active}`, `Intent{kind: need|offer|open_to, text, expires_at, source_kind}`, `Promise{text, due, done}`, `Introduction{state, rationale_a, rationale_b, unknowns, share_preview, draft, approval_source}`, `Card{handle, headline, about, looking_for, can_offer, links, contact_pref, visibility, updated_at}`.

**Exchange (added in v0.3):** `Exchange` (one, under `root.shared`), `IntroRequest{need, from_handle, about_line, status, created_at, expires_at}`, `IntroReply{request_id, from_handle, match_count, strength, status}`. Replies carry no identity until the reveal.

**Edges (typed endpoints):** `Owns: Me→Card`, `Knows: Me→Person{how_met, last_contact, status, source_note}`, `Reported: Person→Person{source_note, span}`, `FromCard: Person→Card`, `Asserts / AssertsIntent / AssertsPromise / Mentions: Note→…{span}`, `FactAbout`, `IntentAbout`, `HasInterest`, `HasGoal`, `HasIntent`, `PromiseTo`, `Proposes: Introduction→Person`, `RelevantTo: Person→Goal{reason, strength, evidence, label}`, `Posted: Exchange→IntroRequest`, `RepliedTo: IntroReply→IntroRequest`.

**Provenance:** sources are `self` (card), `reported` (your note), `web` (Enrich, with URL). Self-asserted wins for what a person does and wants; your note wins for how you know them; conflicts keep both, show both.

**Freshness vs. relationship:** `Fact.observed_at` and `Intent.expires_at` age and expire. `Knows.last_contact` is displayed and may break ties within one goal's ranking; nothing reads it to lower anything.

**Unknown ≠ never met.** No edge between two people means unknown.

## 9. Walkers

All `walker:priv` on the caller's root unless noted. Names are ours, not built-in APIs.

| Walker | Starts at | Does | LLM |
|---|---|---|---|
| `OnboardMe` | Root | about-me → Me, Interests, Goals, self Intents, drafted Card | typed extraction |
| `Capture` | new Note | people, facts, intents, promises, reported ties; get-or-create people, preserve ambiguity | extract |
| `GoalRank` | Goal | visits every known Person (+1 hop Reported), writes RelevantTo, drafts openers | score_relevance, draft_opener |
| `GapFinder` | Goal | needed kinds of person with no known/route → gap alert → optional IntroRequest | find_gaps |
| `ScoreAgainstNeed` | Root | need/offer scoring over the caller's own graph; used by Matchmaker and by the Exchange reply | score_match |
| `Matchmaker` | Goal or Person | pairs from ScoreAgainstNeed → Introduction (fallback second act) | rationale, draft |
| `PostRequest` / `ReplyToRequest` / `ApproveReply` / `OptIn` / `Reveal` | Exchange | the J4 protocol; each step is a state transition on IntroRequest/IntroReply; Reveal does `allow_root(card, requester_root, ReadPerm)` and creates the new Person + Knows | draft_intro |
| `AdvanceIntroduction` | Introduction | state machine enforcement | — |
| `Recall`, `ImportPeople`, `Enrich`, `PublishCard`, `Handshake`, `Forget`, `Receipt` | Tier 1 | | |
| `PathFinder`, `Tend`, `Brief` | Tier 2 | | |

**Rules for all walkers:** explicit depth/result bounds, cycle-aware, permission-filtered *before* anything reaches the model or the client. AI proposes structured claims and drafts prose; deterministic Jac enforces ownership, evidence links, expiry, state transitions, grants, and dedup. Log the facts handed to the model. Pre-warm and cache GoalRank before the demo.

## 10. Matching, gaps, and the Exchange

Candidate generation: explicit topic overlap, need/offer complementarity, goal relevance, known ties. Deterministic exclusions before any ranking: dismissed pairs, expired intents, `proposed` people, missing identity confidence. No universal "probability of success."

**Gap definition:** a kind of person the goal needs (LLM-proposed from the goal text, e.g. "climate-tech VC") for which the goal's RelevantTo set has no `known` or `route` entry. A gap is a statement about *your* graph, never about a person.

**Exchange protocol state:** `IntroRequest.status`: `open → replied → approved → opted_in → revealed | declined | expired`. `IntroReply.status`: `pending → approved → opted_in → revealed | declined`. Every transition after `replied` requires a click from the person whose relationship it is. Requests expire after 7 days. A decline carries no reason across the boundary.

**Warmth is contextual, never global.** "Known collaborator," "unconfirmed route via Maya," "cold prospect for this goal." Never "warm lead." Redacted replies say `strong | medium | weak` about the *friend's* relationship to the match, as judged by the friend's own graph.

## 11. Architecture, stack, hosting

- **Toolchain, pinned:** jaclang 0.16.7, jac-client 0.3.25, byllm 0.6.19, jaseci 2.3.28 on **Python 3.12** (jac-client does not install on 3.11 — use `uv venv --python 3.12`). Scaffold: `jac create <name> --kind fullstack`. The compiler ships reference guides: **run `jac guide <name>` before writing any Jac** (`jac-core-cheatsheet`, `jac-node-edge-patterns`, `jac-walker-patterns`, `jac-by-llm`, `jac-sv-auth`, `jac-sv-multi-user`, `jac-cl-components`, `jac-cl-auth`, `jac-mobile-app`).
- **Language:** Jac full-stack. Server nodes/walkers compile to Python; `cl { }` blocks compile to JavaScript; walkers are HTTP endpoints called from the client with `root spawn`. Client `sv import`s must be awaited.
- **Cross-user primitives (verified in `jac guide jac-sv-multi-user`):** `grant(node, ReadPerm)` opens one node to all logged-in users; `Jac.allow_root(node, root_id, ReadPerm)` to one user; `root.shared` is the public commons. Per-node, not per-subtree — which is exactly the property the Exchange needs.
- **LLM:** Gemini through byLLM (`model_name="gemini/<model>"`, `GOOGLE_API_KEY`; pin in `jac.toml` `[plugins.byllm.model]`). LLM return types are `obj`s, never nodes; copy into nodes to persist.
- **Voice:** ElevenLabs STT from MediaRecorder, called server-side so the key never ships to the client. Conversational agent and TTS are Tier 2.
- **Mobile:** Capacitor target (`jac setup mobile`, `jac build --client mobile --platform ios|android`; confirmed in the installed CLI) wrapping the same bundle. Not the React Native/`@jac/mobui` target (no raw HTML → no d3). PWA fallback Sunday 8:00 AM.
- **Hosting:** Jac Hammer sandbox first; VM running `jac start` behind HTTPS as fallback (`jac guide jac-sv-deploy`). HTTPS is required for the mic on a phone. Decide by 15:30.
- **Frontend graph:** d3-force in a `cl` component; d3 config is the only non-Jac code allowed.

## 12. Data acquisition (the LinkedIn alternative)

1. LinkedIn data export (own data; Settings → Data privacy → Get a copy → Connections; ~10 min).
2. Phone contacts (Capacitor Contacts plugin); Google Contacts later.
3. Proposed `how_met` from export fields × user history, confirmed by swipe.
4. Paste anything — user-directed, not automated.
5. Enrich from the public web with a URL on every fact.
6. Their card, via the Exchange reveal or the QR handshake — self-asserted, consented, the best data in the system.
7. Card/badge photo.

Not done: automated fetching from any platform whose terms forbid it.

## 13. Privacy posture — what we're allowed to say

**True:** "Each user's graph is isolated by construction: it hangs off that user's root and walkers run on that root. An agent answering an Exchange request runs on its own owner's root and returns only a count and a strength until every person involved has approved. The only object that ever leaves an account is the card its owner wrote, granted read-only to one specific user. The model sees only the fields we send it."

**Not true, don't say it:** "private," "secure," "encrypted," "zero-knowledge." Roots and grants don't encrypt at rest or protect from the operator. Everything sent to Gemini or ElevenLabs leaves the server. Hardening is roadmap.

## 14. Build plan

**Split:** A owns `server/` (schema, all walkers, the Exchange protocol). B owns everything client-side, the mobile shell, hosting, voice, seed data, and the demo. Whoever is more comfortable in React takes B.

| When | A (server/) | B (client, shell, demo) | Gate / checkpoint |
|---|---|---|---|
| 14:15–15:00 | Contract review together; #1 isolation test; byLLM+Gemini hello | Contract review; onboarding screens (#2 UI) against mocks | Both: a walker returns data to a cl component |
| 15:00–15:30 | Sponsor block: credits | Sponsor block: Hammer hosting questions | Hosting + phone decided by 15:30 |
| 15:30–18:30 | OnboardMe (#2), Capture (#3) | Capture screen (#3), hosting (#10), ranked-list screen | |
| 18:30–19:30 | Dinner | | **C1:** a text debrief typed on a phone lands in the hosted graph |
| 19:30–21:00 | GoalRank (#5), GapFinder (#6) | Voice (#4), mobile shell (#10), gap-alert UI | |
| **21:00** | | | **9 PM gate:** can account B read a node account A granted? If not → Matchmaker fallback for the second act |
| 21:00–00:00 | ScoreAgainstNeed + state machine (#7), Exchange (#8) | Approval / reveal cards (#9), seed data (#11) | |
| 00:00–02:00 | | | **C2:** full demo path on two phones. **Features freeze 02:00** |
| 02:00–08:00 | Bug fixes, sleep in shifts | Bug fixes, polish, rough video | |
| 08:00–09:00 | Push, deploy check | Video, Devpost writeup | **Partial submission by 9:00** |
| 09:00–11:30 | Fixes only; freeze 11:00 | Rehearse 3× with a timer | **Final by 11:30**; noon hard stop |

**Cut order:** C1 behind → voice to text. 9 PM gate fails → Exchange becomes Matchmaker (same scorer, one graph). Sunday 8:00 → Capacitor to PWA. Never cut: capture with provenance, GoalRank, gap alert, hosted backend, two accounts.

**Jac-percentage guard:** cl UI, walkers, seed loader, and tests are all `.jac`; d3 config is the only JS. Run `scripts/jac_pct.sh` at 02:00 and before the partial submission.

## 15. Demo data policy

- Two real accounts on stage, real names for the two of us.
- Seed network: SK's real contacts and a scrubbed about-me, so "who did you build this for" gets answered with the phone. The on-stage memo is about a judge or mentor met today, with their OK; pre-recorded backup file.
- **The repo is public and will be checked.** Committed seed = pseudonymized (fictional names, real-shaped roles, interests, needs/offers; two people with the same first name; at least three complementary need↔offer pairs; at least one goal with a deliberate gap). Real seed lives in a gitignored file. Never commit real people's facts.
- Request the LinkedIn connections export now.

## 16. Submission checklist

- [ ] GitHub link; ≥40% Jac; all commits inside hacking hours
- [ ] Demo video (≤2 min, §6)
- [ ] Written description: problem → four-step loop → why Jac (graph, walkers, `by llm`, per-user roots + grants) → what's next
- [ ] Star github.com/jaseci-labs/jac
- [ ] Hosted URL in the writeup
- [ ] Devpost tracks: Agentic AI; special awards: Best Mobile through Jac, Best Jaclang, Best JacHammer, Best of Google; Best of ElevenLabs only if #25 or #31 shipped
- [ ] Partial by 9:00 AM Sunday; final by 11:30 AM

## 17. Risks

| Risk | Likelihood | Response |
|---|---|---|
| Cross-user grants take longer than planned | High | 9 PM gate; Matchmaker fallback uses the same scorer; disclose which act we're showing |
| Jac learning curve | High | `jac guide` before every file; keep code simple; pair at 15:00 if either is stuck |
| Slow LLM calls on stage | Medium | Pre-warm; cache GoalRank; screen recording backup |
| Room noise ruins the live memo | Medium | Pre-recorded memo file |
| Judges see it as creepy | Medium | No scraping; memos are yours, never secret recordings; "a human approves every hop"; the only thing that crosses accounts is a card its owner wrote |
| Jac below 40% | Low | UI in cl; d3 config only; check at 02:00 |
| Scope creep | High | §7 is the contract; new ideas go to Part B |
| Mobile build eats an evening | Medium | PWA fallback at 8:00 AM |

## 18. Open items

| Item | Owner | Decide by |
|---|---|---|
| Hosting: Hammer sandbox (persistence, cl bundle, HTTPS, domain) vs VM | B | 15:30 |
| Stage phone: iPhone (Xcode, signing) vs Android | both | 15:30 |
| Gemini + ElevenLabs credit links from Discord | A | 15:30 |
| Who is A / who is B | both | now |
| Teammate consents to being named in the demo and video | both | now |
| Cirql as the shipped name (working name now) | both | before video |

## 19. Provenance

- Vision, three questions, principles, journeys, acceptance examples, graph model, matching rules, state machine, risk list: PRD v0.1.
- Feature ideas, hour estimates, prize mapping, Jac-first framing: feature-list session.
- Four-step loop, gap alert, Exchange protocol and rules, demo hook and close, 9 PM gate, 2 AM freeze, backups, risks table, job-to-be-done wording: Tether PRD (Jesse, Sept 26, 2026). Rejected from it: warmth decay, facts-as-strings, team-of-4 scope, cards-to-roadmap.
- Jac facts: the installed toolchain's `jac guide` output and docs.jaseci.org, Sept 26, 2026.
- Event rules: JacHacks UMich Hacker Guide.
- Decisions on scope, decay, ranking, mobile, hosting, data, scraping, cards, second act, name: SK, this session.
