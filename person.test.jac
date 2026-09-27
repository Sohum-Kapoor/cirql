"""Tests for person.sv.jac (SOH-207 PersonDetail, SOH-199 Brief).

Annex to person.sv.jac — run with `jac test person.sv.jac`. Deterministic
only: no LLM, no ElevenLabs network call.

`jac test person.sv.jac` also runs the test files of every module person.sv.jac
imports (`goals.sv.jac`, `drafts.sv.jac`) against the same shared, persisted
root (`jac-testing`). Two consequences, same reasoning `reads.test.jac` and
`drafts.test.jac` already document for this codebase:
  - `person_detail_for` is exercised directly on hand-built nodes (never
    through `root spawn PersonDetail(...)` for the success path) because it
    takes `me`/`person` as arguments rather than resolving "the" `Me` via
    `[root --> [?:Me]][0]` — ambiguous once more than one test (in this file
    or an earlier `jac test` run) has created a `Me` under the shared root.
  - The one walker test that goes through `root spawn PersonDetail(...)`
    (an unresolvable `person_id`) doesn't depend on which `Me` gets picked,
    so it's safe.
  - `deterministic_brief`/`fallback_recap`/`synthesize_voice` are exercised
    directly on hand-built `EvidenceItem`s and strings — no graph, no LLM,
    no network. `ELEVENLABS_API_KEY` is forced empty so `synthesize_voice`
    takes the `no_key` branch deterministically, mirroring `voice.test.jac`'s
    own `Transcribe`-with-no-key test.
  - The true cross-root isolation negative (a person under account A is
    `not_found` from account B) needs two real, separate roots, so it runs
    through a `JacTestClient` harness — same approach `gate.test.jac` uses:
    JacTestClient cannot target a dotted `*.sv.jac` file directly, so the
    harness copies every module in person.sv.jac's import chain (`schema`,
    `llm`, `goals`, `drafts`, `person`, plus `walkers` for the `DevAddPerson`
    test-seeding helper) into a fresh temp dir next to a dot-free `app.jac`,
    and gives the client its own `base_path`. No `jac clean` anywhere.
"""

import from person {
    PersonDetail, Brief, person_detail_for, deterministic_brief,
    fallback_recap, synthesize_voice, _promise_view
}
import from drafts { EvidenceItem }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, HasGoal, RelevantTo, FromCard
}
import from datetime { datetime, timedelta }
import os;

# ---------------------------------------------------------------- person_detail_for

