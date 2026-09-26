"""CaptureImage — a badge or business-card photo becomes a Person + Facts
via byLLM vision (SOH-192).

OWNER: Person A. See contracts/walkers.md `CaptureImage(...)` for the exact
report shape. Structurally mirrors `capture.sv.jac`'s Note -> Person
get-or-create -> Fact creation with provenance (`Asserts`, `Mentions`,
`Knows`), but the photographed person is resolved by an org-aware
ambiguity rule specific to a badge scan (an existing person with the same
name but a DIFFERENT org is never silently merged) rather than
`capture.sv.jac`'s `resolve_person` (which resolves on name alone, or on
first-token ambiguity) - that rule doesn't exist there, so it is written
locally instead of copied. A newly-seen badge person is always created
`status="proposed"` (same "needs a swipe-confirm" policy `imports.sv.jac`
uses for machine-read data - schema.sv.jac's `Person.status` comment).

Extraction is ONE `by llm` vision call (`read_badge`, gemini-3.8-flash is
vision-capable); graph-writing is the deterministic `apply_badge_read` def,
tested without the LLM in `vision.test.jac`. Email/phone/links are reported
back in `read` only - schema stores no contact details this weekend.
"""

import from schema { Me, Person, Note, Fact, Knows, Asserts, Mentions, FactAbout }
import from llm { llm }
import from datetime { datetime }
import from byllm.lib { Image }
import base64;
import os;
import from uuid { uuid4 }

glob MAX_IMAGE_BYTES: int = 8 * 1024 * 1024;   # 8 MB cap
glob MAX_IMAGE_B64_CHARS: int = 4 * ((MAX_IMAGE_BYTES + 2) // 3) + 256;   # SOH-211: base64 length of the byte cap + room for a data: prefix, checked BEFORE decoding

# ---------------------------------------------------------------- LLM shape

obj BadgeRead {
    has name: str;
    has org: str;
    has title: str;
    has email: str;
    has phone: str;
    has links: list[str];
    has raw_text: str;
    has is_person_card: bool;
}

sem BadgeRead.name = "The person's full name exactly as printed on the badge or card; empty string if none is printed.";
sem BadgeRead.org = "The person's organization or company as printed; empty string if not shown.";
sem BadgeRead.title = "The person's job title or role as printed; empty string if not shown.";
sem BadgeRead.email = "The person's email address as printed; empty string if not shown.";
sem BadgeRead.phone = "The person's phone number as printed; empty string if not shown.";
sem BadgeRead.links = "Any URLs or social handles printed on the badge or card; empty list if none.";
sem BadgeRead.raw_text = "Every line of text visible in the image, in reading order.";
sem BadgeRead.is_person_card = "True when the image is a badge, business card, or name tag identifying one person; false otherwise (a receipt, a poster, an unrelated photo, ...).";

def read_badge(img: Image, context: str) -> BadgeRead by llm(temperature=0.1);
sem read_badge = "Read a photographed badge, business card, or name tag and extract the printed identity fields.";
sem read_badge.img = "The photographed badge, business card, or name tag.";
sem read_badge.context = "Optional free-text context about where or when this photo was taken; empty string if none given.";

# ---------------------------------------------------------------- deterministic helpers

"""Ext (no leading dot) to save the uploaded image under, from the client's
mime type. Falls back to "jpg" for anything unrecognized (including plain
"image/jpeg", which is renamed - not kept as "jpeg")."""
def ext_for(mime: str) -> str {
    if mime == "image/png" {
        return "png";
    }
    if mime == "image/webp" {
        return "webp";
    }
    if mime == "image/heic" {
        return "heic";
    }
    return "jpg";
}

"""The first line of raw_text containing needle (case-insensitive), else
needle itself. needle empty -> needle (never scans for an empty string)."""
def line_with(raw_text: str, needle: str) -> str {
    stripped = needle.strip();
    if len(stripped) == 0 {
        return needle;
    }
    for line in raw_text.split("\n") {
        if stripped.lower() in line.lower() {
            return line.strip();
        }
    }
    return needle;
}

"""Deterministic note text for a badge photo - stable regardless of
whether a Person ends up created from it."""
def badge_to_note_text(read: dict[str, any]) -> str {
    name = read["name"] as str;
    title = read["title"] as str;
    org = read["org"] as str;
    raw_text = read["raw_text"] as str;
    return f"Badge photo: {name}, {title} at {org}. {raw_text}";
}

"""One Fact per non-empty org/title on the badge, each spanned to the
raw_text line it came from (or the bare value if no line matches)."""
def facts_from_read(read: dict[str, any]) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    org = (read["org"] as str).strip();
    title = (read["title"] as str).strip();
    raw_text = read["raw_text"] as str;

    if len(org) > 0 {
        out.append({"text": f"Works at {org}", "span": line_with(raw_text, org)});
    }
    if len(title) > 0 {
        out.append({"text": f"Title: {title}", "span": line_with(raw_text, title)});
    }
    return out;
}

