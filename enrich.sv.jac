"""Enrich — public web facts about one contact, via Gemini REST + Google Search grounding (SOH-182).

OWNER: Person A. See contracts/walkers.md `Enrich(person_id, max_facts)` for the
exact report shape. byllm 0.6.19 has no grounding, so this module makes ONE plain
REST call to `generativelanguage.googleapis.com` with `tools: [{google_search: {}}]`
(same idiom as voice.sv.jac: `os.environ.get`, `requests.post(..., timeout=...)`,
try/except, the key is never logged). Everything around that call is
deterministic and tested without the network in enrich.test.jac:

  - Nothing is asserted without a URL: a fact is kept only when a grounding
    support segment overlaps its text/evidence, and that support's first chunk
    supplies `source_url` / `source_title`.
  - Identity-gated: facts attach only when the model says `identity == "matched"`;
    "ambiguous" / "not_found" reject every fact with reason "identity".
  - Provenance: kept facts hang off ONE `Note(kind="enrich")` via `Asserts(span=...)`
    with `source_kind="web"` and `source_url`. No kept fact -> no Note.
  - Nothing sends; reads only the caller's own graph (`:priv`).
"""

import json;
import os;
import requests;
import from datetime { datetime }
import from schema { Me, Person, Note, Fact, Knows, Asserts, Mentions, FactAbout }
import from reads { my_node }

glob MAX_RESOLVES: int = 5;

# ---------------------------------------------------------------- small dict helpers

def _s(d: dict[str, any], key: str) -> str {
    if key in d {
        v = d[key];
        if v is None {
            return "";
        }
        return str(v);
    }
    return "";
}

def _l(d: dict[str, any], key: str) -> list[any] {
    if key in d {
        v = d[key];
        if isinstance(v, list) {
            return v as list[any];
        }
    }
    return [];
}

def _d(d: dict[str, any], key: str) -> dict[str, any] {
    if key in d {
        v = d[key];
        if isinstance(v, dict) {
            return v as dict[str, any];
        }
    }
    return {};
}

def not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

"""`GEMINI_MODEL` (byLLM form `gemini/<name>`) with the provider prefix stripped."""
def gemini_model_name() -> str {
    m = os.environ.get("GEMINI_MODEL", "gemini/gemini-3.8-flash") or "gemini/gemini-3.8-flash";
    if m.startswith("gemini/") {
        m = m[len("gemini/"):];
    }
    return m;
}

# ---------------------------------------------------------------- prompt

def build_prompt(ctx: dict[str, any], max_facts: int) -> str {
    name = _s(ctx, "name");
    org = _s(ctx, "org");
    title = _s(ctx, "title");
    who_bits: list[str] = [b for b in [org, title] if len(b.strip()) > 0];
    who = f"{name} ({', '.join(who_bits)})" if len(who_bits) > 0 else name;
    context_bits: list[str] = [];
    for t in _l(ctx, "facts") {
        context_bits.append(str(t));
    }
    for t in _l(ctx, "spans") {
        context_bits.append(str(t));
    }
    me_about = _s(ctx, "me_about");
    if len(me_about.strip()) > 0 {
        context_bits.append(f"(about me, the note-taker: {me_about[:160]})");
    }
    context = " | ".join(context_bits) if len(context_bits) > 0 else "(none)";
    # Line format, not JSON: verified 2026-09-26 that gemini-3.8-flash returns NO
    # groundingMetadata when told "Reply ONLY with JSON" (and often skips the
    # search entirely unless told to search). parse_enrich_json reads both.
    return (
        f"Search Google now for {who} and report what the search results currently say about this person. "
        + "Every fact must come from a search result, not from memory. "
        + f"Context from my notes: {context}.\n"
        + "Answer in plain text lines, no JSON, no markdown:\n"
        + "IDENTITY: matched, not_found, or ambiguous\n"
        + "REASON: one sentence on how you told this person apart\n"
        + f"FACT: one-sentence public fact about this person (one line per fact, at most {max_facts})\n"
        + "Only include facts about THIS person; if you cannot tell the person apart from others "
        + "with the same name, write IDENTITY: ambiguous and no FACT lines."
    );
}

