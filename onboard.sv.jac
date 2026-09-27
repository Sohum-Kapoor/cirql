"""OnboardMe — turn a scrubbed about-me paragraph into Me, Interests, Goals,
Intents, and a drafted Card.

OWNER: Person A. See contracts/walkers.md `OnboardMe(about: str)` for the exact
report shape and docs/PRD.md for the model. Idempotent: rerunning updates Me and
Card in place and never duplicates an Interest with the same topic, a Goal with
the same text, or an Intent with the same (kind, lowercase text).
"""

import from llm { llm }
import from datetime { datetime }
import from schema {
    Me, Note, Interest, Goal, Intent, Card,
    Owns, HasInterest, HasGoal, HasIntent, AssertsIntent
}
import from freshness { default_expiry }
import from goals { goal_texts_match }


# ---------------------------------------------------------------- extraction

obj OnboardExtraction {
    has name: str;
    has interests: list[str];
    has goals: list[str];
    has needs: list[str];
    has offers: list[str];
    has headline: str;
    has card_about: str;
    has links: list[str];
}
sem OnboardExtraction.name = "The speaker's own name if they state it (e.g. 'I'm Sam, ...' -> 'Sam'), else empty.";
sem OnboardExtraction.interests = "5 to 10 short topic phrases the person is into (e.g. 'accessible robotics'), lowercase, no duplicates.";
sem OnboardExtraction.goals = "1 to 3 concrete outcomes the person is trying to achieve in the coming months. A goal is any outcome the writer is working toward or wants to achieve, whether or not they call it a goal: raising a round, landing an internship or job, recruiting participants, finding a co-founder, getting feedback from a group. Phrase it as the ask (e.g. 'Raise a pre-seed from climate-tech investors', 'Land a summer 2027 VC internship'), not a description of what they build.";
sem OnboardExtraction.needs = "What they are looking for from other people (intros, feedback, hires, funding), each one short phrase.";
sem OnboardExtraction.offers = "What they can offer others (skills, access, resources), each one short phrase.";
sem OnboardExtraction.headline = "A one-line headline for a contact card, under 80 characters.";
sem OnboardExtraction.card_about = "Two sentences about them in first person, for a card others read.";
sem OnboardExtraction.links = "Any URLs or handles mentioned, verbatim; empty list if none.";

def extract_onboarding(about: str) -> OnboardExtraction by llm(temperature=0.2);

# ---------------------------------------------------------------- deterministic helpers

glob NAME_CUES: list[str] = ["my name is ", "i'm ", "i am ", "im ", "this is ", "call me "];

"""SOH-212 fallback when the model is unavailable: the speaker's own name
from "I'm Sam, ..." / "My name is Sam ..." / "I am Sam Lee." - only a
Capitalized word counts (so "I am a community organizer" yields "")."""
def name_from_about(about: str) -> str {
    text = (about or "").strip();
    low = text.lower();
    for cue in NAME_CUES {
        idx = -1;
        if low.startswith(cue) {
            idx = 0;
        } else {
            pos = low.find(" " + cue);
            if pos >= 0 {
                idx = pos + 1;
            }
        }
        if idx < 0 {
            continue;
        }
        rest = text[idx + len(cue):].strip();
        words: list[str] = [];
        for w in rest.split() {
            word = w.strip(",.;:!?");
            if len(word) == 0 or not word[0].isupper() or not word.replace("-", "").replace("'", "").isalpha() {
                break;
            }
            words.append(word);
            if len(words) >= 2 or w != word {
                break;
            }
        }
        if len(words) > 0 {
            return " ".join(words);
        }
    }
    return "";
}

"""SOH-212: 'Sep 26' style, hand-written month-day - this compiler's
`datetime.strftime` has no `%-d` (no-leading-zero day), so `strftime("%b ")`
(which already includes the trailing space) plus the plain `str(dt.day)`
gets the same result without a leading zero."""
def month_day(dt: datetime) -> str {
    return dt.strftime("%b ") + str(dt.day);
}

"""SOH-212: the `how_met` the onboarding "bring five people" step should use
for people it adds, instead of capture.sv.jac's generic
`default_how_met("paste", ...)` ("from a pasted note on 2026-09-26") - a
human sentence with a hand-written-style date: "added when you set up Cirql
(Sep 26)". `capture.sv.jac`'s own default is untouched (AGENTS.md ownership:
that default serves every OTHER capture, not just onboarding); Capture
already accepts an explicit `how_met` override for exactly this purpose
(SOH-166: "an explicit how_met... wins for NEW edges"). NEEDS B (contracts/
walkers.md, 2026-09-26 SOH-212 note): the onboarding paste call must pass
`how_met=onboard.onboarding_added_how_met()`."""
def onboarding_added_how_met(now: datetime | None = None) -> str {
    dt = now if now is not None else datetime.now();
    return f"added when you set up Cirql ({month_day(dt)})";
}

