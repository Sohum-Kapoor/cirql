# Seed debriefs (draft for B, SOH-175)

Drop-in text for `seed/seed.example.json` (B's file). Pseudonymized, fictional names, real-shaped roles. Designed so the demo works on this data:

- **No warm path to a climate-tech VC in the demo user's graph** → GapFinder raises the gap on stage.
- **Two people named Maya** (Okafor, Lindqvist) → the ambiguity path (`Person(status="proposed")`, never guessed) has something to show.
- **Three complementary need↔offer pairs** inside the graph (marked ★) → ScoreAgainstNeed / Tend have signal.
- **The friend's graph holds the climate-tech VC** (Priya Rao) → the Exchange finds exactly one strong match on the second phone.

Load with `seed/load.jac` (one Capture per string; ~35 model calls on the billed key, about 4 minutes with `SEED_SLEEP=3`). Register the friend account separately and load `friend_debriefs` there.

## Demo user (first phone) — `about_me`

"I'm a CS junior at Michigan. I build accessible robotics with the Michigan Robotics lab and I run the campus hackathon. This summer I want a VC internship in climate tech, and I'm also looking for feedback from wheelchair users on our prototype. I can offer Jac and TypeScript help, and intros in the Ann Arbor student-founder scene. I play trumpet in a jazz combo on weekends."

## Demo user — `goals`

```json
["Land a summer 2027 climate-tech VC internship", "Get feedback from wheelchair users on our accessible robotics prototype"]
```

## Demo user — `debriefs` (30)

```json
[
  "Met Maya Okafor at JacHacks. She works on accessible robotics at the Michigan Robotics lab, knows Arjun Patel from their lab, and wants feedback from wheelchair users on her prototype. I promised to send her our demo.",
  "Coffee with Arjun Patel. He's a PhD student in the robotics lab working on grasping for assistive arms. He offered to review our gripper design and mentioned his advisor Dr. Lena Voss runs the accessibility track.",
  "Ran into Maya Lindqvist at the design school mixer. She's a UX researcher who runs usability sessions with wheelchair users at the U-M Adaptive Sports program. She offered to host a session for our prototype if we bring snacks. ★ (offer ↔ our need)",
  "Talked to Dr. Lena Voss after her seminar. She leads the accessibility track in the robotics lab and wants student projects to test with real users this fall. She said she can introduce us to the Ann Arbor Center for Independent Living.",
  "Met Tomas Reyes at the founder meetup. He's building a battery-recycling startup in Ypsilanti, raising a pre-seed this fall, and wants intros to climate-tech investors. He can offer factory-floor tours. ★ (his need matches nothing in my graph — that's the point)",
  "Dinner with Priyanka Nair, my former TA. She's now an engineer at Rivian on charging infrastructure. She's looking for a co-founder with hardware experience for a side project. She can offer intros at Rivian.",
  "Met Jordan Blake at the hackathon judging table. Jordan is a program manager at a student accelerator and wants more hardware teams to apply. Offered office hours for our pitch deck. ★ (offer ↔ Tomas's need for pitch help)",
  "Chatted with Sofia Marchetti in the jazz combo. She's a music grad student who also does grant writing for the arts school; she offered to look over our NSF I-Corps application.",
  "Met Daniel Osei at the climate club. He's an econ major organizing a campus energy audit and needs volunteers with data skills. I said I'd help with the spreadsheet analysis. I promised to send him our sensor data format.",
  "Met Hana Sato at the robotics lab open house. She's an undergrad building a low-cost wheelchair sensor kit and wants a teammate for the Makeathon. She knows Maya Okafor from the lab.",
  "Lunch with Marcus Lee, an alum who works in product at a mapping company in Detroit. He's looking for student interns for summer. He offered to refer strong candidates.",
  "Met Elena Petrova at the entrepreneurship center. She runs the student venture fund and wants deal flow from hardware teams; she can't invest in climate herself but knows people who do. She promised to send the application link.",
  "Talked to Kwame Mensah at the accessibility panel. He's a wheelchair user and a policy analyst at the county who has been vocal about sidewalk mapping; he offered to test our prototype and give blunt feedback. ★ (offer ↔ my goal)",
  "Met Rachel Kim at the Ann Arbor startup happy hour. She's a recruiter at a solar company and needs junior firmware engineers this fall. I promised to send her two names from the hackathon.",
  "Ran into Ben Carter from my freshman dorm. He's now at a consulting firm and wants to move into climate work; he asked me to keep him in mind for founder intros.",
  "Met Aisha Rahman at the makerspace. She teaches the intro fabrication course and offered to give our team after-hours access to the laser cutter.",
  "Coffee with Noah Fischer, a grad student in mechanical engineering. He's working on lightweight wheelchair frames and wants to collaborate on user testing. He knows Kwame Mensah from a county advisory board.",
  "Met Chloe Dubois at the international student welcome. She's a French exchange student studying public policy and interested in disability rights; she offered to translate our user survey.",
  "Talked to Sam Whitaker after the pitch competition. He founded a tutoring startup, sold it, and now angel invests in edtech only. He offered to do a mock investor Q&A with us.",
  "Met Grace Okonkwo at the women in engineering dinner. She's a senior heading to a battery startup in Boston and wants to stay connected to campus hardware projects.",
  "Chatted with Leo Tanaka at the game night. He's a designer who does motion graphics; he offered to make a 30-second animation for our demo video if we give him a script by next week.",
  "Met Fatima Al-Sayed at the research symposium. She's a postdoc in human-computer interaction studying assistive tech adoption and is looking for prototypes to include in a field study. ★ (need ↔ our prototype)",
  "Talked to Oliver Grant, the hackathon sponsor rep from a cloud company. He offered credits for student projects and asked for a write-up of what we build.",
  "Met Isabella Rossi at the volunteer fair. She coordinates the campus disability services office and wants to pilot new assistive tools with students. She promised to email me the pilot form.",
  "Coffee with Ethan Park, a CS senior who interned at a climate-data nonprofit. He wants to hand off his summer project and can introduce me to his former manager there.",
  "Met Zara Hussain at the debate society social. She's pre-law and interested in accessibility compliance; she offered to review our consent forms for the user study.",
  "Ran into Miguel Santos at the bike co-op. He's a mechanical engineer at a mobility startup in Detroit that makes power-assist wheelchair attachments. He wants to see our prototype and can offer parts at cost.",
  "Met Yuki Nakamura at the language exchange. She's a statistics master's student who offered to help design our user study so the results are publishable.",
  "Talked to David Cohen at the alumni networking night. He's a partner at a law firm doing startup formation and offered a free first consultation for student founders. He asked me to introduce him to Tomas Reyes.",
  "Met Amara Diallo at the climate hackathon kickoff. She's organizing a student climate-tech showcase in November and wants hardware demos; she promised to save us a table."
]
```

## Friend account (second phone) — `about_me`

"I'm Sam, I run a student-founder community in Ann Arbor and spend a lot of time with early-stage investors. I can offer intros to climate-tech VCs and to founders in my community. I'm looking for hardware teams to feature at our next showcase."

## Friend account — `goals`

```json
["Feature three hardware teams at the November showcase"]
```

## Friend account — `debriefs` (6)

```json
[
  "Lunch with Priya Rao. She's a partner at a climate-tech seed fund in Detroit and takes cold pitches from students if a founder she knows vouches. She offered to review decks from my community and to take intros to student founders working on climate hardware.",
  "Met Carlos Mendez at the founder dinner. He runs a solar installation company and is hiring apprentices; he offered site visits for students.",
  "Coffee with Ling Zhao, an associate at a generalist VC in Chicago. She's not doing climate deals this year but wants to meet consumer app founders.",
  "Talked to Jamal Wright, who organizes the Detroit hardware meetup. He wants speakers for the spring series and can offer a slot to student teams.",
  "Met Nadia Petrov at the accelerator demo day. She's a climate policy fellow who can offer intros to state grant programs for clean-tech pilots.",
  "Ran into Owen Hughes, an angel who invests in campus startups; he wants to see more hardware teams and offered to co-host office hours with me."
]
```

Expected on stage: the demo user's GapFinder reports a climate-tech VC gap; the friend's `ReplyToRequest` returns `match_count: 1, strength: "strong"` (Priya) and `Ling Zhao` stays weak or excluded because she is not doing climate deals.
