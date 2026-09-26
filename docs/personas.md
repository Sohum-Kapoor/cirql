# Cirql — user personas and the walkthrough protocol (SOH-208)

Five people who are not us. Each one has a reason to open Cirql, a way of talking into it, and a reason to delete it. Agents play them against a **local** server through the real web UI and through the walkers directly. The goal is not to confirm the demo works; it is to find what breaks, what confuses, and what is missing for someone who is not a CS student at a hackathon.

Product rules still apply to every persona: nothing sends, relationships never decay, nobody gets a worth score, relevance belongs to (person, goal), every claim has a receipt, only a card crosses accounts.

---

## 1. Rosa Delgado — the connector who never used a CRM

**Age 54 · Associate dean at a community college, sits on two nonprofit boards · iPhone, reading glasses, types with one finger, never dictates in public.**

Rosa knows six hundred people and remembers every face and almost no names. She writes notes in the Notes app after events and never reads them again. She has no "goal" in the startup sense; she wants to remember who somebody is when they email her three months later, and she wants to help people, which she does by introducing them.

**Goal she would set:** "Find a mentor for our first-generation students in healthcare careers"

**About-me:** "I'm an associate dean at Washtenaw Community College and I've been in Ann Arbor thirty years. I sit on the boards of the Food Gatherers and a scholarship fund for first-generation students. I know a lot of people in county government, hospitals, and the schools. I'm looking for mentors for our students who want to go into nursing and other healthcare jobs. I can offer introductions to the college and to county programs, and I host a good dinner."

**Debriefs in her voice (typed, long, several people in one note):**
1. "Board dinner last night. Sat next to Dr. Helen Marsh-Whitcombe from Michigan Medicine, she runs the nursing residency and said she is always looking for students from non-traditional backgrounds, told her about our program and she gave me her card. Also talked to Tom (the new director at Food Gatherers, forgot his last name) about the holiday drive, he wants volunteers with trucks. And Reverend Okafor mentioned his daughter is applying to nursing school this year, I said I would send her the scholarship link. Need to do that."
2. "Coffee w/ María José Ibáñez-Santos from the county health dept. She is looking for sites to run a vaccine clinic in the spring. Told her our campus could host. She knows Helen from a committee."
3. "Ran into the young man from the robotics thing at the farmers market, cannot remember his name, he is the one who built the wheelchair sensor. He asked if I knew anyone at the county who handles sidewalk accessibility. I do (Kwame) but I said I'd check first."

**She tries first:** paste a long note and see whether it "gets" the people. Then she looks for a person she met and wants the app to show her what she knows about them.

**She keeps it if:** it never makes her feel like she is grading her friends; the text is big enough; she can find someone by "the robotics young man" and not only by name; the promise to send the scholarship link comes back to her.

**She deletes it if:** it asks her to set a "goal" before she can do anything; it invents a last name; it calls anyone a "lead"; anything says "score".

**Edge cases to hit:** hyphenated and accented names; a person with no name ("Tom"; "the young man from the robotics thing"); three people and two promises in one note; a debrief that mentions a person already in the graph under a slightly different spelling ("Helen Marsh" vs "Dr. Helen Marsh-Whitcombe"); onboarding with no goal at all; a note that is only a to-do ("Need to send the link"), no person.

---

## 2. Marcus Chen — the CRM-native skeptic

**Age 31 · Head of partnerships at a Series B logistics startup · Android and a laptop, lives in HubSpot, thirty meetings a week.**

Marcus has a real CRM and is here to decide whether this is a toy. He captures fast, between meetings, in fragments. He will try to make a person into a "prospect", will look for pipeline stages, and will want to import his 2,000 LinkedIn connections on day one. He is the persona most likely to hit bounds and speed limits.

**Goal he would set:** "Close three 3PL partnerships in the Midwest by Q1"

**About-me:** "Head of partnerships at Freightly, we do last-mile routing for mid-size shippers. Based in Chicago, in Detroit and Ann Arbor twice a month. Looking for 3PL and warehouse operators in the Midwest who want a routing pilot, and for a senior BD hire. Can offer pilots at no cost, intros to our investors, and I know most of the logistics meetup crowd in Chicago."

**Debriefs in his voice (short, fragmentary, several a day):**
1. "Dana Whitfield, VP ops @ MidWest Cold Chain. Interested in pilot, wants ROI deck by Fri. Knows our investor Raj from Techstars. Follow up Thu."
2. "Coffee - Luis Ortega, warehouse GM Gary IN. Not a fit now (union contract renegotiation) but revisit in March. Mentioned his boss Karen wants automation."
3. "Priya Nair, recruiter, placed two BD people at Flexport. Might help with the BD hire. She wants intros to founders hiring in Chicago."

**He tries first:** import a CSV, then set a goal and see whether the ranking is smarter than a filter. Then he pastes ten debriefs back to back and checks how long each takes.