# ---------------------------------------------------------------- response parsing (pure)

"""All text parts of `candidates[0].content.parts`, concatenated."""
def response_text(resp: dict[str, any]) -> str {
    cands = _l(resp, "candidates");
    if len(cands) == 0 or not isinstance(cands[0], dict) {
        return "";
    }
    content = _d(cands[0] as dict[str, any], "content");
    out = "";
    for part in _l(content, "parts") {
        if isinstance(part, dict) {
            out += _s(part as dict[str, any], "text");
        }
    }
    return out;
}

"""`candidates[0].groundingMetadata` or {}."""
def grounding_of(resp: dict[str, any]) -> dict[str, any] {
    cands = _l(resp, "candidates");
    if len(cands) == 0 or not isinstance(cands[0], dict) {
        return {};
    }
    return _d(cands[0] as dict[str, any], "groundingMetadata");
}

def search_queries(grounding: dict[str, any]) -> list[str] {
    return [str(q) for q in _l(grounding, "webSearchQueries")];
}

def _unavailable_parse() -> dict[str, any] {
    return {"identity": "unavailable", "identity_reason": "", "facts": [], "fallback": True};
}

"""The line format the prompt asks for: `IDENTITY: ...`, `REASON: ...`,
`FACT: ...` (one per line; markdown bullets/bold tolerated). No IDENTITY line
-> identity "unavailable", fallback True."""
def parse_enrich_lines(text: str) -> dict[str, any] {
    identity = "";
    reason = "";
    facts: list[dict[str, str]] = [];
    for raw in (text or "").split("\n") {
        line = raw.strip().lstrip("-*• ").replace("**", "").strip();
        upper = line.upper();
        if upper.startswith("IDENTITY:") {
            identity = line[len("IDENTITY:"):].strip().strip(".").lower();
        } elif upper.startswith("REASON:") {
            reason = line[len("REASON:"):].strip();
        } elif upper.startswith("FACT:") {
            ft = line[len("FACT:"):].strip();
            if len(ft) > 0 {
                facts.append({"text": ft, "evidence": ""});
            }
        }
    }
    if len(identity) == 0 {
        return _unavailable_parse();
    }
    if identity not in ["matched", "not_found", "ambiguous"] {
        identity = "ambiguous";
    }
    return {"identity": identity, "identity_reason": reason, "facts": facts, "fallback": False};
}

"""Model text -> {identity, identity_reason, facts: [{text, evidence}], fallback}.
Strips ``` fences; falls back to the first `{` .. last `}`; anything unparsable
-> identity "unavailable", fallback True. Never raises."""
def parse_enrich_json(text: str) -> dict[str, any] {
    t = (text or "").strip();
    if t.startswith("```") {
        lines = t.split("\n");
        lines = lines[1:];
        if len(lines) > 0 and lines[-1].strip().startswith("```") {
            lines = lines[:-1];
        }
        t = "\n".join(lines).strip();
    }
    data: any = None;
    try {
        data = json.loads(t);
    } except Exception {
        data = None;
    }
    if data is None {
        start = t.find("{");
        end = t.rfind("}");
        if start >= 0 and end > start {
            try {
                data = json.loads(t[start:end + 1]);
            } except Exception {
                data = None;
            }
        }
    }
    if not isinstance(data, dict) {
        return parse_enrich_lines(t);
    }
    obj_d = data as dict[str, any];
    identity = _s(obj_d, "identity").strip().lower();
    if identity not in ["matched", "not_found", "ambiguous"] {
        identity = "ambiguous" if len(identity) > 0 else "unavailable";
    }
    facts: list[dict[str, str]] = [];
    for f in _l(obj_d, "facts") {
        if isinstance(f, dict) {
            fd = f as dict[str, any];
            ft = _s(fd, "text").strip();
            if len(ft) > 0 {
                facts.append({"text": ft, "evidence": _s(fd, "evidence").strip()});
            }
        } elif isinstance(f, str) and len(str(f).strip()) > 0 {
            facts.append({"text": str(f).strip(), "evidence": ""});
        }
    }
    return {
        "identity": identity,
        "identity_reason": _s(obj_d, "identity_reason"),
        "facts": facts,
        "fallback": identity == "unavailable"
    };
}

