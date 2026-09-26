"""Tests for enrich.sv.jac (SOH-182). Run with `jac test enrich.sv.jac`.

No network and no model: the pure defs are fed canned Gemini responses, and the
walker tests only exercise paths that stop before the REST call (unknown id,
blank GOOGLE_API_KEY). Every fixture is filtered by its own per-run jid.
"""

import os;
import from enrich {
    Enrich, parse_enrich_json, parse_enrich_lines, resolve_url, attach_urls, apply_rules, dedup_facts,
    response_text, grounding_of, search_queries, overlaps, build_prompt
}
import from schema { Me, Person, Note, Fact, Knows, Mentions, FactAbout }
import from uuid { uuid4 }

def canned_response() -> dict[str, any] {
    body = "{\"identity\": \"matched\", \"identity_reason\": \"creator of Python\", \"facts\": [{\"text\": \"Guido van Rossum created the Python programming language.\", \"evidence\": \"creator of the Python programming language\"}, {\"text\": \"He enjoys sailing on weekends.\", \"evidence\": \"\"}]}";
    return {
        "candidates": [{
            "content": {"parts": [{"text": "```json\n" + body + "\n```"}]},
            "groundingMetadata": {
                "webSearchQueries": ["Guido van Rossum"],
                "groundingChunks": [
                    {"web": {"uri": "https://vertexaisearch.cloud.google.com/grounding-api-redirect/abc", "title": "python.org"}},
                    {"web": {"uri": "https://vertexaisearch.cloud.google.com/grounding-api-redirect/def", "title": "wikipedia.org"}}
                ],
                "groundingSupports": [
                    {"segment": {"startIndex": 0, "endIndex": 60, "text": "Guido van Rossum created the Python programming language."}, "groundingChunkIndices": [1, 0]}
                ]
            }
        }]
    };
}

test "canned response: one fact with a chunk is kept with its uri/title, the other is rejected no_url" {
    resp = canned_response();
    parsed = parse_enrich_json(response_text(resp));
    assert parsed["identity"] == "matched";
    assert not parsed["fallback"];
    assert len(parsed["facts"] as list[dict[str, str]]) == 2;
    g = grounding_of(resp);
    assert search_queries(g) == ["Guido van Rossum"];
    out = apply_rules(parsed, g);
    kept = out["kept"] as list[dict[str, str]];
    rejected = out["rejected"] as list[dict[str, str]];
    assert len(kept) == 1, f"kept {kept}";
    assert kept[0]["uri"] == "https://vertexaisearch.cloud.google.com/grounding-api-redirect/def";
    assert kept[0]["title"] == "wikipedia.org";
    assert kept[0]["evidence"] == "creator of the Python programming language";
    assert len(rejected) == 1;
    assert rejected[0]["reason"] == "no_url";
    assert rejected[0]["text"] == "He enjoys sailing on weekends.";
}

test "attach_urls: evidence overlap and 4-shared-token overlap both attach a url" {
    g: dict[str, any] = {
        "groundingChunks": [{"web": {"uri": "https://example.com/a", "title": "example.com"}}],
        "groundingSupports": [{"segment": {"text": "She leads robotics research partnerships at Acme Labs since 2021"}, "groundingChunkIndices": [0]}]
    };
    facts: list[dict[str, str]] = [
        {"text": "Leads research partnerships in robotics at Acme.", "evidence": ""},
        {"text": "Unrelated.", "evidence": "Acme Labs since 2021"}
    ];
    out = attach_urls(facts, g);
    kept = out["kept"] as list[dict[str, str]];
    assert len(kept) == 2, f"kept {kept}";
    assert kept[0]["uri"] == "https://example.com/a";
    assert not overlaps("abc", "");
    assert overlaps("Python programming", "created the python programming language");
}

test "identity ambiguous or not_found rejects every fact with reason identity" {
    for ident in ["ambiguous", "not_found"] {
        parsed = parse_enrich_json("{\"identity\": \"" + ident + "\", \"facts\": [{\"text\": \"A fact.\", \"evidence\": \"A fact.\"}, {\"text\": \"B fact.\"}]}");
        assert parsed["identity"] == ident;
        out = apply_rules(parsed, grounding_of(canned_response()));
        assert len(out["kept"] as list[dict[str, str]]) == 0;
        rej = out["rejected"] as list[dict[str, str]];
        assert len(rej) == 2;
        assert rej[0]["reason"] == "identity" and rej[1]["reason"] == "identity";
    }
}

test "parse_enrich_json: fenced JSON parses, prose-wrapped JSON parses, garbage is unavailable" {
    fenced = parse_enrich_json("```json\n{\"identity\": \"matched\", \"facts\": []}\n```");
    assert fenced["identity"] == "matched" and not fenced["fallback"];
    wrapped = parse_enrich_json("Here you go: {\"identity\": \"not_found\", \"facts\": []} hope it helps");
    assert wrapped["identity"] == "not_found";
    garbage = parse_enrich_json("There is no verified public record of this person.");
    assert garbage["identity"] == "unavailable";
    assert garbage["fallback"];
    assert len(garbage["facts"] as list[dict[str, str]]) == 0;
    empty = parse_enrich_json("");
    assert empty["identity"] == "unavailable";
}