test "person_detail_for: every section present, right age_days, expired, and relevance" {
    now = datetime.now();

    me = (root ++> Me(name="Person-test Me"))[0];
    p = (me +>:Knows(how_met="conference", last_contact="2026-09-20T00:00:00", status="confirmed", source_note=""):+> Person(
        name="Person-test Target", status="confirmed", org="Acme", title="Engineer",
        email="target@example.com", phone="555-0199", links=["https://target.example.com"], location="Detroit"
    ))[0];

    # One fact, observed exactly 10 days ago.
    fact_note = (root ++> Note(
        text="Person-test: Target works on accessible robotics.",
        kind="debrief", captured_at=(now - timedelta(days=10)).isoformat()
    ))[0];
    fact = (fact_note +>:Asserts(span="works on accessible robotics"):+> Fact(
        text="Works on accessible robotics", observed_at=(now - timedelta(days=10)).isoformat()
    ))[0];
    fact +>:FactAbout:+> p;

    # One expired intent.
    intent_note = (root ++> Note(
        text="Person-test: Target wanted a VC intro last month.",
        kind="debrief", captured_at=(now - timedelta(days=40)).isoformat()
    ))[0];
    expired_intent = (intent_note +>:AssertsIntent(span="wants a VC intro"):+> Intent(
        kind="need", text="wants a VC intro", expires_at=(now - timedelta(days=1)).isoformat()
    ))[0];
    expired_intent +>:IntentAbout:+> p;

    # One open promise.
    promise_note = (root ++> Note(
        text="Person-test: I'll send Target the deck by Friday.",
        kind="debrief", captured_at=(now - timedelta(days=2)).isoformat()
    ))[0];
    promise = (promise_note +>:AssertsPromise(span="send the deck by Friday"):+> Promise(
        text="send the deck", due="2026-10-10", done=False
    ))[0];
    promise +>:PromiseTo:+> p;

    # One note mentioning them.
    mention_note = (root ++> Note(
        text="Person-test: met Target again at the meetup.",
        kind="debrief", captured_at=(now - timedelta(days=1)).isoformat()
    ))[0];
    mention_note +>:Mentions(span="met Target again at the meetup"):+> p;

    # One Reported tie from another person.
    reporter = (root ++> Person(name="Person-test Reporter", status="confirmed"))[0];
    reporter +>:Reported(source_note=jid(mention_note), span="Reporter mentioned Target"):+> p;

    # One active goal with a RelevantTo edge.
    goal = (me +>:HasGoal:+> Goal(text="Person-test goal: find climate VCs", created_at=now.isoformat(), active=True))[0];
    p +>:RelevantTo(reason="Works on accessible robotics, matches the goal.", strength="strong", label="known", opener="Hi Target!"):+> goal;

    # Created from a card.
    card = (root ++> Card(handle="person-test-handle"))[0];
    p +>:FromCard(handle="person-test-handle"):+> card;

    view = person_detail_for(me, p);

    assert (view["person"] as Person).name == "Person-test Target";
    # SOH-216: contact fields are plain fields on the Person node, so they
    # already serialize through `person` with no extra code in this module.
    person_out = view["person"] as Person;
    assert person_out.email == "target@example.com";
    assert person_out.phone == "555-0199";
    assert person_out.links == ["https://target.example.com"];
    assert person_out.location == "Detroit";
    assert view["how_met"] == "conference";
    assert view["knows_status"] == "confirmed";
    assert view["last_contact"] == "2026-09-20T00:00:00";

    relevance = view["relevance"];
    assert relevance is not None, "expected a relevance entry for the active goal";
    rel = relevance as dict[str, any];
    assert rel["goal_id"] == jid(goal);
    assert rel["goal_text"] == "Person-test goal: find climate VCs";
    assert rel["label"] == "known";
    assert rel["strength"] == "strong";
    assert rel["opener"] == "Hi Target!";

    facts = view["facts"] as list[dict[str, any]];
    assert len(facts) == 1;
    assert (facts[0]["fact"] as Fact).text == "Works on accessible robotics";
    assert facts[0]["age_days"] == 10, f"expected age_days == 10, got {facts[0]['age_days']}";
    assert facts[0]["source_note_id"] == jid(fact_note);
    assert facts[0]["span"] == "works on accessible robotics";

    intents = view["intents"] as list[dict[str, any]];
    assert len(intents) == 1;
    assert intents[0]["expired"];
    assert intents[0]["source_note_id"] == jid(intent_note);
    assert intents[0]["span"] == "wants a VC intro";

    promises = view["promises"] as list[dict[str, any]];
    assert len(promises) == 1;
    assert (promises[0]["promise"] as Promise).text == "send the deck";
    assert promises[0]["source_note_id"] == jid(promise_note);
    assert promises[0]["span"] == "send the deck by Friday";
    assert promises[0]["due_label"] == "Oct 10", f"SOH-232: got {promises[0]['due_label']}";

    notes = view["notes"] as list[dict[str, any]];
    assert len(notes) == 1;
    assert (notes[0]["note"] as Note).text == "Person-test: met Target again at the meetup.";
    assert notes[0]["span"] == "met Target again at the meetup";

    reported_by = view["reported_by"] as list[dict[str, str]];
    assert len(reported_by) == 1;
    assert reported_by[0]["person_id"] == jid(reporter);
    assert reported_by[0]["name"] == "Person-test Reporter";
    assert reported_by[0]["span"] == "Reporter mentioned Target";

    assert view["card_handle"] == "person-test-handle";
}

