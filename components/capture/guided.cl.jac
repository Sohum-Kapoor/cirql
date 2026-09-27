"""Guided capture — the draft model and the prose Cirql reads. OWNER: Person B (SOH-209).

The shell keeps one `guided` dict (so the draft survives tab switches and
"Try again"); `compose_guided` turns it into labeled prose for the Capture
extractor, e.g.

  Met Dana Lee (PM, Rivian) at a networking event (MHacks career fair) today
  (2026-09-26). Introduced by Priya. We talked about battery supply chains. Why
  Dana is interesting to me: … How Dana reacted: … Next step: coffee chat.
  I promised to send the deck by the end of this week.

The first sentence starts with "Met <name>": capture.sv.jac stores
`Knows.how_met = "<kind>: <first 60 chars>"`, so the how-met line is what lands
there until `Capture(how_met)` exists (Needs A, SOH-166).

`guided["preview"]` is the user's hand-edited copy of the composed text ("" =
not edited); when set, it is what gets submitted.
"""

glob:pub MET_OPTIONS: list[list[str]] = [
         ["networking", "Networking event"],
         ["coffee", "Coffee chat"],
         ["campus", "Class / campus"],
         ["conference", "Conference"],
         ["intro", "Intro from someone"],
         ["online", "Online"],
         ["other", "Other"]
     ],
     WHEN_OPTIONS: list[list[str]] = [
         ["today", "Today"],
         ["yesterday", "Yesterday"],
         ["week", "Earlier this week"],
         ["date", "Pick a date"]
     ],
     NEXT_OPTIONS: list[list[str]] = [
         ["coffee", "Coffee chat"],
         ["follow_up", "Follow up"],
         ["send", "Send something"],
         ["intro", "Make an intro"],
         ["nothing", "Nothing yet, just remember them"]
     ],
     DUE_OPTIONS: list[list[str]] = [
         ["today", "Today"],
         ["week", "This week"],
         ["date", "Pick a date"]
     ],
     MAX_PEOPLE: int = 3;

# The last "how you met" chip, remembered for the session (a new draft starts on it).
glob _LAST: dict = {"met": ""};

glob _MET_PHRASE: dict = {
         "networking": "at a networking event",
         "coffee": "over coffee",
         "campus": "in class / on campus",
         "conference": "at a conference",
         "intro": "through an intro",
         "online": "online",
         "other": ""
     },
     _MET_SHORT: dict = {
         "networking": "networking event",
         "coffee": "coffee chat",
         "campus": "class / campus",
         "conference": "conference",
         "intro": "intro",
         "online": "online",
         "other": "other"
     },
     _NEXT_PHRASE: dict = {
         "coffee": "Next step: coffee chat.",
         "follow_up": "Next step: follow up.",
         "send": "Next step: send them something.",
         "intro": "Next step: make an intro.",
         "nothing": "Nothing planned yet, just remembering them."
     };

def:pub empty_person() -> dict {
    return {"name": "", "role": ""};
}

def:pub empty_guided() -> dict {
    return {
        "people": [empty_person()],
        "met": _LAST["met"] or "",
        "met_detail": "",
        "intro_by": "",
        "when": "today",
        "when_date": "",
        "talked": "",
        "why": "",
        "reaction": "",
        "next": "",
        "promise": "",
        "promise_due": "",
        "promise_date": "",
        "preview": ""
    };
}

"""Remember the chip for the next draft this session."""
def:pub remember_met(met: str) {
    _LAST["met"] = met;
}

def _pad(n: int) -> str {
    return ("0" + str(n)) if n < 10 else str(n);
}

"""Local calendar date `days_ago` days back, as YYYY-MM-DD."""
def:pub local_date(days_ago: int = 0) -> str {
    d: any = new(Date);  # jac:ignore[W2001]
    d.setDate((d.getDate() as int) - days_ago);
    return str(d.getFullYear()) + "-" + _pad((d.getMonth() as int) + 1) + "-" + _pad(d.getDate() as int);
}

def _named(g: dict) -> list[dict] {
    out: list[dict] = [];
    for p in (g["people"] or []) as list[dict] {
        if ((p["name"] or "") as str).strip() {
            out = out + [p];
        }
    }
    return out;
}

def _person_label(p: dict) -> str {
    name: str = ((p["name"] or "") as str).strip();
    role: str = ((p["role"] or "") as str).strip();
    return (name + " (" + role + ")") if role else name;
}

def _and_list(items: list[str]) -> str {
    if len(items) == 0 {
        return "";
    }
    if len(items) == 1 {
        return items[0];
    }
    head: str = "";
    for (i, s) in enumerate(items[:-1]) {
        head = head + (", " if i > 0 else "") + s;
    }
    return head + " and " + items[-1];
}

