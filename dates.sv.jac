"""dates.sv.jac — deterministic natural-language date parsing (SOH-219).

OWNER: Person A. See contracts/walkers.md for `parse_due`'s exact contract
and the shapes `NormalizeDates`/`UpcomingDates` report. AGENTS.md rules this
file must obey:
  - `parse_due` is a plain, deterministic `def` — no `by llm`, no network,
    no randomness. The same `(text, base_iso)` always yields the same
    result, and it never raises: anything it can't place on a calendar
    (including an unparsable `base_iso`) comes back `""`.
  - `NormalizeDates` / `UpcomingDates` are `:priv`, own-root only, no
    `by llm` anywhere in this module.
  - `_parse_naive_utc` is imported from `goals.sv.jac` rather than
    reimplemented (AGENTS.md: "Importing plain defs across `*.sv.jac`
    works; prefer it to copying helpers").

`parse_due(text, base_iso)` recognizes, case-insensitively with surrounding
whitespace stripped:
  - a weekday name, full or abbreviated ("Fri", "Friday") -> the NEXT such
    day, always 1-7 days strictly after `base_iso`'s own date (never the
    same day, even when `base_iso` itself falls on that weekday).
  - "today" / "tomorrow" / "next week" (+7 days) / "end of month" (the
    last day of `base_iso`'s own month).
  - "in N days" / "in N weeks" / "in N months" — month arithmetic clamps
    the day to the target month's length (Jan 31 + 1 month -> Feb 28/29).
  - "in <Month>" (full or abbreviated name) -> the 1st of that month, ON OR
    AFTER `base_iso`'s date; otherwise the same month next year.
  - "<Month> <D>" / "<Mon> <D>" (e.g. "March 3", "Mar 3") and "M/D" (e.g.
    "3/14") -> that month/day, on or after `base_iso`'s date, else next
    year. An invalid calendar date (e.g. "Feb 30") -> "".
  - "YYYY-MM-DD" -> returned as-is once validated as a real calendar date.
  - anything else -> "".
"""

import re;
import calendar;
import from datetime { datetime, timedelta }
import from goals { _parse_naive_utc }
import from schema {
    Me, Note, Person, Promise, Intent, Event,
    AssertsPromise, AssertsIntent, PromiseTo, IntentAbout, HasEvent
}

# ---------------------------------------------------------------- parse_due

glob _WEEKDAYS: dict[str, int] = {
    "monday": 0, "mon": 0,
    "tuesday": 1, "tue": 1, "tues": 1,
    "wednesday": 2, "wed": 2,
    "thursday": 3, "thu": 3, "thurs": 3,
    "friday": 4, "fri": 4,
    "saturday": 5, "sat": 5,
    "sunday": 6, "sun": 6
};

glob _MONTHS: dict[str, int] = {
    "january": 1, "jan": 1,
    "february": 2, "feb": 2,
    "march": 3, "mar": 3,
    "april": 4, "apr": 4,
    "may": 5,
    "june": 6, "jun": 6,
    "july": 7, "jul": 7,
    "august": 8, "aug": 8,
    "september": 9, "sep": 9, "sept": 9,
    "october": 10, "oct": 10,
    "november": 11, "nov": 11,
    "december": 12, "dec": 12
};

