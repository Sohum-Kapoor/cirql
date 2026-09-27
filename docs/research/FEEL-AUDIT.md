# Cirql — "Why doesn't this feel like a real app" audit

Date: 2026-09-27 · Target: local dev server http://127.0.0.1:8001/ · Build string shown in app: `Cirql · build 2026-09-27`
Test account: `feel_1790483796@example.com` (password not recorded here)
Path walked: sign-up → onboarding 1–4 → Home → Inbox → People (List, Graph, Today, Circles, Events, Notes, Import) → person sheet → Capture (Voice, Guided, Paste; ran a Paste capture) → Settings (Appearance, My card, What a friend sees, Export, Archived, Delete, How Cirql works) → light mode → desktop width.

Scope: feel only. Functional bugs are excluded on purpose. Note on viewport: the Chrome window ignored resize requests, so every screen was observed at 1456 px wide; the app renders as a fixed ~400 px centred column at every width, so the phone-layout findings and the desktop findings below both come from the same rendering.

---

## Ranked list: the 15 highest-leverage changes

| # | What (one line) | Where (screen / file guess) | Effort | Why it matters |
|---|---|---|---|---|
| 1 | **Ask for the user's name (and initials avatar) in onboarding step 1; stop defaulting the account to "me" and the handle to `me-ce846b`.** | Onboarding step 1 (`pages/onboarding*.cl.jac`), Settings → My card, graph "me" node, "What a friend sees" preview | S | The single loudest hackathon tell. Every surface that should carry identity — the graph's centre node, the shared card preview ("me @me-ce846b"), the Inbox ask cards ("from @me-3ce923", "from @me-f73fe7") — says "me" plus a hex suffix. Real products (Clay, Superhuman, Linear) put your name and an avatar within the first 10 seconds. |
| 2 | **Give the app a mark: an icon next to the "Cirql" wordmark, a favicon/splash, and a one-line tagline on the login card.** | Login screen, app header, `[plugins.client.app_meta_data]`, `assets/icon/` | S | The login screen is a bare wordmark + two inputs + the lowercase status string "logged out" under the form. Nothing signals a product exists behind the door. Things/Linear both open on a brand moment. |
| 3 | **Make the Home ranking stable and explain changes: don't flip Maya from "strong" to "medium" on the next re-rank with no visible reason.** | Home "Who can help" (`pages/home*.cl.jac`, `GoalRank` walker output) | M | I watched Maya Chen go strong → medium after one capture that had nothing to do with her. Rankings that flap read as random, and random reads as fake. Either pin the rank tier to the underlying facts or show a "changed because…" line. |
| 4 | **Rewrite the LLM reason strings so they read as product copy, not model output.** Ban "The fact confirms…", "The fact notes that…", "Author's college roommate…", and the "(evidence: "…")" parenthetical. | Home cards, Inbox match cards, person sheet summary; prompt templates in the `by llm` functions (`llm.sv.jac` / `goals.sv.jac`) | S | "The fact confirms she is a firmware engineer…" is the model talking about its own input. "Author's college roommate" leaks the prompt's word for the user. Clay writes "Worked with you at Rivian — knows embedded firmware." One prompt line ("write as a note to the user; never mention 'the fact' or 'the author'") fixes it everywhere. |
| 5 | **Fix the sentence splice in Inbox match titles: "Maya Chen is a strong match for I am looking to find a technical cofounder…".** Store goals as noun phrases ("a technical cofounder with embedded-systems expertise") and render "for your goal: …". | Inbox "New match" card title; goal storage in onboarding step 2 | S | It's the first card a new user reads in the Inbox and it's ungrammatical. Also shortens the Goal header on Home, which currently wraps to two lines of "I am looking to…". |
| 6 | **Give the Inbox a hierarchy: collapse cards to one-line rows (icon · title · time · chevron) and expand one at a time; move "Nothing sends" to a single footer note.** | Inbox (`pages/inbox*.cl.jac`) | M | Today one match card fills the whole 844 px viewport (title, reason, evidence, person row, provenance chip, editable draft, disclaimer, two buttons). Five stranger "Needs your OK" asks arrive before the user has done anything, and the unread badge climbed 5 → 7 → 9 during the session with no visible cause. Superhuman's inbox is scannable because rows are one line. |
| 7 | **Turn the "Here's what Cirql read" screen into the end of a loop: after Done, land on the person you just captured (or Home with the new match highlighted) rather than a silent skeleton re-rank.** | Capture result → route after Done (`pages/capture*.cl.jac`) | S | The capture review is the best screen in the app (people / facts / intents / promises with source chips). Then "Done" drops you on Home with grey skeletons and no acknowledgement that Priya Nair is now ranked. One toast ("Priya added · 2 facts · 1 promise") plus a highlight would give the loop a felt ending. |
| 8 | **Design the empty states.** Today, Circles, Events, and Import are a dashed grey box with one sentence; the Gaps section vanishes entirely when there are none. | People → Today / Circles / Events / Import; Home gaps | M | Things and Notion treat empty states as onboarding: a small illustration, the one action that fills the state, and an example. "Nothing promised yet. Debrief a conversation and promises land here." is a good sentence with no button. The Gaps section simply disappears after "Looking for gaps in your network…", which reads as a failure. |
| 9 | **Collapse the 7-way People sub-tab pill (List · Graph · Today · Circles · Events · Notes · Import) to 3–4, and move Import into Settings or the "+" flow.** | People tab bar (`pages/people*.cl.jac`) | M | Seven segments in a 400 px pill is the widest tab strip I've seen in a personal CRM. Today (promises) is a Home concern; Circles and Events are filters on List, not siblings of it; Import is a one-time task. Notes then has its own second filter row (All / Debrief / Pasted / Import / About me) — nested tab bars are a hackathon IA signal. |
| 10 | **Replace the ~8–10 s "Reading…" / "Capturing…" button-label waits with a progress narrative (what the agent is doing right now) and keep the button size fixed.** | Onboarding step 1 and 3 buttons, Capture "Reading your note…", Home "Walking your graph…" | S | Onboarding step 1's Continue button also moved under the cursor as the textarea auto-grew, so the first tap silently missed. Step 4 already has the right pattern (skeleton + "Walking your graph…"); use it everywhere. "Reading your note… Pulling out people, facts, intents and promises" on Capture is the right idea — add a 3-stage stepper so a 10 s wait feels like work, not a hang. |
| 11 | **Add a desktop layout: at ≥900 px use a left rail (Home / Inbox / People / Capture) and a two-pane People (list + sheet) instead of a 400 px phone column floating in 1000 px of black.** | Shell (`frontend.cl.jac`), tab bar component | L | Judges will open it on a laptop. At 1456 px the mobile tab bar sits in the middle of the screen with a floating "Capture" pill, and the Graph canvas breaks out to ~816 px while everything else stays at 400 px — the only element that knows it's on a desktop. |
| 12 | **Purge internal vocabulary from user-facing copy: "graph", "walking your graph", "agent on the exchange", "Intents", "known" pill, "about-me" / "pasted note" kebab-case kinds, "Author".** Keep "isolated by construction" once (Settings) not on every screen. | Onboarding, Inbox, Capture result, Notes kinds, person sheet pills | S | "2 people added to your graph", "Your agent is walking your graph…", "An agent on the exchange is looking for…", "Checking 5 asks against your graph…" — this is the architecture talking. A user has a network, contacts, and asks. The "known" pill appears on every person with no alternate value visible, so it carries no information. |
| 13 | **Make the person sheet feel like a profile: initials avatar, a real "met" line ("Added Sep 27 · via onboarding"), an "Add contact details" affordance instead of "No contact details yet", and hide "Forget permanently…" behind the overflow.** | Person sheet (`components/person_sheet*.cl.jac`) | S | Inbox rows already draw "MC" / "DO" / "PN" initials; the sheet and the People list don't, so the same person looks different on each screen. "Rivian · firmware engineer — met: added when you set up Cirql (Sep 27)" is a debug string. A red destructive link at the bottom of every profile is a Things-era anti-pattern. |
| 14 | **Settings needs an account header (name, email, avatar, handle) at the top, one "Danger zone" instead of two stacked red cards, and About/version/help outside the "How Cirql works" accordion.** | Settings sheet (`components/settings*.cl.jac`) | S | The sheet opens on "System follows your phone. Your choice is kept on this device." — a footnote for the theme picker, shown as the sheet's subtitle. There is no email, no sign-out here (it's in the header menu), no help/support/feedback link, and the only version string is the last line of a collapsed accordion. |
| 15 | **Add micro-feedback: a toast on save/copy/dismiss, a press state on cards and pills, and a 150 ms slide for the bottom sheets and tab changes.** | Global (`components/ui/*`, tab shell) | M | I copied a draft, saved a card, marked steps done and switched tabs; nothing animated, nothing confirmed, nothing could be undone. Every transition is a hard cut. This is the layer that separates "works" from "feels finished" in Linear and Things, and it is cheap once the primitives exist. |