test "person_detail_for: no relevance when the goal isn't active, no card_handle without FromCard" {
    me = (root ++> Me(name="Person-test Me 2"))[0];
    p = (me +>:Knows(how_met="referral"):+> Person(name="Person-test Plain", status="confirmed"))[0];
    goal = (me +>:HasGoal:+> Goal(text="Person-test inactive goal", created_at="2026-09-20T00:00:00", active=False))[0];
    p +>:RelevantTo(reason="irrelevant", strength="weak", label="cold"):+> goal;

    view = person_detail_for(me, p);
    assert view["relevance"] is None, "an inactive goal's RelevantTo edge must not surface";
    assert view["card_handle"] == "";
    assert view["facts"] == [];
    assert view["intents"] == [];
    assert view["promises"] == [];
    assert view["notes"] == [];
    assert view["reported_by"] == [];
}

test "person_detail_for: note text is capped at 400 chars without mutating the real Note" {
    me = (root ++> Me(name="Person-test Me 3"))[0];
    p = (me +>:Knows(how_met="test"):+> Person(name="Person-test Long Note P", status="confirmed"))[0];
    long_text = "z" * 500;
    long_note = (root ++> Note(text=long_text, kind="paste", captured_at="2026-09-26T09:00:00"))[0];
    long_note +>:Mentions:+> p;

    view = person_detail_for(me, p);
    notes = view["notes"] as list[dict[str, any]];
    assert len(notes) == 1;
    capped = notes[0]["note"] as Note;
    assert len(capped.text) == 400, f"expected 400 chars, got {len(capped.text)}";
    assert len(long_note.text) == 500, "the real, persisted Note must never be mutated";
}