def handle_from_name(name: str) -> str {
    slug = "";
    prev_dash = False;
    for ch in name.lower() {
        if ch.isalnum() {
            slug += ch;
            prev_dash = False;
        } elif not prev_dash {
            slug += "-";
            prev_dash = True;
        }
    }
    slug = slug.strip("-");
    if slug == "" {
        return "me";
    }
    return slug;
}

"""SOH-212 (judge pass): a goal came back as "Identify promising Jac teams to
follow after JacHacks." and the client's own template ("For your goal: {text},
here's...") then rendered a double stop: "...JacHacks., here's". Strip a
trailing run of sentence-ending punctuation ('.', '!', '?') and whitespace
from the END of the text - never anything in the middle - at the point a
goal/intent/interest is stored, so no downstream template can double it up."""
def clean_text(text: str) -> str {
    t = (text or "").strip();
    while len(t) > 0 and t[-1] in ".!? \t\r\n" {
        t = t[:-1];
    }
    return t;
}

def clean_list(xs: list[str]) -> list[str] {
    seen: list[str] = [];
    out: list[str] = [];
    for x in xs {
        t = clean_text(x);
        if t == "" {
            continue;
        }
        key = t.lower();
        if key in seen {
            continue;
        }
        seen.append(key);
        out.append(t);
    }
    return out;
}

def jid_suffix(j: str) -> str {
    tail = j[-6:].lower();
    out = "";
    for ch in tail {
        if ch.isalnum() {
            out += ch;
        }
    }
    return out;
}

def find_by_topic(items: list[Interest], topic: str) -> Interest | None {
    for i in items {
        if i.topic == topic {
            return i;
        }
    }
    return None;
}

"""SOH-225: near-duplicate match (`goals.goal_texts_match`), not exact text
equality, so re-running onboarding (or a batch of extracted goals that
restate the same ask) never creates a second Goal for the same outcome."""
def find_goal_by_text(items: list[Goal], text: str) -> Goal | None {
    for g in items {
        if goal_texts_match(g.text, text) {
            return g;
        }
    }
    return None;
}

"""SOH-225: get-or-create each of `goal_texts` as a Goal under `me`, deduping
by `find_goal_by_text` both against pre-existing goals already in
`existing_goals` and against duplicates within the same extraction batch —
each newly-created goal is appended to `existing_goals` as we go, so a later
near-duplicate in the same call matches it instead of creating a second
Goal. Returns the Goals (existing or new) in extraction order, one per
matched group. Kept as a plain def, testable directly on hand-built nodes."""
def collect_goals(me: Me, existing_goals: list[Goal], goal_texts: list[str], now: str) -> list[Goal] {
    goals: list[Goal] = [];
    for g_text in goal_texts {
        gt = clean_text(g_text);
        if gt == "" {
            continue;
        }
        found_g = find_goal_by_text(existing_goals, gt);
        if found_g {
            if found_g not in goals {
                goals.append(found_g);
            }
        } else {
            new_g = (me +>:HasGoal:+> Goal(text=gt, created_at=now))[0];
            existing_goals.append(new_g);
            goals.append(new_g);
        }
    }
    return goals;
}

"""SOH-164: when extraction (after `collect_goals`/dedupe) found no goal at
all but the person did surface at least one need, don't leave them with an
empty Goals list — promote the `strongest_need` to an active Goal, get-or-
create like any other goal (`find_goal_by_text` against `existing_goals`
first). The need's Intent is untouched by this and is created/kept
separately; the ask is reachable as both a Goal and an Intent. No-op (returns
`goals` unchanged) when `goals` already has something or `needs` is empty."""
def promote_strongest_need(me: Me, existing_goals: list[Goal], goals: list[Goal], needs: list[str], now: str) -> list[Goal] {
    if goals or not needs {
        return goals;
    }
    text = clean_text(strongest_need(needs));
    if text == "" {
        return goals;
    }
    found_g = find_goal_by_text(existing_goals, text);
    if found_g {
        promoted = found_g;
    } else {
        promoted = (me +>:HasGoal:+> Goal(text=text, created_at=now))[0];
        existing_goals.append(promoted);
    }
    if promoted not in goals {
        goals.append(promoted);
    }
    return goals;
}

