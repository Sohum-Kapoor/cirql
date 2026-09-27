"""Small string helpers for client code. OWNER: Person B.

`sep.join(items)` on a `glob` string compiles to a polymorphic call that throws
at runtime ("'str' object has no attribute 'join'"), so join with a loop.
"""

glob NL: str = chr(10);

def:pub join_with(items: list[str], sep: str) -> str {
    out: str = "";
    for (i, s) in enumerate(items) {
        out = out + (sep if i > 0 else "") + s;
    }
    return out;
}

def:pub join_lines(items: list[str]) -> str {
    return join_with(items, NL);
}

"""A note/activity `kind` value (raw, whatever the server stored) -> a short
product-copy label. Known kinds map to a fixed phrase; anything else gets its
first letter upper-cased with hyphens/underscores turned to spaces (SOH-226)."""
def:pub kind_label(kind: str) -> str {
    if not kind {
        return "";
    }
    lk: str = kind.lower();
    if lk == "debrief" {
        return "Debrief";
    }
    if lk == "voice" {
        return "Voice memo";
    }
    if lk == "paste" or lk == "pasted" {
        return "Pasted note";
    }
    if lk == "about-me" or lk == "about_me" {
        return "About you";
    }
    if lk == "import" {
        return "Import";
    }
    if lk == "photo" {
        return "Badge photo";
    }
    if lk == "onboarding" {
        return "Set-up";
    }
    out: str = "";
    for ch in kind {
        out = out + (" " if (ch == "-" or ch == "_") else ch);
    }
    return out[0:1].upper() + out[1:];
}

def:pub split_lines(text: str) -> list[str] {
    return text.split(NL);
}

glob _MONTHS: list[str] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

"""ISO-8601 "2026-09-26T16:10:00Z" -> "Sep 26". "" when it isn't that shape."""
def:pub short_date(iso: str) -> str {
    if not iso or len(iso) < 10 or iso[4] != "-" or iso[7] != "-" {
        return "";
    }
    month: int = int(iso[5:7]);
    day: int = int(iso[8:10]);
    if not (month >= 1 and month <= 12) or not (day >= 1 and day <= 31) {
        return "";
    }
    return _MONTHS[month - 1] + " " + str(day);
}

"""Today as "Sep 26" (local time), for human how-met lines."""
def:pub today_month_day() -> str {
    d: any = new(Date);
    return _MONTHS[d.getMonth() as int] + " " + str(d.getDate());
}

glob _WEEKDAYS: list[str] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

"""ISO date/datetime -> "Due Mon Sep 28" (weekday-aware, local time). "" when
`iso` is blank or doesn't parse (SOH-222)."""
def:pub due_label(iso: str) -> str {
    if not iso {
        return "";
    }
    t: any = Date.parse(iso);  # jac:ignore[W2001]
    if isNaN(t) {  # jac:ignore[W2001]
        return "";
    }
    d: any = new(Date, t);  # jac:ignore[W2001]
    return "Due " + _WEEKDAYS[d.getDay() as int] + " " + _MONTHS[d.getMonth() as int] + " " + str(d.getDate() as int);
}

glob CRLF: str = chr(13) + chr(10);

"""Escape ',' ';' '\\' and turn a bare LF into a literal "\n", per RFC 5545's
TEXT value escaping (§3.3.11) — CRLF stays the ICS line separator, never part
of an escaped value, so a CR is dropped outright (SOH-226)."""
def:pub ics_escape(text: str) -> str {
    out: str = "";
    for ch in text {
        if ch == chr(13) {
            continue;
        }
        if ch == "\\" {
            out = out + "\\\\";
        } elif ch == "," {
            out = out + "\\,";
        } elif ch == ";" {
            out = out + "\\;";
        } elif ch == chr(10) {
            out = out + "\\n";
        } else {
            out = out + ch;
        }
    }
    return out;
}

def _ics_pad2(n: int) -> str {
    s: str = str(n);
    return "0" + s if len(s) < 2 else s;
}

"""Now, UTC, compact "YYYYMMDDTHHMMSSZ" — every ICS event's DTSTAMP, regardless
of its own DTSTART."""
def _ics_now_stamp() -> str {
    d: any = new(Date);  # jac:ignore[W2001,E1053]
    y: int = int(d.getUTCFullYear());  # jac:ignore[W2001]
    mo: int = int(d.getUTCMonth()) + 1;  # jac:ignore[W2001]
    day: int = int(d.getUTCDate());  # jac:ignore[W2001]
    h: int = int(d.getUTCHours());  # jac:ignore[W2001]
    mi: int = int(d.getUTCMinutes());  # jac:ignore[W2001]
    se: int = int(d.getUTCSeconds());  # jac:ignore[W2001]
    return str(y) + _ics_pad2(mo) + _ics_pad2(day) + "T" + _ics_pad2(h) + _ics_pad2(mi) + _ics_pad2(se) + "Z";
}

"""due_iso's leading "YYYY-MM-DD", advanced by `add_days` whole UTC days
(midnight-UTC arithmetic so a date-only string never rolls back a day for a
caller west of UTC) -> compact "YYYYMMDD". "" when `due_iso` doesn't start
with a parseable date."""
def _ics_compact_date(due_iso: str, add_days: int) -> str {
    date_part: str = due_iso[0:10] if len(due_iso) >= 10 else due_iso;
    if len(date_part) != 10 or date_part[4] != "-" or date_part[7] != "-" {
        return "";
    }
    t: any = Date.parse(date_part + "T00:00:00Z");  # jac:ignore[W2001]
    if isNaN(t) {  # jac:ignore[W2001]
        return "";
    }
    ms: int = int(t) + add_days * 86400000;
    d2: any = new(Date, ms);  # jac:ignore[W2001]
    y: int = int(d2.getUTCFullYear());  # jac:ignore[W2001]
    mo: int = int(d2.getUTCMonth()) + 1;  # jac:ignore[W2001]
    day: int = int(d2.getUTCDate());  # jac:ignore[W2001]
    return str(y) + _ics_pad2(mo) + _ics_pad2(day);
}

"""A promise as one downloadable ICS file: a VCALENDAR/VEVENT, all-day on
`due_iso`'s date when `due_iso` carries no time component (the only shape
promises store today), DTSTAMP always "now". `uid` should be the promise's own
id — stable across re-downloads, gets "@cirql.app" appended when it doesn't
already look like one. "" when `due_iso` doesn't parse (caller should only
offer the download when a `due` exists in the first place, SOH-226)."""
def:pub ics_for_promise(title: str, due_iso: str, description: str, uid: str) -> str {
    if not due_iso {
        return "";
    }
    start: str = _ics_compact_date(due_iso, 0);
    if not start {
        return "";
    }
    all_day: bool = "T" not in due_iso;
    full_uid: str = uid if ("@" in uid) else (uid + "@cirql.app");
    lines: list[str] = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Cirql//Promises//EN",
        "CALSCALE:GREGORIAN",
        "BEGIN:VEVENT",
        "UID:" + full_uid,
        "DTSTAMP:" + _ics_now_stamp()
    ];
    if all_day {
        end: str = _ics_compact_date(due_iso, 1) or start;
        lines.append("DTSTART;VALUE=DATE:" + start);
        lines.append("DTEND;VALUE=DATE:" + end);
    } else {
        lines.append("DTSTART:" + start + "T000000Z");
    }
    lines.append("SUMMARY:" + ics_escape(title));
    if description {
        lines.append("DESCRIPTION:" + ics_escape(description));
    }
    lines.append("END:VEVENT");
    lines.append("END:VCALENDAR");
    return join_with(lines, CRLF) + CRLF;
}
