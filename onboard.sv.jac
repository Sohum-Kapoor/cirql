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
sem OnboardExtraction.name = "The person's first name or full name as they refer to themselves; 'me' if absent.";
sem OnboardExtraction.interests = "5 to 10 short topic phrases the person is into (e.g. 'accessible robotics'), lowercase, no duplicates.";
sem OnboardExtraction.goals = "1 to 3 concrete things they are working toward right now, each one sentence.";
sem OnboardExtraction.needs = "What they are looking for from other people (intros, feedback, hires, funding), each one short phrase.";
sem OnboardExtraction.offers = "What they can offer others (skills, access, resources), each one short phrase.";
sem OnboardExtraction.headline = "A one-line headline for a contact card, under 80 characters.";
sem OnboardExtraction.card_about = "Two sentences about them in first person, for a card others read.";
sem OnboardExtraction.links = "Any URLs or handles mentioned, verbatim; empty list if none.";

def extract_onboarding(about: str) -> OnboardExtraction by llm(temperature=0.2);

# ---------------------------------------------------------------- deterministic helpers

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

def clean_list(xs: list[str]) -> list[str] {
    seen: list[str] = [];
    out: list[str] = [];
    for x in xs {
        t = x.strip();
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

def find_goal_by_text(items: list[Goal], text: str) -> Goal | None {
    for g in items {
        if g.text == text {
            return g;
        }
    }
    return None;
}

def find_intent(items: list[Intent], kind: str, text_lower: str) -> Intent | None {
    for i in items {
        if i.kind == kind and i.text.lower() == text_lower {
            return i;
        }
    }
    return None;
}

# ---------------------------------------------------------------- walker

walker:priv OnboardMe {
    """Extract a self-onboarding paragraph into the caller's graph."""
    has about: str;
    has reports: list[dict] = [];

    can go with Root entry {
        now = datetime.now().isoformat();

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
            goal_texts = clean_list(extraction.goals or []);
            needs = clean_list(extraction.needs or []);
            offers = clean_list(extraction.offers or []);
            links = clean_list(extraction.links or []);
            headline = (extraction.headline or "").strip();
            card_about = (extraction.card_about or "").strip();
            extracted_ok = True;
        } except Exception {
            extracted_ok = False;
        }

        # 3. Get-or-create Me. On rerun, always refresh about; refresh name too
        # when this call's extraction succeeded and found a real name.
        existing_me = [root --> [?:Me]];
        if existing_me {
            me = existing_me[0];
            me.about = self.about;
            if extracted_ok and name and name.lower() != "me" {
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
            t = topic.strip().lower();
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
        for g_text in goal_texts {
            gt = g_text.strip();
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

        existing_intents = [me ->:HasIntent:->];
        for n_text in needs {
            nt = n_text.strip();
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
                new_intent = (me +>:HasIntent:+> Intent(kind="need", text=nt, source_kind="self"))[0];
                note +>:AssertsIntent(span=nt):+> new_intent;
                existing_intents.append(new_intent);
                intents.append(new_intent);
            }
        }
        for o_text in offers {
            ot = o_text.strip();
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
                new_intent = (me +>:HasIntent:+> Intent(kind="offer", text=ot, source_kind="self"))[0];
                note +>:AssertsIntent(span=ot):+> new_intent;
                existing_intents.append(new_intent);
                intents.append(new_intent);
            }
        }

        # Extraction failed: report the graph's existing state, not empty lists.
        if not extracted_ok {
            interests = [me ->:HasInterest:->];
            goals = [me ->:HasGoal:->];
            intents = [me ->:HasIntent:->];
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