**He keeps it if:** capture is faster than typing into HubSpot; the reason per person is specific ("said she wants the ROI deck by Friday") and not generic; promises with dates show up somewhere; he can get his data out.

**He deletes it if:** it takes more than ten seconds to capture; there is no way to see all open follow-ups at once; the ranking is the same order as the list; he cannot import or export.

**Edge cases to hit:** "@" and abbreviations in text ("VP ops @ MidWest"); a due date in the promise ("by Fri", "Thu", "in March"); a person marked "not a fit now" (no worth score allowed, but is the intent expiry surfaced?); ten captures in a row against the model (rate limits, latency, GoalRank cache staleness); a CSV with 500+ rows; a goal that is a quota; asking Recall "who did I promise a deck?".

---

## 3. Amara Osei — the researcher who reads the permissions

**Age 27 · PhD candidate in human-computer interaction, studies assistive-technology adoption, wheelchair user · iPhone with VoiceOver on half the time, dark mode always, laptop with keyboard-only navigation.**

Amara will test the app the way she reviews a paper. She wants to know what leaves her phone, who can see a card, what "isolated by construction" means, and whether she can delete someone. She notices contrast, focus order, unlabeled icon buttons, and tap targets under 44 px. She is also the person the product's accessibility story was built for, so she will be blunt about it.

**Goal she would set:** "Recruit twelve wheelchair users for a field study on assistive robotics by December"

**About-me:** "I'm a PhD candidate in HCI at Michigan studying how assistive technology actually gets adopted. I use a wheelchair. I'm looking for participants for a field study this fall and for engineering teams with prototypes worth studying. I can offer study design help, IRB experience, and blunt feedback on accessibility. I care a lot about who sees my data."

**Debriefs in her voice (precise, includes attributions and hedges):**
1. "Met Maya Okafor (Michigan Robotics lab, accessible manipulation) at the HCI mixer. She says she wants feedback from wheelchair users on a prototype; that is exactly my study population, so there is a potential conflict of interest I should note. She mentioned a labmate, Arjun, who works on grasping. I said I would send her our consent form template."
2. "Talked with Kwame Mensah after the county accessibility panel. He is a policy analyst and a wheelchair user; he was skeptical of academic studies that never report back to participants. He would participate if we commit to a results briefing. I promised that."
3. "Email exchange with Dr. Fatima Al-Sayed, postdoc, HCI. She is running a related field study and suggested we pool recruitment. Not sure yet if our IRBs allow that."

**She tries first:** onboarding with VoiceOver, then the card: what is on it, who can read it, and the "Here's what I noted" flow. Then Forget on a person and check that the facts are gone.

**She keeps it if:** every icon has a label; contrast passes in dark mode; the card is off by default and she can see exactly what a friend's agent would receive; Forget works and says what it removed; a fact shows its date.

**She deletes it if:** any copy says "private", "secure", or "encrypted"; a card is readable by anyone without her turning it on; a screen is unusable without a mouse; a person she deleted still appears in a ranking.

**Edge cases to hit:** keyboard-only through onboarding, capture, and the exchange approval; screen-reader names for the mic, camera, and "ask my network" buttons; a hedged claim ("not sure yet if our IRBs allow that", should not become a fact); a conflict-of-interest note; Forget then GoalRank; card with `handshake_only` visibility read by a second account (must be denied); the wording on every privacy-adjacent screen.

---

## 4. Lena Fischer — the exchange student with half a language

**Age 22 · Exchange student from Munich in public policy, in Ann Arbor for one semester · Android, WhatsApp voice notes, English is her third language.**

Lena meets thirty new people a week and forgets names by the next day. Her debriefs are short, mixed-language, with typos, and often describe a person by a feature instead of a name. She is the strongest test of the extractor and of the "never guess" rule. She has no professional goal; she wants friends and a place to stay over winter break.

**Goal she would set:** "Find a place to stay in Ann Arbor over winter break"

**About-me:** "Exchange student from Munich, public policy, here until May. I like climbing and cooking. Looking for a place to stay over winter break because the dorm closes, and for people to go climbing with. I can offer German lessons and I make a good Käsespätzle."

**Debriefs in her voice (short, mixed, typos, emoji):**
1. "met jonas at the stammtisch, er arbeitet bei siemens in detroit?? he said his roommate moves out in december so maybe a room 🙏 i said i will text him"
2. "the tall girl from climbing gym (Sara? Sarah?) is from Ann Arbor, her parents have a house, she said maybe over break but not sure. she knows jonas too i think"
3. "coffe with prof Delgado (rosa) she is so nice, she said she can introduce me to a family who hosts students. i promised to send my cv"

**She tries first:** the mic. Then she looks for "the tall girl from the climbing gym" three days later.

**She keeps it if:** it does not turn "Sara? Sarah?" into a confident person; it finds "the tall girl from climbing" later; the copy is simple; it works on a slow phone and in German-flavoured English.

**She deletes it if:** it corrects her English into facts she did not say; it drops the emoji-laden note; it invents "Jonas Müller"; it demands a LinkedIn.

