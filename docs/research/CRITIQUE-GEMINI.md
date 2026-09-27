### 1. Diagnosis: Why it doesn't feel real
1. **Zero Data Gravity:** A CRM without passive ingestion is a chore; Cirql demands manual voice memos instead of pulling calendar and email exhaust in the background (Symptom: Capture requires a deliberate "30-second voice memo" per encounter).
2. **High-Friction Core Loop:** The app demands work before delivering value, making users declare structured "Goals" just to see their contacts (Symptom: J1 forces setting a goal like "summer 2027 VC internship" before ranking anyone).
3. **Missing Baseline Expectations:** Deliberately rejecting relationship decay makes the app feel static, ignoring how human connections naturally fade over time (Symptom: The PRD strictly bans relationship decay, showing `last_contact` only as a passive tie-breaker).
4. **Abstract Mental Model:** Pushing the "agents walking your network" implementation detail onto the user creates cognitive load instead of solving a problem (Symptom: The one-liner and onboarding copy force users to understand graph traversal rather than clear utility).
5. **Over-engineered Mechanics:** The 6-step Exchange workflow applies heavy, corporate B2B friction to casual personal networking (Symptom: J4 requires redacted requests, local scoring, and dual approvals just to ask a friend for an intro).
6. **Lack of Visual Hierarchy:** Treating connections as raw graph nodes instead of a prioritized task list makes the app feel like a database, not an assistant (Symptom: The demo centers on a "network re-clustered" visualization instead of an actionable list of who to email today).

### 2. The Market Baseline
Compared to Clay, Dex, Folk, Monica, and Covve, Cirql lacks the mechanics that make users feel taken care of:
1. **Passive Ingestion:** Background sync with calendars and email to eliminate manual data entry.
2. **Keep-in-Touch Cadence:** Automated, decay-based recurring reminders to surface dormant relationships.
3. **Rich Context Enrichment:** Silent scraping of social profiles and news mentions to build out a profile instantly.
4. **Action-Oriented Dashboards:** A "Today" view focused strictly on daily relationship tasks and overdue follow-ups.
5. **Frictionless Notes:** Keyboard-first, instant-capture scratchpads without the overhead of structured extraction.

### 3. The Plan: 12 Changes (Impact ÷ Effort)
**Before Submission (Next 6 Hours):**
1. **Rename "Goal" to "Current Focus".** Change the J1 onboarding copy. Users hate feeling like they are treating friends as objectives.
2. **Promote "Promises Owed".** On the Home screen, move the immediate tasks list above the abstract Goal/RelevantTo ranking. Anchor on immediate utility.
3. **Strip "Agent" from the UI.** Change J4 copy from "your agent posts" to "Ask your friends." Speak human, not Jaclang. 
4. **Visually imply freshness.** Since scoring decay is banned, map `last_contact` to a color scale (e.g., solid to faded text) on the ranked list so users can scan for stale ties without altering the rank.
5. **Simplify the Gap Alert.** Replace the dense "No warm path to..." phrasing with a direct CTA button: "Looking for a specific role? Ask your network."
6. **Kill the d3 Graph on Home.** Replace the network visualization with a flat, actionable list of 5 people to message. Graphs are for hackathon judges; lists are for real users.

**After Submission:**
7. **Calendar-Triggered Prompts.** Trigger a push notification 10 minutes after a calendar event ends: "Capture notes from Maya."
8. **Keep-In-Touch Toggles.** Add a simple "Catch up every X months" mechanic to the Person sheet, completely bypassing the complex Goal system.
9. **Meeting Briefing View.** Build an aggregated, read-only view of a Person's facts, past notes, and promises designed to be scanned in an elevator before a meeting.
10. **iOS Share Extension.** Allow adding a person or article directly via the native share sheet from a mobile browser or LinkedIn app.
11. **Unified Command Palette.** Implement a global quick-add for notes or searching a person without navigating tabs.
12. **Blind Deduplication.** Ship the planned identity layer so "James Anderson" merges locally without asking the user to manually resolve duplicates.

### 4. Onboarding Copy
"Cirql remembers the details of your conversations, so you know exactly who to reach out to and why."