---

## Findings by lens (with the concrete moment for each)

### 1. First 60 seconds
- The login card explains the product in one good line ("Other CRMs search your contacts. Cirql's agents walk your network.") but under the form sits a raw status string `logged out` and a footer "Each account's graph is isolated by construction." — two internal-facing lines on the most public screen.
- Tapping "Create account" with empty fields does nothing at all (no shake, no hint). Silence at the first tap.
- Onboarding earns its keep: step 1 (about you) → step 2 (generated card + goal + interest chips) → step 3 (five people) → step 4 ("First recall": ranked people with reasons and openers). Step 4 is a genuine aha — value produced from ~90 s of typing. Keep it.
- But the effort/value order is off: the card (step 2) is a long editable form the user hasn't asked for yet, shown before any value; the "Bring five people" step opens scrolled mid-page so the heading is cut off; the aha only comes on the last step.
- No moment of delight: no animation on the card being generated, no celebration on "2 people added to your graph.", no confetti-equivalent on first recall. The reward is a plain list.

### 2. Speed & feedback
- Long LLM waits everywhere (≈8 s to draft the card, ≈8 s to capture two people, ≈10 s per paste capture, ≈10 s for first recall, ≈8 s inbox agent run). Only the Inbox and step 4 use skeletons; the others swap the button label to "Reading…" / "Capturing…" and leave the form static.
- Layout shift under the cursor: the onboarding step 1 textarea auto-grows after typing, moving Continue down ~33 px; my first click on Continue missed.
- No optimistic updates: after Capture → Done, Home shows full skeletons and re-runs the ranking before the new person appears.
- No toasts, no undo anywhere (Dismiss on an Inbox card is immediate and final; Copy gives no confirmation).
- The Inbox badge went 5 → 7 → 9 during the session without any visible event; unexplained counters feel broken even when correct.
- Rank tiers flap: Maya Chen strong → medium after an unrelated capture.