test "line-format answer (what the prompt asks for): the FACT's own support wins over a REASON line sharing tokens" {
    text = "IDENTITY: matched\nREASON: He is the Dutch programmer who created the Python programming language.\nFACT: He created the Python programming language while working at CWI.\n**FACT:** He joined Microsoft in 2020.\nFACT: He likes long walks.";
    parsed = parse_enrich_json(text);
    assert parsed["identity"] == "matched" and not parsed["fallback"];
    assert parsed["identity_reason"].startswith("He is the Dutch");
    facts = parsed["facts"] as list[dict[str, str]];
    assert [f["text"] for f in facts] == ["He created the Python programming language while working at CWI.", "He joined Microsoft in 2020.", "He likes long walks."], f"{facts}";
    g: dict[str, any] = {
        "groundingChunks": [
            {"web": {"uri": "https://r.example/reason", "title": "reason.org"}},
            {"web": {"uri": "https://r.example/cwi", "title": "cwi.nl"}},
            {"web": {"uri": "https://r.example/ms", "title": "microsoft.com"}}
        ],
        "groundingSupports": [
            {"segment": {"text": "IDENTITY: matched\nREASON: He is the Dutch programmer who created the Python programming language"}, "groundingChunkIndices": [0]},
            {"segment": {"text": "FACT: He created the Python programming language while working at CWI"}, "groundingChunkIndices": [1]},
            {"segment": {"text": "FACT: He joined Microsoft in 2020."}, "groundingChunkIndices": [2]}
        ]
    };
    out = apply_rules(parsed, g);
    kept = out["kept"] as list[dict[str, str]];
    assert len(kept) == 2, f"{kept}";
    assert kept[0]["uri"] == "https://r.example/cwi" and kept[0]["title"] == "cwi.nl";
    assert kept[1]["uri"] == "https://r.example/ms";
    rej = out["rejected"] as list[dict[str, str]];
    assert len(rej) == 1 and rej[0]["reason"] == "no_url" and rej[0]["text"] == "He likes long walks.";
    assert parse_enrich_lines("no identity here")["identity"] == "unavailable";
    assert parse_enrich_lines("IDENTITY: maybe")["identity"] == "ambiguous";
}

test "resolve_url never fetches a LinkedIn-labelled source" {
    u = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/xyz";
    assert resolve_url(u, "linkedin.com") == u;
}

test "dedup_facts: existing text, same url+prefix, and in-batch repeats are rejected duplicate" {
    kept: list[dict[str, str]] = [
        {"text": "Works at Acme.", "evidence": "", "uri": "https://a.example", "title": "a"},
        {"text": "Founded a robotics startup in 2019 in Detroit.", "evidence": "", "uri": "https://b.example", "title": "b"},
        {"text": "Founded a robotics startup in 2019 in Detroit!", "evidence": "", "uri": "https://b.example", "title": "b"},
        {"text": "Speaks at PyCon.", "evidence": "", "uri": "https://c.example", "title": "c"}
    ];
    out = dedup_facts(kept, ["works at acme."]);
    k = out["kept"] as list[dict[str, str]];
    r = out["rejected"] as list[dict[str, str]];
    assert [f["text"] for f in k] == ["Founded a robotics startup in 2019 in Detroit.", "Speaks at PyCon."], f"{k}";
    assert len(r) == 2 and r[0]["reason"] == "duplicate" and r[1]["reason"] == "duplicate";
    reworded: list[dict[str, str]] = [{"text": "He served as Python's Benevolent Dictator For Life until stepping down from the role in July 2018.", "evidence": "", "uri": "https://w.example", "title": "w"}];
    out3 = dedup_facts(reworded, ["He served as Python's Benevolent Dictator for Life until stepping down from the position in July 2018."]);
    assert len(out3["kept"] as list[dict[str, str]]) == 0, "a re-worded repeat is a duplicate";
    out4 = dedup_facts(reworded, ["He joined Microsoft as a Distinguished Engineer in 2020."]);
    assert len(out4["kept"] as list[dict[str, str]]) == 1;
    out2 = dedup_facts([kept[3]], [], ["https://c.example|speaks at pycon."]);
    assert len(out2["kept"] as list[dict[str, str]]) == 0;
}

test "build_prompt carries the name, org, context and the cap" {
    prompt = build_prompt({"name": "Ada Example", "org": "Acme", "title": "CTO", "facts": ["likes robots"], "spans": ["met at PyCon"], "me_about": ""}, 3);
    assert "Ada Example (Acme, CTO)" in prompt;
    assert "likes robots" in prompt and "met at PyCon" in prompt;
    assert "at most 3)" in prompt;
    assert "IDENTITY:" in prompt and "FACT:" in prompt and "Search Google" in prompt;
}

test "Enrich on an unknown id reports not_found" {
    result = root spawn Enrich(person_id="not-a-real-person-id-" + str(uuid4()));
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

test "Enrich with GOOGLE_API_KEY blanked: unavailable, fallback, no note created" {
    run = str(uuid4())[:8];
    me = (root ++> Me(name=f"enrich-test-me-{run}"))[0];
    p = (me +>:Knows(status="confirmed", source_note=""):+> Person(name=f"Enrich Person {run}"))[0];
    had = "GOOGLE_API_KEY" in os.environ;
    saved = os.environ["GOOGLE_API_KEY"] if had else "";
    os.environ["GOOGLE_API_KEY"] = "";
    try {
        result = root spawn Enrich(person_id=jid(p));
    } finally {
        if had {
            os.environ["GOOGLE_API_KEY"] = saved;
        } else {
            del os.environ["GOOGLE_API_KEY"];
        }
    }
    assert len(result.reports) == 1;
    r = result.reports[0] as dict[str, any];
    assert r["person_id"] == jid(p);
    assert r["identity"] == "unavailable";
    assert r["fallback"];
    assert r["note_id"] == "";
    assert len(r["facts"] as list[any]) == 0;
    assert r["error"] == "no_key";
    assert len([p <-:Mentions:<-]) == 0;
    assert len([p <-:FactAbout:<-]) == 0;
}
