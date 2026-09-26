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
- 2026-09-26 — SOH-194, `paths.sv.jac` (`PathFinder`) lands: the warmest EVIDENCED route to a person (PRD Tier 2 #24). `:priv`, own-root only, no `by llm`. A shared `org` is CONTEXT to display, never a hop; "no known route" is always a valid, non-error answer, distinct from `not_found` (the target isn't reachable from Me by ANY traversal — including proposed/unevidenced ties — at all). Never reads `Knows.last_contact` to gate or rank a route; `days_since_contact` is display only, on the first (`via: "knows"`) hop only. Schema: no changes.

  ### `PathFinder(target_person_id: str, max_depth: int = 3)` — SOH-194
  Reports one dict:
  ```
  { found: bool, target: Person | null,
    hops: [{ person: Person, via: "knows"|"reported", evidence: { id: str, kind: "note", span: str, observed_at: str } | null, days_since_contact: int | null }],
    context: [str], reason: str }
  ```
  BFS from Me: level 0 = `[me ->:Knows:->]` restricted to `Person.status == "confirmed" and Knows.status != "proposed"`; each further level follows `Reported` edges out of the frontier, only edges carrying a non-empty `source_note`; cycle-safe (visited by jid); stops at `max_depth` (hard-capped at 4, regardless of the argument). A person reached only via a `Reported` edge whose own `Person.status == "proposed"` may still BE the target but is never expanded further as an intermediate hop. `hops` starts with the level-0 person and ends with the target (a directly-known target is one hop, `via: "knows"`); `evidence` for the `knows` hop is that `Knows` edge's `source_note` resolved to `{id, kind:"note", span:"", observed_at: note.captured_at}` (`null` if empty); for a `reported` hop it's the `Reported` edge's `source_note` + `span` in the same shape. `days_since_contact` is populated only on the `knows` hop (via `goals.sv.jac`'s `compute_days_since_contact`); every `reported` hop's is `null`. Warmest tie-break when more than one same-round route reaches the same node: prefer the route whose level-0 `Knows` edge `status == "confirmed"` over `reported`/`proposed`, then the more recent evidence `observed_at` — never `last_contact`. `context` = display-only lines (`"same org as you: {org}"`) for every level-0 person sharing the target's `org`, independent of whether that person is on the actual route. `reason` is exactly one of: `"Known directly."` (single knows-hop), `"Reported route via {name} ({n} hop(s))."` (`{name}` = the level-0 entry point, `{n}` = the number of Reported hops), `"No known route. Unknown is not never met."` (target exists and is reachable somewhere in the caller's broader network by an unrestricted traversal, just not by a valid evidenced route within `max_depth` — e.g. blocked by a proposed intermediate, or the only tie has no `source_note`), or `"not_found"` (the `target_person_id` doesn't resolve to a `Person` owned by the caller, OR it does but is not reachable from Me by ANY Knows/Reported traversal at all — `target: null`, `hops: []`, `context: []` in that case). `main.jac`: `import from paths { PathFinder }`.
