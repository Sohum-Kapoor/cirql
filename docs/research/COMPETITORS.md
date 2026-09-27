# Cirql vs. the personal CRMs people pay for

Researched 2026-09-27; prices as listed that day.

## 1. Competitor snapshots

| App | Who pays · price | Why they pay | First 3 min · data in | Daily loop | Two complaints |
|---|---|---|---|---|---|
| **Mesh** (ex-Clay; clay.earth now redirects to me.sh) | founders, investors, recruiters · free ≤1,000 contacts, Pro $20/mo ($120/yr) | self-updating contacts; "moments" feed (job changes, birthdays, news); reconnect reminders; pre-meeting context; Nexus AI search | connect Gmail → calendar → LinkedIn/X → imports everyone you emailed or met; also WhatsApp, iMessage, Notion, phone | what changed in my network | Trustpilot 2.2/5: card required for "free", surprise charges; "made up facts about me" from scraped profiles |
| **Dex** | LinkedIn-heavy pros · $12/mo annual ($20 monthly), Pro $20 | LinkedIn sync 2,500–9,000 + job-change alerts; keep-in-touch cadences; AI pre-meeting brief; timeline; one-click Chrome add | extension + LinkedIn + Google → contacts appear; Gmail/Outlook, WhatsApp, phone, CSV | "who's due" list, pre-meeting brief, Kanban | free tier retired without warning; "not built for in-person capture at events" |
| **folk** | 1–20 person teams · $24/user/mo, Premium $48 | folkX LinkedIn scraper; pipelines; email sequences; AI research/meeting assistant; unified timeline | ~8 min: extension → Gmail OAuth → sync; CSV with AI enrichment | pipeline board + tracked email | no mobile app (2026 reviews); per-seat price for solo use; duplicates after import |
| **Monica** | privacy-minded individuals · self-host free, cloud $9/mo (free ≤10) | life events; relationship map between contacts; gifts/debts; journal; reminder emails | sign up → add a contact by hand; vCard/CSV only | reminder emails | all manual; web-only, no AI |
| **Covve** | mobile event networkers · $9.99/mo annual, free ≤20 | fast card scanner; news on contacts; reminders that "don't become noise"; digital card + widget; weekly stats | sync phone contacts → scan a card → set reminder; no LinkedIn | push reminders + news feed | mobile-first, thin web; sync duplicates/erased notes |
| **UpHabit** | small-business networkers · free, paid $19.99/mo ($119.99/yr) | fixed + recurring reminders with snooze; tags; searchable notes; dedup; message templates | import Google/Microsoft/phone → dedup → tag | reminder due list | "lots of manual work"; crashes, imprecise reminder timing |
| **Cloze** | real-estate agents · $17–42/mo | auto-logs email/calls/texts/meetings; AI daily Agenda; auto-built timeline; Ghostwriter drafts | connect Gmail/Outlook + phone → auto-logs; no LinkedIn | morning Agenda | auto-merge loses data; "too full", slow, upsells |
| **Hippo** (Apple) | privacy-first individuals · $14.99/yr or $29.99 lifetime, free ≤25 | on-device, no account; notes/events/to-dos per contact; birthday reminders; Mac app | install → open, zero setup | birthday/event reminders | everything but birthdays manual; crashes |
| **Contacts+** | multi-account users · $9.99/mo annual | unified address book (5 accounts), auto dedup, AI card scan | connect accounts → merge | clean address book; no loop | sync writes back wrong |
| **Nat** | consultants, founders · free signup | "who you're losing touch with" from Gmail/Calendar; notes in Gmail; one-click follow-ups | 1-click Google → pick the people who matter | losing-touch list | "MVP look and feel"; Google-only |
| **Notion/Airtable templates** | tinkerers · free–$10 | own schema in an open workspace | duplicate template, type | none unless built | "pretty spreadsheet": no sync, no reminders, abandoned as network grows |
| **Superhuman** (design ref.) | inbox-heavy pros · $30/mo | <100 ms loads; a shortcut for everything; Cmd+K | mandatory 30-min live onboarding | inbox zero | price; forced onboarding |

Round-up consensus: *personal CRMs die of abandonment; survivors fill themselves in or inherit an existing habit.*