"""Only the fields the report contract's `read` block carries - never
`is_person_card` (internal routing only)."""
def read_report(read: dict[str, any]) -> dict[str, any] {
    return {
        "name": read["name"], "org": read["org"], "title": read["title"],
        "email": read["email"], "phone": read["phone"], "links": read["links"],
        "raw_text": read["raw_text"]
    };
}

"""Get-or-create the badge's Person. Same-name + same-or-blank org reuses
(filling blank org/title, like `imports.sv.jac`'s exact-name reuse);
same-name + a DIFFERENT non-empty org is never merged - a new `proposed`
Person is created and the existing match(es) come back as
`ambiguous_with`. No match at all -> new `proposed` Person, no
ambiguity. New people always get `Knows(status="proposed", how_met="badge
photo")` - a badge/OCR read is machine-read data, same trust level
`imports.sv.jac` gives a CSV row."""
def resolve_badge_person(name: str, org: str, title: str, me: Me, note: Note) -> dict[str, any] {
    key = name.strip().lower();
    new_org = org.strip().lower();

    known: list[Person] = [me ->:Knows:->];
    matches: list[Person] = [];
    for p in known {
        if p.name.strip().lower() == key {
            matches.append(p);
        }
    }

    now = datetime.now().isoformat();

    if len(matches) > 0 {
        same_org: list[Person] = [];
        for p in matches {
            existing_org = p.org.strip().lower();
            if len(existing_org) == 0 or len(new_org) == 0 or existing_org == new_org {
                same_org.append(p);
            }
        }
        if len(same_org) > 0 {
            p = same_org[0];
            if len(p.org.strip()) == 0 and len(org.strip()) > 0 {
                p.org = org;
            }
            if len(p.title.strip()) == 0 and len(title.strip()) > 0 {
                p.title = title;
            }
            return {"person": p, "is_new": False, "ambiguous_with": []};
        }

        ambiguous_with: list[str] = [jid(p) for p in matches];
        new_p = (me +>:Knows(how_met="badge photo", last_contact=now, source_note=jid(note), status="proposed"):+> Person(name=name, org=org, title=title, status="proposed"))[0];
        return {"person": new_p, "is_new": True, "ambiguous_with": ambiguous_with};
    }

    new_p = (me +>:Knows(how_met="badge photo", last_contact=now, source_note=jid(note), status="proposed"):+> Person(name=name, org=org, title=title, status="proposed"))[0];
    return {"person": new_p, "is_new": True, "ambiguous_with": []};
}

