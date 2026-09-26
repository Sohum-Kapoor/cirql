"""Tests for vision.sv.jac (SOH-192).

Annex of vision.sv.jac; run with `jac test vision.sv.jac`. Deterministic
only — no model, no network:
  - `ext_for`, `badge_to_note_text`, `facts_from_read`, `read_report` are
    plain `def`s exercised directly.
  - `resolve_badge_person` / `apply_badge_read` are exercised directly with
    a hand-built `read` dict standing in for a `BadgeRead` the LLM would
    have produced (same idiom `capture.test.jac` uses for
    `CaptureExtraction`).
  - The empty/too-large walker paths return before ever building a
    `BadgeRead` or touching `read_badge`.
  - The "fallback" walker path is forced with 3 garbage bytes saved under
    a `.jpg` name: `Image(path)` (byllm) opens the file locally with PIL
    to validate it BEFORE any network call and raises
    `PIL.UnidentifiedImageError` on unparsable bytes — caught by the same
    `try/except` around `read_badge`, so this test never reaches Gemini.

Every test that writes under `uploads/` removes the file it created.
"""

import from vision {
    BadgeRead, ext_for, badge_to_note_text, facts_from_read, read_report,
    resolve_badge_person, apply_badge_read, CaptureImage, MAX_IMAGE_B64_CHARS
}
import from schema { Me, Person, Note, Knows, Mentions }
import uuid;
import from datetime { datetime }
import os;
import base64;

def _uid() -> str {
    return uuid.uuid4().hex[:8];
}

def _fresh_me() -> Me {
    return (root ++> Me(name="me-" + _uid()))[0];
}

def _fresh_note(text: str) -> Note {
    return (root ++> Note(text=text, kind="paste", captured_at=datetime.now().isoformat()))[0];
}

def _cleanup(path: str) {
    if os.path.exists(path) {
        os.remove(path);
    }
}

# ---------------------------------------------------------------- ext_for

test "ext_for maps known image mimes, falls back to jpg" {
    assert ext_for("image/jpeg") == "jpg";
    assert ext_for("image/png") == "png";
    assert ext_for("image/webp") == "webp";
    assert ext_for("image/heic") == "heic";
    assert ext_for("application/octet-stream") == "jpg";
    assert ext_for("") == "jpg";
}

# ---------------------------------------------------------------- badge_to_note_text / facts_from_read

test "badge_to_note_text builds the deterministic note text" {
    read: dict[str, any] = {
        "name": "Maya Okafor", "org": "University of Michigan", "title": "Robotics Lab",
        "email": "", "phone": "", "links": [], "raw_text": "MAYA OKAFOR\nRobotics Lab\nUniversity of Michigan"
    };
    text = badge_to_note_text(read);
    assert text == "Badge photo: Maya Okafor, Robotics Lab at University of Michigan. MAYA OKAFOR\nRobotics Lab\nUniversity of Michigan";
}

test "facts_from_read: one fact per non-empty org/title, spanned to the raw_text line" {
    read: dict[str, any] = {
        "name": "Maya Okafor", "org": "University of Michigan", "title": "Robotics Lab",
        "email": "", "phone": "", "links": [],
        "raw_text": "MAYA OKAFOR\nRobotics Lab\nUniversity of Michigan"
    };
    facts = facts_from_read(read);
    assert len(facts) == 2;
    assert facts[0]["text"] == "Works at University of Michigan";
    assert facts[0]["span"] == "University of Michigan";
    assert facts[1]["text"] == "Title: Robotics Lab";
    assert facts[1]["span"] == "Robotics Lab";
}

test "facts_from_read: empty org/title yields no facts" {
    read: dict[str, any] = {
        "name": "Someone", "org": "", "title": "",
        "email": "", "phone": "", "links": [], "raw_text": "SOMEONE"
    };
    assert facts_from_read(read) == [];
}

test "facts_from_read: span falls back to the bare value when no raw_text line matches" {
    read: dict[str, any] = {
        "name": "Someone", "org": "Acme Corp", "title": "",
        "email": "", "phone": "", "links": [], "raw_text": "no company name printed here"
    };
    facts = facts_from_read(read);
    assert len(facts) == 1;
    assert facts[0]["span"] == "Acme Corp";
}