def _first_name(p: dict) -> str {
    name: str = ((p["name"] or "") as str).strip();
    return name.split(" ")[0] if name else "they";
}

def _end(s: str) -> str {
    t: str = s.strip();
    if not t {
        return "";
    }
    last: str = t[-1];
    return t if last == "." or last == "!" or last == "?" else t + ".";
}

def _when_phrase(g: dict) -> str {
    w: str = (g["when"] or "today") as str;
    if w == "yesterday" {
        return "yesterday (" + local_date(1) + ")";
    }
    if w == "week" {
        return "earlier this week";
    }
    if w == "date" and g["when_date"] {
        return "on " + (g["when_date"] as str);
    }
    return "today (" + local_date(0) + ")";
}

def _due_phrase(g: dict) -> str {
    d: str = (g["promise_due"] or "") as str;
    if d == "today" {
        return " by today (" + local_date(0) + ")";
    }
    if d == "week" {
        return " by the end of this week";
    }
    if d == "date" and g["promise_date"] {
        return " by " + (g["promise_date"] as str);
    }
    return "";
}

"""Short how-met line for `Capture(how_met)` / the person edit form:
"coffee chat, Ross café", "networking event, MHacks career fair", "intro via Priya"."""
def:pub how_met_line(g: dict) -> str {
    met: str = (g["met"] or "") as str;
    detail: str = ((g["met_detail"] or "") as str).strip();
    if met == "intro" {
        by: str = ((g["intro_by"] or "") as str).strip();
        base: str = ("intro via " + by) if by else "intro";
        return (base + ", " + detail) if detail else base;
    }
    if not met {
        return detail;
    }
    if met == "other" {
        return detail or "other";
    }
    short: str = (_MET_SHORT[met] or met) as str;
    return (short + ", " + detail) if detail else short;
}

"""The labeled prose Cirql reads (see module docstring)."""
def:pub compose_guided(g: dict) -> str {
    people: list[dict] = _named(g);
    if len(people) == 0 {
        return "";
    }
    labels: list[str] = [];
    for p in people {
        labels = labels + [_person_label(p)];
    }
    who: str = _and_list(labels);
    met: str = (g["met"] or "") as str;
    phrase: str = (_MET_PHRASE[met] or "") as str;
    detail: str = ((g["met_detail"] or "") as str).strip();
    first: str = "Met " + who;
    if phrase {
        first = first + " " + phrase;
    }
    if detail {
        first = first + (" (" + detail + ")" if phrase else " at " + detail + ",");
    }
    first = first + " " + _when_phrase(g) + ".";
    parts: list[str] = [first];
    by: str = ((g["intro_by"] or "") as str).strip();
    if met == "intro" and by {
        parts = parts + ["Introduced by " + by + "."];
    }
    subject: str = _first_name(people[0]) if len(people) == 1 else "they";
    talked: str = ((g["talked"] or "") as str).strip();
    if talked {
        parts = parts + ["We talked about " + _end(talked)];
    }
    why: str = ((g["why"] or "") as str).strip();
    if why {
        lead: str = ("Why " + subject + " is interesting to me: ") if len(people) == 1 else "Why they're interesting to me: ";
        parts = parts + [lead + _end(why)];
    }
    reaction: str = ((g["reaction"] or "") as str).strip();
    if reaction {
        parts = parts + ["How " + subject + " reacted: " + _end(reaction)];
    }
    nxt: str = (g["next"] or "") as str;
    if nxt and _NEXT_PHRASE[nxt] {
        parts = parts + [_NEXT_PHRASE[nxt] as str];
    }
    promise: str = ((g["promise"] or "") as str).strip().rstrip(".");
    if promise {
        body: str = promise[3:] if promise.lower().startswith("to ") else promise;
        parts = parts + ["I promised to " + body + _due_phrase(g) + "."];
    }
    out: str = "";
    for (i, s) in enumerate(parts) {
        out = out + (" " if i > 0 else "") + s;
    }
    return out;
}

"""What gets submitted: the hand-edited preview if any, else the composed text."""
def:pub guided_text(g: dict) -> str {
    edited: str = ((g["preview"] or "") as str).strip();
    return edited if edited else compose_guided(g);
}

"""The names typed into the form (Review uses them to pre-fill how you met)."""
def:pub guided_names(g: dict) -> list[str] {
    out: list[str] = [];
    for p in _named(g) {
        out = out + [((p["name"] or "") as str).strip()];
    }
    return out;
}

"""Missing required fields, as short labels ("" when ready)."""
def:pub guided_missing(g: dict) -> str {
    if len(_named(g)) == 0 {
        return "Add who you met.";
    }
    if not g["met"] {
        return "Pick how you met.";
    }
    return "";
}