"""Deterministic, testable: turns an already-read BadgeRead dict into
graph writes off an already-created Note. Returns the CaptureImage
contract dict minus `photo_ref`/`fallback` (the walker adds those -
`apply_badge_read` never touches the filesystem)."""
def apply_badge_read(note: Note, me: Me, read: dict[str, any]) -> dict[str, any] {
    name = (read["name"] as str).strip();
    is_person_card = read["is_person_card"] as bool;

    if not is_person_card or len(name) == 0 {
        return {
            "note_id": jid(note),
            "people": [], "facts": [], "intents": [], "promises": [], "ties": [],
            "read": read_report(read),
            "error": "no_person"
        };
    }

    org = read["org"] as str;
    title = read["title"] as str;

    entry = resolve_badge_person(name, org, title, me, note);
    p = entry["person"] as Person;
    note +>:Mentions(span=name):+> p;

    people_report: list[dict[str, any]] = [{
        "person": p, "is_new": entry["is_new"] as bool,
        "ambiguous_with": entry["ambiguous_with"] as list[str], "span": name
    }];

    facts_report: list[dict[str, any]] = [];
    for fd in facts_from_read(read) {
        span = fd["span"] as str;
        f = (note +>:Asserts(span=span):+> Fact(text=fd["text"] as str, observed_at=datetime.now().isoformat(), source_kind="reported"))[0];
        f +>:FactAbout:+> p;
        facts_report.append({"fact": f, "about": jid(p), "span": span});
    }

    return {
        "note_id": jid(note),
        "people": people_report,
        "facts": facts_report,
        "intents": [],
        "promises": [],
        "ties": [],
        "read": read_report(read),
        "error": ""
    };
}

# ---------------------------------------------------------------- walker

walker:priv CaptureImage {
    """Decode a badge/business-card photo, save it, read it with ONE
    vision `by llm` call, then deterministically get-or-create the Person
    and write provenance-linked Facts. Reports exactly one object
    (contracts/walkers.md `CaptureImage`)."""
    has image_b64: str;
    has mime: str = "image/jpeg";
    has context: str = "";
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        empty_read = {"name": "", "org": "", "title": "", "email": "", "phone": "", "links": [], "raw_text": ""};

        def error_shape(err: str) -> dict[str, any] {
            return {
                "note_id": "", "people": [], "facts": [], "intents": [], "promises": [], "ties": [],
                "photo_ref": "", "read": empty_read, "fallback": False, "error": err
            };
        }

        if len(self.image_b64.strip()) == 0 {
            report error_shape("empty");
            disengage;
        }

        # SOH-211: length check before decoding; strict base64 only.
        if len(self.image_b64) > MAX_IMAGE_B64_CHARS {
            report error_shape("too_large");
            disengage;
        }
        b64 = self.image_b64.strip();
        if b64.startswith("data:") and "," in b64 {
            b64 = b64[b64.index(",") + 1:];
        }
        raw = b"";
        try {
            raw = base64.b64decode(b64, validate=True);
        } except Exception {
            report error_shape("bad_base64");
            disengage;
        }

        if len(raw) == 0 {
            report error_shape("empty");
            disengage;
        }

        if len(raw) > MAX_IMAGE_BYTES {
            report error_shape("too_large");
            disengage;
        }

        existing_me = [root --> [?:Me]];
        if len(existing_me) > 0 {
            me = existing_me[0];
        } else {
            me = (root ++> Me(name="me"))[0];
        }

        ext = ext_for(self.mime);
        os.makedirs("uploads", exist_ok=True);
        photo_ref = os.path.join("uploads", f"{str(uuid4())}.{ext}");
        with open(photo_ref, "wb") as f {
            f.write(raw);
        }

        try {
            parsed = read_badge(Image(photo_ref, mime_type=self.mime), self.context);
            read: dict[str, any] = {
                "name": parsed.name, "org": parsed.org, "title": parsed.title,
                "email": parsed.email, "phone": parsed.phone, "links": parsed.links,
                "raw_text": parsed.raw_text, "is_person_card": parsed.is_person_card
            };
        } except Exception {
            note = (root ++> Note(text="Badge photo (unreadable)", kind="paste", captured_at=datetime.now().isoformat(), audio_ref=photo_ref))[0];
            result = error_shape("");
            result["note_id"] = jid(note);
            result["photo_ref"] = photo_ref;
            result["fallback"] = True;
            report result;
            disengage;
        }

        note_text = badge_to_note_text(read);
        note = (root ++> Note(text=note_text, kind="paste", captured_at=datetime.now().isoformat(), audio_ref=photo_ref))[0];

        result = apply_badge_read(note, me, read);
        result["photo_ref"] = photo_ref;
        result["fallback"] = False;
        report result;
    }
}
