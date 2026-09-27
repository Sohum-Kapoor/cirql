# Walker contract

**Append-only.** Every walker the client calls, with its inputs and the exact shape
it `report`s. A builds walkers that emit these; B builds screens against
`components/mocks/` that match them. Changes are appended as a dated line at the
bottom and announced on Linear SOH-160.

Wire format (verified live on jaclang 0.16.7): `POST /walker/<Name>` with a JSON body
of the walker's `has` fields and `Authorization: Bearer <token>` →
`{"ok": true, "data": {"reports": [...]}}`. In `.cl.jac`: `result = root spawn Name(...)`,
then `result.reports`. Node reports arrive as objects with the node's `has` fields
plus `_jac_id` (use as the id everywhere below).

All ids are `jid` strings. All timestamps are ISO-8601 strings. All walkers are
`:priv` (JWT required, run on the caller's root) unless marked `:pub`.

---

## Smoke / read (exist in `walkers.sv.jac` now)

| Walker | Input | Reports |
|---|---|---|
| `Ping` | — | `["ok"]` |
| `GetMe` | — | `[Me]` or `[]` |
| `ListPeople` | — | `[Person, ...]` (Me →Knows→ Person) |
| `ListGoals` | — | `[Goal, ...]` |

## Tier 0

### `OnboardMe(about: str)` — SOH-164
Reports one object:
```
{ me: Me, interests: [Interest], goals: [Goal], intents: [Intent], card: Card,
  note_id: str }
```
Idempotent: a second call updates rather than duplicates Me/Card.

### `Capture(text: str, kind: str)` — SOH-166
`kind` ∈ `debrief | paste`. Reports one object; every item carries provenance:
```
{ note_id: str,
  people:   [{ person: Person, is_new: bool, ambiguous_with: [person_id] }],
  facts:    [{ fact: Fact, about: person_id, span: str }],
  intents:  [{ intent: Intent, about: person_id, span: str }],
  promises: [{ promise: Promise, to: person_id, span: str }],
  ties:     [{ from: person_id, to: person_id, span: str }] }
```
A failed extraction still reports `{ note_id, people: [], ... }` — the note is never lost.

### `Transcribe` — SOH-168 (B, server-side `def:priv`)
`def:priv transcribe(audio: UploadFile) -> { transcript: str, audio_ref: str }`. Client then calls `Capture(text=transcript, kind="debrief")`.

### `GoalRank(goal_id: str)` — SOH-169
Rebuilds the goal's `RelevantTo` edges. Reports, ordered best-first:
```
[{ person: Person, label: "known"|"route"|"cold", strength: "high"|"med"|"low",
   reason: str, evidence: [{ id: str, kind: "note"|"fact"|"intent"|"card", observed_at: str, span: str }],
   days_since_contact: int | null, opener: str }]
```
`days_since_contact` is display only and may break ties; it is never a score input.

### `SetGoal(text: str)` / `CloseGoal(goal_id: str)` — SOH-169
`SetGoal` reports `[Goal]` (deactivates others). `CloseGoal` reports `["closed"]` and deletes that goal's `RelevantTo` edges.

### `GapFinder(goal_id: str)` — SOH-203
```
[{ kind: str, why_needed: str, has_path: false, suggested_need: str }]
```
Empty list = no gaps. Never names a person.

### `ScoreAgainstNeed(need: str, exclude_handles: [str])` — SOH-171
Over the caller's own root only:
```
[{ person_id: str, strength: "strong"|"medium"|"weak", why: str, evidence_ids: [str] }]
```

### `Matchmaker(goal_id: str = "", person_id: str = "")` — SOH-171 (fallback second act)
```
[{ introduction: Introduction, a: Person, b: Person,
   evidence: [{ id, kind, observed_at, span }], already_know_each_other: bool | null }]
```

### `AdvanceIntroduction(intro_id: str, to_state: str, approval_source: str = "")` — SOH-171
Reports `[Introduction]` with the new state, or reports `{ error: "invalid_transition", from: str, to: str }`.

### Exchange — SOH-205
| Walker | Input | Reports |
|---|---|---|
| `PostRequest(need, about_line)` | from a gap | `[IntroRequest]` (status `open`) |
| `ListIncomingRequests` | — | `[IntroRequest]` posted by others, not yet replied by me |
| `ReplyToRequest(request_id)` | friend's phone | `[IntroReply]` — `match_count`, `strength`, **no identity** |
| `ListMyRequests` | — | `[{ request: IntroRequest, replies: [IntroReply] }]` |
| `ListMyReplies` | friend's phone | `[{ request: IntroRequest, reply: ReplyView, why: str }]` — friend's OWN replies, newest first |
| `ApproveReply(reply_id)` | friend clicks | `[IntroReply]` (status `approved`) |
| `OptIn(reply_id)` | friend clicks (stands in for the contact) | `[{ reply: IntroReply, opt_in_draft: str }]` |
| `Reveal(reply_id)` | friend's side completes | `[{ reply: IntroReply, revealed_card_handle: str }]` |
| `ClaimReveal(reply_id)` | requester's side | `[{ person: Person, card: Card, intro_draft: str }]` — creates Person + Knows{how_met="intro via <friend>"} in the requester's graph |
| `Decline(id)` | either side | `["declined"]` — no reason crosses |

## Tier 1 (shapes to be appended when picked up)

`PublishCard`, `get_card(handle)` (`:pub`, card fields only), `ImportPeople`,
`ConfirmPerson`, `SkipPerson`, `Enrich`, `Handshake`, `Recall`, `Forget`,
`Receipt`, `ListPromises`, `CompletePromise`, `DraftFollowUp`, `GraphView`.

---

## Change log
- 2026-09-26 14:20 — v1, from PRD v0.3.
- 2026-09-26 15:10 — v1.1, contract review decisions (SOH-160; approved by SK + Jesse). Each line supersedes the matching text above:
  1. **One `strength` enum project-wide: `strong | medium | weak`.** `GoalRank` reports `strength: "strong"|"medium"|"weak"` (was high/med/low). `RelevantTo.strength` in the schema changed to match.
  2. **Redacted reply view.** `ReplyToRequest`, `ListMyRequests`, `ApproveReply`, `OptIn`, `Reveal` report a `ReplyView` object, never the raw `IntroReply` node: `{ _jac_id, request_id, from_handle, match_count, strength, status }`. `match_person_id` never leaves the friend's root.
  3. **`AdvanceIntroduction`** always reports `[{ ok: bool, introduction: Introduction | null, error: str | null, from: str, to: str }]` (`error` = `"invalid_transition"` when `ok` is false).
  4. **`Decline(id)` is split** into `DeclineRequest(request_id: str)` and `DeclineReply(reply_id: str)`, both report `["declined"]`.
  5. **`CloseGoal`** sets `Goal.active = False`, deletes that goal's `RelevantTo` edges, never deletes the node. `ListGoals` reports every goal with its `active` field; the client filters.
  6. **`GapFinder`** drops `has_path`; shape is `[{ kind, why_needed, suggested_need }]`.
  7. **`Capture.ambiguous_with`** is report-only, recomputed per call; the duplicate candidate is created as `Person(status="proposed")`. No schema change.
  8. **Evidence.** `evidence: [{ id, kind: "note"|"fact"|"intent"|"card", observed_at, span }]` is rebuilt at report time (dates normalized into `observed_at` from `Fact.observed_at`, `Note.captured_at`, `Card.updated_at`; Intents use their Note's `captured_at`). Schema: `RelevantTo.evidence` is now `list[str]` of jids and `RelevantTo.opener: str` caches the drafted opener. Reported shape unchanged.
  9. **Exchange wording.** The Exchange on `root.shared` carries `need`, `about_line`, `from_handle` and never a name from anyone's graph; the only graph object that crosses accounts is a Card via `allow_root`. AGENTS.md wording amended.
  A-side notes, no shape change: `Introduction.state` keeps `sent` in the enum, unreachable this weekend; `Reveal` performs the `allow_root`, `ClaimReveal` reads the granted Card; Fact/Intent/Promise provenance is the incoming `Asserts*` edge with `span`; `OnboardMe` creates `Note(kind="about_me")`; `PostRequest` requires the caller to own a Card and uses its handle; `Matchmaker.already_know_each_other` = a `Knows` or `Reported` edge exists between the two.
- 2026-09-26 15:10 — added `DevAddPerson(name: str, me_name: str = "me")` → `[Person]`; dev/test helper only, get-or-creates Me and attaches a Person via Knows. Not for the client.
- 2026-09-26 — SOH-178 `PublishCard` + `get_card`, the only public read.
  `PublishCard(headline: str = "", about: str = "", looking_for: list[str] = [], can_offer: list[str] = [], links: list[str] = [], contact_pref: str = "", visibility: str = "link", name: str = "")` (`walker:priv`) → `[Card]`. Get-or-creates the caller's Me/Card; only non-empty arguments overwrite fields, `visibility` is always applied (`link` | `handshake_only`, else reports `[{error: "bad_visibility"}]`). `link` grants the Card `ReadPerm` to every user and lists it under the shared `CardDirectory`; `handshake_only` unlists it and `revoke()`s the grant.
  `get_card(handle: str)` (`def:pub` — no JWT, served at `POST /function/get_card`) → `{ found: bool, name, handle, headline, about, looking_for, can_offer, links, contact_pref, updated_at }`. Card fields only — never `visibility`, `_jac_id`, or anything else off the Card node — and `found: false` with empty fields when no `link`-visible card matches the handle (including a `handshake_only` card, enforced inside `get_card` itself, not only by the grant). Schema: adds `node CardDirectory` (one, under `root.shared`) and `edge Lists: CardDirectory --> Card {}`.
- 2026-09-26 16:20 — SOH-186/187/185, `reads.sv.jac` lands. All four are `:priv`, own-root only, no LLM.

### `Receipt(id: str)` — SOH-186
Reports one object:
```
{ kind: "note"|"fact"|"intent"|"promise"|"person"|"card"|"goal", id: str, text: str,
  source_note_id: str, span: str, note_text: str, captured_at: str,
  source_kind: str, source_url: str }
```
or `{ error: "not_found" }` — for an unknown id, an id that resolves but isn't readable, or an id that resolves and is readable but is owned by a different root (e.g. a Card allow_root'ed to us via Exchange: Receipt never surfaces another account's data even when it's grantable-readable). `text` is the node's own text/name/handle; empty strings where a field doesn't apply to that kind. Fact/Intent/Promise carry the asserting Note's id/text/captured_at and the `Asserts*` edge's span; Person prefers its own `Mentions` edge span, else falls back to its `Knows` edge's `source_note`; Note reports itself; Card reports `source_kind: "self"`, no note; Goal reports text only.

### `ListPromises()` — SOH-187
```
[{ promise: Promise, to: Person | null, source_note_id: str, span: str }]
```
Open (`done == False`) first, ordered by `due` ascending with `""` last; then done ones (same due ordering within the group).

### `CompletePromise(promise_id: str, done: bool = True)` — SOH-187
Reports `[Promise]`, or `[{ error: "not_found" }]` for an unknown/unowned id (same ownership rule as `Receipt`).

### `GraphView(goal_id: str = "")` — SOH-185
Reports one dict:
```
{ nodes: [{ id: str, kind: "me"|"person"|"goal", label: str, status: str, org: str, title: str }],
  edges: [{ from: str, to: str, kind: "knows"|"reported"|"relevant_to", label: str, strength: str }] }
```
Nodes: Me, every `Knows` Person (capped at 300), and the chosen Goal (the given `goal_id` if it matches one of the caller's goals, else the caller's active goal, else no goal node at all — no goal, no `relevant_to` edges). Edges: every `Knows` (`label` = `how_met`, `strength` = `Knows.status`), every `Reported` between two included people (`label` = `"reported"`, `strength` = `""`), every `RelevantTo` into the chosen goal (`label`/`strength` copied off the edge).
- 2026-09-26 — SOH-180 (server half of SOH-181): `ImportPeople`, `ConfirmPerson`, `SkipPerson` land in `imports.sv.jac`. LinkedIn export / phone contacts / vCard rows are parsed CLIENT-side into `list[dict]` rows; these walkers only ever see `{ name, org, title, how_met, email }` per row (unknown keys ignored, `email` stored nowhere this weekend).
  - **`ImportPeople(rows: list[dict], source: str = "csv")`** reports one dict:
    ```
    { note_id: str,
      imported: [{ person: Person, is_new: bool }],
      skipped:  [{ name: str, reason: "empty_name"|"duplicate_in_batch"|"over_limit" }] }
    ```
    Get-or-creates Me; creates one `Note(kind="import", text=f"Imported {n} people from {source}")`. Per row with a non-empty stripped name: deduped within the batch by lowercase name (a later duplicate row is `skipped` with `"duplicate_in_batch"`, never creates a second person); reuses an existing `[me ->:Knows:->]` person with the same lowercase name (`is_new=false`, `status`/`org`/`title` never overwritten except filling org/title when they were empty) or creates `Person(status="proposed")` with a `Knows(status="proposed", how_met=how_met or f"imported from {source}", source_note=jid(note))` edge (`is_new=true`). Every imported person (new or reused) gets one `Note +>:Mentions(span=name):+> Person` edge from this call's note. Bounded at 500 rows per call; rows past the bound are `skipped` with reason `"over_limit"` and never touch the graph.
  - **`ConfirmPerson(person_id: str, how_met: str = "")`** → `[Person]` with `status="confirmed"` and the matching `Knows` edge `status="confirmed"` (`how_met` overwritten only when non-empty); `[{ error: "not_found" }]` when `person_id` is not a `[me ->:Knows:->]` person of the caller.
  - **`SkipPerson(person_id: str)`** → `["skipped"]`: only when the person is `status="proposed"` — deletes the caller's `Knows` edge to them, their `Mentions` edges, and the `Person` node. `[{ error: "not_proposed" }]` on a confirmed person; `[{ error: "not_found" }]` when unknown.
- 2026-09-26 — SOH-191/189, `drafts.sv.jac` (`DraftFollowUp`) and `recall.sv.jac` (`Recall`) land. Both `:priv`, ONE `by llm` call each (wrapped in `try/except`; deterministic fallback always available — Gemini's daily quota was exhausted at write time, so both were verified fallback-only), never read `Knows.last_contact`, nothing sends.

### `DraftFollowUp(person_id: str, intent: str = "")` — SOH-191
Reports one entry:
```
[{ person_id: str, draft: str,
   based_on: [{ id: str, kind: "note"|"fact"|"intent"|"promise", observed_at: str, span: str }],
   fallback: bool }]
```
or `[{ error: "not_found" }]` when `person_id` isn't one of the caller's own `[me ->:Knows:->]` people. Evidence: the person's Facts, their non-expired Intents, their OPEN Promises (`PromiseTo`, `done == False`), and Notes mentioning them — merged newest-first by `observed_at`, capped at 8. `intent` is optional context for the LLM (what the user wants the message to do); the deterministic fallback never reads it. Fallback (`fallback: true`) picks, in order: the newest open Promise (draft mentions its text; `based_on` = that promise, plus the newest Fact if one exists) → the newest Fact/Intent (draft mentions its text) → a generic "good meeting you" opener (`based_on: []`) when there's no evidence at all.

### `Recall(question: str, max_items: int = 40)` — SOH-189
Reports one dict:
```
{ answer: str,
  citations: [{ id: str, kind: "note"|"fact"|"intent"|"promise", observed_at: str, span: str, person: str }],
  insufficient: bool, fallback: bool }
```
Bounded traversal over the caller's own root: every Note (text capped at 300 chars), Fact, Intent, and Promise, each paired with its about-person's name where one applies, newest-first, capped at `max_items`. Deterministic pre-filter: keep items sharing a lowercase, non-stopword, length-≥4 token with the question; zero matches short-circuits straight to `{ answer: "Insufficient evidence in your notes.", citations: [], insufficient: true, fallback: true }` without spending the one `by llm` call; 1–2 matches widen to the newest 12 items in the whole pool (too few to answer from confidently, not nothing); 3+ matches use the strict set as-is. Fallback (`fallback: true`) otherwise: `"Your notes mention: "` + the top 3 selected items formatted `"{person}: {span} ({observed_at})"`, `insufficient: false`, `citations` = those 3. On the LLM path, an empty `answer` or empty `citation_indices` without the model itself claiming `insufficient` is forced to the same canonical insufficient response server-side (never invents, never silently returns nothing).
- 2026-09-26 — SOH-190/188, `freshness.sv.jac` + `forget.sv.jac` land. All five walkers below are `:priv`, own-root only, no LLM. Relationships still never decay — nothing here touches `Knows`; only `Fact.status`/`Fact.valid_to` and `Intent.expires_at` are ever written by `freshness.sv.jac`, and `forget.sv.jac` is the one walker that actually deletes graph data (a stale Fact is flagged, never deleted automatically; an expired Intent is only ever listed). Schema: no changes — `Fact.status`/`valid_to` and `Intent.expires_at` already existed; this just gives them a reader and a writer.

  ### `FreshnessSweep(stale_after_days: int = 180)` — SOH-190
  Reports one dict:
  ```
  { stale_facts: [Fact], expired_intents: [Intent], checked_facts: int, checked_intents: int }
  ```
  Every Fact reachable from the caller's own Notes (`Note ->:Asserts:-> Fact`, deduped by jid) with `status != "stale"` and either a non-empty `valid_to` in the past or `observed_at` older than `stale_after_days` gets `status = "stale"` and is listed in `stale_facts` (never deleted — a stale fact is flagged, the user corrects it). Every Intent reachable via `Note ->:AssertsIntent:-> Intent` or `Me ->:HasIntent:-> Intent` (deduped by jid) whose `expires_at` is non-empty and already past is listed in `expired_intents` (never mutated — `GoalRank`'s `gather_evidence` already skips it). An unparsable date is skipped, never flagged. Idempotent for facts: a fact already `status == "stale"` is skipped on a later sweep (still counted in `checked_facts`); an expired intent has no such durable flag and is relisted every sweep until reconfirmed.

  ### `ReconfirmFact(fact_id: str, valid_to: str = "")` — SOH-190
  Reports `[Fact]` with `status = "confirmed"`, `observed_at` bumped to now, and `valid_to` overwritten when given (left alone otherwise); `[{ error: "not_found" }]` for an unknown id or one owned by a different root (same ownership rule as `Receipt`).

  ### `ReconfirmIntent(intent_id: str, expires_at: str = "")` — SOH-190
  Reports `[Intent]` with `expires_at` set to the given value, or `default_expiry(kind, now)` when none is given (`need` → +90 days, `offer`/`open_to` → +180 days, same ISO-8601 shape as `datetime.now().isoformat()`); `[{ error: "not_found" }]` as above. `default_expiry` also now backfills an empty `expires_at` on every Intent `capture.sv.jac`/`onboard.sv.jac` create.

  ### `Forget(id: str)` — SOH-188
  Reports one dict:
  ```
  { deleted: "person"|"fact"|"intent"|"promise", id: str,
    retracted: { facts: int, intents: int, promises: int, edges: int, introductions_canceled: int, relevant_to: int } }
  ```
  or `[{ error: "not_found" }]` for an unknown id, one owned by a different root, or any node kind other than Person/Fact/Intent/Promise. **Person**: deletes every Fact/Intent/Promise whose ONLY `FactAbout`/`IntentAbout`/`PromiseTo` target is this person (their `Asserts*`/`*About` edges go with them); a Fact/Intent/Promise about this person AND someone else survives, keeping its edge(s) to whoever else it's about. Deletes the person's `Mentions`, `Knows`, and `Reported` (both directions) edges and its `RelevantTo` edges (counted in `edges` and `relevant_to` respectively); every `Introduction` with a `Proposes` edge to them gets `state = "canceled"` (counted in `introductions_canceled`, never deleted); then deletes the Person node. **Fact/Intent/Promise**: deletes the node (its asserting `Asserts*` edge and its `*About`/`PromiseTo` edge(s) go with it, counted in `edges`) and prunes its jid out of every `RelevantTo.evidence` list it appears in under the caller's root (counted in `relevant_to`). The Note (the receipt) is never touched, never deleted, in either case.
- 2026-09-26 — SOH-169 `GoalRank(goal_id, refresh=False)`: serves the materialized RelevantTo ranking without a model call when edges exist; `refresh: true` rebuilds; entries carry `cached: bool`.
- 2026-09-26 — SOH-205 reply persistence (hosted bug: A's `ListMyRequests` showed `replies: []` after B replied). **No shape change**: `ReplyView` is still `{ _jac_id, request_id, from_handle, match_count, strength, status }`; `Reveal` still reports `{ reply: ReplyView, revealed_card_handle }`; error codes unchanged. Storage only:
  - `IntroReply` now hangs under `root.shared` (still owned by the friend, `allow_root`'ed read-only to the requester). `ListMyRequests` finds replies there by `request_id`; the `RepliedTo` edge is still written but nothing reads it.
  - `IntroReply` loses `match_person_id` / `revealed_card_id` and gains `revealed_card_handle` (set at `Reveal`). The friend's private ids move to a new `node ReplyPrivate { reply_id, match_person_id, revealed_card_id }` under the FRIEND's root.
  - `Reveal` also lists the revealed Card in the shared `CardDirectory` (listing is not granting; `get_card` still refuses `handshake_only`). `ClaimReveal` finds the Card there by `revealed_card_handle`, owned by the replying friend and readable by the caller.
  - Shared containers (`root.shared`, `Exchange`, `CardDirectory`) are now traversed untyped and filtered with `isinstance`, so requests posted by a user who did not create the `Exchange`, and cards listed by a user who did not create the `CardDirectory`, survive a restart.
- 2026-09-26 — SOH-183, `handshake.sv.jac` lands: the QR handshake, the consented two-sided Card exchange across accounts (PRD J5 / Tier 1 #17). All four walkers are `:priv`, no `by llm`. One `HandshakeOffer` per scan, hung directly off `root.shared` (no container node), ambient `grant(..., ReadPerm)` so both parties can read it. A "signal" HandshakeOffer (status `accepted`/`declined` answering a still-`offered` reversed counterpart) is never listed as its own entry — only the requester-derives-status-lazily idiom (from `exchange.sv.jac`) applies it as an override to the primary offer. Schema: adds `node HandshakeOffer` (`from_handle`, `to_handle`, `status` = `offered | accepted | declined | expired`, `created_at`, `expires_at`), under root.shared. `cards.sv.jac`: `PublishCard` now lists the Card in the shared `CardDirectory` for BOTH visibilities (`get_card`'s own `visibility == "link"` check is what protects a `handshake_only` card; unlisting was never the actual protection) — a handshake needs the OTHER side's handshake_only card to be findable by handle before either side has granted anything.

  ### `OfferHandshake(to_handle: str)` — SOH-183
  Reports `[{ offer_id: str, to_handle: str, status: "offered" }]`, or `[{error: "no_card"}]` (caller has no Card), `[{error: "not_found"}]` (no Card with that handle in the shared CardDirectory, any visibility), `[{error: "self"}]` (`to_handle` is the caller's own handle). Grants the caller's own Card `ReadPerm` to the target's root (`Jac.allow_root`) so the target can read it once they act; an identical `offered` pair already posted by the caller is returned as-is, never duplicated.

  ### `ListHandshakes()` — SOH-183
  Reports `[{ offer_id: str, from_handle: str, to_handle: str, status: str, direction: "incoming"|"outgoing", person_id: str }]`. Every `HandshakeOffer` under `root.shared` touching the caller's handle, expired ones skipped. Lazy materialization: an OUTGOING offer whose counterpart has posted a reciprocal "accepted" signal gets `status: "accepted"` and — first call only, idempotent thereafter — creates `Person(status="confirmed")` + `Knows(how_met="handshake", status="confirmed")` + best-effort `FromCard` (falls back to a `card:<handle>` marker on the Knows edge's `source_note` when the cross-root edge attach is silently denied — only `ReadPerm`, not `ConnectPerm`, was ever granted) + one `Fact` (`source_url="card:<handle>"`) when `card.about` is non-empty; `person_id` is set once materialized. A "declined" signal on an INCOMING offer hides that whole pair from the decliner's own list; the original sender's side keeps seeing `"offered"` until it expires — no reason ever crosses back to them.

  ### `AcceptHandshake(offer_id: str)` — SOH-183
  Reports `[{ person: Person, card: Card }]`, or `[{error: "no_card"|"not_found"|"invalid_state"|"forbidden"}]`. Offer must be addressed to the caller's handle and still `"offered"`, and the caller must not have already responded (accepted or declined) to that same pair. Materializes the Person/Knows/FromCard/Fact immediately (same shape as `ListHandshakes`'s lazy path), grants the caller's Card back to the offerer's root, and posts a reciprocal `HandshakeOffer(status="accepted")` — the accepter cannot write the original offer's own `status` field.

  ### `DeclineHandshake(offer_id: str)` — SOH-183
  Reports `["declined"]`, or `[{error: "no_card"|"not_found"|"invalid_state"}]`. An offer addressed to the caller posts a reciprocal `HandshakeOffer(status="declined")` (no reason crosses); the caller's own outgoing offer has its `status` flipped directly (they own it).

  Gotchas surfaced fixing this (see AGENTS.md): typed traversals into a container other users attach to (`root.shared`, the `CardDirectory`) can silently miss cross-owner edges after a restart — use `[x for x in [n -->] if isinstance(x, T)]`, proven here with a real two-process `jac start` restart test; a denied `edge_write` (target granted only `ReadPerm`, not `ConnectPerm`) is a SILENT no-op — no exception, just a log line — so `get_or_create_person_from_card` verifies the `FromCard` edge actually landed (untyped traversal from the node the caller owns) before trusting it, rather than trusting a bare `try/except`.
- 2026-09-26 — SOH-200, `health.sv.jac` (`NetworkHealth`) lands: the shape of the caller's OWN network (PRD Tier 2 #32) — bridges, weak ties, echo-chamber share. `:priv`, own-root only, no `by llm`, fully deterministic. Never a per-person score: every field describes the graph as a whole. Never reads `Knows.last_contact`. Schema: no changes.

  ### `NetworkHealth()` — SOH-200
  Reports one dict:
  ```
  { people: int, confirmed: int, proposed: int, ties: int,
    clusters: [{ label: str, size: int, sample: [str] }],
    bridges: [{ person: Person, connects: [str] }],
    weak_tie_share: float, echo_share: float,
    notes: [str] }
  ```
  `people`/`confirmed`/`proposed` = the caller's own `[me ->:Knows:->]` people, split by `Person.status`. Graph G (this walker's own definition, distinct from `PathFinder`'s route graph) = every `status == "confirmed"` known person as a node, every `Reported` edge between two such nodes read as ONE undirected tie regardless of which direction it was recorded in (`ties` = that count). `clusters` = connected components of G with size >= 2, labeled by the most common non-empty `org` in the component (ties broken alphabetically; "unlabeled" when nobody in the component has an org), `sample` = up to 3 names from the component, largest components first, capped at 8. `bridges` = articulation points of G (a person whose removal splits their component into >= 2 pieces), `connects` = the resulting pieces' labels (same labeling rule as `clusters`, computed per piece), capped at 10. `weak_tie_share` = share of confirmed people with no Reported tie to anyone else in G (isolated), rounded to 2 decimals. `echo_share` = share of confirmed people whose `org` equals the single most common org across ALL confirmed people (not just those with a tie), rounded to 2 decimals, `0.0` when nobody has an org. `notes` = up to 3 plain, deterministic sentences derived from the numbers above (one each, in this order, only when the underlying metric is non-zero/non-empty: the `weak_tie_share` sentence, the `echo_share` sentence, one bridge's two-cluster sentence) — never a sentence that ranks or scores a person. No known people at all → the all-zero/empty shape (`clusters`/`bridges`/`notes` all `[]`, shares `0.0`). `main.jac`: `import from health { NetworkHealth }`.
- 2026-09-26 — SOH-196, `tend.sv.jac` (`Tend`) lands: reason-based nudges, no timers, no decay (PRD J6). `:priv`, own-root only, no `by llm`. Never reads `Knows.last_contact` to decide inclusion or rank anything except its own `newly_relevant` block's display order — a stale `last_contact` alone, with no other reason, produces no nudge. Schema: no changes.

  ### `Tend(limit: int = 8)` — SOH-196
  Reports, most-actionable-first, capped at `limit`:
  ```
  [{ kind: "open_promise"|"expiring_intent"|"newly_relevant"|"stale_fact",
     person: Person | null,
     reason: str,
     evidence: { id: str, kind: "promise"|"intent"|"fact"|"note", span: str, observed_at: str },
     suggested_action: str,
     days_since_contact: int | null }]
  ```
  Fixed block order (never a global sort across kinds): (1) every OPEN promise (`done == False`) made to a known person, `due` ascending with `""` due last, `reason` = `"You promised {name}: {text}"` (+ `" (due {due})"` when set), `suggested_action` = `"Send it"`; (2) every Intent about a known person whose `expires_at` is set, parseable, and within the next 14 days inclusive (`0 <= days_until <= 14`; already-expired is `FreshnessSweep`'s concern, not surfaced here), soonest first, `reason` = `"{name}'s {need|offer|interest} '{text}' expires in {N} days"`, `suggested_action` = `"Reconfirm or let it lapse"`; (3) at most 3 people with a `strength == "strong"` `RelevantTo` edge on the caller's ACTIVE goal (gathered from the goal, so a "route"/"cold" candidate with no direct `Knows` edge from the caller is still eligible), ordered by `days_since_contact` descending with `null` first (display only), `reason` = `"{name} is a strong match for your goal '{goal text}'"`, `suggested_action` = `"Reach out (use the drafted opener)"`, evidence = the first jid off the edge's own `evidence` list that still resolves (via `goals.sv.jac`'s `evidence_item_from_jid`) — `materialize` guarantees a `"strong"` edge always has at least one; (4) at most 2 Facts with `status == "stale"` about a known person, oldest `observed_at` first, `reason` = `"A fact about {name} is stale: '{text}' (observed {observed_at})"`, `suggested_action` = `"Reconfirm or forget"`. The whole ordered list (blocks 1–4 concatenated, blocks 3–4 already capped) is then truncated to `limit`. No active goal → block 3 is empty; no qualifying items in a block → that block is empty; no `Me` yet → `[]`.
- 2026-09-26 — SOH-166: `Capture.people[]` entries now `{ person, is_new, ambiguous_with, span }`; span = the Mentions span (verbatim substring of the note, else the name).
- 2026-09-26 — SOH-168, `voice.sv.jac` lands: server-side ElevenLabs speech-to-text so the key never ships to the client. `:priv`, own-root only, no `by llm`, no graph writes at all — doesn't create a `Note`; the client still calls `Capture(text=transcript, kind="debrief")` itself with the returned transcript. Schema: no changes.

  ### `Transcribe(audio_b64: str, mime: str = "audio/mp4")` — SOH-168
  Reports one entry:
  ```
  [{ transcript: str, audio_ref: str, duration_ms: int, error: str }]
  ```
  Decodes `audio_b64`, caps it at 15 MB (`error: "too_large"`, `transcript: ""`, `audio_ref: ""` — nothing written to disk), else picks an extension from `mime` (`audio/mp4`→`.m4a`, `audio/webm*`→`.webm`, `audio/wav`→`.wav`, `audio/mpeg`→`.mp3`, else `.bin`; client audio is `audio/mp4` AAC from Safari/iOS or `audio/webm;codecs=opus` from Chrome — never transcoded) and writes the bytes to `uploads/<jid(root)>/<uuid>.<ext>` relative to the cwd (`audio_ref` = that relative path; the directory is created as needed; nothing under `uploads/` is ever served). POSTs to `https://api.elevenlabs.io/v1/speech-to-text` (`xi-api-key` header, multipart `file` + `model_id=scribe_v1`, `timeout=60`); `transcript` = the response's `"text"` field. `duration_ms` is always `0` (unknown — `scribe_v1`'s response doesn't carry it). Key comes from `os.environ.get("ELEVENLABS_API_KEY", "")`, never logged; missing key → `error: "no_key"`, `transcript: ""`, but `audio_ref` is still set — the audio itself is not lost, the client can retry later or let the user type the note. A non-2xx ElevenLabs response → `error: f"stt_{status}"`. `uploads/` is gitignored.
- 2026-09-26 — SOH-168: `Capture(text, kind, audio_ref: str = "")` — pass `Transcribe`'s `audio_ref` so the stored Note carries it (`Note.audio_ref`). Shape unchanged.
- 2026-09-26 — SOH-198, `reverse.sv.jac` (`WhoNeedsWhatIHave`) lands: the reverse ask (Tier 2 #28) — `PostRequest` (exchange.sv.jac) broadcasts a need; this answers "who out there needs what I have?". `:priv`, own-root only. Reuses `exchange.sv.jac`'s `all_requests`, `shared_replies`, `owner_root`, `my_me`, `now_iso` and `scoring.sv.jac`'s `score_against_need` — no schema change, no new node/edge, never posts a reply itself (`ReplyToRequest` is still the only walker that does that; the user decides after seeing this list), never names the requester beyond `IntroRequest.from_handle`.

  ### `WhoNeedsWhatIHave(limit: int = 5, dry_run: bool = True)` — SOH-198
  Reports, ordered strong → medium → weak then newest-request-first within each bucket:
  ```
  [{ request: IntroRequest, match_count: int, strength: "strong"|"medium"|"weak",
     top_why: str, already_replied: bool }]
  ```
  Candidates = every shared `IntroRequest` NOT posted by me, `status != "declined"`, not expired (`expires_at` unset or `>= now`) — same filter `ListIncomingRequests` applies, MINUS its "not yet answered by me" exclusion (an already-answered request is still shown here, flagged via `already_replied`, not hidden). Sorted newest-`created_at`-first, then capped at `limit` BEFORE any scoring happens — the model-call budget is one `score_against_need(me, req.need, [req.from_handle])` call per candidate, so at most `limit` calls per invocation. For each: `kept` = that request's matches with strength `strong` or `medium` (`weak` never counts); `match_count = len(kept)`; `strength` = `kept[0]`'s strength, else `"weak"`; `top_why` = `kept[0]["why"]`, else `""`. A request with `match_count == 0` is still returned (`strength: "weak"`) so the user sees what's out there. `already_replied` = a shared `IntroReply` for that request, owned by me, already exists. `dry_run` is reserved for a future "post this reply for me" action; it changes nothing this weekend — this walker never posts either way, `dry_run=False` behaves identically. No `Me` yet → `[]`. Deterministic assembly (`select_candidates` / `assemble`, reverse.sv.jac) is a plain `def` pair, tested directly in `reverse.test.jac` on hand-built `IntroRequest` nodes and hand-built score dicts — no LLM, no server.
- 2026-09-26 — SOH-197, `plan.sv.jac` (`GamePlan`) lands: a pre-event plan from a guest list (Tier 2 #27). `:priv`, own-root only, no `by llm` — openers reuse whatever `GoalRank` already cached on `RelevantTo.opener`; a fresh line is built only when that cache is empty. Reuses `paths.sv.jac`'s `find_path`, `goals.sv.jac`'s `gather_evidence`, and `reads.sv.jac`'s `list_promises_raw` rather than re-implementing them. Schema: no changes.

  ### `GamePlan(names: list[str], event: str = "")` — SOH-197
  Reports one dict:
  ```
  { event: str,
    known:   [{ name: str, person: Person, why_talk: str, open_promise: str, opener: str, goal_label: str, goal_strength: str }],
    routes:  [{ name: str, person: Person, via: str, hops: int, why_talk: str }],
    unknown: [str],
    ambiguous: [{ name: str, candidates: [Person] }],
    suggested_order: [str] }
  ```
  Resolution per guest name (normalized, case-insensitive), capped at 60 names: every person under `[me ->:Knows:->]` (confirmed or proposed) whose full name matches exactly, or — only when the guest name is a single token — whose first name token matches, is a candidate (deduped by jid across both rules); exactly one -> `known`; two or more -> `ambiguous`. Else: a `Reported` edge one hop out of any known person whose target's full name matches -> `routes` (`via` = that known person's name, `hops` = `len(find_path(me, target, 3)["hops"])`, or `2` if `find_path` itself doesn't confirm the route — e.g. the connecting known person fails `find_path`'s own confirmed/non-proposed filter). Else `unknown`. For `known`: `open_promise` = the text of the first open (`done == False`) Promise addressed to them via `reads.sv.jac`'s `list_promises_raw`, else `""`; `goal_label`/`goal_strength` = the `RelevantTo` edge's `label`/`strength` on the caller's ACTIVE goal, else `""`/`""`; `opener` = the active goal's cached `RelevantTo.opener` if non-empty, else a line naming the first Fact/Intent from `gather_evidence` (`"Ask {first_name} about {span}."`), else `""`; `why_talk` = one sentence, priority open promise > strong/medium goal relevance > a recent Fact > `"You know them; say hello."`. `suggested_order` = known-with-open-promise first, then known-with-strong/medium-goal-relevance, then other known, then routes — each bucket in the guest list's own order; ambiguous/unknown names never appear in it. No `Me` yet -> `{ event, known: [], routes: [], unknown: names[:60], ambiguous: [], suggested_order: [] }`.
- 2026-09-26 — SOH-194, `paths.sv.jac` (`PathFinder`) lands: the warmest EVIDENCED route to a person (PRD Tier 2 #24). `:priv`, own-root only, no `by llm`. A shared `org` is CONTEXT to display, never a hop; "no known route" is always a valid, non-error answer, distinct from `not_found` (the target isn't reachable from Me by ANY traversal — including proposed/unevidenced ties — at all). Never reads `Knows.last_contact` to gate or rank a route; `days_since_contact` is display only, on the first (`via: "knows"`) hop only. Schema: no changes.

  ### `PathFinder(target_person_id: str, max_depth: int = 3)` — SOH-194
  Reports one dict:
  ```
  { found: bool, target: Person | null,
    hops: [{ person: Person, via: "knows"|"reported", evidence: { id: str, kind: "note", span: str, observed_at: str } | null, days_since_contact: int | null }],
    context: [str], reason: str }
  ```
  BFS from Me: level 0 = `[me ->:Knows:->]` restricted to `Person.status == "confirmed" and Knows.status != "proposed"`; each further level follows `Reported` edges out of the frontier, only edges carrying a non-empty `source_note`; cycle-safe (visited by jid); stops at `max_depth` (hard-capped at 4, regardless of the argument). A person reached only via a `Reported` edge whose own `Person.status == "proposed"` may still BE the target but is never expanded further as an intermediate hop. `hops` starts with the level-0 person and ends with the target (a directly-known target is one hop, `via: "knows"`); `evidence` for the `knows` hop is that `Knows` edge's `source_note` resolved to `{id, kind:"note", span:"", observed_at: note.captured_at}` (`null` if empty); for a `reported` hop it's the `Reported` edge's `source_note` + `span` in the same shape. `days_since_contact` is populated only on the `knows` hop (via `goals.sv.jac`'s `compute_days_since_contact`); every `reported` hop's is `null`. Warmest tie-break when more than one same-round route reaches the same node: prefer the route whose level-0 `Knows` edge `status == "confirmed"` over `reported`/`proposed`, then the more recent evidence `observed_at` — never `last_contact`. `context` = display-only lines (`"same org as you: {org}"`) for every level-0 person sharing the target's `org`, independent of whether that person is on the actual route. `reason` is exactly one of: `"Known directly."` (single knows-hop), `"Reported route via {name} ({n} hop(s))."` (`{name}` = the level-0 entry point, `{n}` = the number of Reported hops), `"No known route. Unknown is not never met."` (target exists and is reachable somewhere in the caller's broader network by an unrestricted traversal, just not by a valid evidenced route within `max_depth` — e.g. blocked by a proposed intermediate, or the only tie has no `source_note`), or `"not_found"` (the `target_person_id` doesn't resolve to a `Person` owned by the caller, OR it does but is not reachable from Me by ANY Knows/Reported traversal at all — `target: null`, `hops: []`, `context: []` in that case). `main.jac`: `import from paths { PathFinder }`.
- 2026-09-26 — SOH-195, `merge.sv.jac` lands: duplicate merge — propose, confirm, undo. All three walkers are `:priv`, own-root only (over the caller's `[me ->:Knows:->]` people), no `by llm`. `ProposeMerges` never merges anything by itself; nothing is merged until `MergePeople` is called explicitly with both ids; every merge is undoable via `UndoMerge`. Schema: adds `node MergeRecord { kept_id: str, removed_name/org/title/status: str, moved: list[str], created_at: str, undone: bool = False }`, under root.

  ### `ProposeMerges()` — SOH-195
  ```
  [{ a: Person, b: Person, reason: "same_name"|"same_first_last_initial"|"first_name_only_vs_full"|"same_org_similar_name", confidence: "high"|"medium" }]
  ```
  Over `[me ->:Knows:->]`, max 20 pairs, each person in at most one pair; deterministic priority order per pair (first match wins): normalized names equal → `high`/`same_name`; a single-token name equal to the other's first token (e.g. "Maya" vs "Maya Okafor") → `medium`/`first_name_only_vs_full`; one side's first token is an initial matching the other's first-letter, same last token (e.g. "M. Okafor" vs "Maya Okafor") → `medium`/`same_first_last_initial`; same non-empty org and one name a prefix of the other → `medium`/`same_org_similar_name`. Candidates are ranked (confidence, then rule priority — ties keep discovery order) and greedily selected without reusing a person.

  ### `MergePeople(keep_id: str, remove_id: str)` — SOH-195
  ```
  [{ kept: Person, record_id: str, moved: { facts: int, intents: int, promises: int, mentions: int, reported: int, relevant_to: int, introductions: int } }]
  ```
  or `[{error: "same_person"}]` (`keep_id == remove_id`) or `[{error: "not_found"}]` (either id not one of the caller's own `[me ->:Knows:->]` people). Every `FactAbout`/`IntentAbout`/`PromiseTo` (incoming), `Mentions` (incoming from Notes), `Reported` (both directions), `RelevantTo` (outgoing), `Proposes` (incoming from Introductions), `FromCard` (outgoing) edge touching `remove` is re-created on `keep` (skipped if an identical edge already exists there) and the old edge deleted; `keep.org`/`title` filled from `remove` when empty; `remove.status == "confirmed"` with `keep`'s `Knows` edge `"proposed"` confirms both; a `MergeRecord` is written under root with `remove`'s captured fields and a description of every edge moved; `remove`'s `Knows` edge and the `remove` node are deleted last (a `del` of a node cascades away its own remaining edges, so provenance only survives because it was re-pointed onto `keep` first — `jac guide jac-node-edge-patterns`). `FromCard` is moved but not counted in `moved` (no slot in the report shape).

  ### `UndoMerge(record_id: str)` — SOH-195
  ```
  [{ restored: Person, record_id: str }]
  ```
  or `[{error: "not_found"}]` (unknown/foreign record) or `[{error: "already_undone"}]`. Recreates the removed Person from the `MergeRecord`'s captured fields plus a fresh `Knows` edge (`how_met="restored after merge"`, `status` = the recorded `removed_status`), moves every edge listed in `moved` back off `keep` (when `keep` still exists) onto the restored person — parsing each description; an entry whose non-`keep` node no longer exists is skipped — and marks the record `undone`. `MergeRecord.moved` entries are `"<Kind>:<id>"` (`FactAbout`, `IntentAbout`, `PromiseTo`, `Proposes` — no extra data needed to reverse) or `"<Kind>:<id>\x1f<field>\x1f..."` (`Mentions`: span; `ReportedFrom`/`ReportedTo`: the other person's id, source_note, span; `RelevantTo`: goal id, reason, strength, opener, label, evidence joined by `,`; `FromCard`: card id, handle, received_at) — an internal storage detail, not part of any walker's report shape.
- 2026-09-26 — SOH-205 polish (Exchange, three fixes after a live two-phone run):
  1. **`ListMyReplies()`** (friend side, new): `[{ request: IntroRequest, reply: ReplyView, why: str }]` — every shared `IntroReply` OWNED by the caller (`owner_root(reply) == jid(root)`), newest first, paired with its request (skipped if the request is gone/unreadable) and `why`. Every reply status is included (pending/approved/opted_in/revealed/declined), so a friend who reloads mid-flow still sees in-progress replies. `why` is the friend-private "why it fits" text, read off the caller's own `ReplyPrivate` node — it NEVER appears on `ReplyView` and never crosses to the requester. Schema: `ReplyPrivate` gains `why: str = ""`, filled at `ReplyToRequest` time from `score_against_need`'s `kept[0]["why"]`, or `"No strong match in your graph."` when `kept` is empty.
  2. **`ClaimReveal`'s intro draft** now addresses both people by name instead of "Hi both". `requester_name` = the requester's own `Card.name` if non-empty, else `Me.name` if it isn't the onboarding default `"me"`, else `req.from_handle` — computed inside `ClaimReveal` (the caller IS the requester there) and threaded into both `draft_intro` (new `requester_name` param, `sem` updated: "...from the friend to both people, addressing them by name...") and the deterministic `intro_template` fallback (`"Hi {card_name} and {requester_name}, ..."`). Never the literal `"[Name]"`.
  3. **`OptIn`'s draft**: the fact snippet is stripped of trailing `.`/whitespace before being wrapped in parentheses, so it reads `(Priya is a partner at a climate-tech seed fund)`, never `(… seed fund.),`.
  No other report shapes changed; `ReplyView` is still exactly `{ _jac_id, request_id, from_handle, match_count, strength, status }`.
- 2026-09-26 — SOH-184, `noted.sv.jac` (`NotedCard`, `ApplyCorrection`) lands: "Here's what I noted" — share the card you keep on someone so they can correct it (Tier 1 #18). Both `:priv`, own-root only, no `by llm`. `person_id` is resolved directly among `[me ->:Knows:->]` (same idiom `drafts.sv.jac`'s `DraftFollowUp` uses) — a person only reaches that traversal via this account's own Capture/Import/Confirm flow. Nothing sends: `share_text` is a plain string the user copies by hand. Schema: no changes.

  ### `NotedCard(person_id: str)` — SOH-184
  Reports one dict:
  ```
  { person: Person,
    facts: [{ id: str, text: str, observed_at: str, status: str }],
    intents: [{ id: str, kind: str, text: str, expires_at: str }],
    promises: [{ id: str, text: str, due: str, done: bool }],
    how_met: str,
    share_text: str }
  ```
  or `{ error: "not_found" }` (`person_id` isn't one of the caller's own `[me ->:Knows:->]` people). `facts`/`intents`/`promises` are every `FactAbout`/`IntentAbout`/`PromiseTo` reverse-edge target of that Person, in traversal order — including stale facts and expired intents (nothing here hides them from the card itself, only from `share_text`). `how_met` is the caller's own `Knows` edge's `how_met` field. `share_text` is a plain-text message: an opening line (`"Hi {name}, here's what I have noted about you so I get it right. Correct anything:"`), then one line per fact whose `status != "stale"` (`"- {text} (noted {observed_at[:10]})"`, no date suffix when `observed_at` is empty) and one line per intent that isn't already expired (`expires_at` unset, unparsable, or in the future) — `"- {prefix} {text}"` where `prefix` is `"looking for:"` (need), `"can offer:"` (offer), or `"open to:"` (open_to) — then a closing line (`"Reply with fixes and I'll update my notes."`). Promises never appear in `share_text` (they are the caller's own commitments, not the person's to correct) and no score/relevance word ever appears in it.

  ### `ApplyCorrection(person_id: str, text: str, replace_fact_id: str = "", kind: str = "fact")` — SOH-184
  Reports `[{ fact: Fact }]` (kind `"fact"`) or `[{ intent: Intent }]` (kind `"need"|"offer"|"open_to"`), or `[{error: "not_found"}]` / `[{error: "bad_kind"}]`. `kind` is validated BEFORE `person_id` is resolved, so a bad kind reports the same way regardless of whether the person id is also wrong. Always creates a `Note(kind="correction", text=text, captured_at=now)` under root first. `kind="fact"`: a new `Fact(text, observed_at=now, status="confirmed", source_kind="self")` via `Asserts(span=text)` off that Note, plus `FactAbout` to the person; when `replace_fact_id` names one of that person's own Facts (matched via the reverse `FactAbout` edge), that OLD fact's `status` is flipped to `"stale"` — it is never deleted, so its provenance and history survive. `kind` one of `"need"|"offer"|"open_to"`: a new `Intent(kind, text, source_kind="self", expires_at=default_expiry(kind, now))` via `AssertsIntent(span=text)` + `IntentAbout` to the person (`default_expiry` imported from `freshness.sv.jac`, same helper `capture.sv.jac`/`onboard.sv.jac` use). `main.jac`: `import from noted { NotedCard, ApplyCorrection }`.
- 2026-09-26 — SOH-201, `serendipity.sv.jac` (`Serendipity`) lands: serendipity nudges — paste an article title/summary or an event description; which of my contacts would care, and why, with the evidence (PRD Tier 2 #33). `:priv`, own-root only, **no `by llm`** — deterministic token-overlap matching only, on purpose (a model pass can be added later behind its own `by llm` call without changing this shape). Never ranks a person's worth: report order is match COUNT only, then newest evidence to break ties. Reuses `recall.sv.jac`'s `_tokenize` (lowercase/alnum/length>=4/non-stopword) and `goals.sv.jac`'s `gather_evidence`/`EvidenceItem` (facts, non-expired intents, mentioning notes — the same 8-item cap) rather than re-implementing either. Schema: no changes.

  ### `Serendipity(text: str, url: str = "", limit: int = 5)` — SOH-201
  Reports, ordered by matched-token count desc then newest evidence desc, capped at `limit`:
  ```
  [{ person: Person, matched: [str], why: str,
     evidence: [{ id, kind: "fact"|"intent"|"note", span: str, observed_at: str }],
     share_draft: str }]
  ```
  Tokenizes `text`; for every confirmed-known person (`Person.status == "confirmed"` AND the caller's own `Knows` edge `status != "proposed"` — same "known" rule `goals.sv.jac` uses), gathers their evidence via `gather_evidence` and computes `matched` = distinct tokens shared between `text` and that evidence's spans (also matching a token against the person's `org`/`title`). Qualifies at `>= 2` matched tokens, or `>= 1` when at least one matched token came from an Intent specifically (an explicit want beats a bare keyword). `why` cites the single top evidence item (Intent > Fact > Note priority, ties broken by newest `observed_at`; falls back to an `org`/`title` clause when no individual evidence item itself overlapped) plus a two-token, text-order "topic" phrase, e.g. `"Maya wants feedback from wheelchair users; this piece is about accessible robotics."`. `share_draft` = `"Hi {name}, saw this and thought of you: {url or text[:80]} — {why sentence minus the leading name}. No pressure."` — a draft only, never sent. No `Me` yet, or zero qualifying tokens in `text` at all -> `[]`. `main.jac`: `import from serendipity { Serendipity }`.
- 2026-09-26 — SOH-192, `vision.sv.jac` (`CaptureImage`) lands: a badge/business-card photo becomes a Person + Facts, same provenance shape as `Capture` (PRD Tier 1). `:priv`, own-root only. ONE `by llm` vision call (`read_badge(img: Image, context: str) -> BadgeRead by llm()`, gemini-3.8-flash reads the photo directly — no OCR step); graph-writing (`apply_badge_read`) is deterministic and tested without the model. The photographed person is resolved by an org-aware rule specific to a badge scan: same name + same-or-blank org reuses (filling blank org/title); same name + a DIFFERENT non-empty org is NEVER merged — a new `proposed` Person is created and the existing match(es) come back as `ambiguous_with` (this differs from `capture.sv.jac`'s `resolve_person`, which has no org check and instead disambiguates on shared first tokens — the two rules solve different problems and aren't interchangeable). Every new badge person is created `status="proposed"` with `Knows(status="proposed", how_met="badge photo")` — a badge/OCR read is machine-read data, same trust level `imports.sv.jac` gives a CSV row (never the more-trusted `"reported"`/`"confirmed"` a typed debrief gets from `Capture`). Schema: no changes — the photo reuses `Note.audio_ref` as its `photo_ref` (same field `Transcribe` uses for saved audio); email/phone/links never touch the graph (schema stores no contact fields this weekend), they ride back in the report's `read` block only.

  ### `CaptureImage(image_b64: str, mime: str = "image/jpeg", context: str = "")` — SOH-192
  Reports one object:
  ```
  { note_id: str,
    people:   [{ person: Person, is_new: bool, ambiguous_with: [person_id], span: str }],
    facts:    [{ fact: Fact, about: person_id, span: str }],
    intents: [], promises: [], ties: [],   # always empty — a badge/card carries no needs/offers/ties
    photo_ref: str,
    read: { name: str, org: str, title: str, email: str, phone: str, links: [str], raw_text: str },
    fallback: bool, error: str }
  ```
  `image_b64` decode failure or an empty/whitespace-only string -> `error: "empty"` (`note_id`/`photo_ref` both `""`, nothing written to disk or the graph). Decoded bytes over 8 MB -> `error: "too_large"` (same: nothing written). Otherwise the image is saved to `uploads/<uuid>.<ext>` (`ext` from `mime`: `image/png`->`png`, `image/webp`->`webp`, `image/heic`->`heic`, anything else including `image/jpeg`->`jpg`) as `photo_ref` BEFORE the model call, so the photo is never lost even if the read fails. `read_badge` raising (bad/corrupt image bytes — byllm's `Image(path)` validates locally via PIL before any network call, so this never needs the model) -> `fallback: true`, a `Note(kind="paste", text="Badge photo (unreadable)", audio_ref=photo_ref)` is still created, all lists empty, `error: ""`. On a successful read: the note text is always `f"Badge photo: {name}, {title} at {org}. {raw_text}"` (deterministic, built even when no person results); `read.is_person_card == false` OR an empty/whitespace `name` -> `error: "no_person"`, `people`/`facts` empty (the note and its raw text are still kept). Otherwise: one `Mentions(span=name)` edge from the note to the resolved Person, `people` has exactly that one entry, and `facts` gets one entry per non-empty `org` (`"Works at {org}"`) and non-empty `title` (`"Title: {title}"`), each via `Asserts(span=<raw_text line containing the value, or the bare value if no line matches>)` + `FactAbout`, `source_kind="reported"`. `main.jac`: `import from vision { CaptureImage }`.
- 2026-09-26 — SOH-207 + SOH-199, `person.sv.jac` (`PersonDetail`, `Brief`) lands: everything the person sheet needs in one call, and a spoken pre-meeting recap. Both `:priv`, own-root only. `person_id` is resolved directly among `[me ->:Knows:->]` (same idiom `drafts.sv.jac`'s `DraftFollowUp` and `noted.sv.jac`'s `NotedCard` use). `PersonDetail` has no `by llm`; `Brief` makes exactly ONE `by llm` call per invocation, wrapped in `try/except`, with a deterministic fallback (`fallback_recap`) that always produces a usable recap — reused both when there's no evidence at all and when the LLM call fails. Reuses `goals.sv.jac`'s `_parse_naive_utc` and `drafts.sv.jac`'s `gather_follow_up_evidence`/`EvidenceItem`/`item_to_dict`/`person_summary_text`/`build_evidence_text`/`map_evidence_indices` rather than re-implementing any of them. Schema: no changes.

  ### `PersonDetail(person_id: str)` — SOH-207
  Reports one entry:
  ```
  [{ person: Person, how_met: str, knows_status: str, last_contact: str,
     relevance: { goal_id: str, goal_text: str, label: str, strength: str, reason: str, opener: str } | null,
     facts:    [{ fact: Fact, age_days: int, source_note_id: str, span: str }],
     intents:  [{ intent: Intent, expired: bool, source_note_id: str, span: str }],
     promises: [{ promise: Promise, source_note_id: str, span: str }],
     notes:    [{ note: Note, span: str }],
     reported_by: [{ person_id: str, name: str, span: str }],
     card_handle: str }]
  ```
  or `[{ error: "not_found" }]` when `person_id` isn't one of the caller's own `[me ->:Knows:->]` people. `how_met`/`knows_status`/`last_contact` come straight off the caller's own `Knows` edge to this person (`last_contact` is copied for DISPLAY only; nothing computes from it). `relevance` = the `RelevantTo` edge from this person into the caller's ACTIVE goal (`me`'s `HasGoal` with `active == true`), else `null`. `facts` = every `FactAbout` reverse-edge target, newest-`observed_at`-first, each paired with `age_days` (tz-safe via `goals.sv.jac`'s `_parse_naive_utc`) and its asserting `Asserts` Note's id/span (`""` if the fact has no asserting Note). `intents` = every `IntentAbout` reverse-edge target, newest-first by its asserting `AssertsIntent` Note's `captured_at`, `expired` = `expires_at` set, parseable, and in the past. `promises` = every `PromiseTo` reverse-edge target, open (`done == false`) first then done, `due` ascending within each group (empty `due` last) — same ordering `reads.sv.jac`'s `ListPromises` uses — each paired with its asserting `AssertsPromise` Note's id/span. `notes` = every Note with a `Mentions` edge to this person, newest-`captured_at`-first, `span` from that edge; the reported `note` is a fresh, UNattached `Note` copy with `text` capped at 400 chars (the real, persisted Note is never mutated). `reported_by` = every person with a `Reported` edge INTO this person, with that edge's own `span`. `card_handle` = the `Card`'s `handle` if this person has an outgoing `FromCard` edge, else `""`. Every list is bounded at 50. No `Me` yet -> `[{error: "not_found"}]` (same as an unresolvable id).

  ### `Brief(person_id: str, voice: bool = True)` — SOH-199
  Reports one entry:
  ```
  [{ person_id: str, text: str, audio_b64: str, mime: str,
     based_on: [{ id: str, kind: "note"|"fact"|"intent"|"promise", observed_at: str, span: str }],
     fallback: bool, voice_error: str }]
  ```
  or `[{ error: "not_found" }]` (same person_id resolution rule as `PersonDetail`). Evidence = `drafts.sv.jac`'s `gather_follow_up_evidence` (facts, non-expired intents, open promises, mentioning notes — newest-first, capped at 8), plus the caller's active-goal `RelevantTo` reason on this person (if any) appended as an extra, unnumbered context line in the prompt (never itself citable as `based_on` evidence, since it isn't a Fact/Intent/Note/Promise node). ONE `by llm` call (`spoken_brief(person_summary, evidence_text) -> Recap { text, evidence_indices }`, `temperature=0.4`) when there IS evidence; `based_on` = `evidence_indices` mapped back to full evidence dicts (`drafts.sv.jac`'s `map_evidence_indices`). No evidence at all, or the LLM call fails / returns an empty `text` / cites no evidence -> `fallback_recap`: deterministic text `"{name}, {title} at {org}. Last time: {newest note span or fact}. You promised: {open promise text or 'nothing open'}. They wanted: {need intent text or 'nothing on record'}."` (empty clauses dropped cleanly), `based_on` = every evidence item (no LLM-picked subset to narrow to), `fallback: true`. Voice: `voice=false` -> `audio_b64: "", mime: "", voice_error: "voice_disabled"`; `voice=true` with no `ELEVENLABS_API_KEY` -> `voice_error: "no_key"`; `voice=true` with a key -> POSTs the recap text to ElevenLabs TTS (`voice_id` from `ELEVENLABS_VOICE_ID`, default `21m00Tcm4TlvDq8ikWAM`, `model_id: eleven_turbo_v2_5`, `output_format=mp3_44100_64`) — 200 -> `audio_b64` = base64 of the response bytes, `mime: "audio/mpeg"`, `voice_error: ""`; any failure -> `audio_b64: ""`, `mime: ""`, `voice_error` = the status code or exception, capped at 120 chars, never logged. `main.jac`: `import from person { PersonDetail, Brief }`. `.env.example`: adds `ELEVENLABS_VOICE_ID` (optional, commented).
- 2026-09-26 — SOH-182, `enrich.sv.jac` (`Enrich`) lands: public web facts about one contact, every one with a URL. `:priv`, own-root only. byllm 0.6.19 has no grounding, so this is ONE plain REST call to Gemini `generateContent` (model = `GEMINI_MODEL` minus the `gemini/` prefix) with `tools: [{google_search: {}}]`, `timeout=45`; the key is read server-side from `GOOGLE_API_KEY` and never logged. Nothing sends. Schema: no changes (`Note.kind="enrich"`, `Fact.source_kind="web"`, `Fact.source_url` already existed).

  ### `Enrich(person_id: str, max_facts: int = 5)` — SOH-182
  Reports ONE entry:
  ```
  [{ person_id: str, note_id: str,
     identity: "matched"|"not_found"|"ambiguous"|"unavailable",
     facts: [{ fact: Fact, source_url: str, source_title: str, span: str }],
     rejected: [{ text: str, reason: "no_url"|"identity"|"duplicate" }],
     queries: [str], fallback: bool, error: str }]
  ```
  or `[{ error: "not_found" }]` when `person_id` is not one of the caller's own `[me ->:Knows:->]` people. Rules: (1) identity-gated — facts attach only when the model answers `identity == "matched"`; otherwise every fact is rejected `identity`. (2) nothing without a URL — a fact is kept only when a `groundingSupports[].segment.text` overlaps its text or evidence (case-insensitive substring either way, or >= 4 shared tokens of >= 4 chars); that support's first valid chunk gives `groundingChunks[i].web.uri`/`.title` (`source_title` is the domain Google reports); no chunk -> rejected `no_url`. (3) the grounding redirect is followed with `HEAD` (max 5 per call; on failure the redirect uri is kept) and stored as `Fact.source_url`. (4) duplicates of an existing Fact on the person (lowercase text equal, same `source_url` + first 40 chars, or token-set Jaccard >= 0.6 on tokens of >= 4 chars — the model re-words facts between runs) or of an earlier fact in the batch -> rejected `duplicate`. The prompt asks for plain `IDENTITY:` / `REASON:` / `FACT:` lines, not JSON: gemini-3.8-flash returns no `groundingMetadata` when told "Reply ONLY with JSON" (verified 2026-09-26); the parser still accepts JSON (fenced or not). The support that overlaps a fact best wins (substring beats token overlap). A source Google labels LinkedIn is never fetched (redirect uri kept). Kept facts: ONE `Note(kind="enrich", text="Web enrichment for {name}: {queries joined by '; '}")` under root, `Mentions(span=name)` to the person, and per fact `Fact(text, observed_at=now, status="reported", source_kind="web", source_url)` via `Asserts(span=evidence or text)` + `FactAbout` to the person. No kept fact -> no Note, `note_id: ""`. Missing key -> `identity:"unavailable", fallback:true, error:"no_key"`; network/HTTP failure -> same with `error` = the exception text (<= 200 chars, e.g. `gemini_http_429`); unparsable model text -> `identity:"unavailable", fallback:true`. `queries` = `groundingMetadata.webSearchQueries`. `main.jac`: `import from enrich { Enrich }`.
- 2026-09-26 — SOH-210, `export.sv.jac` (`ExportGraph`) lands: the caller's whole graph as one JSON dict — a full data export (PRD provenance/portability). `:priv`, own-root only, no `by llm`. Traversal starts only from `root` and the caller's own `Me` — never `root.shared`, never a `jobj(id)` lookup of a foreign id, nothing from the Exchange (requests/replies) is exported. Every node dict uses `jid(n)` for its id, never a node object — the whole report is plain JSON-serialisable. `Knows.last_contact` is copied verbatim (this is the user's own export of their own data) and is never read to compute or rank anything. Facts/Intents/Promises are gathered by walking every Note's own `Asserts*` edges (same idiom `reads.sv.jac`'s `list_promises_raw` uses for promises), deduped by jid, so each entry naturally carries its own `source_note`/`span`. Schema: no changes.

  ### `ExportGraph()` — SOH-210
  Reports one dict:
  ```
  { exported_at: str, me: {id, name, about} | null,
    goals: [{id, text, active}], card: {id, handle, name, headline, about, looking_for, can_offer, links, contact_pref, visibility, updated_at} | null,
    people: [{id, name, org, title, status}],
    knows: [{from: me_id, to: person_id, status, how_met, source_note, span, last_contact}],
    reported: [{from, to, source_note, span}],
    facts: [{id, about: person_id, text, observed_at, valid_to, status, source_kind, source_url, source_note, span}],
    intents: [{id, about: person_id|me_id, kind, text, expires_at, source_kind, source_note, span}],
    promises: [{id, to: person_id, text, due, done, source_note, span}],
    notes: [{id, kind, text, captured_at, audio_ref}],
    counts: {people, facts, intents, promises, notes},
    truncated: bool }
  ```
  No `Me` yet -> `{exported_at, me: null, goals: [], card: null, people: [], knows: [], reported: [], facts: [], intents: [], promises: [], notes: [], counts: {people:0,facts:0,intents:0,promises:0,notes:0}, truncated: false}`. `people` = every `[me ->:Knows:->]` Person (confirmed or proposed — every Person a user's own graph has is reached this way); `knows`/`reported` pair each with its own edge's fields (`reported` only between two people both present in `people`, i.e. within the caller's own graph); a `knows` entry's `span` is the `Mentions` edge span from the `Knows` edge's own `source_note` to that Person, `""` if none. `intents.about` is the target Person's id when an `IntentAbout` edge exists, else the caller's own `me_id` (a self-onboarded Intent via `HasIntent`, never targeted at a Person). Bounded: `people`/`facts`/`intents`/`promises`/`notes` combined stop past 5,000 total items and `truncated` flips `true` (the walker's real cap; `build_export(me, cap)`'s `cap` param exists so a test can drive the same path with a small cap instead of building 5,000 nodes). `main.jac`: `import from export { ExportGraph }`.
- 2026-09-26 — SOH-166, `edits.sv.jac` (`UpdatePerson`, `UpdatePromise`) lands: B's "Needs A" own-root edits for the person sheet/promise list. Both `:priv`, own-root only, no `by llm`. Only NON-EMPTY (stripped) args overwrite a field; an omitted/blank arg leaves the existing value alone. `person_id` is resolved directly among `[me ->:Knows:->]` (same idiom `person.sv.jac`'s `PersonDetail` uses); the lookup+mutate logic lives in the plain `update_person_for(me, ...)` so tests can call it on a hand-built `me`/`p` pair without the shared-persisted-test-root ambiguity of `[root --> [?:Me]][0]`. `promise_id` ownership reuses `reads.sv.jac`'s `my_node` helper (imported, not reimplemented) — the same jobj/check_read_access/owner_root idiom `CompletePromise` uses. Schema: no changes.

  ### `UpdatePerson(person_id: str, name: str = "", org: str = "", title: str = "", how_met: str = "")` — SOH-166
  Reports `[Person]` (the updated node), or `[{ error: "not_found" }]` when `person_id` isn't one of the caller's own `[me ->:Knows:->]` people. `name`/`org`/`title` land on the `Person` node; `how_met` lands on the caller's own `Knows` edge to that person (found via `[edge me ->:Knows:-> p]`). Never touches `Person.status`, `Knows.last_contact`, or any other edge. `main.jac`: `import from edits { UpdatePerson, UpdatePromise }`.

  ### `UpdatePromise(promise_id: str, text: str = "", due: str = "")` — SOH-166
  Reports `[Promise]`, or `[{ error: "not_found" }]` when `promise_id` doesn't resolve to a Promise owned by the caller (ownership rule identical to `reads.sv.jac`'s `CompletePromise`). `done` is never touched by this walker.
- 2026-09-26 19:00 — SOH-211 hardening (adversarial review). New error values and behavior changes; every other shape unchanged.
  - **Gate walkers unserved.** `main.jac` no longer imports `gate` — `GateMyRoot`, `GatePostShared`, `GateListShared`, `GateMakeCard`, `GateReadCard` now 404 over HTTP (tests import the module directly).
  - **Unique handles.** `PublishCard` → `[{ error: "handle_taken" }]` when a Card with the same `handle`, owned by a different root, is already listed in the `CardDirectory` (the card is not listed, not granted, fields not written). `DevMakeCard(handle, name)` → same `[{ error: "handle_taken" }]` before creating anything.
  - **Handshake-only cards findable.** Listing now also hangs a public `CardListing { handle, card_id }` (owned by the card's owner, `ReadPerm` to all) off the `CardDirectory`; `listed_cards()` resolves it, so `OfferHandshake(to_handle)` finds a `handshake_only` card published in the same server session (was `[{ error: "not_found" }]`: a traversal silently skips targets the caller cannot read). `get_card` still refuses anything but `visibility == "link"`. Schema: adds `node CardListing`.
  - **Request state on every Exchange transition.** `ApproveReply`, `OptIn`, `Reveal`, `ClaimReveal` → `[{ error: "request_closed" }]` when the request is `declined`/`expired` or past `expires_at` (ownership/`not_found`/`forbidden` checks still come first). `ClaimReveal` on a reply the friend declined (even after reveal) → `[{ error: "reply_declined" }]`.
  - **ClaimReveal is cached.** A second `ClaimReveal` on the same reply reports the same `{ person, card, intro_draft }` with the stored draft — no second model call. Schema: adds `node ClaimedIntro { reply_id, person_id, intro_draft }` under the requester's root.
  - **Scorer fallback.** When the model call fails, `ScoreAgainstNeed`/`score_against_need` report only candidates sharing ≥ 1 non-stopword token of length ≥ 4 with the need, always `strength: "weak"`, `evidence_ids` = the overlapping items, `why: "Shares a keyword with the need (scored without the model)."`; no overlap → the candidate is omitted. The fallback never reports `medium`/`strong` (so `ReplyToRequest` reports `match_count: 0` when the model is down).
  - **Bounded budgets.** `WhoNeedsWhatIHave.limit` clamped to [0, 25]; `Recall.max_items` to [0, 100]; `Serendipity.limit`, `Tend.limit` to [0, 50]. `PathFinder.max_depth` was already capped at 4.
  - **Forget.** Forgetting a Fact/Intent/Promise deletes any `RelevantTo` edge whose `evidence` becomes empty (still counted in `retracted.relevant_to`); forgetting a Person removes its `RelevantTo` edges (node-delete cascade, now tested).
  - **Strict base64.** `Transcribe`: `audio_b64` longer than the base64 length of the 15 MB cap (20,971,520 chars) → `error: "too_large"` before decoding; non-strict base64 → `error: "bad_base64"` (was `"bad_audio"`). `CaptureImage`: same, cap = base64 length of 8 MB + 256 (a leading `data:…;base64,` prefix is stripped); non-strict base64 → `error: "bad_base64"` (was `"empty"`; an empty string is still `"empty"`).
- 2026-09-26 — SOH-212 persona fixes (Rosa, Amara, Lena, Marcus) + SOH-166 asks from B. New module `names.sv.jac` (plain defs, no walker: `name_key`, `match_names`, `trim_words`, `display_how_met`). **Schema: `Goal` gains `has ranked_at: str = ""`** (ISO, set by every GoalRank rebuild). No new walkers; `main.jac` unchanged.

  ### `Capture(text, kind = "debrief", audio_ref = "", how_met: str = "")` — shape unchanged, behavior:
  - **Names** (shared rule in `names.sv.jac`, also used by `ProposeMerges`): honorifics (Dr./Prof./Professor/Rev./Reverend/Mr./Ms./Mrs.) are stripped from `Person.name` (a Dr/Prof/Rev honorific goes to `title` when `title` is empty); a parenthetical is an alias, not part of the name; trailing `?`s dropped. Exact clean-name match -> that person (`is_new: false`), **unless both orgs are set and differ** -> ambiguous. Same first name with non-contradicting last names ("Helen" vs "Dr. Helen Marsh-Whitcombe", "Maya O." vs "Maya Okafor") -> **ambiguous**: a NEW `Person(status="proposed")` + `Knows(status="proposed")`, `ambiguous_with: [jid]` filled — this now also applies when exactly ONE known person shares the first name (previously that silently resolved to them). "Maya Lindqvist" vs "Maya Okafor" -> distinct.
  - Extraction obj additions: `XPerson.named: bool` (false = known only by description; the description is the name; created `proposed`, promises to them still attach), `XPerson.distinct_from: str` ("not the X one" -> forced new proposed Person, `ambiguous_with` includes X), `XFact.source_kind` (`self` for notes-to-self such as "conflict of interest", "keep in mind").
  - Hedges: a fact whose `span` hedges ("maybe", "??", "not sure", "I think", "possibly", "probably", ...) but whose text does not carry one of possibly/maybe/unsure/unconfirmed/not sure/reportedly/probably is stored as `"Possibly: <text>"`.
  - Promises: sem now asks for the concrete deliverable even when phrased as the other person's want ("wants ROI deck by Fri" -> Promise "send the ROI deck", due "Fri"). The model does not reliably follow it, so a deterministic guard backs it: a bare "follow up"/"check in" promise to a person who has a `need` intent in the same note is stored as `"Follow up on: <that need>"` (e.g. `"Follow up on: ROI deck by Fri"`, due kept).
  - `how_met` (SOH-166, **Needs B** to pass it): non-empty -> every NEW `Knows` edge this capture creates carries it; existing people's edges untouched. Default `how_met` is now `"{kind}: {first 60 chars cut on a word boundary}…"`.

  ### `Recall(question, max_items = 40)` — shape unchanged
  Gathers Facts/Intents/Promises through each Note's `Asserts*` edges (they never hung off root, so promises were invisible). A question containing promise/promised/said I would/send/owe/follow up keeps every promise item first; fallback text for a promise reads `"you promised {person}: {text} ({observed_at})"`.

  ### `ProposeMerges()` — shape unchanged
  Adds the `names.sv.jac` rule: honorific-only difference -> `same_name`/`high`; "Helen" vs "Dr. Helen Marsh-Whitcombe" -> `first_name_only_vs_full`; "Maya O." vs "Maya Okafor" -> `same_first_last_initial`.

  ### `OnboardMe(about: str, name: str = "")` — **Needs B**: pass the signup name
  `name` non-empty -> `Me.name` and `Card.name` = it. Else the extracted name (sem: "the speaker's own name if they state it, else empty"); else a deterministic "I'm Sam, …"/"My name is …" read of `about`; else unchanged (`"me"` for a new Me). Report shape unchanged.

  ### `NotedCard(person_id)` — shape unchanged
  `how_met` shown on a word boundary with "…" (legacy 60-char cuts are re-trimmed for display).

  ### `ApplyCorrection(person_id, text, replace_fact_id = "", kind = "fact", replace_intent_id: str = "")` — SOH-166
  `replace_intent_id` names an Intent about this person: its `expires_at` is set to now (ISO, `datetime.now().isoformat()`, same as freshness) — never deleted — and the replacement Intent is created as before (`source_kind="self"`, default expiry). Report shape unchanged (`[{ intent: Intent }]`).

  ### `Serendipity(text, url, limit)` — shape unchanged
  Matches only on the person's OWN Facts/Intents (`FactAbout`/`IntentAbout`); a Note that merely mentions them no longer counts, and `evidence` lists only those Facts/Intents. `why` = `"{name} {clause}; this piece is about {topic}."` where an intent already leading with a verb ("Looking for …") is used as-is, otherwise `"wants …"` / `"can offer …"` (offer intents); quoted text is lower-cased at the first letter and loses its trailing period.

  ### `GapFinder()` — shape unchanged; `suggested_need` sem: one short sentence, everyday words, no jargon, <= 14 words.

  ### `ImportPeople(rows, source)` — unchanged
  Could not reproduce "26 new rows all `is_new: false`" (fresh and concurrent runs report `true`; a re-import of the same names correctly reports `false`, which a retried call would do). Regression test added.

  ### `GoalRank(goal_id, refresh = False)` — every entry gains four keys
  ```
  { ...existing keys..., stale: bool, ranked_at: str, truncated: bool, total_people: int }
  ```
  `ranked_at` = `Goal.ranked_at` (set at every rebuild). `stale` = some `Note.captured_at` is later than `ranked_at` (always `false` on a fresh rebuild; `true` for a cached ranking with no `ranked_at`). Never auto-refreshes: the client decides (`refresh: true`). `total_people` = distinct candidate people before the 60 cap; `truncated` = `total_people > 60`.

  ### `GamePlan(names, event = "")` — the report dict gains
  ```
  { ...existing keys..., total_names: int, processed: int, truncated: bool, not_processed: [str] }
  ```
  Only the first 60 names are resolved; the rest come back verbatim, in order, in `not_processed` (never silently dropped).

  ### Known, not fixed here: `warnings` on every response after `PublishCard`/`PostRequest`
  Reproduced: once a user has run `PublishCard` or `PostRequest`, EVERY later response for that user (even `Ping`) carries two `"Permission denied: field_write on Root[<root.shared>] owned by root[<system>]"` warnings, until the server restarts. Not caused by the read walkers: `cards.sv.jac`/`exchange.sv.jac` traverse/attach on `root.shared` (`[root.shared -->]`, `root.shared ++> …`), which leaves the shared root's anchor dirty in that user's memory; every commit then retries the denied write. Fix belongs in `cards.sv.jac` / `exchange.sv.jac` (outside this change).
- 2026-09-26 — SOH-214 Capture polish. `Capture` report shape unchanged; behavior:
  - **Promises need the speaker's commitment.** Extraction sem says so, and a deterministic guard backs it: a promise whose `span` has a want cue (wants/wanted/looking for/needs/is hiring/asked for) and no commitment cue (i said/i'll/i will/i promised/promised/owe/told/send/will send/i'd), in a note with no follow-up cue anywhere (follow up/follow-up/check back), is stored as `Intent(kind="need", source_kind="reported")` on that person via `AssertsIntent(span)` + `IntentAbout`, and reported under `intents`, not `promises`. "wants ROI deck by Fri. Follow up Thu." still yields the promise "send the ROI deck".
  - **Default `how_met`** (no `how_met` arg) on NEW `Knows` edges is a human line: `"from a debrief on YYYY-MM-DD"`, `"from a pasted note on …"`, `"from an import on …"`, `"from your about-me on …"` (date = the Note's `captured_at`). It never contains note text.
  - **"you", never "the author".** Fact/intent/promise text refers to the note's writer as "you": sem instruction plus a post-pass (`second_person`) that rewrites whole-word "the author/speaker/user/writer" (any case; "'s" -> "your", "was/is/has" -> "were/are/have").
- 2026-09-26 — SOH-218 friend-gated Exchange (`exchange.sv.jac`). **Needs B**: an audience toggle on Post, a Friends list, a Block action.
  - **Friends** = handles of Cards I hold: a Person under `[me ->:Knows:->]` with a `FromCard` edge (`edge.handle`), or a `Knows.source_note == "card:<handle>"` marker (a handshake whose cross-root attach was denied). Own root only.
  - `PostRequest(need, about_line = "", ttl_days = 7, audience: str = "friends")` — report unchanged except the `IntroRequest` now carries `audience: "friends" | "everyone"` (anything else is stored as `"friends"`). **Default is friends-only**: a client that omits `audience` posts to friends only.
  - `ListIncomingRequests()` — shape unchanged; a request is listed only if `audience == "everyone"` or its `from_handle` is one of my friends, and never when `from_handle` is in `Me.blocked_handles`.
  - `ReplyToRequest(request_id)` — same gate; a request not visible to me reports `{ error: "not_visible" }` (after `not_found`/`forbidden`/own-request `invalid_state`).
  - `ListMyReplies()` — shape unchanged; replies to requests no longer visible to me (e.g. requester blocked) are omitted.
  - `ListMyRequests()` — shape unchanged; replies whose `from_handle` is in my `blocked_handles` are omitted.
  - `ListFriends()` → one report per friend handle:
    ```
    { handle: str, person: Person, since: str }   # since = FromCard.received_at, "" for the source_note marker
    ```
  - `BlockHandle(handle: str)` / `UnblockHandle(handle: str)` → `[{ blocked: [str] }]` (the full list after the change; idempotent). Errors: `{ error: "bad_handle" }` (blank), `{ error: "no_me" }` (not onboarded).
- 2026-09-26 — SOH-215 Identity layer 2: blinded identity tokens (`identity.sv.jac`).
  - **`Person.identity_tokens: [str]`** (already in the schema) is now filled: `"<kind>:<32 hex>"`, HMAC-SHA256 under a server salt (`IDENTITY_SALT`, else `JWT_SECRET`, else a dev default; never reported). Kinds: `n` = name|org (org with legal suffixes like Inc/Corp/LLC dropped), `n0` = name alone when org is empty, `e` = email, `p` = phone (digits, >= 7), `u` = link (lower, no scheme/www/query/trailing slash). Recomputed when Capture creates a person, when CaptureImage reads a badge (also fills empty `email`/`phone` and absent `links` from the read), when Enrich lands web facts (each fact's `source_url` is appended to `links` if its canonical form is absent; grounding redirects are never stored), and when a handshake creates a person from a Card (`links` from the Card). Tokens appear on the owner's own Person objects only.
  - **`RefreshIdentityTokens()`** `:priv`, own root, no model → `[{ updated: int }]` (people whose tokens changed).
  - **`ListMyRequests()`** — each entry gains `same_person_groups`, each reply view gains `same_as` and `same_reason`:
    ```
    { request: IntroRequest,
      replies: [ { ...ReplyView (unchanged keys)..., same_as: [reply_id], same_reason: "contact" | "name+org" | "name" | "" } ],
      same_person_groups: [ [reply_id, ...] ] }   // only groups of >= 2 replies whose top matches look like the same person
    ```
    `same_reason`: `contact` = an email/phone/link token matched; `name+org` = the name|org token matched; `name` = only the name-alone token matched (both sides have no org; "likely", not "same"). `same_as` = the other replies in the same group (empty when none). Tokens never appear in any report: `IntroReply.match_tokens` (set by `ReplyToRequest` from the friend's top match, hashes only) stays server-side and is not in ReplyView.
- 2026-09-26 — SOH-216, `search.sv.jac` (`Search`) lands: keyword search across the caller's own people, facts, intents, promises, and notes, plus contact fields (`email`, `phone`, `links`, `location`) added to `UpdatePerson` (`edits.sv.jac`), `ImportPeople` (`imports.sv.jac`), `PersonDetail` (`person.sv.jac`), and `ExportGraph` (`export.sv.jac`). `Search` is `:priv`, own-root only, no `by llm`, deterministic. Schema: no changes (all fields already landed with SOH-215/220's `Person.email/phone/links/location`).

  ### `Search(query: str, limit: int = 25, kinds: list[str] = [])` — SOH-216
  Reports one dict:
  ```
  { query: str, total: int,
    results: [{ kind: "person"|"fact"|"intent"|"promise"|"note", id: str,
                text: str, person_id: str, person_name: str, span: str,
                score: int, observed_at: str }] }
  ```
  Own-root only: only `[me ->:Knows:->]` people (and what hangs off them) are ever considered; an archived person, and every Fact/Intent/Promise/Note reached only through them, is skipped entirely. Deterministic scoring: tokenize `query` (lowercase, alnum runs of length >= 2, stopwords dropped); per candidate row, `score = sum over tokens of (3 if the token is a PREFIX of one of the person's name words, 2 if the token appears anywhere in org/title/location/email, 1 per occurrence of the token in the row's own text)`; the whole stripped-lowercased `query`, if it appears as a substring anywhere across name/org/title/location/email/text, DOUBLES the row's score. A row scoring 0 is dropped. A `person` row's own `text` is the person's `name` (so a description-only `Person.name`, e.g. "tall girl from the climbing gym", is found by its own words). `kinds` (empty = every kind) filters which row kinds are built at all. Sort: score descending; ties broken `person` rows first, then newest first (`_parse_naive_utc` on the row's `observed_at` — a `fact`'s own `observed_at`, an `intent`/`promise`'s asserting Note's `captured_at`, a `note`'s own `captured_at`; a `person` row has none, but the kind tie-break already puts it first regardless). `limit` clamped to `[0, 100]` (default 25); `total` counts every scored row BEFORE that clamp. No `Me` yet -> `{ query, results: [], total: 0 }`. `main.jac`: `import from search { Search }`.

  ### `UpdatePerson(...)` gains `email: str = ""`, `phone: str = ""`, `links: list[str] = []`, `location: str = ""` — SOH-216
  Same non-empty-overwrite rule as `name`/`org`/`title`, except `links`: a non-empty list REPLACES the whole list (no per-item merge). Never crosses accounts. `refresh_person_tokens(p)` (SOH-215's `identity.sv.jac`) is a `# TODO(SOH-215)` in `edits.sv.jac` — that module doesn't exist yet.

  ### `ImportPeople(rows, source)` — unchanged shape, `rows` now also reads `email`/`phone`/`location`
  Kept on a NEW person (written straight onto the `Person` node, never crossing accounts); on a REUSED person (exact lowercase name match), filled only when the row has a value AND the existing field is still blank — same fill-blank-on-reuse rule `org`/`title` already use.

  ### `PersonDetail(person_id)` — shape unchanged
  `person.email`/`.phone`/`.links`/`.location` already serialize through the reported `Person` node (plain fields, no code change needed beyond confirming it).

  ### `ExportGraph()` — `people[]` entries gain `email`, `phone`, `links`, `location`
  Plain fields on the `Person` node, copied the same way `org`/`title`/`status` already are.
- 2026-09-26 — SOH-219 notes timeline, real dates, weekly digest. New modules `notes.sv.jac` and `dates.sv.jac`, no schema changes. `edits.sv.jac`'s `UpdatePromise(due)` now runs `due` through `dates.sv.jac`'s `parse_due` before storing it (report shape unchanged). Every walker below is `:priv`, own-root only, no `by llm`. `main.jac`: `import from notes { ListNotes, DeleteNote, ConfirmFact, Digest }`, `import from dates { NormalizeDates, UpcomingDates }`.
- 2026-09-26 — SOH-219 notes timeline, real dates, weekly digest. New modules `notes.sv.jac` and `dates.sv.jac`, no schema changes. `edits.sv.jac`'s `UpdatePromise(due)` now runs `due` through `dates.sv.jac`'s `parse_due` before storing it (report shape unchanged). Every walker below is `:priv`, own-root only, no `by llm`. `main.jac`: `import from notes { ListNotes, DeleteNote, ConfirmFact, Digest, DevSeedNote }`, `import from dates { NormalizeDates, UpcomingDates }` (`DevSeedNote` is a dev/test seeding helper, same convention as `DevAddPerson`/`DevMakeCard`/`GapDevSeed`).

  ### `parse_due(text: str, base_iso: str) -> str` — plain `def`, `dates.sv.jac`, not served
  Deterministic natural-language date parser used by `UpdatePromise`/`NormalizeDates`/`UpcomingDates`/`Digest`. Recognizes (case-insensitive, whitespace-stripped): a weekday name full or abbreviated ("Fri"/"Friday", always 1-7 days strictly after `base_iso`'s date, never the same day); "today"/"tomorrow"/"next week" (+7)/"end of month" (last day of `base_iso`'s month); "in N days/weeks/months" (month arithmetic clamps the day to the target month's length: Jan 31 + 1 month -> Feb 28/29); "in \<Month\>" (1st of that month, on/after `base_iso`'s date else next year); "\<Month\> D"/"\<Mon\> D"/"M/D" (that month/day, on/after `base_iso`'s date else next year); "YYYY-MM-DD" (returned as-is once validated as a real calendar date). Anything else, an invalid calendar date ("Feb 30"), or an unparsable `base_iso` -> `""`.

  ### `ListNotes(limit: int = 50, before: str = "", kind: str = "")` — SOH-219
  Reports one entry per Note, newest `captured_at` first:
  ```
  { note: Note, people: [{id, name}], counts: {facts, intents, promises}, text_preview: str }
  ```
  `kind` (non-empty) filters to that `Note.kind`. `before` is an ISO cursor: only Notes with `captured_at` strictly earlier than `before` are returned (page by passing the last item's `note.captured_at`). `people` = every Person the Note `Mentions`, deduped by jid. `counts` = the Note's own `Asserts`/`AssertsIntent`/`AssertsPromise` edge counts. `text_preview` = `note.text` cut at 140 chars on a word boundary, `"…"`-suffixed when truncated. `limit` clamped to `[0, 200]` (SOH-211 bounded-budget idiom).

  ### `DeleteNote(note_id: str)` — SOH-219
  Deletes the Note, and every Fact/Intent/Promise it asserts whose ONLY asserting Note it was (a claim another Note also asserts survives — only the dangling `Asserts*` edge to the deleted Note disappears, node-delete cascade). People are NEVER deleted. Deletion of each doomed Fact/Intent/Promise is delegated to `forget.sv.jac`'s `_forget_fact`/`_forget_intent`/`_forget_promise` (so `RelevantTo` evidence pruning stays in one place). Reports one dict:
  ```
  { deleted: {facts: int, intents: int, promises: int}, kept_people: int }
  ```
  `kept_people` = the number of distinct people the deleted Note `Mentions` (counted before the delete; the Person nodes themselves are untouched). `[{error: "not_found"}]` when `note_id` isn't a Note owned by the caller (same ownership idiom as `Forget`).

  ### `ConfirmFact(fact_id: str)` — SOH-219
  Sets `status = "confirmed"` on the caller's own Fact. Reports `[Fact]`, or `[{error: "not_found"}]` when `fact_id` isn't a Fact owned by the caller.

  ### `NormalizeDates()` — SOH-219
  Re-runs `parse_due` over every Promise's `due` and every Intent's `expires_at` reachable from the caller's own Notes; a non-empty result that differs from the stored raw text overwrites it (idempotent: an already-ISO value re-parses to the same string, a full ISO timestamp with a time component never matches any `parse_due` pattern and is left alone). Reports one dict `{ promises_updated: int, intents_updated: int }`.

  ### `UpcomingDates(days: int = 14)` — SOH-219
  Reports one dict:
  ```
  { promises: [{promise: Promise, to: Person|null, due: str}],
    intents_expiring: [{intent: Intent, about: Person|null, expires_at: str}],
    events: [{event: Event}] }
  ```
  `promises` = open (`done == False`) Promises whose `due` (re-parsed through `parse_due` so an un-normalized raw text still counts) lands in `[now, now + days]` inclusive, ascending by due date. `intents_expiring` = Intents with a set, parseable `expires_at` in the same window, ascending; `about` is the `IntentAbout` target or `null` for a self-onboarded Intent. `events` = the caller's own `HasEvent` Events with a set, parseable `date` in the same window, ascending. `days` clamped to `[0, 90]`.

  ### `Digest()` — SOH-219
  No args, deterministic, no `by llm`. Reports one dict:
  ```
  { week_of: str, promises_due: [...same shape as UpcomingDates.promises...],
    intents_expiring: [...same shape as UpcomingDates.intents_expiring...],
    new_people: [{id, name, how_met}], stale_ranking: bool,
    suggestions: [...same shape as Tend...], lines: [str] }
  ```
  `week_of` = the ISO date of the Monday starting the current week. `promises_due`/`intents_expiring` = `UpcomingDates`' own gathering with a fixed 14-day window. `new_people` = people the caller met (`Knows`) whose `source_note` resolves to a Note captured in the last 7 days (inclusive), newest first. `stale_ranking` = `true` when the active Goal's `ranked_at` predates a Note's `captured_at` (reuses `goals.sv.jac`'s own `ranking_is_stale` rule verbatim), `false` with no active Goal. `suggestions` = the top 3 items from `tend.sv.jac`'s `tend_for` (same shape as `Tend`'s report). `lines` = exactly five plain-English sentences (week-of, promise count, intent count, new-people count, ranking freshness) a phone can show as-is.
- 2026-09-26 — SOH-222 A1 (Settings data panel, client). `components/settings/DataPanel.cl.jac` +
  `components/mocks/data.cl.jac` + `components/api.cl.jac` wrappers `export_graph`, `list_archived`,
  `restore_person`, `delete_my_data`. `export_graph()` is live (`sv import from ..export { ExportGraph }`,
  SOH-210) — the panel downloads the report as `cirql-export-<YYYY-MM-DD>.json` via a Blob + object URL and
  shows `counts`. `ListArchived`, `RestorePerson`, `DeleteMyData` are **not yet on main** (parallel branch);
  the client calls them by name through `jacSpawn` (same pattern as `PersonDetail`/`Brief`) against these
  exact shapes, gated under `?mock=1`/`USE_MOCKS`:
  - `ListArchived()` -> `[Person]` (every `Person` with `archived == True`, restorable).
  - `RestorePerson(person_id: str)` -> `[Person]`, the caller's remaining archived people after clearing
    `archived` on `person_id` (own-root only; `person_id` not one of the caller's archived people -> no-op,
    same list returned unchanged).
  - `DeleteMyData(confirm: str)` -> `{ deleted: { people, facts, intents, promises, notes, goals, cards,
    circles, events }, ok: true }` when `confirm == "DELETE"` (counts of everything actually deleted off the
    caller's own root), or `{ error: "confirm_mismatch" }` otherwise — the client only ever sends
    `confirm="DELETE"` (button is disabled client-side until the user types it exactly), so the server-side
    check is defense in depth, not the only gate. Once `A`'s branch lands, flip these three to `sv import` +
    `root spawn` in `components/api.cl.jac` (comment there marks the swap point).
- 2026-09-26 — SOH-217, `circles.sv.jac` and `events.sv.jac` land: named groups the user puts people into, and where-we-met. Both `:priv`, own-root only, no `by llm`. Schema: no changes (`Circle`/`Event`/`HasCircle`/`InCircle`/`HasEvent`/`MetAt` already existed, SOH-215). `circle_id`/`event_id`/`person_id` are resolved directly among the caller's own `[me ->:HasCircle:->]` / `[me ->:HasEvent:->]` / `[me ->:Knows:->]` — isolated by construction, no `jobj` lookup of a foreign id, no grant ever given.

  ### `CreateCircle(name: str)` — SOH-217
  Get-or-create Me; create a named `Circle` via `HasCircle`. Reports `[Circle]`, or `[{ error: "exists" }]` when `name` (case-insensitively, stripped of surrounding/repeated whitespace) matches a circle this user already has.

  ### `RenameCircle(circle_id: str, name: str)` — SOH-217
  Reports `[Circle]` (the renamed node), `[{ error: "not_found" }]` when `circle_id` isn't one of the caller's own circles, or `[{ error: "exists" }]` when `name` collides (case-insensitively) with another circle this user already has (renaming a circle to its own current name is fine — the collision check excludes the circle being renamed).

  ### `DeleteCircle(circle_id: str)` — SOH-217
  Deletes the `Circle` node; the node-delete cascade removes its `HasCircle` edge from Me and every `InCircle` edge from a Person, but never the Person nodes themselves. Reports `[{ ok: true }]`, or `[{ error: "not_found" }]`.

  ### `AddToCircle(person_id: str, circle_id: str)` / `RemoveFromCircle(person_id: str, circle_id: str)` — SOH-217
  Attach/detach `InCircle` (Person -> Circle); `AddToCircle` is idempotent (attaching twice creates one edge). Reports `[{ ok: true }]`, or `[{ error: "not_found" }]` when `person_id`/`circle_id` don't resolve to the caller's own graph.

  ### `ListCircles()` — SOH-217
  Reports `[{ circle: Circle, count: int }]` for every circle the caller has; `count` = how many people are `InCircle` it. Empty list when there's no `Me` yet.

  ### `CreateEvent(name: str, date: str = "", location: str = "")` — SOH-217
  Get-or-create Me; create an `Event` via `HasEvent`. Reports `[Event]`.

  ### `ListEvents()` — SOH-217
  Reports `[{ event: Event, count: int }]`, newest `date` first (an event with no `date` sorts last); `count` = how many people `MetAt` this event. Empty list when there's no `Me` yet.

  ### `AddToEvent(person_id: str, event_id: str, source_note: str = "")` / `RemoveFromEvent(person_id: str, event_id: str)` — SOH-217
  Attach/detach `MetAt` (Person -> Event, carries `source_note`); `AddToEvent` is idempotent (attaching twice never overwrites `source_note`). Reports `[{ ok: true }]`, or `[{ error: "not_found" }]`.

  ### `EventPeople(event_id: str)` — SOH-217
  Reports `[Person]`, every person `MetAt` this event, or `[{ error: "not_found" }]` when `event_id` isn't one of the caller's own events.

  ### `UpdateEvent(event_id: str, name: str = "", date: str = "", location: str = "")` — SOH-217
  Only NON-EMPTY (stripped) args overwrite a field, same idiom `edits.sv.jac`'s `UpdatePerson` uses. Reports `[Event]`, or `[{ error: "not_found" }]`.

  ### `walkers.sv.jac`'s `ListPeople(circle_id: str = "", event_id: str = "", include_archived: bool = False)` — SOH-217
  Shape unchanged (`list[Person]`, no wrapper). Archived people (`Person.archived`) are excluded unless `include_archived=True`; a non-empty `circle_id`/`event_id` narrows to people with a matching `InCircle`/`MetAt` edge.

  ### `capture.sv.jac`'s `Capture(text, kind, audio_ref, how_met, event_id: str = "")` — SOH-217
  Shape unchanged. `event_id` non-empty and resolving among the caller's own `[me ->:HasEvent:->]` -> every NEW person this capture creates (`is_new: true` in the `people` report) gets a `MetAt(source_note=jid(note))` tie to that event; people the capture only re-mentioned are untouched. An unknown/foreign `event_id` is silently ignored (no MetAt attached, no error).
- 2026-09-26 — SOH-220 Lifecycle (`lifecycle.sv.jac`). All `:priv`, own root only, no model call.
  - `ArchivePerson(person_id: str)` / `RestorePerson(person_id: str)` → `[Person]` (the node, `archived` set to `true` / `false`), or `[{ error: "not_found" }]` for an unknown id or another account's person.
  - `ListArchived()` → `[Person, ...]` (one report per archived person the caller knows; `[]` when none).
  - Archived people are skipped by GoalRank candidates (fresh and cached), Tend, GamePlan (known + reported routes), ScoreAgainstNeed candidates (so ReplyToRequest / WhoNeedsWhatIHave never match them), PathFinder (never a hop or entry point), Serendipity, NetworkHealth, and Recall evidence (facts/intents/promises about them; a note keeps its text but never names them). Nothing is deleted; RestorePerson brings everything back. Report shapes of those walkers unchanged.
  - `DeleteMyData(confirm: str)` → `[{ deleted: { people, facts, intents, promises, notes, goals, cards, circles, events, other, files }, ok: bool }]` (all ints). Runs only when `confirm == "DELETE"`; otherwise all zeros and `ok: false`. Deletes every node the caller owns reachable from their root (Me, people, notes and their claims, goals, interests, card, circles, events, introductions, ReplyPrivate, ClaimedIntro, MergeRecord, ...), their own `CardListing` on the shared CardDirectory, and upload files their notes reference (`audio_ref` under `uploads/<file>` or `uploads/<caller root>/<file>` only; `other` counts Me/listings/remaining kinds, `files` counts removed files). Exchange requests/replies and handshake offers under `root.shared` are not touched. Another account is untouched.
  - `ImportGraph(data: dict, mode: str = "merge")` → `[{ imported: { people, facts, intents, promises, notes, goals, circles }, skipped: int, id_map_size: int, truncated: bool }]`, or `[{ error: "bad_mode" }]` for any mode other than `"merge"`. `data` is the `ExportGraph` report (extra optional keys read when present: person `email/phone/links/location/identity_tokens/archived`; `circles: [{id, name, members?: [person ids]}]`, `in_circle: [{person, circle}]`). Order: notes (reused when text + captured_at already exist; `audio_ref` kept only under `uploads/<caller root>/`) → people (reused by identity token, else by exact clean name + org; new ones get `Me -Knows->`, with the export's `how_met/status/last_contact/source_note` remapped and the `span` recreated as a Mentions edge from the source note) → Reported ties (need both people and a mapped source note) → facts/intents/promises under their mapped source Note with the same span, plus FactAbout/IntentAbout/PromiseTo (an intent about the exported Me gets `Me -HasIntent->`) → goals (inactive, except the first exported active goal when the caller has none active) → circles. A row whose source note or target id is unknown is skipped and counted in `skipped`. At most 5,000 nodes are created (`truncated: true` after that). Merge is idempotent: importing the same export twice creates nothing the second time.
- 2026-09-26 — SOH-222 A3, PersonSheet contact fields + archive (client, B). `PersonDetail`'s `person` already carries `email`/`phone`/`location`/`links`/`archived` as of the SOH-215..220 schema addition (it reports the whole `Person` node) — no server change needed to read them. Two walker shapes the client now calls by name (`jacSpawn`, same "may not be on main yet" pattern `PersonDetail`/`Brief` use in `components/api.cl.jac`); needs A to build against these exact shapes:
  ### `UpdatePerson(person_id: str, name: str = "", org: str = "", title: str = "", how_met: str = "", email: str = "", phone: str = "", location: str = "", links: list[str] = [])` — SOH-222, extends the SOH-166 shape
  Reports `[Person]` (the updated node) or `[{ error: "not_found" }]` — same `person_id` resolution as the existing 4-arg `UpdatePerson`. Only NON-EMPTY (stripped) `name`/`org`/`title`/`how_met`/`email`/`phone`/`location` overwrite their field; `links` overwrites (replaces, not merges) only when the caller sends a non-empty list. Never touches `Person.status`/`archived`/`Knows.last_contact`/any other edge.
  ### `ArchivePerson(person_id: str)` — SOH-222, new
  Reports `[Person]` (with `archived: true`) or `[{ error: "not_found" }]` — same `person_id` resolution (`[me ->:Knows:->]`) as `UpdatePerson`/`PersonDetail`. Soft delete only: sets `Person.archived = True`, hidden from lists and rankings (GoalRank/ListPeople should filter `archived` people out; restorable, no UI for that yet), never deletes/retracts any Fact/Intent/Promise/edge — unlike `Forget`.
  Client (`components/person/PersonSheet.cl.jac`): a header pencil button opens an inline form (name/org/title/how_met/email/phone/location/links-as-textarea, one link per line) that sends only changed fields non-empty, optimistic with rollback + an error line on failure. Read-only view is a "Contact" block (email `mailto:`, phone `tel:`, location, links `target="_blank" rel="noopener noreferrer"`), never shows `identity_tokens` (internal-only per AGENTS.md). "Forget this person" is now "Archive" (confirms: "Hides them from lists and rankings. Restore any time from Settings.") plus a "More" dropdown -> "Forget permanently" (the existing SOH-207 Forget flow, unchanged). Mocks: `components/mocks/person.cl.jac` `mock_update_person`/`mock_archive_person`, state in `MOCK_PERSON["overrides"]`/`["archived"]`.
- 2026-09-26 — SOH-222 A4, B builds Circles + Events screens (`components/circles/Circles.cl.jac`, `components/events/Events.cl.jac`) against these shapes; walkers are on a parallel A branch, not on main yet — `components/api.cl.jac` calls them via `jacSpawn` (same pattern as `PersonDetail`/`Brief`) until they land, then flip to `sv import` + `root spawn`. `Circle`/`Event` nodes and `HasCircle`/`InCircle`/`HasEvent`/`MetAt` edges already exist in `schema.sv.jac` (SOH-215). All `:priv`, own-root only. Mocks in `components/mocks/circles.cl.jac`.

  ### `CreateCircle(name: str)`
  `[Circle]` (`{ _jac_id, name, created_at }`) or `[{ error: "exists" }]` (case-insensitive name match against the caller's own circles).

  ### `RenameCircle(circle_id: str, name: str)`
  `[Circle]` (updated) or `[{ error: "not_found" }]`.

  ### `DeleteCircle(circle_id: str)`
  `[{ ok: true }]` or `[{ error: "not_found" }]`. Deletes the `Circle` node and its `InCircle` edges only — the people in it are untouched (no cascade to `Person`, `Knows`, or anything else).

  ### `AddToCircle(person_id: str, circle_id: str)` / `RemoveFromCircle(person_id: str, circle_id: str)`
  `[{ ok: true }]` or `[{ error: "not_found" }]`. Idempotent (adding an existing member / removing a non-member is still `{ ok: true }`).

  ### `ListCircles()`
  `[{ circle: Circle, count: int }, ...]`, one row per circle the caller owns; `count` = number of `InCircle` members.

  ### `CreateEvent(name: str, date: str = "", location: str = "")`
  `[Event]` (`{ _jac_id, name, date, location }`). `date` is a plain ISO date string (`YYYY-MM-DD`) when set, else `""`; no uniqueness check (unlike `CreateCircle`).

  ### `UpdateEvent(event_id: str, name: str, date: str, location: str)`
  `[Event]` (updated) or `[{ error: "not_found" }]`. No `DeleteEvent` walker — events are edited, not removed.

  ### `ListEvents()`
  `[{ event: Event, count: int }, ...]`. Report order is unspecified; the client sorts newest-`date`-first (events with no date sort last).

  ### `AddToEvent(person_id: str, event_id: str)` / `RemoveFromEvent(person_id: str, event_id: str)`
  Same shape as `AddToCircle`/`RemoveFromCircle`.

  ### `EventPeople(event_id: str)`
  `[Person, ...]` — everyone attached to that event via `MetAt`. Same `Person` shape as `ListPeople`.

  ### `ListPeople(circle_id: str = "", event_id: str = "", include_archived: bool = False)` — extends the existing no-arg `ListPeople`
  Same `[Person, ...]` shape. `circle_id` set -> only that circle's `InCircle` members; `event_id` set -> only that event's `MetAt` attendees (mutually exclusive; `circle_id` wins if both are set); neither set -> every known person, exactly today's behavior. `include_archived` (default `False`) -> `Person.archived == True` rows are dropped unless `True`.
- 2026-09-26 — SOH-222 A5 (`components/search/SearchBox.cl.jac`, OWNER: Person B). Client-only change, no walker shape touched — noted here since it's the first consumer of `Search`:
  - `components/api.cl.jac` gains `search(query, limit=25, kinds=[])` and `recall(question, max_items=40)`. Both are now live: `search()` calls `sv import from ..search { Search }` (`root spawn`, SOH-216 landed on `main`); `recall()` calls the live `sv import from ..recall { Recall }` (`root spawn`, SOH-189). No client shape change needed either way — the mocks (`components/mocks/search.cl.jac`) already matched the documented shapes exactly.
  - Both gated by the existing `mocks_on()`/`?mock=1` switch; `components/mocks/search.cl.jac` adds `mock_search`/`mock_recall` fixtures reusing the SAME pseudonymous people `components/mocks/person.cl.jac`/`goalrank.cl.jac` already use (Maya Chen, Dev Okafor, Lena Park, Sam Ruiz), so a result's person link or a Recall citation chip opens a person sheet with real data instead of two mocks disagreeing on ids.
- 2026-09-26 — SOH-222 (client, brief C notes): `components/notes/Timeline.cl.jac` needs a notes timeline. These two walkers do not exist on any `*.sv.jac` branch yet — built against this shape via `components/mocks/notes.cl.jac` and `jacSpawn("ListNotes"/"DeleteNote", ...)` in `components/api.cl.jac` (same not-yet-live pattern as `PersonDetail`/`Brief`). A: please build to this shape, or comment on SOH-160 with a different one.

  ### `ListNotes(limit: int = 50, before: str = "", kind: str = "")`
  Reports one row per Note the caller owns, newest first by `captured_at`:
  ```
  [{ note: Note, people: [{ id: str, name: str }],
     counts: { facts: int, intents: int, promises: int }, text_preview: str }]
  ```
  `kind` ∈ `"" | about_me | debrief | paste | import | enrich` (`""` = every kind). `before`, when set, is an ISO `captured_at`: only rows strictly OLDER than it are returned (exclusive), for "Load older" paging. `people` is every Person the note `Mentions` (their current name); `counts` are how many Facts/Intents/Promises this note is the sole source of (see `DeleteNote`). `text_preview` is the note's first ~160 chars (+ `"…"` if truncated) for the collapsed row; the client shows the full `note.text` on expand.

  ### `DeleteNote(note_id: str)`
  Reports one object:
  ```
  { deleted: { facts: int, intents: int, promises: int }, kept_people: [str] } | { error: "not_found" }
  ```
  Deletes the Note itself, plus every Fact/Intent/Promise reachable from it via a single `Asserts*` edge that has no OTHER Note asserting the same claim (a fact/intent/promise with two source notes loses only the `Asserts*` edge to this one and survives). Every Person the note `Mentions` is kept regardless — `kept_people` lists their ids. `not_found` when `note_id` isn't a Note the caller owns.
- 2026-09-26 — SOH-222 correction (client, brief C notes): the `ListNotes`/`DeleteNote` shape drafted above (before `notes.sv.jac`, SOH-219, landed on `main`) got one field wrong — `DeleteNote`'s `kept_people` is an `int` (count), not `[str]`. `components/api.cl.jac` now calls the live walkers via `sv import` + `root spawn`; `components/mocks/notes.cl.jac` updated to match. `Timeline.cl.jac` never rendered `kept_people`, so this was a documentation-only fix. Everything else (both `ListNotes` and `DeleteNote`) matches as shipped.
- 2026-09-26 — SOH-223 Agent inbox (`agent.sv.jac`). All `:priv`, own root only, no model call. Nothing sends.
  - **Schema** (additive): `node AgentAction { kind, title, why, evidence: [str], person_id = "", goal_id = "", request_id = "", draft = "", payload_json = "", status = "open", created_at = "", resolved_at = "", source_walker = "", dedup_key = "", approval_source = "" }` under `Me -HasAction->`; `node AgentRun { ran_at, reason, model_backed = false, strengths_json = "" }` under `Me -HasAgentRun->` (throttle + previous RelevantTo strengths).
  - `kind`: `new_match | ask_network | route | promise_due | follow_up | reconnect | answer_ask`. `status`: `open | approved | dismissed | snoozed`. `dedup_key` = `"<kind>|<person_id>|<goal_id>|<request_id>|<extra id>"` (extra = route target / Tend evidence id). `evidence` is never empty (no evidence, no action); `why` quotes evidence text. Titles never carry a person-level score (a strength is always (Person, Goal)).
  - `RunAgent(reason: str = "manual")` →
    ```
    [{ run_id: str, ran_at: str, new: int, total_open: int, skipped: [str] }]   // or [{ error: "not_found" }] before onboarding
    ```
    Steps (deterministic): `new_match` = active goal(s)' `RelevantTo` strong/medium with resolvable evidence (first run: strong only; later runs: only when the (person, goal) strength rose since the previous run; `payload_json = {strength, prev_strength}`, `draft` = the edge's cached opener). `ask_network` = an active goal with no warm (known/route, strong/medium) path (`gaps.warm_lines_for` empty; GapFinder's per-kind list needs the model) → `evidence = [goal_id]`, `draft` = need, `payload_json = {need, about_line}`. `route` = top 2 of those gaps × 1 evidenced `PathFinder` route to a reported person whose title/org shares a word with the goal → `person_id` = the connector, title `"<Connector> knows someone at <Org> — ask <Connector>?"`, template draft to the connector, `payload_json = {target_id, connector_id}`. `promise_due` / `follow_up` / `reconnect` = Tend's `open_promise` / `expiring_intent` / `stale_fact` (never decay), draft = DraftFollowUp's template; promise_due `payload_json = {promise_id, complete: false}`. `answer_ask` = incoming requests visible to me (same filter as ListIncomingRequests, 10 newest) where ScoreAgainstNeed's deterministic fallback finds ≥ 1 candidate → `request_id`, evidence = my matching Fact/Intent ids. Serendipity: skipped (`skipped` always contains `"serendipity"`; `"throttled"` appears only when a model-backed step is added and one ran in the last 10 minutes).
    Upsert: a `dismissed` key is never re-proposed; an `open` key is refreshed (title/why/evidence/payload), never duplicated; every `snoozed` action reopens at the start of the next run; an `approved` new_match reopens only when its strength rose. `new` = actions created or reopened by this run.
  - `ListAgentActions(status: str = "open", limit: int = 30)` (`status: "all"` for every status; limit 1..100) → one report per action, newest first (by minute), `promise_due` first within the same minute:
    ```
    { action: AgentAction, person: Person | null, evidence: [{ id, kind, observed_at, span }] }
    ```
    `evidence` resolved through Receipt's `receipt_for` on the caller's own nodes (`observed_at` = the source Note's `captured_at`; `kind` includes `goal` and `note`).
  - `ResolveAgentAction(action_id: str, decision: "approve" | "dismiss" | "snooze", edited_draft: str = "", complete: bool = false)` →
    ```
    [{ action: AgentAction, result: dict }]   // or [{ error: "not_found" | "invalid_state" }]
    ```
    Only an `open` or `snoozed` action resolves; an unknown decision is `invalid_state`; another account's id is `not_found`. `approval_source = "in_app"` and `resolved_at` set on approve; `resolved_at` also on dismiss/snooze. `edited_draft` (non-blank) replaces `draft`.
    `result` by kind on approve: `ask_network` → `{ step: "PostRequest", request: IntroRequest }` (need = `edited_draft` if given, else the payload need; audience `"everyone"`; the action's `request_id` becomes the new request); `answer_ask` → `{ step: "ReplyToRequest", reply: ReplyView }`; `promise_due` with `complete: true` (arg or payload) → `{ step: "CompletePromise", promise: Promise }`, else `{ step: "none", draft }`; `new_match | route | follow_up | reconnect` → `{ step: "draft_saved", draft }`. If the mapped step fails, `result` is its `{ error }` and the action stays as it was. Dismiss → `{ step: "dismissed" }`; snooze → `{ step: "snoozed" }`.
  - `DevSeedAgent(tag: str = "")` DEV/TEST ONLY: seeds the caller's root (goal + strong evidenced RelevantTo, a no-warm-path goal, a reported route, an open promise) and reports the ids. Never call it from the client.
  - Refactors (no shape change): `exchange.post_request(...)` / `exchange.reply_to_request(request_id)` are the PostRequest / ReplyToRequest bodies as plain defs; `gaps.warm_lines_for(me, goal)` is GapFinder's warm-line builder.
- 2026-09-26 — SOH-223 amendment (review + B's client comment). Supersedes the matching lines of the SOH-223 block above:
  - `ResolveAgentAction` approve `result`: `ask_network` → `{ step: "posted", request: IntroRequest }`. The need is `edited_draft` when it is non-blank, else `payload.need`; the about line is `payload.about_line`; the audience is `"everyone"`. The client lists the request under "Your asks". `answer_ask` → `{ step: "replied", reply: ReplyView }` (from `reply_to_request`). The client resolves first, then opens its reply flow on the returned reply. Other kinds are unchanged (`CompletePromise` / `none` / `draft_saved`).
  - `answer_ask` `dedup_key` = `"answer_ask|<request_id>"` only, so a dismissed ask stays dismissed when the top candidate changes. The top candidate's id is also in `payload_json.top_person_id`, and `person_id` still carries it.
  - Evidence ids are kept only when `reads.my_node` resolves them (readable AND owned by the caller) to a Fact / Intent / Note / Goal / Promise.
  - `ListAgentActions` evidence for a Goal is `{ id, kind: "goal", observed_at: Goal.created_at, span: Goal.text }`.
- 2026-09-26 — SOH-225 (population-run fixes, `goals.sv.jac` / `onboard.sv.jac` / `capture.sv.jac`). No report SHAPE change for `SetGoal`/`OnboardMe`; `Capture`'s shape gains one additive field.
  - `SetGoal(text: str)` now reuses an existing goal instead of creating a near-duplicate: `goals.goal_texts_match(a, b)` normalises both texts (lowercase, strip punctuation, keep words >= 4 chars, drop a short stopword list) and matches when the Jaccard similarity of the two word sets is >= 0.6 or one normalised text contains the other. If a match is found among the caller's goals, `SetGoal` sets it active and deactivates the rest (creating nothing); otherwise behavior is unchanged. `OnboardMe` applies the same `goal_texts_match` (via `onboard.find_goal_by_text`, now near-duplicate rather than exact-text) both against goals already on the root and among the goals its own extraction call proposes, so a batch with two near-duplicate asks still yields one `Goal`, with the first surviving one active as before.
  - `Capture(text, kind, audio_ref, how_met, event_id)`'s report gains `skipped_people: int` (0 when nothing was skipped): the extraction sem now tells the model that a bare relation/role word ("her manager", "a friend", "the CEO", "my roommate") is not a person and should become a fact on the named person it relates to, or be dropped. As defense-in-depth, `capture.is_role_only(name)` is a deterministic guard applied in `apply_extraction`: any extracted person, fact/intent-subject, promise-recipient, or tie-endpoint whose stripped lowercase name is a bare role word or matches `^(his|her|their|my|our|a|an|the|this|that|some) (manager|boss|friend|colleague|coworker|co-worker|co-founder|cofounder|partner|roommate|teammate|advisor|assistant|ceo|cto|cfo|founder|investor|professor|teacher|dad|mom|father|mother|brother|sister|wife|husband|girlfriend|boyfriend|son|daughter|cousin|neighbor|neighbour)$` is skipped — no Person node is created for it, and any fact/intent/promise/tie that would have pointed at it is dropped too. `skipped_people` counts the distinct such names skipped across the whole call. A name with any distinguishing context beyond the role word ("the tall girl from the climbing gym", "the young man from the robotics thing who built the wheelchair sensor") is unaffected and still becomes a Person as before.
- 2026-09-26 — SOH-164 (`onboard.sv.jac`). No report shape change for `OnboardMe`. Fixes the "empty Goals / For your goal: —" bug: an about-me that only phrases its ask as a need (never says "my goal") was extracting `goals: []`.
  - `OnboardExtraction.goals`'s sem is broadened: a goal is now any outcome the writer is working toward in the coming months, whether or not they call it a goal (raising a round, landing an internship/job, recruiting participants, finding a co-founder, getting feedback), phrased as the ask, not a description of what they build.
  - Deterministic backstop for when the model still returns no goal: after `collect_goals` dedupe, if `goals` is empty and there is at least one `need` intent this call extracted, `onboard.promote_strongest_need` promotes `onboard.strongest_need(needs)` (the longest need text naming an outcome per `has_outcome_keyword` — raise/land/get/find/hire/recruit/close/launch/ship/intro/internship/job/funding/round/feedback/participants/co-founder/customers/pilot — else the first need) to an active `Goal` under `me`, get-or-created like any other goal (`find_goal_by_text` against goals already on the root first). The promoted text is also still a `need` Intent — promotion never removes it. No-op when `goals` already has something or there were no needs.
  - `looks_like_goal`'s bad-prefix filter ("I am"/"I'm"/"I build"/"I work"/"we build"/"we are") is loosened: a candidate that starts with one of those prefixes still counts as a goal if it names an outcome (`has_outcome_keyword`), so an ask phrased like a need ("I'm raising a pre-seed round...") is not thrown out for its phrasing alone.
  - Verified live (curl, port 8041, real Gemini call): "I'm a senior at Michigan building thermal batteries for small factories. I'm raising a pre-seed this fall and want intros to climate-tech investors. I can help student founders with hardware prototyping." now extracts `goals: [{text: "Raise a pre-seed round from climate-tech investors this fall", active: true}]` directly (the broadened sem alone resolved this repro; the promotion backstop is proven by `onboard.test.jac`'s no-LLM fixture tests, not exercised in this particular live call).
- 2026-09-26 — SOH-226 In-app account deletion (`account.sv.jac`), App Store guideline 5.1.1(v). `:priv`, own root only, no model call.
  - **Runtime investigation** (this venv has NO `jac-scale`/`jaseci` installed — plain `jaclang 0.16.7` serves auth): `jaclang.runtimelib.server.UserManager` (SQLite `users(username, password_hash, token, root_id)`, one file at `<base_path>/.jac/data/main.db`) has no `delete_user`/`remove_user` and no lookup from `root_id` back to `username`; `update_username`/`update_password` both re-verify the CURRENT username/password first, which a walker never has (only a valid JWT, already consumed before the walker runs). So none of `/user/register|login|info`, `PUT /user/username`, `PUT /user/password` can be driven from inside a walker to erase or disable the row as-is.
  - `DeleteAccount(confirm: str)` → `[{ ok: bool, deleted: <same shape as DeleteMyData's counts>, identity_removed: bool, identity_disabled: bool }]`. Runs only when `confirm == "DELETE"` (else all-zero counts, `ok: false`, both identity flags `false`, nothing touched). On confirm: wipes the graph via `lifecycle.delete_my_data()` (imported, not duplicated), then disables the auth identity the safest way this runtime allows — opens the SAME on-disk SQLite file the runtime's own `UserManager` uses (path resolved the same way `UserManager.postinit` does; `Jac.get_context().base_path_dir`, falling back to `Jac.get_base_path_dir()` then `os.getcwd()` — the context value is preferred because it is NOT run through `set_base_path`'s `isdir(...) else dirname(...)` fallback, which can point at the wrong directory when the data dir doesn't exist yet, e.g. under a fresh `JacTestClient`) and runs one UPDATE: rotates the password hash to a random 32-byte secret (`hashlib.sha256`, matching `UserManager`'s own scheme), rotates the `token` column to a random 32-byte secret too (one step further than `PUT /user/password` bothers with, so the caller's current bearer token is rejected on its very next use, not just at JWT expiry), and renames the username to `deleted-<8 hex>` so the old username/email is free to re-register. `identity_removed` is always `false` (no API removes the row outright); `identity_disabled` is `true` only when a row for this root was actually found and rewritten (`false` if the db file doesn't exist yet or the write failed — the graph wipe still happened either way).
  - Verified live (JacTestClient + a real `jac start` + curl): after `DeleteAccount(confirm="DELETE")`, the caller's old bearer token gets `401` on the next walker call, `/user/login` with the old username/password returns `401 UNAUTHORIZED`, and re-`POST /user/register`-ing the old username succeeds with a brand-new `root_id`. Account B, and every other row, untouched.
- 2026-09-26 — SOH-223 tune (B's live feedback on a real 25-person account: first `RunAgent` produced 19 actions — 8 `new_match` for every strong person, 8 `answer_ask` including "experienced nurses..." on an account with no nurses). `agent.sv.jac` only; no report SHAPE change (`RunAgent` / `ListAgentActions` / `ResolveAgentAction` all unchanged from the blocks above) — this tightens which findings get proposed and what `answer_ask`'s `why` says.
  - `new_match`, first run for the account ONLY (`prior_strengths(me)` returns `None` — verified by reading back a real previous `AgentRun.strengths_json`, not just assuming it): at most the top 3 candidates across every active goal are proposed, never more — strong ranks before medium, ties (same rank) broken by newest evidence (`observed_at` on the cited evidence item, descending). The other qualifying candidates are still recorded in `current` (so next run's `prior` sees their real strength) but not created. On every later run (`prior` is not `None`): unchanged — propose only when `_rank(strength) > _rank(prev)` (a real rank rise since last run), no cap. Either way, a key already tracked by an `AgentAction` is NEVER re-proposed while that action is `open`, `approved` or `dismissed` (an `open` action is refreshed in place, never duplicated; `approved`/`dismissed` are left alone — the previous behavior of reopening an `approved` new_match on a further rise is removed, since a decision was already recorded for it).
  - `answer_ask`: `scoring.fallback_results` (unchanged, still the module's own; not edited) is used only as a cheap ≥1-token pre-filter. A candidate is now kept only when either it already carries a cached scorer strength of `strong`/`medium` (none this weekend — `score_need` is never called from this deterministic module — kept so a future cached score bypasses the gate without a second one), or **at least 2 distinct need tokens** (`scoring.fallback_tokens`: lowercased, alphanumeric, ≥ 4 chars, not a stopword) name something in that ONE candidate's own facts/intents/title/org text — never anywhere else on the root. Token identity allows a simple prefix relation (`nurse` <-> `nurses`) so a plural/verb-form need still matches a candidate's own wording. Capped at 5 proposals per run (`AGENT_MAX_ANSWERS`), newest request first (unchanged ordering; `AGENT_MAX_REQUESTS = 10` still bounds how many requests are scanned). `why` now names the matched tokens: `"...; N person(s) in your graph may fit: \"<quote>\" (matches: <token>, <token>). Replying shares a count and a strength, no names."`; `payload_json` gains `matched: [str]` (additive).
  - Verified: `jac check agent.sv.jac agent.test.jac main.jac` clean; `jac test agent.sv.jac` — 121 tests, all green, including three new ones — first-run cap (6 strong/medium candidates -> exactly the 3 newest STRONG ones proposed, both mediums excluded regardless of their newer evidence), a medium -> strong rise on a later run (0 proposed unchanged, 1 proposed after the rise), and an `answer_ask` round-trip through a real `RunAgent` (a "experienced nurses in Detroit" ask against an account with no nurse/hospital/Detroit tokens anywhere -> 0 `answer_ask`; after adding one person whose own Fact says "nurse at Michigan Medicine, Detroit" -> exactly 1 `answer_ask`, `why` containing `"(matches: nurses, detroit)"`).
- 2026-09-26 — SOH-226 `ExportContacts` (`export.sv.jac`) lands: "take my contacts out of Cirql" as one VERSION:3.0 vCard file (RFC 6350). `:priv`, own-root only, no `by llm`. Schema: no changes.

  ### `ExportContacts()` — SOH-226
  Reports one dict:
  ```
  { vcf: str, count: int }
  ```
  No `Me` yet -> `{ vcf: "", count: 0 }`. `count` = the number of active (non-archived) people the caller `[me ->:Knows:->]` (`lifecycle.active_people(me)`, same filter every other list uses — an archived person is excluded, same as everywhere else). `vcf` is that many `BEGIN:VCARD…END:VCARD` blocks, CRLF-terminated, concatenated in `active_people`'s order (no folding — every value here is short). Per person: `N:<family>;<given>;;;` and `FN:<name>` (name split on the LAST space into family/given; no space -> the whole name is `family`, `given` is empty); `ORG`/`TITLE`/`EMAIL`/`TEL` when that field is non-empty; one `URL:` line per non-empty entry in `links`; `location` (non-empty) as `ADR:;;;<location>;;;` (locality component only — no street/region/postal/country captured); a single `NOTE:` line, present only when the caller's own `Knows` edge to that person has `how_met` and/or `source_note` set (`"Met via <how_met>"` / `"Source note: <source_note>"`, joined with `"; "` when both are set). Every text value is escaped per RFC 6350 §3.4: backslash first, then comma, then semicolon, then any CR/LF folded to a literal `\n` escape. `build_vcard(p, ke)` renders one card and `build_contacts_vcf(me)` is the deterministic, testable core (mirrors `build_export`'s pattern); the walker resolves "the" caller's `Me` via `[root --> [?:Me]][0]`, same idiom and same caveat as `ExportGraph`. `main.jac`: `import from export { ExportGraph, ExportContacts }`.

- 2026-09-27 — SOH-226 `DeleteAccount`: `ok` is now `true` only when BOTH the graph wipe and the identity rotation happened (`ok == deleted_ok and identity_disabled`); a wiped graph whose login could not be disabled reports `ok: false, identity_disabled: false` so the client can say so. `ExportContacts`: `URL` lines are raw URIs (no text escaping of `;`/`,`; CR/LF stripped).
- 2026-09-26 — SOH-212 judge-pass fixes (`gaps.sv.jac`, `onboard.sv.jac`, `drafts.sv.jac`). No report shape changes.
  - **`GapFinder`**: a proposed gap `kind` is now also dropped when any ACTIVE known person (own root; `Person.status == "confirmed"`, not archived — same test `scoring.collect_candidates` uses) already covers it, even if that person has no (yet-scored) warm `RelevantTo` tie to this particular goal — the LLM's own `covered_by` only ever sees the warm people it was shown in `warm_people`, so it had no way to know about someone who covers the kind but isn't warm YET. Rule (`gaps.kind_covered_by_person`, reusing `scoring.fallback_tokens`'s tokenizer/stopword list): >= 1 shared meaningful token (lowercased, alnum, >= 4 chars, non-stopword) between the kind and that person's `title`+`org`, OR >= 2 shared tokens with their own Fact texts (facts are noisier free text, so a single shared word isn't enough on its own). Also: the words "score"/"scores"/"scoring" are banned from `why_needed`/`suggested_need` — the `sem` says so, and `gaps.strip_score_words` (word-boundary, case-insensitive -> "results") enforces it deterministically as a backstop.
  - **`OnboardMe`**: every stored goal/intent/interest text is now passed through `onboard.clean_text` (strips a trailing run of `.`/`!`/`?`/whitespace — nothing in the middle) at the point it is stored, so a client template that appends its own punctuation ("For your goal: {text}, here's...") never renders a doubled stop ("...JacHacks., here's"). **Needs B**: the onboarding "bring five people" paste step (`components/onboarding/PeopleStep.cl.jac` -> `Capture(text, kind="paste")`) currently leaves `how_met` empty, so those people get `capture.sv.jac`'s generic `default_how_met("paste", ...)` -> "from a pasted note on 2026-09-26". `capture.sv.jac`'s own default is intentionally untouched (it's shared by every other paste); instead `onboard.sv.jac` now exports `onboarding_added_how_met(now: datetime | None = None) -> str`, a human, hand-written-style date sentence — "added when you set up Cirql (Sep 26)" (`onboard.month_day`: `strftime("%b ") + str(dt.day)`, no leading zero). The onboarding paste call should pass `how_met=onboard.onboarding_added_how_met()` to `Capture` (already accepts an explicit override, SOH-166) instead of leaving it blank.
  - **`agent.sv.jac`'s `promise_due` draft** (via `drafts.fallback_draft`, which it already reused — no duplication): the promise's stored text is verb-first by design (`capture.sv.jac`'s `XPromise.text` sem: "send the ROI deck"), so gluing it straight after "following up on" read as a verb-form clash ("following up on send company's intern posting"). `drafts.promise_noun_phrase` now renders it as a noun phrase when the text starts with a short list of commitment verbs (send/intro/introduce/share/forward/connect): "About the company's intern posting I said I'd send: here it is." (no double article when the text already has its own, e.g. "the ROI deck"); anything else is quoted plainly ("About what I said I'd do: <text>."). The optional context clause (a related Fact) is now only appended when that fact's own text is under 80 chars, with its own trailing stop stripped first, so the draft can never end in "..".
- 2026-09-27 — SOH-179 `MyCard` (`cards.sv.jac`) lands: the card editor's own-root read (the editor previously had no owner-side read and went through `ExportGraph`'s whole-graph shape instead). `:priv`, own-root only, no `by llm`. Schema: no changes.

  ### `MyCard()` — SOH-179
  Reports one dict:
  ```
  { found: bool,
    card: { name, handle, headline, about, looking_for, can_offer, links, contact_pref, updated_at, visibility },
    handle: str }
  ```
  Same field set `get_card` returns, plus `visibility` — but unlike `get_card`, returns the caller's Card regardless of `visibility` (a `handshake_only` card is still returned to its own owner; `get_card`'s refusal of anything but `visibility=="link"` does not apply here) and unlike `PublishCard`, never writes anything. Resolution is `PublishCard`'s own idiom: `[root --> [?:Me]]` then the `Me ->:Owns:-> Card` edge — both own-root, so the typed traversal is safe (the "typed traversal drops cross-owner edges after a restart" gotcha only applies to containers OTHER users attach to, e.g. `root.shared`/`CardDirectory`, not a caller's own Me/Card). `found: false` with all-empty `card` fields (`visibility: ""`) and top-level `handle: ""` when there is no Me yet or no Card yet. `main.jac`: `import from cards { PublishCard, get_card, MyCard }`. `components/api_card.cl.jac`'s `my_card()` now calls `MyCard` directly instead of reading `ExportGraph`'s `card` field.

- 2026-09-27 — SOH-223 `promise_due` actions: `payload_json` gains `due` (the Promise's `due` string, `""` when none) so the Inbox can label the card "Due Mon Sep 28" instead of the action's age.

- 2026-09-27 — SOH-179 (follow-up) `Card.interests` lands: the card's own public one-per-line interests list, distinct from the private `node Interest` (never copied onto the card automatically — the owner types it into the card editor). Schema: `node Card` gains `has interests: list[str] = []`. `PublishCard(interests: list[str] = [])` follows the exact same non-empty-overwrite rule as `looking_for`/`can_offer`/`links` (an empty `interests` argument on republish keeps the stored value). `get_card` and `MyCard` both add `interests` to their returned `card`/dict shape (right after `links`, before `contact_pref`); a card published with no interests reports `interests: []`. `export.sv.jac`'s `card_dict` (used by `ExportGraph`) adds `interests` alongside the other explicit Card fields. `cards.test.jac`: "cards 9" covers publish-with-interests -> `get_card`/`MyCard` both return them, an empty-list republish keeps the old values, and a card published without interests returns `[]`; the exact-key-set assertions in "cards 1" and "cards 5" now include `interests`. Client (SOH-179, Person B territory but landed here as part of the same field): `components/api_card.cl.jac`'s `publish_card_full` gains an `interests: list[str]` parameter threaded straight through to `PublishCard`; `CardEditor` gets an "Interests (one per line)" textarea (same `_clean_lines` idiom as Looking for/Can offer); `CardPreview` renders them as badges under an "Interests" label, same shape as `looking_for`/`can_offer`; `components/mocks/card.cl.jac` updated to match.

- 2026-09-26 — SOH-212 judge3-pass fixes (`drafts.sv.jac`, `agent.sv.jac`). No report shape changes.
  - **`drafts.fallback_draft`** (reused as-is by `agent.sv.jac`'s `promise_due` draft): the greeting now uses the person's FIRST name only (`drafts.first_name`, splits on the first space — "Sarah Lin" -> "Hi Sarah,"), never the full name. The promise noun-phrase's closing clause (`drafts.promise_noun_phrase`) is now "sending it over now." for a singular deliverable and "sending them over now." for a plural one — `drafts._looks_plural` treats the noun phrase's last word as plural when it ends in "s" (except a short known-singular exception list, currently `["news"]`); "the ROI deck" -> it, "the intro notes" / "the notes on the Jac teams" -> them. The optional context-clause Fact is now NEVER spliced straight after "with" unless that fact's own text opens with a trusted lowercase noun-phrase prefix (`drafts._fact_is_spliceable`: "the ", "your ", "her ", "his ", "their ") — a fact like "Works in ML at Google and is a fellow judge this weekend" (capitalized, verb-first) is dropped and the draft ends with the plain "Hope things are going well." instead of "...well with Works in ML at Google...". `Person.org` is unaffected (an org name reads fine after "with"). Verified against the exact judge3 repro: `fallback_draft` on a promise "send the notes on the Jac teams" + fact "Works in ML at Google and is a fellow judge this weekend" now produces exactly `"Hi Sarah, About the notes on the Jac teams I said I'd send: sending them over now. Hope things are going well."`.
  - **`agent.sv.jac` `run_agent_for`**: a still-`open` `ask_network` AgentAction for an active goal is set to a NEW status, `status = "stale"` (added to the `AgentAction.status` comment in `schema.sv.jac`, alongside `open | approved | dismissed | snoozed`), with `resolved_at` = now and `approval_source = "agent:warm_path_found"` (added to the `approval_source` comment), the run that `gaps.warm_lines_for(me, goal)` — the same test `gap_goals` already uses to decide whether to keep proposing `ask_network` for that goal — first comes back non-empty for it (`agent.stale_ask_network_actions`, called from `run_agent_for` right after `gap_goals`, before `step_ask_network`). `ListAgentActions`' default `status="open"` listing already excludes `stale` (same as `dismissed`/`approved`/`snoozed`) since it isn't `"open"`; `status="all"` still shows it. `upsert`'s existing "a key already tracked by an AgentAction is never re-proposed" rule now also covers `stale` (comment updated) — moot in practice, since `step_ask_network` only proposes for goals still in `gaps`, so a goal with a warm path never generates a new `ask_network` finding to upsert in the first place.
  - Verified: `jac check drafts.sv.jac drafts.test.jac agent.sv.jac agent.test.jac main.jac` clean; `jac test drafts.sv.jac` — 33 tests, all green (incl. the exact judge3 repro, a singular "the ROI deck" and plural "the intro notes" case, and a trusted-prefix fact still splicing); `jac test agent.sv.jac` — 143 tests, all green (incl. a 3-run sequence: goal has no warm path -> `ask_network` open; a strong known `RelevantTo` edge added -> that run reports `new: 0` and the action is `stale` with `approval_source: "agent:warm_path_found"`; a third run still reports `new: 0` and the action stays `stale`, never reopened).

- 2026-09-27 — SOH-226 (B, client-only so far). **Request for A:** `ListPeople` (`walkers.sv.jac`) currently reports bare `list[Person]` — no per-row `Knows.last_contact`/`how_met` (those live on the `Knows` edge, not `Person`; `PersonDetail` already resolves them for a single person the same way `filter_people`'s traversal would need to for every row). The People List's new "Quiet 90+ days" filter (client, `components/HomeView.cl.jac`) needs both per row to be anything but inert. **Ask:** add `last_contact: str` and `how_met: str` to each `ListPeople` row (e.g. report a `{ person: Person, last_contact: str, how_met: str }` wrapper, or copy both fields onto a client-only dict alongside `Person` — whichever keeps `filter_people`'s existing archived/circle/event filtering intact) without removing the existing shape callers rely on; then a `walkers.test.jac` case and a line here confirming the new shape. Until then, `HomeView.cl.jac` reads `person["last_contact"]`/`person["how_met"]` defensively (client `.cl.jac` dict-key access returns `undefined`/falsy on a missing key, never a crash) — every row shows as quiet with "no notes yet" today; the moment the field lands the filter/labels start reflecting real data with no client change needed. Landed today, client-only: People sub-tabs 7 -> 4 (List · Graph · Today · More, with Circles/Events/Notes under More, `more_choice` remembered in component state) and Import moved to a "+" (`aria-label="Add people"`) on the List heading, opening `ImportPeople` in place — no change to `ImportPeople.cl.jac` itself, no walker/report-shape change.

- 2026-09-27 — SOH-226 `ListPeople` rows are now flat dicts: every Person field the client already read (`_jac_id`, `name`, `org`, `title`, `status`, `archived`, `email`, `phone`, `links`, `location`, `identity_tokens`) plus the caller's `Knows.last_contact` and `how_met` (display only; nothing ranks or decays on them). Same filters as before.
- 2026-09-27 — SOH-226 "model output as product copy" (POLISH-PLAN §3 item 3). **No report shape changes anywhere** — every field named below already existed with the same type; only the STRING CONTENT changes. Fixes the judge-audit findings: "The fact confirms she is a firmware engineer…", "The fact notes that…", "Author's college roommate…", a reason ending `(evidence: "…")`, and an Inbox title splicing a raw first-person goal sentence ("Maya Chen is a strong match for I am looking to find a technical cofounder…").
  - **`scoring.sv.jac`** gains `polish_reason(text: str) -> str`: strips a leading "The fact confirms/notes/states/shows (that)"/"The note says" preamble, replaces "author's"/"the author"/"author" with "your"/"you"/"you", drops a trailing `(evidence...)` parenthetical, collapses double spaces, capitalizes the first letter, and ensures one terminal `.`/`!`/`?`. Idempotent, empty-safe. Applied once, at each module's own composed/walker boundary (never inside the low-level `post_process`/`fallback_results`/`materialize`-fed `RankedItem`/deterministic-brief helpers those modules' OWN unit tests exercise directly with placeholder text) — `scoring.score_against_need`'s `why`; `goals.materialize`'s `reason`/`opener` (written to the `RelevantTo` edge itself, so a cached `GoalRank` re-serve never needs to redo this); `gaps.compute_gaps`'s `why_needed`/`suggested_need`; `person.sv.jac`'s `Brief`-reported `text`; `agent.sv.jac`'s `make_finding` (every `title`/`why` for every kind: `new_match`/`ask_network`/`route`/`promise_due`/`follow_up`/`reconnect`/`answer_ask`).
  - **`goals.sv.jac`** gains `goal_noun_phrase(text: str) -> str`: strips ONE leading first-person/imperative prefix ("I am looking to", "I'm looking to", "I want to", "I'd like to", "My goal is to", "Looking to", "Trying to", "Find ", "To ", longest/most-specific first), then lowercases the new first letter unless the second character is already uppercase (a proper noun/acronym start, e.g. "AI grants" stays as-is). Applied once, at goal-CREATION time, so `Goal.text` is stored as a noun phrase everywhere it's read back: `goals.set_goal_for` (`SetGoal`), `onboard.collect_goals`/`onboard.promote_strongest_need` (`OnboardMe`). `agent.sv.jac`'s `new_match`/`ask_network`/`route` templates also apply it defensively at read time (a no-op on an already-noun-phrase goal; a real fix for a goal stored before this landed).
  - **`agent.sv.jac`** `step_new_match`'s title changes from `"{name} is a {strength} match for {goal.text}"` (spliced the raw, possibly first-person, goal sentence) to `"{first_name}: {strength} match for '{goal_noun_phrase(goal.text)}'"` — first name only, quoted noun phrase, never a full sentence splice. `why` drops the trailing `(evidence: "…")` parenthetical (the cited evidence still rides on the finding's own `evidence: [str]` list, resolved separately by `ListAgentActions`/`Receipt`). `step_ask_network`/`step_route` splice `goal_noun_phrase(goal.text)` instead of the raw goal text into their own `title`/`why`/`draft`.
  - Sem instructions (product-copy: second person, never "the fact"/"the note"/"the author"/"the speaker"/"the user", never a parenthetical evidence quote, one sentence under 160 chars where applicable, first name only) added to: `scoring.NeedMatch.why`, `goals.RankedItem.reason`/`.opener`, `gaps.NeededKind.why_needed`/`.suggested_need`, `drafts.FollowUp.draft`, `person.Recap.text`, `capture.XFact.text`/`XIntent.text`/`XPromise.text`/`XPerson.name`, `onboard.OnboardExtraction.goals`/`.needs`/`.offers`.
  - `noted.sv.jac`/`serendipity.sv.jac` have no `by llm` and their existing deterministic templates already read as product copy (second person, no "the fact"/"the author") — left unchanged.
  - Verified: `jac check` clean on `scoring.sv.jac`, `scoring.test.jac`, `goals.sv.jac`, `goals.test.jac`, `gaps.sv.jac`, `gaps.test.jac`, `drafts.sv.jac`, `capture.sv.jac`, `capture.test.jac`, `onboard.sv.jac`, `onboard.test.jac`, `person.sv.jac`, `person.test.jac`, `agent.sv.jac`, `agent.test.jac`, `main.jac`. `jac test`: `scoring.sv.jac` 17/17, `goals.sv.jac` 40/40, `gaps.sv.jac` 24/24, `capture.sv.jac` 62/62, `onboard.sv.jac` 68/68, `person.sv.jac` 63/63, `agent.sv.jac` 152/152 — all green, including new tests for `polish_reason`/`goal_noun_phrase` on the exact audit strings and for `step_new_match`'s new title/why format.

- 2026-09-27 — SOH-226 ranking stability (POLISH-PLAN §10 / FEEL-AUDIT #3: "Maya Chen went strong -> medium after one capture that had nothing to do with her"). **`GoalRank` report gains two additive fields on every entry** (cached or fresh): `prev_strength: str` and `change_reason: str` (both `""` unless that ONE candidate's strength just changed on this call). **`GoalRank` gains one new walker parameter**: `force: bool = False` — distinct from the existing `refresh: bool` the client already sends (`components/api.cl.jac`'s `goal_rank(goal_id, refresh)`, called with `refresh=true` both by the explicit "Re-rank" button and automatically after every capture, per `frontend.impl.jac`'s `ensure_rank`/`rerank`; left untouched, not a client file). No other shape change.
  - **Rule**: a candidate's `RelevantTo` edge (strength/label/reason/opener) may change only when something about THAT person or THAT goal changed since the edge was last (re-)computed: a new/edited Fact (`observed_at`), Intent or Promise (via its asserting Note's `captured_at`), or Note mentioning them, newer than the edge's own `ranked_at`; OR the goal's text changed since `ranked_at` (`ranked_goal_text` snapshot); OR `force=True`. Otherwise the candidate is never sent to the model at all (saves a call) and its edge is reported byte-for-byte unchanged, `cached: true`. On an actual change, `prev_strength` = the strength before, and `change_reason` is one of `"new note on Sep 27"` / `"goal edited"` / `"re-ranked on request"`.
  - Schema (`schema.sv.jac`): `edge RelevantTo` gains `has ranked_at: str = ""` (per-edge, distinct from `Goal.ranked_at` which stays goal-level/display), `has ranked_goal_text: str = ""`, `has prev_strength: str = ""`, `has change_reason: str = ""`.
  - `goals.sv.jac`: new pure defs (no LLM, all directly testable) — `newest_evidence_at(p)`, `existing_relevant_to(p, goal)`, `stale_trigger(prior, goal_text, newest_at, force)` (`"new"|"goal"|"evidence"|"force"|""`), `candidate_is_stale`, `change_reason_text(trigger, newest_at)`, `compute_stale_indices(candidates, goal, goal_text, force)`, `prune_stale_relevantto(goal, candidates)` (drops a no-longer-a-candidate person's edge), and `materialize_stable(...)` (the selective rebuild — replaces the old blanket `materialize(goal, ranked, candidates)` call inside `GoalRank` specifically; `materialize` itself is UNCHANGED and still used/tested as the plain delete-all/recreate-all primitive it always was). `serve_cached` (the `refresh=False` cache-only path, unchanged behavior) now also reads `prev_strength`/`change_reason` off the edge into its report.
  - Verified: `jac check` clean on `schema.sv.jac`, `goals.sv.jac`, `goals.test.jac`, `tend.sv.jac`, `tend.test.jac`, `scoring.sv.jac`, `gaps.sv.jac`, `agent.sv.jac`, `merge.sv.jac`, `main.jac`. `jac test goals.sv.jac` 46/46 (new: `newest_evidence_at` across fact/intent/promise/note; `stale_trigger`'s five branches; an unrelated capture leaves the untouched candidate's `stale_trigger` empty and its edge byte-for-byte identical on a second rebuild — the exact Maya repro; a real evidence change on ONE candidate changes only that one, with `prev_strength`/`change_reason` set; `force` re-evaluates a candidate with nothing else stale; `prune_stale_relevantto`).
  - **`tend.sv.jac`** title splice fix (same finding, different surface — `_gather_newly_relevant`'s `reason` still spliced the raw goal sentence: `"{name} is a strong match for your goal '{goal.text}'"`). Now reuses `goals.goal_noun_phrase` + the `scoring.polish_reason` idiom `agent.sv.jac`'s `step_new_match` already established: `"{first_name}: strong match for '{goal_noun_phrase(goal.text)}'"`, first name only, never a full sentence. `jac test tend.sv.jac` 52/52 (new: an exact raw-first-person-goal repro asserting the old sentence never appears).

- 2026-09-27 — SOH-226 judge pass 4 leftovers (server). **No report shape changes anywhere.**
  - **`scoring.sv.jac` `polish_reason`**: `_FACT_PREAMBLE_RE` extended from the old `"the fact (confirms|notes|states|shows)( that)?|the note says"` to `^(her|his|their|the)\s+(intent|intents|evidence|fact|facts|note|notes|profile)\s+(explicitly\s+)?(mentions|states|notes|confirms|shows|says|indicates)(\s+that)?\s+` (still case-insensitive, still fully backward-compatible with every existing preamble) — kills the judge's own two repros, `"Her intent explicitly mentions that…"` and `"Her evidence explicitly states that…"`. When the stripped noun was `intent`/`intents`, a leftover whole-word "intent" elsewhere in the SAME sentence is also rewritten to "want" (`"their main intent is to relocate"` -> `"their main want is to relocate"`) — scoped to a matched preamble only, so an unrelated `"no ill intent"` is never touched.
  - **Sem never-say list** (the one consistent sentence: `…never say 'the fact', 'the note', 'the author', 'the speaker', or 'the user'…`) gains `'the intent'`, `'the evidence'`, `'the profile'` in all three copies that use this exact sentence: `scoring.NeedMatch.why`, `goals.RankedItem.reason`, `gaps.NeededKind.why_needed`. (Two OTHER, differently-worded never-say sems — `drafts.FollowUp.draft` and `person.Recap.text` — were left alone: not the same sentence, out of scope for this pass.)
  - **`capture.sv.jac` `default_how_met`**: the date is now a hand-written month-name string via a new `_human_date(day: str) -> str` (same `strftime("%b ") + str(dt.day)` no-leading-zero idiom `onboard.sv.jac`'s `month_day` already uses, duplicated rather than imported per that file's own ownership note) — `"from a debrief on 2026-09-27"` -> `"from a debrief on Sep 27"`; the year is appended only when it differs from the current year (`"Sep 27, 2020"`). No other capture behavior changed.
  - **`capture.sv.jac` sem**: `CaptureExtraction.facts` gains one clause — "Ignore the writer's remarks about the note itself or about this app ('nothing to do with my project', 'not sure if this matters'); they are not facts about the person." No other prompt change.
  - **`imports.sv.jac` `ImportPeople`**: a NEWLY created `Knows` edge (the person wasn't already known) now gets `last_contact=now` (ISO), same display-only field every other capture path (`capture.sv.jac`, `vision.sv.jac`, `handshake.sv.jac`, `exchange.sv.jac`) already sets — a person imported a minute ago no longer reads as quiet 90+ days. A REUSED existing edge's `last_contact` is left untouched (not "relationships never decay" wiring — just parity with the other capture paths).
  - Verified: `jac check` clean on `scoring.sv.jac`, `scoring.test.jac`, `goals.sv.jac`, `gaps.sv.jac`, `capture.sv.jac`, `capture.test.jac`, `imports.sv.jac`, `imports.test.jac`, `main.jac`. `jac test scoring.sv.jac` 18/18, `jac test capture.sv.jac` 63/63, `jac test imports.sv.jac` 35/35 — all green (new tests on both judge preamble strings + the scoped intent->want rewrite + the "leave an unrelated intent alone" case; the old/new-year `default_how_met` cases; `last_contact` set on a new edge and left alone on a reused one).

- 2026-09-27 — SOH-229 asks (server half; the client is being built to read these fields defensively). **Additive only — every existing key on every row below is unchanged.**
  - Schema (`schema.sv.jac`): `node IntroRequest` gains `has goal_text: str = ""` — the requester's goal as a noun phrase (run through `goals.goal_noun_phrase`), `""` when not tied to a goal.
  - `exchange.sv.jac` `PostRequest(need, about_line = "", ttl_days = 7, audience = "everyone", goal_text = "")` — new `goal_text` param, stored via `goal_noun_phrase(goal_text.strip())` when non-blank, else `""`. `post_request(...)` (the plain-def body `agent.sv.jac`'s `approve()` also calls for `ask_network`) takes the same new `goal_text` positional arg; `approve()`'s `ask_network` branch now passes the finding's own `Goal.text` through, so a request posted by approving an `ask_network` action carries that goal's text automatically.
  - `exchange.sv.jac` `ListIncomingRequests` rows: **same flat shape the raw `IntroRequest` node always serialized as** (`_jac_id, need, from_handle, about_line, status, created_at, expires_at, audience`) — `r["_jac_id"]` etc. still work unchanged — PLUS `goal_text` (off the node) and two new computed, non-persisted fields: `from_name` (the requester's own first name, resolved ONLY through their published, `visibility=="link"` Card via `cards.get_card` — imported, not copied; `""` for a `handshake_only` or missing card, never a name off anyone's graph) and `need_key` (see below). `ListMyRequests` rows are unchanged in shape (`{request: IntroRequest, replies, same_person_groups}`) — `request.goal_text` now simply exists on the serialized node.
  - `exchange.sv.jac` gains `need_key(need: str) -> str`: lowercase, strip punctuation (char-scan tokenizer, same idiom as `scoring.fallback_tokens`), drop a fixed stopword list (`a, an, the, who, someone, that, for, in, and, with, of, to, is, are, or`), light-stem each remaining token (strip ONE trailing suffix, longest/most-specific first: `ers, ing, ors, es, or, s`, never below 3 letters), dedupe, sort, join with spaces. Two of Jesse's live asks ("An investor in climate companies who hires summer interns." / "Someone who invests in climate startups and hires university interns.") converge on `climate`/`hir`/`intern`/`invest` after this (`investor`/`invests` both stem to `invest`); "companies" vs "startups" and "summer" vs "university" are genuinely different words and correctly keep their own tokens — NOT a promise that two differently-worded asks fully collapse, a deterministic grouping key. Also gains `requester_first_name(handle) -> str`, the `get_card`-backed lookup above.
  - `agent.sv.jac` `step_answer_ask`: `title` changes from `"Answer an ask: <need>"` to `"<from_name or @handle> is looking for <need, goal_noun_phrase'd>."` (reuses the existing `make_finding` -> `polish_reason` idiom, no em-dashes); `why` unchanged. `payload_json` gains `from_name`, `need_key`, `goal_text` (additive; `need`, `from_handle`, `top_person_id`, `matched` unchanged).
  - Verified: `jac check` clean on `schema.sv.jac`, `exchange.sv.jac`, `agent.sv.jac`, `exchange.test.jac`, `agent.test.jac`, `main.jac`. `jac test exchange.sv.jac` 132/132, `jac test agent.sv.jac` 165/165, `jac test cards.sv.jac` 94/94 — all green (new: `need_key`'s exact output on both real asks plus a nurse ask sharing none of their tokens; `goal_text` round-tripping through `PostRequest` -> `ListIncomingRequests` -> `ListMyRequests`, empty when omitted; `from_name` present for a `link`-visible Card and empty for `handshake_only`; the `answer_ask` title/payload shape for a link-visible requester vs a `@handle` fallback).
