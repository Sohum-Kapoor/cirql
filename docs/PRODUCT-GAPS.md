# Cirql beyond the demo — what a daily user is missing, and the plan

Written 2026-09-26 20:00 after five persona walkthroughs (SOH-208), two adversarial reviews (Gemini 3.1 Pro on product, Codex Astra on security) and a product-gap review by a third model. SK's direction: "build something we can use for the rest of our lives". The demo path stays frozen from 02:00; everything else below is real product work.

## The identity question (the one SK raised)

"I put James Anderson in; my friend puts James Anderson in; James will never install the app. How do we know it is the same James, and how do we verify him, without LinkedIn?" Three layers, none of which scrape anything:

1. **Do not need it where you do not.** The Exchange never requires two accounts to agree who James is. Each agent matches on its own graph; only a count and a strength cross; identity crosses only after the humans approve, and then the requester sees a card and knows. "Same person?" only matters when two friends both reply: a counting problem.
2. **Blinded identity tokens (SOH-215, built tonight).** Every Person carries keyed hashes of normalised name+org, email, phone and each canonical URL. Hashes may be compared across accounts; names never leave a graph. Two replies to one request that share a token are shown to the requester as "likely the same person, by contact / by name and org"; never auto-merged.
3. **Verification comes from the person's own public presence, then from the person.** Enrich (Gemini + Google Search grounding) resolves name + captured context to the person's own site, company page, GitHub, papers, each with a URL that feeds a token. NotedCard sends "here's what I noted about you"; the missing piece is a no-account confirmation link, so James can tap "that's me" or correct a line from his email without installing anything. Roadmap.

## A. Must have to use daily

| Gap | Why | Owner | Status |
|---|---|---|---|
| Search over people, facts, notes | the most frequent CRM action; Recall is a model call | server SOH-216, client search box on Home | building / Needs B |
| Contact details on a person (email, phone, links, location) | you have to be able to act on a connection | server SOH-216, sheet fields | building / Needs B |
| Notes timeline (list, delete a note and retract only what it alone supported) | preparing for a meeting means reading what happened | server SOH-219, client tab | building / Needs B |
| Real dates on promises and intents ("Fri", "in March" → a date), upcoming view | a task list that cannot sort by date is not one | server SOH-219 | building |
| Card editor with "what a friend would see" preview | the card is the only thing that crosses accounts; users must control it | client SOH-179 | Needs B |
| Friend list: exchange visible to people you exchanged cards with | today every account sees every open request | server SOH-218, client copy | building / Needs B |
| Archive instead of delete; delete my data; restore from export | a lifelong graph needs an undo and a way out | server SOH-220, settings UI | building / Needs B |
| Bulk import (CSV, paste a list) in the UI | onboarding takes five people at a time; ImportPeople exists | client SOH-181 | Needs B |
| Onboarding shows the extracted goal (em-dash bug) | three personas hit it on the first screen | client | Needs B |

## B. Makes it stick

Promises owed to you (a `direction` on Promise; "he said he'd send his deck" is an offer Intent today, by design, so Today lists only what you owe) · Circles and Events (SOH-217, building) · weekly Digest (SOH-219, building) · offline capture queue (client) · Apple Contacts import (Capacitor plugin) · iOS share extension for articles → Serendipity · push notifications for promises due and incoming asks · triage swipe for proposed people and merges (SOH-181) · an ambiguity inbox for "Sara? Sarah?" · interaction cadence per person (from notes, never decay) · quick-add widget · persona-found copy fixes.

## C. Later

Calendar and email connectors (permissioned) · teams / shared graphs · webhooks and API keys · bulk edit · command palette · custom fields · a query builder over the graph · raw audio retention with the transcript · intro email generation once sending exists · the no-account confirmation link (identity layer 3).

## Structural risks we accept for now

- Relevance is tied to goals, so a user with no active goal has a thinner home screen; Circles, Search and the timeline give the "rolodex" view without a score.
- Identity tokens can be flooded with synthetic identities; the friend gate and human approval bound the damage.
- Export is our own JSON, now with an importer (SOH-220); vCard/CSV export is a small follow-up.
- One model call per capture is fine for a person; a team plan needs batching.
- Offline capture will need a merge policy (server wins on conflicts, local queue replays in order).
