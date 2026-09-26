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
