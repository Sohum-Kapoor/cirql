"""Identity layer 2 (SOH-215) — blinded identity tokens on Person.

OWNER: Person A. Plain defs + one walker. No `by llm`, no network.

A token is `kind:hmac_sha256(salt, normalised value)[:32]`. Kinds:
  n   name|org        (name via names.name_key clean, org with legal suffixes dropped)
  n0  name alone      (only when the org is empty)
  e   email           (lower-cased)
  p   phone           (digits only, >= 7 digits; a US leading 1 on 11 digits is dropped)
  u   link            (lower, no scheme/www/query/fragment/trailing slash)

Tokens are the only thing about a person that may be compared across
accounts (IntroReply.match_tokens). The salt is never logged or reported.
Nothing here reads `Knows.last_contact`.
"""

import from schema { Me, Person, Knows }
import from names { name_key }
import hmac;
import hashlib;
import os;

glob ORG_SUFFIXES: list[str] = ["inc", "llc", "ltd", "corp", "corporation", "co", "company", "plc", "gmbh"];

"""The HMAC key. Never logged, never reported."""
def identity_salt() -> str {
    return os.environ.get("IDENTITY_SALT") or os.environ.get("JWT_SECRET") or "cirql-dev-salt";
}

def _hmac32(value: str) -> str {
    return hmac.new(identity_salt().encode("utf-8"), value.encode("utf-8"), hashlib.sha256).hexdigest()[:32];
}

"""Lower, every non-alphanumeric -> space, collapse spaces."""
def _alnum_words(s: str) -> str {
    out = "";
    for ch in (s or "").lower() {
        out = out + (ch if ch.isalnum() else " ");
    }
    return " ".join(out.split());
}

def norm_name(name: str) -> str {
    clean = name_key(name or "")["clean"].lower();
    out = "";
    for ch in clean {
        if ch.isalnum() or ch.isspace() {
            out = out + ch;
        }
    }
    return " ".join(out.split());
}

def norm_org(org: str) -> str {
    words: list[str] = _alnum_words(org).split();
    while len(words) > 1 and words[-1] in ORG_SUFFIXES {
        words = words[:-1];
    }
    return " ".join(words);
}

def norm_email(email: str) -> str {
    e = (email or "").strip().lower();
    if e.startswith("mailto:") {
        e = e[7:];
    }
    return e if "@" in e else "";
}

def norm_phone(phone: str) -> str {
    digits = "";
    for ch in (phone or "") {
        if ch.isdigit() {
            digits = digits + ch;
        }
    }
    if len(digits) == 11 and digits.startswith("1") {
        digits = digits[1:];
    }
    return digits if len(digits) >= 7 else "";
}

"""Canonical link: lower, no scheme, no leading www., no query/fragment, no trailing slash."""
def canonical_url(url: str) -> str {
    u = (url or "").strip().lower();
    for scheme in ["https://", "http://"] {
        if u.startswith(scheme) {
            u = u[len(scheme):];
        }
    }
    if u.startswith("www.") {
        u = u[4:];
    }
    for sep in ["#", "?"] {
        if sep in u {
            u = u[:u.index(sep)];
        }
    }
    while u.endswith("/") {
        u = u[:-1];
    }
    return u;
}

"""One token for one kind. "" when the value normalises to nothing.
Kind `n` takes `name|org`; an empty org yields kind `n0` over the name alone."""
def token(kind: str, value: str) -> str {
    k = kind;
    v = "";
    if kind == "n" or kind == "n0" {
        name = value;
        org = "";
        if "|" in value {
            name = value[:value.index("|")];
            org = value[value.index("|") + 1:];
        }
        nn = norm_name(name);
        if len(nn) == 0 {
            return "";
        }
        no = norm_org(org);
        if len(no) == 0 {
            k = "n0";
            v = nn;
        } else {
            k = "n";
            v = nn + "|" + no;
        }
    } elif kind == "e" {
        v = norm_email(value);
    } elif kind == "p" {
        v = norm_phone(value);
    } elif kind == "u" {
        v = canonical_url(value);
    }
    if len(v) == 0 {
        return "";
    }
    return k + ":" + _hmac32(k + "\u0000" + v);
}

def tokens_for(p: Person) -> list[str] {
    out: list[str] = [];
    cands: list[str] = [
        token("n", p.name + "|" + p.org),
        token("e", p.email),
        token("p", p.phone)
    ];
    for link in p.links {
        cands.append(token("u", link));
    }
    for t in cands {
        if len(t) > 0 and t not in out {
            out.append(t);
        }
    }
    return out;
}

"""Recompute and store p.identity_tokens; returns them."""
def refresh_person_tokens(p: Person) -> list[str] {
    toks = tokens_for(p);
    p.identity_tokens = toks;
    return toks;
}

