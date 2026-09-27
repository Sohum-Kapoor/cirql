# Cirql on the App Store — what is true today, and what is still missing

Written 2026-09-26 22:00, after the product wave. Status words: **done** (on main, verified), **partial**, **missing**.

## App Review basics

| Requirement | Status | Notes |
|---|---|---|
| Unique bundle id, display name, icon, launch screen | done | `com.jessechang.cirql` / `com.sohumkapoor.cirql` per team; icon and splash from `assets/icon/` via `scripts/ios_build.sh` |
| Version and build numbers | done (SOH-226 plist) | `MARKETING_VERSION 0.1.0`, build from the date |
| Purpose strings for microphone, camera, photo library | done (SOH-226 plist) | voice capture, badge photo |
| Export-compliance flag | done | `ITSAppUsesNonExemptEncryption = false` |
| Sign in works without a third-party account | done | username + password on our own server |
| Account deletion from inside the app (Guideline 5.1.1(v)) | partial | "Delete my data" wipes the graph, card listing and uploads; the login identity itself is not deleted (jac-scale exposes no user-delete endpoint). Needs a `DeleteAccount` that also removes the auth user. |
| Works without network | missing | every screen needs the server; an offline capture queue is roadmap |
| No crashes on first launch, no placeholder content | partial | three personas hit "For your goal: —" on the first screen after signup (B fixing) |
| Privacy policy URL | missing | the text exists in "How Cirql works" and `docs/SUBMISSION.md`; needs a hosted page |

## Privacy nutrition label (what we would declare)

- **Data linked to you:** name and email (account), contacts you type in (names, orgs, titles, contact details), notes and voice memos, goals. All stored on our server under your own root; not used for tracking or advertising.
- **Data sent to third parties:** note text and about-me text to Google (Gemini) for extraction and ranking; audio to ElevenLabs for transcription; web enrichment queries (a person's name and context) to Google Search grounding. No data broker, no analytics SDK, no ads.
- **Data that crosses accounts:** only a card you wrote, granted read-only to one person; on the exchange a need, one line about you and your handle; blinded identity tokens (hashes) on replies.
- **User controls:** export everything (JSON), archive or forget a person, delete a note, delete my data, block a handle, choose card visibility.

## Robustness a store reviewer will test

| Check | Status | Notes |
|---|---|---|
| Every list has loading, empty and error states | done for A's components (SOH-226 audit); B's screens: partial | |
| Destructive actions confirm | done | Forget, archive, delete note, delete circle, delete my data |
| Accessibility: labels on icon buttons, focus order, 44 px targets | partial | person sheet and A's components fixed; login form label, onboarding textarea label pending (B) |
| Dark and light mode | done | persisted appearance setting |
| Phone width without horizontal scroll | done on every screen tested at 375 px | six sub-tabs fit at 360 px |
| Large graphs (500 people) | partial | ranking caps at 60 with a `truncated` flag; lists are not virtualised |
| Concurrency | known limit | one `jac start` process serves requests one at a time; two phones fine, a crowd is not |

## What would make it a real release (in order)

1. `DeleteAccount` that removes the auth identity as well as the graph.
2. A hosted privacy page and support address; the "How Cirql works" text is the draft.
3. Offline capture queue with replay.
4. Push notifications for promises due and incoming asks (needs APNs setup).
5. Phone contacts import through the Capacitor Contacts plugin.
6. A production host (not a quick tunnel to a laptop) with TLS, backups of `.jac/data`, and a process manager.
7. Rate limiting per account on model-backed walkers.
8. TestFlight round with the five personas as real testers.