**Edge cases to hit:** mixed German/English; "??" uncertainty markers; a person known only by description; two possible spellings of one name in one note; a debrief where the promise is to a third party; a goal that is personal, not professional; lowercase everything; a debrief of eight words; a 10-second silent audio clip; a 3-minute audio clip.

---

## 5. Devon Park — the organizer who works a room

**Age 38 · Runs a 200-person monthly Detroit hardware meetup and a recruiting side business · iPhone, badge scanner in the other hand, uses Luma, Airtable and a spreadsheet of everyone.**

Devon's unit of work is the event, not the person. He wants to walk in with a plan, capture forty people in two hours, and follow up with all of them on Monday. He will paste a guest list, photograph badges, scan QR codes, and then want a list of who to email. He is also the persona who will ask "can I run this for my whole meetup?" and "can attendees see each other?"

**Goal he would set:** "Fill the March speaker slate with six hardware founders"

**About-me:** "I run the Detroit Hardware Meetup, about 200 people a month, and I do technical recruiting on the side. Looking for hardware founders to speak in the spring series and for a co-organizer who can handle sponsors. Can offer a speaker slot, a table at the meetup, and intros to most hardware people in Detroit."

**Debriefs in his voice (rapid, batch, lots of names):**
1. "Tonight: Tomas Reyes battery recycling Ypsilanti wants investors, Grace Okonkwo heading to Boston battery co, Miguel Santos mobility startup power assist attachments, Hana Sato wheelchair sensor kit undergrad. All four possible speakers. Miguel and Tomas already know each other. Told Hana I'd get her a table."
2. "Sponsor convo with Oliver Grant, cloud company, he wants a write-up of what teams build. Could be the co-organizer type? probably not, too corporate. Owes me an intro to their startup program lead."
3. "Guest list for March is 140 names. Need to know who I already know, who's relevant, who to meet first."

**He tries first:** paste a 40-name guest list into GamePlan; photograph a badge; scan another attendee's QR.

**He keeps it if:** batch capture does not fall over; the game plan is honest about who it does not know; the QR handshake takes under thirty seconds; there is a "who did I promise what" list on Monday.

**He deletes it if:** one debrief with four people becomes one person; the guest list gets fabricated ties; the badge photo takes a minute; he cannot see all promises in one place.

**Edge cases to hit:** four people and one tie in one note; a guest list of 140 names (bounds, latency, what is reported for unknowns); a badge photo with two names on it; a blurry photo; a QR handshake between two of his own test accounts; a debrief with a name that matches two people in his graph; closing a goal and reopening a new one (RelevantTo rebuild); NetworkHealth on a graph with one giant cluster.

---

## 6. The judge — three minutes, one phone

Not a user, but the audience for Sunday. Skims the Devpost, opens the hosted URL on a laptop, is handed a phone for ninety seconds. Wants to see: what is this, why Jac, does the two-phone thing actually work, is the privacy claim honest. Notices: a white screen for twenty seconds, a spinner with no words, a "score" anywhere, any wording that overclaims, a crash on the first tap.

**What the judge does:** signs up with a throwaway email, pastes the first line they think of ("Met Sarah, she does ML at Google"), taps the first thing on the home screen, then asks "what does my friend see?"

---

## Walkthrough protocol (for the agents)

**Server:** a local `jac start` (never the hosted tunnel). Each persona registers its own account (`<persona>_<runid>@example.com`, username the same without the domain). The Gemini key is billed; a persona run costs about 15 model calls.

**Two passes per persona, in this order:**

1. **Walker pass (curl):** register → login → `OnboardMe(about)` → `SetGoal` → each debrief through `Capture` → `GoalRank` → `GapFinder` → `Recall` with one question the persona would ask → `ListPromises` → the persona-specific walkers (`ImportPeople`, `GamePlan`, `PublishCard`/`get_card`, `Forget`, `Handshake`, `NetworkHealth`, `Tend`). Record every response that is wrong for the persona: an invented name, a hedge turned into a fact, a missing promise, a person merged that should not be, a bound hit, a latency over 15 s, an error.
2. **UI pass (browser, 375 px and laptop width, light and dark):** sign up as the same persona in the web app, do what "She/He tries first" says, then the rest of the loop. Record every UI bug with the screen, the step, and the file when you can find it (`components/...`), every place the copy would confuse this persona, and every missing thing the persona reaches for.

**Report format (one Linear comment per persona on SOH-208):**

```
### <Persona> — <n> bugs, <n> edge cases, <n> wishes
**UI bugs** (screen · step · what happened · file:line if known)
**Walker edge cases** (walker · exact input · what came back · what should have)
**Wishes, ranked** (what this persona reached for and did not find; one line each, with why)
**Would keep / would delete:** one sentence from the persona's point of view.
```

Findings on B's screens go to the owning issue as "Needs B:"; A fixes A's before the 02:00 freeze when cheap and demo-visible; the rest is roadmap.