"""`base_dt` shifted by `n` calendar months, clamping the day to the target
month's length (Jan 31 + 1 month -> Feb 28/29, never rolls into March)."""
def _add_months(base_dt: datetime, n: int) -> datetime {
    total = base_dt.month - 1 + n;
    year = base_dt.year + (total // 12);
    month = (total % 12) + 1;
    last_day = calendar.monthrange(year, month)[1];
    day = min(base_dt.day, last_day);
    return datetime(year, month, day);
}

"""The next `month`/`day` on or after `base_dt`'s own date; the same
month/day next year otherwise. `""` when `month`/`day` isn't a real
calendar date in either candidate year (e.g. "Feb 30")."""
def _next_month_day(base_dt: datetime, month: int, day: int) -> str {
    try {
        target = datetime(base_dt.year, month, day);
    } except ValueError {
        return "";
    }
    if target.date() < base_dt.date() {
        try {
            target = datetime(base_dt.year + 1, month, day);
        } except ValueError {
            return "";
        }
    }
    return target.date().isoformat();
}

def parse_due(text: str, base_iso: str) -> str {
    base_dt = _parse_naive_utc(base_iso);
    if base_dt is None {
        return "";
    }

    raw = text.strip();
    if not raw {
        return "";
    }
    low = raw.lower();

    if low == "today" {
        return base_dt.date().isoformat();
    }
    if low == "tomorrow" {
        return (base_dt + timedelta(days=1)).date().isoformat();
    }
    if low == "next week" {
        return (base_dt + timedelta(days=7)).date().isoformat();
    }
    if low == "end of month" {
        last_day = calendar.monthrange(base_dt.year, base_dt.month)[1];
        return datetime(base_dt.year, base_dt.month, last_day).date().isoformat();
    }

    m_days = re.fullmatch(r"in (\d+) days?", low);
    if m_days is not None {
        n = int(m_days.group(1));
        return (base_dt + timedelta(days=n)).date().isoformat();
    }
    m_weeks = re.fullmatch(r"in (\d+) weeks?", low);
    if m_weeks is not None {
        n = int(m_weeks.group(1));
        return (base_dt + timedelta(days=n * 7)).date().isoformat();
    }
    m_months = re.fullmatch(r"in (\d+) months?", low);
    if m_months is not None {
        n = int(m_months.group(1));
        return _add_months(base_dt, n).date().isoformat();
    }

    if low in _WEEKDAYS {
        target_wd = _WEEKDAYS[low];
        delta = (target_wd - base_dt.weekday()) % 7;
        if delta == 0 {
            delta = 7;
        }
        return (base_dt + timedelta(days=delta)).date().isoformat();
    }

    m_in_month = re.fullmatch(r"in ([a-z]+)", low);
    if m_in_month is not None {
        name = m_in_month.group(1);
        if name in _MONTHS {
            return _next_month_day(base_dt, _MONTHS[name], 1);
        }
        return "";
    }

    m_month_day = re.fullmatch(r"([a-z]+)\s+(\d{1,2})", low);
    if m_month_day is not None {
        name = m_month_day.group(1);
        day = int(m_month_day.group(2));
        if name in _MONTHS {
            return _next_month_day(base_dt, _MONTHS[name], day);
        }
        return "";
    }

    m_slash = re.fullmatch(r"(\d{1,2})/(\d{1,2})", low);
    if m_slash is not None {
        month = int(m_slash.group(1));
        day = int(m_slash.group(2));
        return _next_month_day(base_dt, month, day);
    }

    m_iso = re.fullmatch(r"\d{4}-\d{2}-\d{2}", low);
    if m_iso is not None {
        try {
            parsed = datetime.strptime(low, "%Y-%m-%d");
        } except ValueError {
            return "";
        }
        return parsed.date().isoformat();
    }

    return "";
}

# ---------------------------------------------------------------- gather: upcoming

def _promise_due_sort_key(item: dict[str, any]) -> int {
    return item["_days"] as int;
}

"""Every OPEN (`done == False`) Promise asserted by any of `notes`, deduped
by jid, whose `due` (re-parsed through `parse_due` so an un-normalized raw
text still counts) lands within `[now, now + days]` inclusive. `to` is the
Promise's `PromiseTo` target, or `None` when it has none yet."""
def _gather_promises_due(notes: list[Note], now: datetime, days: int) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    seen: list[str] = [];
    for note in notes {
        for pr in [note ->:AssertsPromise:->] {
            pid = jid(pr);
            if pid in seen {
                continue;
            }
            seen.append(pid);
            if pr.done {
                continue;
            }
            due_iso = parse_due(pr.due, now.isoformat());
            if not due_iso {
                continue;
            }
            due_dt = _parse_naive_utc(due_iso);
            if due_dt is None {
                continue;
            }
            days_until = (due_dt.date() - now.date()).days;
            if days_until < 0 or days_until > days {
                continue;
            }
            to_list: list[Person] = [pr ->:PromiseTo:->];
            to_person = to_list[0] if to_list else None;
            out.append({"promise": pr, "to": to_person, "due": due_iso, "_days": days_until});
        }
    }
    ordered = sorted(out, key=_promise_due_sort_key);
    return [{"promise": it["promise"], "to": it["to"], "due": it["due"]} for it in ordered];
}

def _intent_expiring_sort_key(item: dict[str, any]) -> int {
    return item["_days"] as int;
}

"""Every Intent asserted by any of `notes`, deduped by jid, with a set,
parseable `expires_at` within `[now, now + days]` inclusive (already-expired
intents are FreshnessSweep's concern, not this walker's). `about` is the
`IntentAbout` target when one exists, `None` for a self-onboarded Intent
(`HasIntent`, no target Person)."""
def _gather_intents_expiring(notes: list[Note], now: datetime, days: int) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    seen: list[str] = [];
    for note in notes {
        for it in [note ->:AssertsIntent:->] {
            iid = jid(it);
            if iid in seen {
                continue;
            }
            seen.append(iid);
            if not it.expires_at {
                continue;
            }
            exp_dt = _parse_naive_utc(it.expires_at);
            if exp_dt is None {
                continue;
            }
            days_until = (exp_dt.date() - now.date()).days;
            if days_until < 0 or days_until > days {
                continue;
            }
            about_list: list[Person] = [it ->:IntentAbout:->];
            about = about_list[0] if about_list else None;
            out.append({"intent": it, "about": about, "expires_at": it.expires_at, "_days": days_until});
        }
    }
    ordered = sorted(out, key=_intent_expiring_sort_key);
    return [{"intent": it["intent"], "about": it["about"], "expires_at": it["expires_at"]} for it in ordered];
}