test "read_report strips is_person_card, keeps the contact fields" {
    read: dict[str, any] = {
        "name": "N", "org": "O", "title": "T", "email": "e@x.com", "phone": "555",
        "links": ["https://x.com"], "raw_text": "raw", "is_person_card": True
    };
    r = read_report(read);
    assert "is_person_card" not in r;
    assert r["name"] == "N";
    assert r["email"] == "e@x.com";
    assert r["links"] == ["https://x.com"];
}

# ---------------------------------------------------------------- resolve_badge_person

test "resolve_badge_person: brand-new name creates a proposed Person + proposed Knows" {
    me = _fresh_me();
    note = _fresh_note("Badge photo: placeholder");
    name = "Priya" + _uid();

    entry = resolve_badge_person(name, "Acme", "Eng", me, note);
    p = entry["person"] as Person;

    assert entry["is_new"];
    assert len(entry["ambiguous_with"] as list[str]) == 0;
    assert p.status == "proposed";
    assert p.org == "Acme";
    assert p.title == "Eng";

    edges = [edge me ->:Knows:-> p];
    assert len(edges) == 1;
    knows = edges[0] as Knows;
    assert knows.status == "proposed";
    assert knows.how_met == "badge photo";
}

test "resolve_badge_person: same name, blank existing org -> reused and filled in" {
    me = _fresh_me();
    note = _fresh_note("Badge photo: placeholder");
    name = "Arjun" + _uid();

    first = resolve_badge_person(name, "", "", me, note);
    original = first["person"] as Person;
    assert original.status == "proposed";

    second = resolve_badge_person(name, "Globex", "Manager", me, note);
    reused = second["person"] as Person;

    assert not second["is_new"];
    assert jid(reused) == jid(original);
    assert reused.org == "Globex";
    assert reused.title == "Manager";
    assert len(second["ambiguous_with"] as list[str]) == 0;
}

test "resolve_badge_person: same name, same org -> reused, not ambiguous" {
    me = _fresh_me();
    note = _fresh_note("Badge photo: placeholder");
    name = "Devika" + _uid();

    first = resolve_badge_person(name, "Initech", "PM", me, note);
    original = first["person"] as Person;

    second = resolve_badge_person(name, "Initech", "Senior PM", me, note);
    reused = second["person"] as Person;

    assert not second["is_new"];
    assert jid(reused) == jid(original);
    # Title already set - never overwritten once non-empty.
    assert reused.title == "PM";
}

test "resolve_badge_person: same name, DIFFERENT org -> never merged, comes back ambiguous_with" {
    me = _fresh_me();
    note = _fresh_note("Badge photo: placeholder");
    name = "Sam" + _uid();

    first = resolve_badge_person(name, "Acme", "Eng", me, note);
    existing = first["person"] as Person;

    second = resolve_badge_person(name, "Globex", "Eng", me, note);
    fresh = second["person"] as Person;

    assert second["is_new"];
    assert jid(fresh) != jid(existing);
    ambiguous_with = second["ambiguous_with"] as list[str];
    assert len(ambiguous_with) == 1;
    assert jid(existing) in ambiguous_with;
    assert fresh.status == "proposed";
    assert fresh.org == "Globex";
}

# ---------------------------------------------------------------- apply_badge_read

test "apply_badge_read: is_person_card false -> no person, error no_person, note untouched" {
    me = _fresh_me();
    note = _fresh_note("Badge photo: A poster, not a badge.");
    read: dict[str, any] = {
        "name": "", "org": "", "title": "", "email": "", "phone": "", "links": [],
        "raw_text": "SPEAKER LINEUP", "is_person_card": False
    };

    result = apply_badge_read(note, me, read);
    assert result["note_id"] == jid(note);
    assert result["people"] == [];
    assert result["facts"] == [];
    assert result["error"] == "no_person";
    assert "is_person_card" not in (result["read"] as dict[str, any]);
}

test "apply_badge_read: empty name -> no person, error no_person" {
    me = _fresh_me();
    note = _fresh_note("Badge photo: placeholder");
    read: dict[str, any] = {
        "name": "   ", "org": "Acme", "title": "", "email": "", "phone": "", "links": [],
        "raw_text": "blurry", "is_person_card": True
    };

    result = apply_badge_read(note, me, read);
    assert result["people"] == [];
    assert result["error"] == "no_person";
}

