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