# ---------------------------------------------------------------- URL rule (pure)

def _tokens4(s: str) -> list[str] {
    out: list[str] = [];
    cur = "";
    for ch in (s or "").lower() {
        if ch.isalnum() {
            cur += ch;
        } else {
            if len(cur) >= 4 and cur not in out {
                out.append(cur);
            }
            cur = "";
        }
    }
    if len(cur) >= 4 and cur not in out {
        out.append(cur);
    }
    return out;
}

"""0 = no overlap; 1000 = case-insensitive substring either way; otherwise the
number of shared tokens (>= 4 chars) when there are at least 4."""
def overlap_score(segment: str, candidate: str) -> int {
    a = (segment or "").strip().lower();
    b = (candidate or "").strip().lower();
    if len(a) == 0 or len(b) == 0 {
        return 0;
    }
    if a in b or b in a {
        return 1000;
    }
    ta = _tokens4(a);
    shared = 0;
    for tok in _tokens4(b) {
        if tok in ta {
            shared += 1;
        }
    }
    return shared if shared >= 4 else 0;
}

def overlaps(segment: str, candidate: str) -> bool {
    return overlap_score(segment, candidate) > 0;
}

def _first_web(sd: dict[str, any], chunks: list[any]) -> dict[str, str] {
    for i in _l(sd, "groundingChunkIndices") {
        if isinstance(i, int) and (i as int) >= 0 and (i as int) < len(chunks) and isinstance(chunks[i as int], dict) {
            web = _d(chunks[i as int] as dict[str, any], "web");
            u = _s(web, "uri");
            if len(u) > 0 {
                return {"uri": u, "title": _s(web, "title")};
            }
        }
    }
    return {"uri": "", "title": ""};
}

"""For each fact, the groundingSupport whose segment text overlaps the fact's
text or evidence best supplies its first chunk's web uri/title. No chunk ->
rejected "no_url". Returns {kept: [{text, evidence, uri, title}], rejected: [{text, reason}]}."""
def attach_urls(facts: list[dict[str, str]], grounding: dict[str, any]) -> dict[str, any] {
    chunks = _l(grounding, "groundingChunks");
    supports = _l(grounding, "groundingSupports");
    kept: list[dict[str, str]] = [];
    rejected: list[dict[str, str]] = [];
    for f in facts {
        text = f["text"] if "text" in f else "";
        evidence = f["evidence"] if "evidence" in f else "";
        # Best-overlapping support wins (a substring match beats a token match),
        # so a REASON line sharing a few words cannot steal a FACT's source.
        uri = "";
        title = "";
        best = 0;
        for sup in supports {
            if not isinstance(sup, dict) {
                continue;
            }
            sd = sup as dict[str, any];
            seg = _s(_d(sd, "segment"), "text");
            score = max(overlap_score(seg, text), overlap_score(seg, evidence));
            if score <= best {
                continue;
            }
            web = _first_web(sd, chunks);
            if len(web["uri"]) > 0 {
                best = score;
                uri = web["uri"];
                title = web["title"];
            }
        }
        if len(uri) > 0 {
            kept.append({"text": text, "evidence": evidence, "uri": uri, "title": title});
        } else {
            rejected.append({"text": text, "reason": "no_url"});
        }
    }
    return {"kept": kept, "rejected": rejected};
}

