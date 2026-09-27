# Why Cirql doesn't feel like a real app yet, and what to do about it

Written 2026-09-27 00:45 (local), ~10 hours before submission. Inputs: a competitive
analysis of the personal CRMs people pay for (`COMPETITORS.md`), a product-feel
audit of the live build by a designer persona (`FEEL-AUDIT.md`), and two
independent product critiques from different model families (Gemini 3.1 Pro,
Codex Astra) given the PRD, the submission write-up, the personas and the backlog.
Where all four agree, the point is treated as fact; where one says it, it is marked.

## 1. The diagnosis in one paragraph

Cirql demonstrates intelligence before it establishes dependability. The screens
narrate the machinery ("walking your graph", "your agent posts", "an agent on the
exchange", `@me-3ce923` as the user's identity, "the fact confirms…") instead of
showing a person with a name at the centre and telling them who to talk to today.
The value arrives after homework (about-me, card, five people, a goal) rather
than before it. Nothing brings you back (no reminders that fire, no morning
surface, no data flowing in from calendar or contacts). And the small things that
signal "someone lives here" are missing: a name and avatar, toasts, transitions,
designed empty states, a settings page with an account on it.

## 2. What every paid personal CRM has that we don't (see COMPETITORS.md)

| Mechanic | Who has it | Cirql today |
|---|---|---|
| It fills itself in (email + calendar sync in minute one) | Mesh, Dex, folk, Cloze, Nat | missing; import only |
| Reminders that actually fire (push / email), with snooze | all of them | in-app only |
| One morning surface ("Agenda", "moments", "who's due") | Cloze, Mesh, Dex, Nat | Home leads with a goal ranking |
| Life events and birthdays | Mesh, Dex, Monica, Cloze, Hippo | missing |
| A person page that is the hub (timeline + contacts + next step) | all of them | pieces exist, in separate places |
| Keyboard and speed (`/` search, Cmd+K, sub-second lists) | Mesh, folk, Superhuman | missing |
| Native feel: avatars, toasts, motion, empty states, account header | Hippo, Covve, Superhuman | mostly missing |
| Honest pricing and a trust row on the first screen | Hippo, Monica | trust text exists, buried in Settings |

What none of them have and we do: provenance on every claim, relevance as a
property of (person, goal) with a cited reason, gap detection, and a consented
exchange where only a self-authored card crosses accounts. Their attack on us is
predictable: "empty until your friends install it" and "AI extraction
hallucinates". Our answers exist (receipts, deterministic fallback, export,
privacy page) but live three taps deep.

## 3. The plan

Budget: two people, about six build-hours before the 11:00 freeze, then a life
after the hackathon. Ranked by feel-impact divided by effort. Owner in brackets.

### Before submission (do in this order)

1. **Identity.** Ask for the user's name in onboarding step 1 (one field, before
   the about-me), show an initials avatar in the header, person rows and the
   sheet, and derive the handle from the name. Kill every `me-xxxx` on screen.
   [B: onboarding + header; A: `OnboardMe` already takes `name`, `handle_from_name`
   exists]. **S, 45 min.** Loudest hackathon tell across every surface.
2. **Vocabulary purge.** Replace architecture words with the user's: "graph" →
   "your people"; "walking your graph" → "reading your notes"; "agent on the
   exchange" → "a friend is looking for"; "Ask your network" stays; "Intents" →
   "Wants"; drop the "known" pill (it carries no information); "isolated by
   construction" stays only on the privacy surfaces. [B: client copy; A: server
   strings that reach the UI, e.g. gap and Inbox titles]. **S, 45 min.**
3. **Model output as product copy.** One instruction in every `sem` prompt that
   produces user-facing text: no "the fact confirms", no "author", no
   "(evidence: …)", no goal text spliced into a sentence ("a strong match for I
   am looking to…"); store goals as noun phrases. [A]. **S, 30 min.** Fixes Home
   cards, Inbox titles and sheet reasons at once.
4. **Home becomes Today.** Order: promises due (with Done / Snooze) → who to
   reach out to for the active goal (top 3, one reason line) → gap alert as a
   single "Looking for a specific role? Ask your network" button → nothing else.
   The graph leaves Home entirely (it is already under People). Empty Today
   shows one sentence and a Capture button. [B]. **M, 1.5 h.** This is the
   morning surface every competitor has; all four inputs are already computed.
5. **Capture → landing.** After "Here's what Cirql read" → Done, land on the new
   person's sheet (or a highlighted Home row) with a toast "Priya added". Keep
   the note text on failure and offer Retry without creating a second note.
   [B]. **S, 45 min.** The best screen in the app currently ends on grey skeletons.
6. **Micro-feedback.** Toasts on save / copy / dismiss / archive, a press state on
   buttons, a 150 ms slide on sheets and tabs. One shared `toast()` and two CSS
   transitions. [B]. **S, 45 min.** Every transition is a hard cut today.
7. **Settings with an account.** Header with name, email, avatar, handle;
   sections: Appearance · My card · Data · Danger zone; About / version / privacy
   / feedback link outside the accordion. [A owns the panels]. **S, 30 min.**
8. **Trust strip on the login screen.** One line under the form: "Your notes stay
   yours: export any time, delete in one tap, only a card you write is ever
   shared." Replace the raw `logged out` status text. [B]. **S, 15 min.**
9. **People sub-tabs: 7 → 4.** List · Graph · Today · More (Circles, Events,
   Notes); Import moves to a "+" on List. [A wrote the wiring]. **S, 30 min.**
10. **Ranking stability.** A person's tier must not change unless a note about
    them or the goal changed; show "why this changed" when it does. [A:
    `GoalRank` caching on (person, goal) with an invalidation rule]. **M, 1 h.**
    A ranking that flaps reads as random.
11. **"Quiet for 90 days" filter on People** (display only, no scoring): the
    keep-in-touch loop without decay. [A]. **S, 30 min.**
12. **Promises as calendar events.** `.ics` download per promise from the sheet
    and from Today. [A]. **S, 30 min.** The cheapest "reminder that fires".

Total ≈ 8 person-hours across two people. Cut from the bottom.

### After the hackathon (in order)

1. Push notifications for promises due and incoming asks (Capacitor
   LocalNotifications for promises; APNs for asks).
2. Onboarding that starts with import (vCard / LinkedIn export / phone contacts)
   and shows the first recall before asking for a card or a goal.
3. Calendar connection: a prompt ten minutes after a meeting ends ("Capture notes
   from Maya"), and a pre-meeting brief on the event.
4. Life events on facts (birthday, move, new job) → an Upcoming section on Today.
5. Command palette and keyboard layer (`/` search, `c` capture, Cmd+K).
6. Desktop layout: left rail, two-pane People, graph on the projector.
7. iOS share sheet and a home-screen widget for Today.
8. Promises owed to you (a direction on Promise) and a "they owe you" list.
9. Email connection for a mixed timeline per person (opt-in, read-only).
10. The no-account "that's me" link for identity verification (layer 3).

## 4. The sentence at the top of onboarding

Both critiques landed on the same idea; use one of these, not a feature list:

> Cirql remembers the details of your conversations, so you know exactly who to
> reach out to and why.

> Remember the people you meet, and follow through on what matters to them.

## 5. Things we should stop saying

"Agent" on any screen a user sees (keep it in the write-up). "Graph" except in
Graph view. "Score". "Exchange" as a noun (say "your friends' asks"). Handles as
names. "The author". Dates as ISO strings anywhere a human reads them.
