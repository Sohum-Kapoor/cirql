# Cirql — the two-minute demo, tap by tap

Two phones on the hosted server, two real accounts, a laptop on the projector showing the website's People tab with the graph. Phone A = SK (the demo user, seeded from `docs/seed_debriefs.md`). Phone B = Jesse (the friend account, seeded with the six friend debriefs, card published). Nothing else touches the host during these two minutes.

Rules said out loud, once each: an agent never reads another person's graph; a human approves every step; nothing sends.

## Before walking on (checklist, 10 minutes before)

- Host up: `curl -s -o /dev/null -w '%{http_code}' https://<tunnel>/` → 200. `scripts/demo_check.jac` run within the last hour: 22 PASS.
- Phone A logged in as the demo user; Home shows the active goal "Land a summer 2027 climate-tech VC internship" and a ranked list. Phone B logged in as the friend; Inbox empty.
- Both phones on the same hotspot as the laptop that runs the host. Pollers at 3 s or slower.
- Mic permission already granted on Phone A. A 5-second debrief rehearsed: "Met Maya Okafor at JacHacks. She works on accessible robotics, knows Arjun from their lab, wants feedback from wheelchair users. I promised to send our demo."
- Laptop: website logged in as the demo user, People → Graph, dark mode, browser zoom 125%.

## 0:00 — Capture (Phone A, 25 s)

1. Tap Capture (bottom bar). Voice opens by default. Hold, say the Maya line, release.
2. Transcript appears; tap Save. Review screen: Maya (new person), the robotics fact, the wheelchair-user need, the reported tie to Arjun, the promise "send our demo", each with a source chip.
3. Tap one source chip: the exact words highlight. Say: "every claim points back at what I said."
4. Tap Done. Home re-ranks.

## 0:25 — Aim (Phone A, 20 s)

5. Home: the goal at the top, the ranked list under it. Say: "the ranking is a property of the goal, not the person; nobody gets a score."
6. Tap Maya's row: the person sheet, with the reason for her rank, her facts with ages, the promise, Draft follow-up. Do not send anything. Close.

## 0:45 — Find the gap (Phone A, 15 s)

7. Home shows the gap card: "No warm path to a climate-tech VC." Say: "the agent walked my graph and found who the goal needs that I don't have."
8. Tap Ask my network. The sheet shows the need and one line about me, no names. Confirm. Say: "a need, one line, and a handle. Nothing from my graph leaves."

## 1:00 — Ask the network (both phones, 45 s)

9. Phone B: Inbox shows "A friend's agent is looking for a climate-tech VC. You have 1 strong match." Say: "Jesse's agent searched only Jesse's graph and answered with a count."
10. Phone B: tap Approve. Then the opt-in card for Priya Rao: say "in the demo a tap stands in for Priya's reply, and we say so." Tap Opt in, then Reveal.
11. Phone A: the reveal card arrives: Priya Rao's card, granted read-only, with the three-way intro draft. Tap Claim. Priya lands in A's people.
12. Laptop: the graph re-draws with Priya attached. Tap Priya on the projector: her ties light up, everything else dims.

## 1:45 — Close (15 s)

Say: "Capture, aim, find the gap, ask the network. Four walkers on a graph, in Jac, with a human at every hop, and a receipt on everything. Ask it who we should meet next; that's the agent inbox." Open Inbox on Phone A once: three proposed actions with evidence. Stop.

## If something breaks

- Network dies: open the app's mock mode (Settings) and continue the same taps; say it out loud.
- Model slow on Capture: keep talking through the receipts; the note is saved before extraction, it will land.
- Phone B never gets the request: Phone A's request card shows the status chip; say "the host queues one request at a time", pull to refresh on B.
- Reveal arrives without a name: the requester's card had no name; that account's onboarding must set one before the demo.