"""Identity rule then URL rule. identity != "matched" -> every fact rejected "identity"."""
def apply_rules(parsed: dict[str, any], grounding: dict[str, any]) -> dict[str, any] {
    facts = parsed["facts"] as list[dict[str, str]];
    if _s(parsed, "identity") != "matched" {
        rej: list[dict[str, str]] = [{"text": f["text"], "reason": "identity"} for f in facts];
        return {"kept": [], "rejected": rej};
    }
    return attach_urls(facts, grounding);
}

"""Token-set Jaccard (tokens >= 4 chars) - catches the model re-wording a fact
it already gave on a previous Enrich run."""
def similarity(a: str, b: str) -> float {
    ta = _tokens4(a);
    tb = _tokens4(b);
    if len(ta) == 0 or len(tb) == 0 {
        return 0.0;
    }
    inter = 0;
    for t in ta {
        if t in tb {
            inter += 1;
        }
    }
    union = len(ta) + len(tb) - inter;
    return inter / union if union > 0 else 0.0;
}

glob DUP_SIMILARITY: float = 0.6;

"""Drop kept facts that repeat an existing Fact on the person (lowercase text
equality, same source_url + first 40 chars, or >= 0.6 token Jaccard) or an
earlier kept fact. `existing_keys` are `url|first40` strings of existing facts.
Returns {kept, rejected} (rejected reason "duplicate")."""
def dedup_facts(kept: list[dict[str, str]], existing_texts: list[str], existing_keys: list[str] | None = None) -> dict[str, any] {
    seen_texts: list[str] = [t.strip().lower() for t in existing_texts];
    seen_keys: list[str] = list(existing_keys) if existing_keys is not None else [];
    out: list[dict[str, str]] = [];
    rejected: list[dict[str, str]] = [];
    for f in kept {
        low = f["text"].strip().lower();
        url = f["uri"] if "uri" in f else "";
        key = f"{url}|{low[:40]}";
        dup = low in seen_texts or (len(url) > 0 and key in seen_keys);
        if not dup {
            for prev in seen_texts {
                if similarity(prev, low) >= DUP_SIMILARITY {
                    dup = True;
                    break;
                }
            }
        }
        if dup {
            rejected.append({"text": f["text"], "reason": "duplicate"});
            continue;
        }
        seen_texts.append(low);
        seen_keys.append(key);
        out.append(f);
    }
    return {"kept": out, "rejected": rejected};
}

# ---------------------------------------------------------------- network (the only impure bits)

"""Follow the grounding redirect to the real page; any failure keeps `uri`.
Never fetches a source Google labels as LinkedIn (AGENTS.md: no automated
fetching from platforms whose terms forbid it) - the redirect uri is kept."""
def resolve_url(uri: str, title: str = "") -> str {
    if "linkedin" in title.lower() {
        return uri;
    }
    try {
        resp = requests.head(uri, allow_redirects=True, timeout=5);
        final = str(resp.url or "");
        if len(final) > 0 {
            return final;
        }
    } except Exception {
        return uri;
    }
    return uri;
}

"""ONE grounded generateContent call. Returns the parsed JSON body; raises on
network error or non-2xx (message carries the status, never the key)."""
def call_gemini(prompt: str, api_key: str) -> dict[str, any] {
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{gemini_model_name()}:generateContent";
    resp = requests.post(
        url,
        headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
        json={"contents": [{"parts": [{"text": prompt}]}], "tools": [{"google_search": {}}]},
        timeout=45
    );
    if resp.status_code < 200 or resp.status_code >= 300 {
        raise RuntimeError(f"gemini_http_{resp.status_code}");
    }
    return resp.json() as dict[str, any];
}

# ---------------------------------------------------------------- graph helpers

"""The caller's Me that Knows `p`, or None (p not in any of the caller's `[me ->:Knows:->]`)."""
def owning_me(p: Person) -> object {
    for me in [root --> [?:Me]] {
        for q in [me ->:Knows:->] {
            if jid(q) == jid(p) {
                return me;
            }
        }
    }
    return None;
}