test "apply_badge_read: full read builds one person, one Mentions edge, two facts with provenance" {
    me = _fresh_me();
    suffix = _uid();
    name = "Maya" + suffix;
    raw_text = f"{name.upper()}\nRobotics Lab\nUniversity of Michigan";
    note = _fresh_note(f"Badge photo: {name}, Robotics Lab at University of Michigan. {raw_text}");

    read: dict[str, any] = {
        "name": name, "org": "University of Michigan", "title": "Robotics Lab",
        "email": "maya@example.com", "phone": "555-0100", "links": ["https://example.com/maya"],
        "raw_text": raw_text, "is_person_card": True
    };

    result = apply_badge_read(note, me, read);
    assert result["error"] == "";
    assert result["note_id"] == jid(note);

    people = result["people"] as list[dict[str, any]];
    assert len(people) == 1;
    p = people[0]["person"] as Person;
    assert p.name == name;
    assert p.org == "University of Michigan";
    assert people[0]["is_new"];
    assert people[0]["span"] == name;

    mentions: list[Person] = [note ->:Mentions:->];
    count = 0;
    for m in mentions {
        if jid(m) == jid(p) {
            count += 1;
        }
    }
    assert count == 1;

    facts = result["facts"] as list[dict[str, any]];
    assert len(facts) == 2;
    for fe in facts {
        assert fe["about"] == jid(p);
    }

    read_block = result["read"] as dict[str, any];
    assert read_block["email"] == "maya@example.com";
    assert read_block["phone"] == "555-0100";
    assert read_block["links"] == ["https://example.com/maya"];
    assert "is_person_card" not in read_block;
}

# ---------------------------------------------------------------- CaptureImage walker: error paths (no model reached)

test "CaptureImage: empty image_b64 reports error empty, no note, no graph write" {
    result = root spawn CaptureImage(image_b64="", mime="image/jpeg");
    assert len(result.reports) == 1;
    out = result.reports[0];
    assert out["error"] == "empty";
    assert out["note_id"] == "";
    assert out["photo_ref"] == "";
    assert not (out["fallback"] as bool);
}

test "CaptureImage: too-large image reports error too_large, no file written" {
    too_big = b"x" * (8 * 1024 * 1024 + 1);
    b64 = base64.b64encode(too_big).decode("ascii");

    before = set(os.listdir("uploads")) if os.path.exists("uploads") else set();
    result = root spawn CaptureImage(image_b64=b64, mime="image/jpeg");
    after = set(os.listdir("uploads")) if os.path.exists("uploads") else set();

    assert len(result.reports) == 1;
    out = result.reports[0];
    assert out["error"] == "too_large";
    assert out["photo_ref"] == "";
    assert after == before, "no file should be written for a rejected upload";
}

test "CaptureImage SOH-211: non-strict base64 -> bad_base64; over-long string -> too_large before decoding" {
    bad = root spawn CaptureImage(image_b64="QUJD*REVG", mime="image/jpeg");
    assert len(bad.reports) == 1;
    assert bad.reports[0]["error"] == "bad_base64", bad.reports[0];
    assert bad.reports[0]["note_id"] == "";

    # "!" is not base64, so too_large proves the length check ran first.
    too_long = root spawn CaptureImage(image_b64="!" * (MAX_IMAGE_B64_CHARS + 1), mime="image/jpeg");
    assert too_long.reports[0]["error"] == "too_large", too_long.reports[0];
}

# ---------------------------------------------------------------- CaptureImage walker: fallback (no model reached)

test "CaptureImage: unreadable image bytes fall back to a saved, note-carrying result" {
    garbage = b"abc";   # 3 bytes: not a valid image; PIL rejects it before any network call
    b64 = base64.b64encode(garbage).decode("ascii");

    result = root spawn CaptureImage(image_b64=b64, mime="image/jpeg", context="test");
    assert len(result.reports) == 1;
    out = result.reports[0];

    assert out["fallback"] as bool;
    assert out["note_id"] != "";
    assert out["photo_ref"] != "";
    photo_ref = out["photo_ref"] as str;
    assert photo_ref.endswith(".jpg");
    assert os.path.exists(photo_ref);
    assert out["people"] == [];
    assert out["facts"] == [];

    note = jobj(out["note_id"] as str) as Note;
    assert note.text == "Badge photo (unreadable)";
    assert note.audio_ref == photo_ref;

    _cleanup(photo_ref);
}