## 2. Feature matrix

UpHabit, Contacts+ and Nat track Covve/Monica here.

| Feature | Mesh | Dex | folk | Monica | Covve | Cloze | Hippo | **Cirql** |
|---|---|---|---|---|---|---|---|---|
| Email/calendar sync | ✓ | ✓ | ✓ | – | – | ✓ | – | **missing** (roadmap) |
| LinkedIn connections | ✓ | ✓ | ✓ | – | – | – | – | **partial** (own export CSV, by design) |
| Phone/vCard/CSV import | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **have** (+ confirm by swipe) |
| Dedup / merge | ✓ | ✓ | ~ | – | ~ | auto (lossy) | – | **have** (propose, confirm, undo) |
| Reminders that fire (push/email) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **partial** (in-app Tend, promise dates) |
| Cadence / decay score | ✓ | ✓ | – | ✓ | ✓ | ✓ | – | **missing, deliberate** (no decay) |
| Birthdays / life events | ✓ | ✓ | – | ✓ | – | ✓ | ✓ | **missing** |
| Timeline per person | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **have** |
| Tags / groups / how-met | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | – | **have** (circles, events) |
| Pre-meeting brief | ✓ | ✓ | ✓ | – | – | ✓ | – | **partial** (Brief/GamePlan, not on calendar) |
| Enrichment with source URL | no receipts | no receipts | no receipts | – | news | no receipts | – | **partial** (URL per fact) |
| Voice → structured graph | – | voice mode | meeting asst | – | – | – | – | **have** |
| Provenance on every claim | – | – | – | – | – | – | – | **have, unique** |
| Goal-relative ranking | – | – | – | – | – | – | – | **have, unique** |
| Gap detection + ask network | – | – | – | – | – | – | – | **have, unique** |
| Consented card / QR | – | – | – | – | digital card | – | – | **have** |
| Export / restore | ✓ | ✓ | ✓ | ✓ | Pro | ✓ | – | **have** (JSON, vCard) |
| Mobile app | ✓ | ✓ | – | – | ✓ | ✓ | ✓ | **have** (Capacitor) |
| Widget / share sheet | ✓ | – | – | – | ✓ | – | – | **missing** |
| Keyboard / Cmd+K | ✓ | ~ | ✓ | – | n/a | – | – | **missing** |

## 3. What makes them feel real and worth money

1. **It fills itself in.** Survivors connect email + calendar in minute one; the user annotates instead of typing. Manual-entry apps stay cheap and churn.
2. **Reminders that actually fire** (push on phone, email digest on desktop) with snooze.
3. **One morning surface**: Mesh moments, Cloze Agenda, Nat losing-touch, Dex due list.
4. **Job-change and life-event signals**: the most-cited reason to open the app unprompted.
5. **Speed and keyboard**: sub-second lists, `/` to search, one key to add a note.
6. **A mixed timeline** per person: emails, meetings, notes, reminders, intros in one scroll.
7. **Tags/groups with bulk actions**; a Kanban of follow-ups.
8. **Frictionless mobile capture**: card scan, share sheet, widget, voice.
9. **Pre-meeting brief on the calendar.**
10. **Honest pricing**: a usable free tier, one paid tier at $10–20/mo. Card-required "free" and post-trial upsells are the top complaints.
11. **Trust in one row**: export, delete account, plain list of data sources. Hippo's "no account, ever" wins reviews alone.
12. **Native feel and consistency**: Hippo/Covve praised for "simple, great interface"; Cloze dinged for "feels like a website."

## 4. What only Cirql does, and how they'd attack it

**Unique:** relevance as a property of (person, goal) with a cited reason; gap detection ("no warm path to climate-tech VC"); the consented Exchange where each agent answers on its own graph and only a self-authored card crosses; a provenance span on every fact; voice debrief → typed graph; no decay, no worth scores. The paradigm split: Mesh, Cloze and Covve score tie strength from contact frequency (what Cirql refuses), and Dex/folk depend on LinkedIn-scraping extensions that break on DOM changes and risk account restrictions (what Cirql avoids).

