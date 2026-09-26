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