def find_intent(items: list[Intent], kind: str, text_lower: str) -> Intent | None {
    for i in items {
        if i.kind == kind and i.text.lower() == text_lower {
            return i;
        }
    }
    return None;
}

"""SOH-164: outcome-shaped words/phrases. Shared by `looks_like_goal` (an
"I'm ..." ask still counts as a goal if it names one of these) and
`strongest_need` (which need reads most like a goal when none was stated)."""
glob GOAL_OUTCOME_KEYWORDS: list[str] = [
    "raise", "land", "get", "find", "hire", "recruit", "close", "launch",
    "ship", "intro", "internship", "job", "funding", "round", "feedback",
    "participants", "co-founder", "customers", "pilot"
];

def has_outcome_keyword(text: str) -> bool {
    t = text.lower();
    for kw in GOAL_OUTCOME_KEYWORDS {
        if kw in t {
            return True;
        }
    }
    return False;
}

"""Reject candidates that describe what the person does/builds rather than
asking for an outcome. Case-insensitive prefix check on the stripped text —
loosened (SOH-164) so an ask phrased like a need ("I'm raising a pre-seed
round...") is not thrown out just because it starts with "I'm"/"we are": a
bad-prefixed candidate still counts as a goal if it names an outcome
(`has_outcome_keyword`)."""
def looks_like_goal(text: str) -> bool {
    t = text.strip().lower();
    bad_prefixes = ["i am", "i'm", "i build", "i work", "we build", "we are"];
    for prefix in bad_prefixes {
        if t.startswith(prefix) {
            return has_outcome_keyword(t);
        }
    }
    return True;
}

"""SOH-164: which need reads most like the outcome the person is actually
after — the longest one that names an outcome (`has_outcome_keyword`), else
just the first non-empty need. Empty string when `needs` is empty/blank."""
def strongest_need(needs: list[str]) -> str {
    best = "";
    best_len = -1;
    for n in needs {
        nt = n.strip();
        if nt == "" {
            continue;
        }
        if has_outcome_keyword(nt) and len(nt) > best_len {
            best = nt;
            best_len = len(nt);
        }
    }
    if best != "" {
        return best;
    }
    for n in needs {
        nt = n.strip();
        if nt != "" {
            return nt;
        }
    }
    return "";
}

"""Set the FIRST goal in `goals` (extraction order) active and every other
Goal under `me` (including ones extraction never touched) inactive. No-op if
`goals` is empty. Mirrors SetGoal's single-active-goal behavior."""
def activate_first_goal(me: Me, goals: list[Goal]) -> None {
    if not goals {
        return;
    }
    first = goals[0];
    for g in [me ->:HasGoal:->] {
        g.active = jid(g) == jid(first);
    }
}

# ---------------------------------------------------------------- walker