def gather_context(me: Me, p: Person) -> dict[str, any] {
    fact_texts: list[str] = [];
    fact_keys: list[str] = [];
    for f in [p <-:FactAbout:<-] {
        fact_texts.append(f.text);
        if len(f.source_url) > 0 {
            fact_keys.append(f"{f.source_url}|{f.text.strip().lower()[:40]}");
        }
    }
    spans: list[str] = [];
    for n in [p <-:Mentions:<-] {
        if len(spans) >= 3 {
            break;
        }
        for e in [edge n ->:Mentions:-> p] {
            if len(e.span.strip()) > 0 and e.span not in spans and len(spans) < 3 {
                spans.append(e.span);
            }
        }
    }
    return {
        "name": p.name, "org": p.org, "title": p.title,
        "facts": fact_texts[:6], "all_fact_texts": fact_texts, "fact_keys": fact_keys,
        "spans": spans, "me_about": me.about
    };
}

# ---------------------------------------------------------------- walker

walker:priv Enrich {
    has person_id: str;
    has max_facts: int = 5;
    has reports: list[dict[str, any]] = [];

    can go with Root entry {
        n = my_node(self.person_id);
        if n is None or not isinstance(n, Person) {
            report not_found();
            disengage;
        }
        p = n as Person;
        owner = owning_me(p);
        if owner is None {
            report not_found();
            disengage;
        }
        me = owner as Me;
        ctx = gather_context(me, p);
        cap = self.max_facts if self.max_facts > 0 else 5;
        cap = cap if cap <= 10 else 10;

        out: dict[str, any] = {
            "person_id": jid(p), "note_id": "", "identity": "unavailable",
            "facts": [], "rejected": [], "queries": [], "fallback": True, "error": ""
        };

        api_key = os.environ.get("GOOGLE_API_KEY", "") or "";
        if len(api_key.strip()) == 0 {
            out["error"] = "no_key";
            report out;
            disengage;
        }

        resp: dict[str, any] = {};
        try {
            resp = call_gemini(build_prompt(ctx, cap), api_key);
        } except Exception as e {
            out["error"] = str(e)[:200];
            report out;
            disengage;
        }

        grounding = grounding_of(resp);
        queries = search_queries(grounding);
        parsed = parse_enrich_json(response_text(resp));
        out["queries"] = queries;
        out["identity"] = parsed["identity"];
        out["fallback"] = parsed["fallback"];

        ruled = apply_rules(parsed, grounding);
        kept = (ruled["kept"] as list[dict[str, str]])[:cap];
        rejected = list(ruled["rejected"] as list[dict[str, str]]);

        resolves = 0;
        for f in kept {
            if resolves < MAX_RESOLVES {
                f["uri"] = resolve_url(f["uri"], f["title"]);
                resolves += 1;
            }
        }

        deduped = dedup_facts(kept, ctx["all_fact_texts"] as list[str], ctx["fact_keys"] as list[str]);
        final = deduped["kept"] as list[dict[str, str]];
        rejected += deduped["rejected"] as list[dict[str, str]];
        out["rejected"] = rejected;

        if len(final) == 0 {
            report out;
            disengage;
        }

        now = datetime.now().isoformat();
        q_text = "; ".join(queries) if len(queries) > 0 else p.name;
        note = (root ++> Note(text=f"Web enrichment for {p.name}: " + q_text, kind="enrich", captured_at=now))[0];
        note +>:Mentions(span=p.name):+> p;
        facts_out: list[dict[str, any]] = [];
        for f in final {
            span = f["evidence"] if len(f["evidence"]) > 0 else f["text"];
            fact = (note +>:Asserts(span=span):+> Fact(
                text=f["text"], observed_at=now, status="reported",
                source_kind="web", source_url=f["uri"]
            ))[0];
            fact +>:FactAbout:+> p;
            facts_out.append({"fact": fact, "source_url": f["uri"], "source_title": f["title"], "span": span});
        }
        out["note_id"] = jid(note);
        out["facts"] = facts_out;
        report out;
    }
}