test "PersonDetail: an unresolvable person_id reports not_found" {
    result = root spawn PersonDetail(person_id="not-a-real-person-id-at-all");
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# ---------------------------------------------------------------- Brief: deterministic pieces

test "deterministic_brief: names the person, drops empty clauses cleanly when there's no evidence" {
    p = Person(name="Person-test Bare", status="confirmed");
    text = deterministic_brief(p, []);
    assert text == (
        "Person-test Bare. You haven't captured a conversation with them yet. "
        "You promised: nothing open. They wanted: nothing on record."
    );
}

test "fallback_recap: text carries the name, the open promise, and the need; based_on carries every evidence item" {
    p = Person(name="Person-test Fallback P", status="confirmed", org="Acme", title="Engineer");
    ev = [
        EvidenceItem(id="ev-promise", kind="promise", observed_at="2026-09-20T10:00:00", span="send the demo by Friday"),
        EvidenceItem(id="ev-intent", kind="intent", observed_at="2026-09-21T10:00:00", span="wants feedback from wheelchair users")
    ];

    fb = fallback_recap(p, ev);
    text = fb["text"] as str;
    assert "Person-test Fallback P" in text;
    assert "Engineer at Acme" in text;
    assert "send the demo by Friday" in text, f"fallback text must mention the promise, got: {text}";
    assert "wants feedback from wheelchair users" in text, f"fallback text must mention the need, got: {text}";

    based_on = fb["based_on"] as list[dict[str, str]];
    assert len(based_on) == 2, "based_on must carry every evidence item when there's no LLM-picked subset";
    ids = [it["id"] for it in based_on];
    assert "ev-promise" in ids and "ev-intent" in ids;
}

test "SOH-232 deterministic_brief: 'Last time' skips an import note and picks the newest debrief/paste/voice note instead" {
    import_note = (root ++> Note(
        text="Imported 3 people from LinkedIn", kind="import", captured_at="2026-09-20T09:00:00"
    ))[0];
    debrief_note = (root ++> Note(
        text="Grabbed coffee, talked about the sensor demo", kind="debrief", captured_at="2026-09-25T09:00:00"
    ))[0];
    ev = [
        EvidenceItem(id=jid(import_note), kind="note", observed_at="2026-09-20T09:00:00", span="Imported 3 people from LinkedIn"),
        EvidenceItem(id=jid(debrief_note), kind="note", observed_at="2026-09-25T09:00:00", span="Grabbed coffee, talked about the sensor demo")
    ];
    p = Person(name="Person-test LastTime", status="confirmed");
    text = deterministic_brief(p, ev);
    assert "Last time: Grabbed coffee, talked about the sensor demo." in text, f"got: {text}";
    assert "Imported 3 people from LinkedIn" not in text, f"an import note must never be the 'Last time' line, got: {text}";
}

test "SOH-232 deterministic_brief: no debrief/paste/voice note at all reports the have-not-captured line, never an about_me/onboarding note" {
    about_me_note = (root ++> Note(text="Casey Audit: cofounder search", kind="about_me", captured_at="2026-09-20T09:00:00"))[0];
    ev = [EvidenceItem(id=jid(about_me_note), kind="note", observed_at="2026-09-20T09:00:00", span="Casey Audit: cofounder search")];
    p = Person(name="Person-test NoConversation", status="confirmed");
    text = deterministic_brief(p, ev);
    assert "You haven't captured a conversation with them yet." in text, f"got: {text}";
    assert "Casey Audit: cofounder search" not in text, f"an about_me note must never be the 'Last time' line, got: {text}";
}

test "SOH-232 deterministic_brief: the intent label is 'They offered:' for an offer, 'They wanted:' for a need" {
    offer_intent = (root ++> Intent(kind="offer", text="Offered to review your pitch deck next week", expires_at=""))[0];
    ev_offer = [EvidenceItem(id=jid(offer_intent), kind="intent", observed_at="2026-09-20T09:00:00", span="Offered to review your pitch deck next week")];
    p_offer = Person(name="Person-test OfferLabel", status="confirmed");
    text_offer = deterministic_brief(p_offer, ev_offer);
    assert "They offered: Offered to review your pitch deck next week." in text_offer, f"got: {text_offer}";
    assert "They wanted:" not in text_offer, f"got: {text_offer}";

    need_intent = (root ++> Intent(kind="need", text="wants an intro to a recruiter", expires_at=""))[0];
    ev_need = [EvidenceItem(id=jid(need_intent), kind="intent", observed_at="2026-09-20T09:00:00", span="wants an intro to a recruiter")];
    p_need = Person(name="Person-test NeedLabel", status="confirmed");
    text_need = deterministic_brief(p_need, ev_need);
    assert "They wanted: wants an intro to a recruiter." in text_need, f"got: {text_need}";
}

test "SOH-232 _promise_view: due_label resolves even from an un-normalized raw due span, is '' when due is empty or unparsable" {
    now = datetime.now();

    pr_raw_span = Promise(text="send the intro deck", due="October 15", done=False);
    view_raw = _promise_view(pr_raw_span, now);
    assert view_raw["due_label"] != "", f"a resolvable raw span must still get a due_label, got: {view_raw}";
    assert view_raw["due_label"] == "Oct 15", f"due_label must never be the raw un-normalized span, got: {view_raw['due_label']}";

    pr_empty = Promise(text="send the notes", due="", done=False);
    view_empty = _promise_view(pr_empty, now);
    assert view_empty["due_label"] == "";

    pr_unparsable = Promise(text="send the thing", due="whenever works", done=False);
    view_unparsable = _promise_view(pr_unparsable, now);
    assert view_unparsable["due_label"] == "";
}

test "synthesize_voice: no ElevenLabs key reports no_key with empty audio" {
    os.environ["ELEVENLABS_API_KEY"] = "";
    out = synthesize_voice("hi, quick recap before you meet them.");
    assert out["voice_error"] == "no_key";
    assert out["audio_b64"] == "";
    assert out["mime"] == "";
}

test "Brief: an unresolvable person_id reports not_found" {
    result = root spawn Brief(person_id="not-a-real-person-id-at-all", voice=False);
    assert len(result.reports) == 1;
    assert result.reports[0] == {"error": "not_found"};
}

# Note: `Brief`'s success path resolves "the" `Me` via `[root --> [?:Me]][0]`
# same as `DraftFollowUp`/`PersonDetail` - ambiguous on the shared, persisted
# `jac-testing` root once more than one test (in this file, or an earlier
# `jac test` run) has created a `Me`. The "no evidence -> fallback" scenario
# is exercised below, inside the isolation harness, where each registered
# account is a fresh, real, single-`Me` root.

# ---------------------------------------------------------------- isolation (two real roots)

import from jaclang.runtimelib.testing { JacTestClient }
import shutil;
import tempfile;

glob PERSON_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

"""Copy person.sv.jac's whole import chain (schema, llm, goals, drafts) plus
walkers.sv.jac (for the `DevAddPerson` test-seeding helper) into a fresh temp
dir next to a dot-free `app.jac` — `JacTestClient.from_file` can't target a
dotted `*.sv.jac` module name directly (AGENTS.md gotcha)."""
def _person_harness(tmp_dir: str) -> str {
    for name in ["schema.sv.jac", "llm.sv.jac", "goals.sv.jac", "drafts.sv.jac", "person.sv.jac", "walkers.sv.jac"] {
        shutil.copyfile(os.path.join(PERSON_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write(
        "import from person { PersonDetail, Brief }\n"
        "import from walkers { DevAddPerson }\n"
    );
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"person-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _person_register(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _person_call(client: JacTestClient, token: str, wname: str, body: dict[str, any]) -> list[any] {
    client.set_auth_token(token);
    resp = client.post(f"/walker/{wname}", json=body);
    assert resp.ok, f"{wname} failed: {resp.status_code} {resp.text}";
    return list(resp.data["reports"]);
}

test "isolation: a person under A's root is not_found from B's, found from A's own" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_person_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _person_register(cl, "person_a@example.com");
        b = _person_register(cl, "person_b@example.com");

        seeded = _person_call(cl, a, "DevAddPerson", {"name": "Person-test Isolation Target"});
        person_id = str(seeded[0]["_jac_id"]);
        print(f"[person isolation] A seeded person_id={person_id}");

        a_view = _person_call(cl, a, "PersonDetail", {"person_id": person_id});
        print(f"[person isolation] A's own PersonDetail -> {a_view}");
        a_entry = a_view[0] as dict[str, any];
        assert len(a_view) == 1 and "error" not in a_entry, f"A must see its own person: {a_view}";

        b_view = _person_call(cl, b, "PersonDetail", {"person_id": person_id});
        print(f"[person isolation] B's PersonDetail on A's person -> {b_view}");
        assert b_view == [{"error": "not_found"}], f"B must never see A's person: {b_view}";

        b_brief = _person_call(cl, b, "Brief", {"person_id": person_id, "voice": False});
        assert b_brief == [{"error": "not_found"}], f"B's Brief on A's person must also be not_found: {b_brief}";

        # A's own Brief on a person with no evidence at all: falls back
        # without an LLM call (no evidence -> `fallback_recap` path, never
        # `spoken_brief`), voice off.
        a_brief = _person_call(cl, a, "Brief", {"person_id": person_id, "voice": False});
        assert len(a_brief) == 1;
        a_out = a_brief[0] as dict[str, any];
        print(f"[person isolation] A's own Brief (no evidence, voice off) -> {a_out}");
        assert a_out["fallback"];
        assert "Person-test Isolation Target" in str(a_out["text"]);
        assert a_out["voice_error"] == "voice_disabled";
        assert a_out["audio_b64"] == "";
        assert a_out["based_on"] == [];
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