walker:priv OnboardMe {
    """Extract a self-onboarding paragraph into the caller's graph."""
    has about: str;
    has name: str = "";      # SOH-212: the signup name; wins over anything extracted
    has reports: list[dict] = [];

    can go with Root entry {
        now_dt = datetime.now();
        now = now_dt.isoformat();

        # 1. Store the note first so it is never lost, even if extraction fails.
        note = (root ++> Note(text=self.about, kind="about_me", captured_at=now))[0];

        # 2. One LLM call. Never loop it.
        name: str = "me";
        interest_topics: list[str] = [];
        goal_texts: list[str] = [];
        needs: list[str] = [];
        offers: list[str] = [];
        headline: str = "";
        card_about: str = "";
        links: list[str] = [];
        extracted_ok = False;

        try {
            extraction = extract_onboarding(self.about);
            if extraction.name and extraction.name.strip() {
                name = extraction.name.strip();
            }
            interest_topics = clean_list(extraction.interests or []);
            candidate_goals = clean_list(extraction.goals or []);
            goal_texts = [g for g in candidate_goals if looks_like_goal(g)];
            needs = clean_list(extraction.needs or []);
            offers = clean_list(extraction.offers or []);
            links = clean_list(extraction.links or []);
            headline = (extraction.headline or "").strip();
            card_about = (extraction.card_about or "").strip();
            extracted_ok = True;
        } except Exception {
            extracted_ok = False;
        }

        # SOH-212: explicit name > extracted name > "I'm Sam" in the text > "me".
        name_given = False;
        if len(self.name.strip()) > 0 {
            name = self.name.strip();
            name_given = True;
        } elif name.lower() == "me" {
            guessed = name_from_about(self.about);
            if len(guessed) > 0 {
                name = guessed;
                name_given = True;
            }
        } else {
            name_given = extracted_ok;
        }

        # 3. Get-or-create Me. On rerun, always refresh about; refresh name too
        # when this call's extraction succeeded and found a real name.
        existing_me = [root --> [?:Me]];
        if existing_me {
            me = existing_me[0];
            me.about = self.about;
            if name_given and name and name.lower() != "me" {
                me.name = name;
            }
        } else {
            me = (root ++> Me(name=name, about=self.about))[0];
        }

        # 4. Interests, goals, intents (deduped, with provenance on new intents).
        interests: list[Interest] = [];
        goals: list[Goal] = [];
        intents: list[Intent] = [];

        existing_interests = [me ->:HasInterest:->];
        for topic in interest_topics {
            t = clean_text(topic).lower();
            if t == "" {
                continue;
            }
            found_i = find_by_topic(existing_interests, t);
            if found_i {
                if found_i not in interests {
                    interests.append(found_i);
                }
            } else {
                new_i = (me +>:HasInterest:+> Interest(topic=t))[0];
                existing_interests.append(new_i);
                interests.append(new_i);
            }
        }

        existing_goals = [me ->:HasGoal:->];
        goals = collect_goals(me, existing_goals, goal_texts, now);

        existing_intents = [me ->:HasIntent:->];
        for n_text in needs {
            nt = clean_text(n_text);
            if nt == "" {
                continue;
            }
            found_n = find_intent(existing_intents, "need", nt.lower());
            if found_n {
                note +>:AssertsIntent(span=nt):+> found_n;
                if found_n not in intents {
                    intents.append(found_n);
                }
            } else {
                new_intent = (me +>:HasIntent:+> Intent(kind="need", text=nt, source_kind="self", expires_at=default_expiry("need", now_dt)))[0];
                note +>:AssertsIntent(span=nt):+> new_intent;
                existing_intents.append(new_intent);
                intents.append(new_intent);
            }
        }
        for o_text in offers {
            ot = clean_text(o_text);
            if ot == "" {
                continue;
            }
            found_o = find_intent(existing_intents, "offer", ot.lower());
            if found_o {
                note +>:AssertsIntent(span=ot):+> found_o;
                if found_o not in intents {
                    intents.append(found_o);
                }
            } else {
                new_intent = (me +>:HasIntent:+> Intent(kind="offer", text=ot, source_kind="self", expires_at=default_expiry("offer", now_dt)))[0];
                note +>:AssertsIntent(span=ot):+> new_intent;
                existing_intents.append(new_intent);
                intents.append(new_intent);
            }
        }

        # SOH-164: no goal was stated but at least one need was — promote the
        # strongest need to an active Goal rather than reporting an empty
        # Goals list. No-op if `goals` already has something or there were
        # no needs (both true when extraction failed, since `needs` stays []).
        goals = promote_strongest_need(me, existing_goals, goals, needs, now);

        # Extraction failed: report the graph's existing state, not empty lists,
        # and leave goal activation untouched.
        if not extracted_ok {
            interests = [me ->:HasInterest:->];
            goals = [me ->:HasGoal:->];
            intents = [me ->:HasIntent:->];
        } else {
            # Exactly one active goal: the first extracted goal wins; every
            # other Goal under Me (new or pre-existing) goes inactive.
            activate_first_goal(me, goals);
        }

        # 5. Get-or-create the Card; update in place on rerun. Handle is stable
        # once assigned and unique across users (name slug + jid suffix).
        existing_card = [me ->:Owns:-> [?:Card]];
        if existing_card {
            card = existing_card[0];
        } else {
            handle = handle_from_name(me.name) + "-" + jid_suffix(jid(me));
            card = (me +>:Owns:+> Card(handle=handle))[0];
        }
        if extracted_ok {
            card.headline = headline;
            card.about = card_about;
            card.looking_for = needs;
            card.can_offer = offers;
            card.links = links;
        }
        card.name = me.name;
        card.updated_at = now;

        # 6. One report.
        report {
            "me": me,
            "interests": interests,
            "goals": goals,
            "intents": intents,
            "card": card,
            "note_id": jid(note)
        };
    }
}