### 3. Visual system
- Good bones: Inter, consistent 12 px radii, one accent (indigo), dark and light both render cleanly with no parity gaps found, chips and cards share a language, provenance chips (`fact · Sep 27`) are a nice signature.
- Inconsistencies: initials avatars appear in Inbox rows but not in People list or the person sheet; Home cards show "firmware engineer, Rivian" while Daniel Osei (no role) leaves a blank line; note kinds render as `pasted note` / `about-me` (mixed case styles); the Notes tab shows a "Load older" button with only two notes.
- Density: Home cards carry six stacked elements (name/pills, role, reason, "last contact today", italic opener, provenance chips); "last contact today" appears on every card and means nothing for people added today.
- Empty states are all the same dashed box with one sentence; no illustration, no CTA (Today, Circles, Events), and Import is a paragraph of format instructions.
- Graph tab: the canvas breaks out of the 400 px column to ~816 px, its legend is clipped under the tab bar, the goal node is labelled with the truncated goal sentence "I am looking to find a tech…", and the centre node is literally "me".
- Events uses a native `mm/dd/yyyy` date input, visually foreign to the rest of the system.
- Two stacked destructive cards in Settings (Delete my data, Delete account) both in red-on-dark-red.

### 4. Information architecture
- Bottom tabs Home / Inbox / People + a Capture pill is right; Capture as the primary action is obvious and good.
- Home earns its place only partly: it is "Who can help" for one goal. Gaps and promises (Today) belong here too; the Goal card's chevron hints at multiple goals but there is no visible way to add one.
- People has seven sub-tabs, and Notes has its own five-way filter beneath them (nested tab bars). Import is a task, not a place.
- Inbox mixes three different things at the same level (your agent's matches, promises you owe, strangers' asks that need your OK) with a second filter row (All / Asks / Routes / Follow-ups / Matches). "Needs your OK" appears both as a section heading and as a pill on every row.
- Settings is reached through an unlabeled "…" menu next to the wordmark; Log out lives there but not in Settings.

