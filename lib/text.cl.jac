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