def _event_sort_key(item: dict[str, any]) -> str {
    return item["_date"] as str;
}

"""Every Event hung off `me` (`HasEvent`) with a set, parseable `date`
within `[now, now + days]` inclusive."""
def _gather_events(me: Me, now: datetime, days: int) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    for ev in [me ->:HasEvent:->] {
        if not ev.date {
            continue;
        }
        ev_dt = _parse_naive_utc(ev.date);
        if ev_dt is None {
            continue;
        }
        days_until = (ev_dt.date() - now.date()).days;
        if days_until < 0 or days_until > days {
            continue;
        }
        out.append({"event": ev, "_date": ev.date});
    }
    ordered = sorted(out, key=_event_sort_key);
    return [{"event": it["event"]} for it in ordered];
}

"""Deterministic, testable directly on a hand-built `me` + `notes` (see
dates.test.jac): promises due, intents expiring, and events, each within the
next `days` days and each sorted ascending by its own date. Reused by
`notes.sv.jac`'s `Digest`."""
def upcoming_dates_for(me: Me, notes: list[Note], now: datetime, days: int) -> dict[str, any] {
    return {
        "promises": _gather_promises_due(notes, now, days),
        "intents_expiring": _gather_intents_expiring(notes, now, days),
        "events": _gather_events(me, now, days)
    };
}

walker:priv UpcomingDates {
    """Own root only, no LLM. `[me ->:HasEvent:->]`/notes gathered fresh
    every call. `days` clamped to [0, 90] (SOH-211 bounded-budget idiom)."""
    has days: int = 14;
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing = [root --> [?:Me]];
        if not existing {
            report {"promises": [], "intents_expiring": [], "events": []};
            disengage;
        }
        me = existing[0];
        notes: list[Note] = [root --> [?:Note]];
        result = upcoming_dates_for(me, notes, datetime.now(), min(max(self.days, 0), 90));
        report result;
    }
}

# ---------------------------------------------------------------- NormalizeDates

"""Every OPEN OR DONE Promise's `due` re-run through `parse_due`; a
non-empty result that differs from the stored raw text overwrites it.
Idempotent: an already-ISO `due` re-parses to the same string (no-op), and
a full ISO timestamp (with a time component) never matches any `parse_due`
pattern, so it is left untouched."""
def _normalize_promises(notes: list[Note], now: datetime) -> int {
    count = 0;
    seen: list[str] = [];
    for note in notes {
        for pr in [note ->:AssertsPromise:->] {
            pid = jid(pr);
            if pid in seen {
                continue;
            }
            seen.append(pid);
            if not pr.due {
                continue;
            }
            parsed = parse_due(pr.due, now.isoformat());
            if parsed and parsed != pr.due {
                pr.due = parsed;
                count += 1;
            }
        }
    }
    return count;
}

"""Same idea for `Intent.expires_at`. In current practice every Intent's
`expires_at` is already ISO (`freshness.sv.jac`'s `default_expiry`), so this
is normally `0` — kept for any Intent that ever picks up raw natural-language
text (a future capture path, a hand-edited seed) without needing a second
walker."""
def _normalize_intents(notes: list[Note], now: datetime) -> int {
    count = 0;
    seen: list[str] = [];
    for note in notes {
        for it in [note ->:AssertsIntent:->] {
            iid = jid(it);
            if iid in seen {
                continue;
            }
            seen.append(iid);
            if not it.expires_at {
                continue;
            }
            parsed = parse_due(it.expires_at, now.isoformat());
            if parsed and parsed != it.expires_at {
                it.expires_at = parsed;
                count += 1;
            }
        }
    }
    return count;
}

walker:priv NormalizeDates {
    """Own root only, no LLM. Reports one dict
    `{promises_updated, intents_updated}`."""
    has reports: list[dict[str, int]] = [];

    can run with Root entry {
        notes: list[Note] = [root --> [?:Note]];
        now = datetime.now();
        promises_updated = _normalize_promises(notes, now);
        intents_updated = _normalize_intents(notes, now);
        report {"promises_updated": promises_updated, "intents_updated": intents_updated};
    }
}