**Their counter-positioning:** Mesh/Dex: "We already show who in your network works at that fund, from real email and LinkedIn, on day one, not from memos you must record." Dex: "The Exchange is empty until your friends install it; our reminders work alone." Monica/Hippo: "Your memos go to Gemini; we never leave the device." All: "AI extraction hallucinates; we log what happened." Cirql's answers exist (receipts, deterministic fallback, privacy page, export) but live in Settings; put them on the first screen.

## 5. Ten recommendations, ranked by impact ÷ effort

Two people, ~12 person-hours; the table sums to ~9 h. Cut after #6 if behind.

| # | Recommendation | Lands on | Effort |
|---|---|---|---|
| 1 | **"Today" home**: promises due, Tend nudges, gap alerts, incoming asks in one list, a reason line each (Cloze Agenda pattern). All four already computed. | Agent inbox / home | 1.5 h |
| 2 | **Onboarding step 2 = import, step 3 = first recall.** After the about-me: "Import your .vcf / LinkedIn export" with a 3-line how-to, then "For your goal, here's who you already know." | Onboarding, Import | 1.5 h |
| 3 | **Keyboard palette**: `/` search, `c` capture, `Cmd+K` command list. Linear/Superhuman feel on the projector. | Shell | 45 min |
| 4 | **Person sheet header**: how-met chip, circles, days since last capture (display only), "next step" (open promise or drafted opener), then the timeline. | Person sheet | 1 h |
| 5 | **Trust strip** on Settings and the card page: isolated by construction · export · delete my data · what leaves the server, buttons inline. | Settings, card page | 30 min |
| 6 | **"Quiet for 90 days" filter** on People, display only, no scoring: the keep-in-touch loop without violating no-decay. | People list | 30 min |
| 7 | **Reminders that fire**: `.ics` download for promise due dates (30 min). Capacitor LocalNotifications only if the iOS build is idle; plugin + permission work has burned evenings before. | Promises / upcoming | 30 min–2 h |
| 8 | **Dated life events on Facts** (birthday, move, new job) from Capture → "Upcoming" on Today. | Capture walker, person sheet | 1 h |
| 9 | **Paste-from-clipboard + `?text=` share target on Capture** so a bio or a text thread lands in one tap. | Capture | 45 min |
| 10 | **Brand pass**: one accent, one icon set, one caption style, icon = splash = favicon, written empty states. | Everything | 45 min |

Skip this weekend: email/calendar sync (say "roadmap"), cadence reminders (contradicts no-decay), team features.

## Sources

- Mesh/Clay: https://me.sh/ · https://use-apify.com/blog/clay-personal-crm-review-2026 · https://www.trustpilot.com/review/clay.earth · https://www.mogulnetworking.com/blog/best-personal-crm-apps
- Dex: https://getdex.com/pricing/ · https://gist.github.com/xigy7015/c8a10cf227d767e9778bb65482d7f24c · https://www.capterra.com/p/275020/Dex/reviews/
- folk: https://hackceleration.com/folk-crm-review · https://getdex.com/blog/folk-crm-review/
- Monica: https://www.monicahq.com/en/ · https://www.dench.com/blog/monica-crm-review
- Covve: https://apps.apple.com/us/app/covve-personal-crm/id958935377 · https://getdex.com/blog/covve-review/ · https://www.onepagecrm.com/blog/best-personal-crm/
- UpHabit: https://uphabit.com/ · https://justuseapp.com/en/app/1335632832/uphabit-the-personal-crm/reviews
- Cloze: https://getdex.com/blog/cloze-crm-review/ · https://apps.apple.com/us/app/cloze-relationship-management/id596927802
- Hippo: https://gethippo.app/ · https://apps.apple.com/us/app/hippo-personal-crm/id1458330948
- Contacts+: https://www.contactsplus.com/ · Nat: https://www.nat.app/ · https://paolo.blog/blog/atomic-review-nat-personal-crm/
- Notion/Airtable: https://efficient.app/videos/airtable-notion-crm · https://medium.com/@ukcharlietaylor/using-notion-as-a-personal-crm-7c6ddd7c95a6
- Superhuman: https://get-alfred.ai/blog/is-superhuman-worth-it · https://nickgray.net/superhuman/
- Round-ups: https://www.storyflow.so/blog/best-personal-crm-tools-2026 · https://wavecnct.com/blogs/personal-crm