"""Append `url` to p.links unless a link with the same canonical form is
already there. Grounding redirect URLs are never stored. Returns True if added."""
def add_link(p: Person, url: str) -> bool {
    c = canonical_url(url);
    if len(c) == 0 or c.startswith("vertexaisearch.cloud.google.com") {
        return False;
    }
    for existing in p.links {
        if canonical_url(existing) == c {
            return False;
        }
    }
    p.links = p.links + [url.strip()];
    return True;
}

"""Fill empty email/phone and absent links from a read (badge, card), then
refresh the tokens. Never overwrites a value the user already has."""
def fill_contact(p: Person, email: str, phone: str, links: list[str]) -> list[str] {
    if len(p.email.strip()) == 0 and len(norm_email(email)) > 0 {
        p.email = email.strip();
    }
    if len(p.phone.strip()) == 0 and len(norm_phone(phone)) > 0 {
        p.phone = phone.strip();
    }
    for link in (links or []) {
        add_link(p, str(link));
    }
    return refresh_person_tokens(p);
}

"""Why two token lists name the same person: "contact" (an e/p/u token
matches), "name+org" (the n token matches), "name" (only n0 matches), or ""."""
def match_reason(a: list[str], b: list[str]) -> str {
    shared: list[str] = [t for t in a if t in b];
    if len(shared) == 0 {
        return "";
    }
    for t in shared {
        if t.startswith("e:") or t.startswith("p:") or t.startswith("u:") {
            return "contact";
        }
    }
    for t in shared {
        if t.startswith("n:") {
            return "name+org";
        }
    }
    for t in shared {
        if t.startswith("n0:") {
            return "name";
        }
    }
    return "";
}

""""same" on a contact or name|org match, "likely" on a name-only (n0) match, "" otherwise."""
def same_person(a: list[str], b: list[str]) -> str {
    r = match_reason(a, b);
    if r == "contact" or r == "name+org" {
        return "same";
    }
    if r == "name" {
        return "likely";
    }
    return "";
}

def _reason_rank(r: str) -> int {
    if r == "contact" {
        return 3;
    }
    if r == "name+org" {
        return 2;
    }
    if r == "name" {
        return 1;
    }
    return 0;
}

"""Group replies ({"id", "tokens"}) whose tokens intersect (same_person != "").
Returns {"groups": list[list[str]] (size >= 2 only), "same_as": {id: [other ids]},
"same_reason": {id: strongest reason vs any reply in its group, or ""}}."""
def group_same_person(items: list[dict[str, any]]) -> dict[str, any] {
    ids: list[str] = [str(it["id"]) for it in items];
    label: dict[str, int] = {};
    reason: dict[str, str] = {};
    for (i, rid) in enumerate(ids) {
        label[rid] = i;
        reason[rid] = "";
    }
    for i in range(len(items)) {
        for j in range(i + 1, len(items)) {
            r = match_reason(items[i]["tokens"] as list[str], items[j]["tokens"] as list[str]);
            if len(r) == 0 {
                continue;
            }
            a = ids[i];
            b = ids[j];
            if _reason_rank(r) > _reason_rank(reason[a]) {
                reason[a] = r;
            }
            if _reason_rank(r) > _reason_rank(reason[b]) {
                reason[b] = r;
            }
            old = label[b];
            new = label[a];
            if old != new {
                for k in ids {
                    if label[k] == old {
                        label[k] = new;
                    }
                }
            }
        }
    }
    groups: list[list[str]] = [];
    seen: list[int] = [];
    for rid in ids {
        lab = label[rid];
        if lab in seen {
            continue;
        }
        seen.append(lab);
        members: list[str] = [k for k in ids if label[k] == lab];
        if len(members) > 1 {
            groups.append(members);
        }
    }
    same_as: dict[str, list[str]] = {};
    for rid in ids {
        same_as[rid] = [k for k in ids if k != rid and label[k] == label[rid]];
    }
    return {"groups": groups, "same_as": same_as, "same_reason": reason};
}

walker:priv RefreshIdentityTokens {
    """Recompute identity_tokens for every Person the caller knows. Own root only.
    Reports [{updated}] = how many people's tokens changed."""
    has reports: list[dict[str, int]] = [];

    can go with Root entry {
        updated = 0;
        # Untyped-then-filtered (AGENTS gotcha: typed traversals read an owner-side
        # index that can miss edges); Me -> Person is only ever a Knows edge.
        people: list[Person] = [];
        for m in [x for x in [root -->] if isinstance(x, Me)] {
            for x in [m -->] {
                if isinstance(x, Person) and x not in people {
                    people.append(x);
                }
            }
        }
        for p in people {
            before = list(p.identity_tokens);
            if refresh_person_tokens(p) != before {
                updated += 1;
            }
        }
        report {"updated": updated};
    }
}
