"""Names — one shared, deterministic reading of a person's name (SOH-212).

OWNER: Person A. Plain defs only (no walker, no graph writes, no `by llm`).
Used by `capture.sv.jac` (resolve_person) and `merge.sv.jac` (ProposeMerges)
so both apply the same rule:

  - honorifics are dropped from the display name (Dr., Prof., Professor,
    Rev., Reverend, Mr., Ms., Mrs. - with or without the period, any case);
  - a parenthetical is an alias, not part of the name ("Delgado (rosa)" ->
    name "Delgado", alias "rosa"); trailing "?"s are dropped;
  - exact clean match -> same person; same first name where the last names
    do not contradict (one side has none, or one side is only an initial
    that matches) -> ambiguous; anything else -> distinct.
"""

glob HONORIFICS: list[str] = ["dr", "prof", "professor", "rev", "reverend", "mr", "ms", "mrs", "mx"];

"""Split a raw name into its parts. Returns
{clean, first, last, initial, alias, honorific} - `first`/`last`/`initial`/
`alias` are lower-case, `clean` keeps the writer's casing."""
def name_key(name: str) -> dict[str, str] {
    raw = (name or "").strip();
    while raw.endswith("?") {
        raw = raw[:-1].strip();
    }

    alias = "";
    base = "";
    depth = 0;
    inner = "";
    for ch in raw {
        if ch == "(" {
            depth += 1;
            continue;
        }
        if ch == ")" {
            if depth > 0 {
                depth -= 1;
                if depth == 0 and len(alias) == 0 {
                    alias = inner.strip();
                }
                inner = "";
            }
            continue;
        }
        if depth > 0 {
            inner = inner + ch;
        } else {
            base = base + ch;
        }
    }

    tokens: list[str] = base.split();
    honorific = "";
    while len(tokens) > 1 and tokens[0].rstrip(".").lower() in HONORIFICS {
        honorific = tokens[0] if len(honorific) == 0 else honorific;
        tokens = tokens[1:];
    }
    clean = " ".join(tokens);
    if len(clean) == 0 {
        clean = raw;
    }

    first = "";
    last = "";
    if len(tokens) > 0 {
        first = tokens[0].rstrip(".,").lower();
    }
    if len(tokens) > 1 {
        last = tokens[-1].rstrip(".,").lower();
    }
    initial = last[:1] if len(last) > 0 else "";
    return {
        "clean": clean,
        "first": first,
        "last": last,
        "initial": initial,
        "alias": alias.lower(),
        "honorific": honorific
    };
}

"""Last names that do not contradict each other: either side absent, equal,
or one side is a bare initial ("O" / "O.") matching the other's first letter."""
def _lasts_compatible(a: dict[str, str], b: dict[str, str]) -> bool {
    la = a["last"];
    lb = b["last"];
    if len(la) == 0 or len(lb) == 0 {
        return True;
    }
    if la == lb {
        return True;
    }
    if len(la) == 1 and lb.startswith(la) {
        return True;
    }
    if len(lb) == 1 and la.startswith(lb) {
        return True;
    }
    # Hyphenated surnames: "Marsh" is compatible with "Marsh-Whitcombe".
    if la in lb.split("-") or lb in la.split("-") {
        return True;
    }
    return False;
}

"""Compare two raw names. Returns "same" | "ambiguous" | "distinct".
Never "same" on anything short of an exact clean-name match."""
def match_names(incoming: str, known: str) -> str {
    a = name_key(incoming);
    b = name_key(known);
    ca = " ".join(a["clean"].lower().split());
    cb = " ".join(b["clean"].lower().split());
    if len(ca) == 0 or len(cb) == 0 {
        return "distinct";
    }
    if ca == cb {
        return "same";
    }
    if len(a["first"]) > 0 and a["first"] == b["first"] and _lasts_compatible(a, b) {
        return "ambiguous";
    }
    # "prof Delgado (rosa)" vs "Rosa Delgado": alias is the first name and the
    # lone remaining token is the known last name.
    if len(a["alias"]) > 0 and a["alias"] == b["first"] and len(a["last"]) == 0 and a["first"] == b["last"] {
        return "ambiguous";
    }
    if len(b["alias"]) > 0 and b["alias"] == a["first"] and len(b["last"]) == 0 and b["first"] == a["last"] {
        return "ambiguous";
    }
    return "distinct";
}

"""Cut `text` to at most `limit` characters on a word boundary and append
"…" when anything was cut (SOH-212: "…after the county accessibility pane")."""
def trim_words(text: str, limit: int) -> str {
    t = " ".join((text or "").split());
    if len(t) <= limit {
        return t;
    }
    cut = t[:limit];
    space = cut.rfind(" ");
    if space > 0 {
        cut = cut[:space];
    }
    return cut.rstrip(" ,;:-") + "…";
}

"""A stored `how_met` of the form "<kind>: <first 60 chars of the note>"
(the pre-SOH-212 default) was cut mid-word; re-trim it on a word boundary
for display. Anything else is returned unchanged."""
def display_how_met(how_met: str) -> str {
    sep = how_met.find(": ");
    if sep > 0 and sep < 12 {
        head = how_met[:sep + 2];
        body = how_met[sep + 2:];
        if len(body) == 60 and not body.endswith("…") {
            return head + trim_words(body, 59);
        }
    }
    return how_met;
}