### 5. Copy & voice
- Strong lines exist: "Nothing sends. Copy it into your own message.", "Here's what Cirql read", "Circles are your own labels — family, the robotics lab, investors. Never a score.", the "How Cirql works" page.
- Jargon that leaks: graph (everywhere), "walking your graph", "agent on the exchange", "Intents", "Routes", "known", "Author's college roommate", "(evidence: …)", "The fact confirms…".
- Case is inconsistent: "here's who you already know" (lowercase subhead) next to "First recall" (sentence case) next to `about-me` (kebab).
- Machine handles used as names: `@me-3ce923`, `@alex-3b29cd`, `me-ce846b`.
- Generated openers all start with "I was thinking…" / "It was great…" / "Hope things are going well…"; three in a row on Home read as a template.

### 6. Trust & polish signals
- No app icon or mark, no splash, no profile (name defaults to "me"), no avatar, no email shown anywhere after sign-up, no notification story (the Inbox badge is the only signal and it is unexplained), no help/support/feedback entry, no About screen; the build date is the last line of a collapsed accordion.
- Positive: export (JSON + .vcf), archive, delete-my-data and delete-account all exist and are worded honestly; "What a friend sees" preview is a real trust feature; the privacy language follows the PRD ("isolated by construction", "granted read-only").

### 7. Absences felt during use
- A place to add a person directly (there is Import and Capture, but no "+ Add person" on the People list).
- Reminders / due dates surfaced anywhere but the Inbox ("due Friday" is text, not a date).
- A per-person timeline (facts, notes, promises are separate accordions; no chronological view).
- Tags beyond Circles; birthdays; a "last contact" that is real rather than "today".
- Search from Home and Inbox (only People has the search field).
- Share sheet / native share for a card; a shareable public card URL (only a handle to copy).
- Multiple goals with a switcher; a goal editor.
- Offline / sync state indicator; "saving…" states.
- Keyboard shortcuts and command palette on desktop.

---

## The one thing that makes it feel like a hackathon app

It talks about itself. The interface keeps narrating its own architecture — "walking your graph", "agent on the exchange", "the fact confirms", "isolated by construction", `@me-3ce923` — instead of talking about the user's people. A real product hides the machinery and shows a person with a name and a face at the centre; here the centre node of the graph, the name on the shared card, and the sender of every ask is literally "me" plus a hex code. Fix identity (name, avatar, handle) and rewrite the model-facing strings as user-facing ones, and the same screens read as a product rather than a demo of a walker engine.
