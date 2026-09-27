"""The one swap point between mocks and live walkers. OWNER: Person B.

Screens call these functions, never the mocks or `root spawn` directly. When a
walker lands on main, flip its branch to the live `root spawn` form below. Mocks
stay as a demo fallback (`USE_MOCKS`). `onboard_me` / `capture` return the walker's
single report; `goal_rank` / `list_people` return the whole report list — exactly
the shapes in contracts/walkers.md.

Dev-only override: `?mock=1` in the page URL routes every call here through the
mocks (no Gemini budget spent) even though `USE_MOCKS` ships False.
"""

import from .mocks.onboard { mock_onboardme }
import from .mocks.capture { mock_capture, mock_list_people }
import from .mocks.edits { mock_transcribe, mock_apply_correction }
import from ..lib.local_edits { local_put, local_view, local_drop }
import from .mocks.goalrank { mock_goalrank }
import from .mocks.goals { mock_list_goals, mock_set_goal, mock_close_goal }
import from .mocks.exchange {
    mock_gap_finder, mock_publish_card, mock_post_request, mock_list_my_requests,
    mock_decline_request, mock_claim_reveal, mock_list_incoming, mock_reply_to_request,
    mock_approve_reply, mock_opt_in, mock_reveal, mock_decline_reply
}
# LIVE: OnboardMe lives in onboard.sv.jac, Capture in capture.sv.jac, GoalRank in
# goals.sv.jac (not all in walkers.sv.jac as this comment used to assume).
sv import from ..onboard { OnboardMe }
sv import from ..capture { Capture }
sv import from ..goals { GoalRank, SetGoal, CloseGoal }
sv import from ..walkers { ListPeople, ListGoals }
sv import from ..gaps { GapFinder }
sv import from ..cards { PublishCard }
sv import from ..exchange {
    PostRequest, ListMyRequests, DeclineRequest, ClaimReveal, ListIncomingRequests,
    ReplyToRequest, ApproveReply, OptIn, Reveal, DeclineReply
}
sv import from ..voice { Transcribe }
sv import from ..noted { ApplyCorrection }
sv import from ..edits { UpdatePerson, UpdatePromise }
sv import from ..schema { Person }
# SOH-185 / SOH-192 (appended): graph view + badge photo capture.
import from .mocks.graph { mock_graph_view }
import from .mocks.photo { mock_capture_image }
sv import from ..reads { GraphView }
sv import from ..vision { CaptureImage }

# SOH-209: `UpdatePerson` / `UpdatePromise` are live (edits.sv.jac, SOH-166). Under
# ?mock=1 edits stay on this device (lib/local_edits) and the UI says so.
glob:pub UPDATE_PERSON_LIVE: bool = True,
     UPDATE_PROMISE_LIVE: bool = True;

glob USE_MOCKS: bool = False,
     MOCK_DELAY_MS: int = 600,
     MOCK_FAST_MS: int = 150;

"""True when mocks are on: the ship flag, or `?mock=1` in the URL (dev only)."""
def:pub mocks_on() -> bool {
    if USE_MOCKS {
        return True;
    }
    search: str = String(window.location.search);  # jac:ignore[W2001]
    return "mock=1" in search;
}

async def fake_delay(ms: int) {
    await new(Promise, lambda(resolve: any, reject: any) { setTimeout(resolve, ms); });
}

"""OnboardMe(about) -> { me, interests, goals, intents, card, note_id }"""
async def:pub onboard_me(about: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_onboardme(about);
        return out;
    }
    result = root spawn OnboardMe(about=about);
    if not result.reports {
        raise Exception("OnboardMe returned no report");
    }
    out = result.reports[0];
    return out;
}

"""Capture(text, kind, audio_ref, how_met) -> { note_id, people, facts, intents, promises, ties }.
`audio_ref` is Transcribe's (voice capture); "" for typed notes.
`how_met` (SOH-166, live): the Guided form's "how you met" line; when set, every NEW
Knows edge this capture creates carries it. Voice / Paste send ""."""
async def:pub capture(text: str, kind: str, audio_ref: str = "", how_met: str = "") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_capture(text, kind);
        return out;
    }
    result = root spawn Capture(text=text, kind=kind, audio_ref=audio_ref, how_met=how_met);
    if not result.reports {
        raise Exception("Capture returned no report");
    }
    out = result.reports[0];
    return out;
}

# ---------------------------------------------------------------- voice + corrections (SOH-168 / SOH-209)

"""Transcribe(audio_b64, mime) -> { transcript, audio_ref, duration_ms, error }.
`error` is "" | "no_key" | "too_large" | "read_failed" | "stt_<code>" | …; the
audio is kept server-side (audio_ref) whenever it was saved."""
async def:pub transcribe(audio_b64: str, mime: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_transcribe(audio_b64, mime);
        return out;
    }
    result = root spawn Transcribe(audio_b64=audio_b64, mime=mime);
    out = _first(result, "Transcribe") as dict;
    return out;
}

"""ApplyCorrection(person_id, text, replace_fact_id, kind) -> { fact } | { intent } | { error }.
kind "fact" + replace_fact_id: the old fact goes stale server-side (kept, never deleted)."""
async def:pub apply_correction(person_id: str, text: str, replace_fact_id: str = "", kind: str = "fact") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_apply_correction(person_id, text, replace_fact_id, kind);
        return out;
    }
    result = root spawn ApplyCorrection(person_id=person_id, text=text, replace_fact_id=replace_fact_id, kind=kind);
    out = _first(result, "ApplyCorrection") as dict;
    return out;
}

"""UpdatePerson(person_id, name, org, title, how_met) -> { person, local } | { error }.
Live: only non-empty fields overwrite; `how_met` lands on the caller's Knows edge
(not on the Person report, so it is also remembered locally for display)."""
async def:pub update_person(person: dict, name: str, org: str, title: str, how_met: str) -> dict {
    pid: str = (person["_jac_id"] or "") as str;
    if mocks_on() or not UPDATE_PERSON_LIVE {
        local_put("person", pid, {"name": name, "org": org, "title": title, "how_met": how_met});
        return {"person": local_view("person", person), "local": True};
    }
    result = root spawn UpdatePerson(person_id=pid, name=name, org=org, title=title, how_met=how_met);
    out: dict = _first(result, "UpdatePerson") as dict;
    if out["error"] {
        return out;
    }
    local_drop("person", pid);
    if how_met {
        local_put("person", pid, {"how_met": how_met});
    }
    return {"person": out, "local": False};
}

"""UpdatePromise(promise_id, text, due) -> { promise, local } | { error }."""
async def:pub update_promise(promise: dict, text: str, due: str) -> dict {
    prid: str = (promise["_jac_id"] or "") as str;
    if mocks_on() or not UPDATE_PROMISE_LIVE {
        local_put("promise", prid, {"text": text, "due": due});
        return {"promise": local_view("promise", promise), "local": True};
    }
    result = root spawn UpdatePromise(promise_id=prid, text=text, due=due);
    out: dict = _first(result, "UpdatePromise") as dict;
    if out["error"] {
        return out;
    }
    local_drop("promise", prid);
    return {"promise": out, "local": False};
}

"""GoalRank(goal_id) -> [{ person, label, strength, reason, evidence, days_since_contact, opener }]"""
async def:pub goal_rank(goal_id: str, refresh: bool = False) -> list[dict] {
    rows: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        rows = mock_goalrank(goal_id);
        return rows;
    }
    result = root spawn GoalRank(goal_id=goal_id, refresh=refresh);
    rows = result.reports;
    return rows;
}

"""ListPeople() -> [Person]. In mock mode, the people mock captures produced."""
async def:pub list_people() -> list[Person] {
    found: list[Person] = [];
    if mocks_on() {
        found = mock_list_people() as list[Person];
        return found;
    }
    result = root spawn ListPeople();
    found = result.reports;
    return found;
}

"""ListGoals() -> [Goal] (every goal, with `active`; the caller filters)."""
async def:pub list_goals() -> list[dict] {
    goals: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        goals = mock_list_goals();
        return goals;
    }
    result = root spawn ListGoals();
    goals = result.reports as list[dict];
    return goals;
}

"""SetGoal(text) -> the Goal (created, or reactivated when the text matches an
existing goal). Every other goal is deactivated server-side. Switching goals is
`set_goal(<that goal's text>)`."""
async def:pub set_goal(text: str) -> dict {
    goal: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        goal = mock_set_goal(text);
        return goal;
    }
    result = root spawn SetGoal(text=text);
    if not result.reports {
        raise Exception("SetGoal returned no report");
    }
    goal = result.reports[0] as dict;
    return goal;
}

"""CloseGoal(goal_id) -> "closed" | "not_found". Sets active False, never deletes."""
async def:pub close_goal(goal_id: str) -> str {
    status: str = "";
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        status = mock_close_goal(goal_id);
        return status;
    }
    result = root spawn CloseGoal(goal_id=goal_id);
    status = (result.reports[0] if result.reports else "not_found") as str;
    return status;
}

# ---------------------------------------------------------------- Exchange (SOH-172)
# Walkers report `{ error: "no_card" | "not_found" | "forbidden" | "invalid_state" }`
# instead of raising; these helpers return that dict as-is (callers check
# `out["error"]`) and raise only when the call itself fails or reports nothing.

"""The walker's first report, or raise when it reported nothing."""
def _first(result: any, name: str) -> any {
    if not result.reports {
        raise Exception(name + " returned no report");
    }
    return result.reports[0];
}

"""GapFinder(goal_id) -> [{ kind, why_needed, suggested_need }]; [] = no gap."""
async def:pub gap_finder(goal_id: str) -> list[dict] {
    rows: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        rows = mock_gap_finder(goal_id);
        return rows;
    }
    result = root spawn GapFinder(goal_id=goal_id);
    rows = result.reports as list[dict];
    return rows;
}

"""PublishCard(name, headline, about, visibility="handshake_only") -> Card.
Only called when PostRequest / ReplyToRequest report no_card (the user has no
Card yet, e.g. they skipped OnboardMe). handshake_only: the card exists so the
Exchange can use its handle, but it is not granted to anyone."""
async def:pub publish_card(name: str, headline: str, about: str) -> dict {
    card: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        card = mock_publish_card(name, headline, about);
        return card;
    }
    result = root spawn PublishCard(name=name, headline=headline, about=about, visibility="handshake_only");
    card = _first(result, "PublishCard") as dict;
    return card;
}

"""PostRequest(need, about_line) -> IntroRequest | { error: "no_card" }."""
async def:pub post_request(need: str, about_line: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_post_request(need, about_line);
        return out;
    }
    result = root spawn PostRequest(need=need, about_line=about_line);
    out = _first(result, "PostRequest") as dict;
    return out;
}

"""ListMyRequests() -> [{ request: IntroRequest, replies: [ReplyView] }]."""
async def:pub list_my_requests() -> list[dict] {
    rows: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_my_requests();
        return rows;
    }
    result = root spawn ListMyRequests();
    rows = result.reports as list[dict];
    return rows;
}

"""DeclineRequest(request_id) -> "declined" | error code."""
async def:pub decline_request(request_id: str) -> str {
    out: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_decline_request(request_id);
        return out as str;
    }
    result = root spawn DeclineRequest(request_id=request_id);
    out = _first(result, "DeclineRequest");
    if out == "declined" {
        return "declined";
    }
    return ((out["error"] or "failed") as str) if out else "failed";
}

"""ClaimReveal(reply_id) -> { person, card, intro_draft } | { error }."""
async def:pub claim_reveal(reply_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_claim_reveal(reply_id);
        return out;
    }
    result = root spawn ClaimReveal(reply_id=reply_id);
    out = _first(result, "ClaimReveal") as dict;
    return out;
}

"""ListIncomingRequests() -> [IntroRequest] from others, not yet answered by me."""
async def:pub list_incoming_requests() -> list[dict] {
    rows: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_incoming();
        return rows;
    }
    result = root spawn ListIncomingRequests();
    rows = result.reports as list[dict];
    return rows;
}

"""ReplyToRequest(request_id) -> ReplyView | { error }. Scores MY graph only."""
async def:pub reply_to_request(request_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_reply_to_request(request_id);
        return out;
    }
    result = root spawn ReplyToRequest(request_id=request_id);
    out = _first(result, "ReplyToRequest") as dict;
    return out;
}

"""ApproveReply(reply_id) -> ReplyView (approved) | { error }."""
async def:pub approve_reply(reply_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_approve_reply(reply_id);
        return out;
    }
    result = root spawn ApproveReply(reply_id=reply_id);
    out = _first(result, "ApproveReply") as dict;
    return out;
}

"""OptIn(reply_id) -> { reply: ReplyView, opt_in_draft } | { error }."""
async def:pub opt_in(reply_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_opt_in(reply_id);
        return out;
    }
    result = root spawn OptIn(reply_id=reply_id);
    out = _first(result, "OptIn") as dict;
    return out;
}

"""Reveal(reply_id) -> { reply: ReplyView, revealed_card_handle } | { error }."""
async def:pub reveal(reply_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_reveal(reply_id);
        return out;
    }
    result = root spawn Reveal(reply_id=reply_id);
    out = _first(result, "Reveal") as dict;
    return out;
}

"""DeclineReply(reply_id) -> "declined" | error code."""
async def:pub decline_reply(reply_id: str) -> str {
    out: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_decline_reply(reply_id);
        return out as str;
    }
    result = root spawn DeclineReply(reply_id=reply_id);
    out = _first(result, "DeclineReply");
    if out == "declined" {
        return "declined";
    }
    return ((out["error"] or "failed") as str) if out else "failed";
}

# ---------------------------------------------------------------- Person sheet + Today (SOH-207 / SOH-187)
# PersonDetail / Brief land from the parallel SOH-207 server branch (person.sv.jac).
# Until that merges, `sv import from ..person` would not resolve, so those two go
# through the runtime's string-named `jacSpawn` (same POST /walker/<Name> call);
# flip them to `sv import` + `root spawn` once person.sv.jac is on main.
import from "@jac/runtime" { jacSpawn }
import from .mocks.person {
    mock_person_detail, mock_brief, mock_list_promises, mock_complete_promise,
    mock_draft_follow_up, mock_forget, mock_update_person, mock_archive_person
}
sv import from ..reads { ListPromises, CompletePromise }
sv import from ..drafts { DraftFollowUp }
sv import from ..forget { Forget }

"""The first report of a list, or `{ error: "no_report" }`."""
def _first_or_error(rows: any) -> dict {
    found: list[dict] = (rows or []) as list[dict];
    if len(found) > 0 {
        return found[0];
    }
    return {"error": "no_report"};
}

"""PersonDetail(person_id) -> { person, how_met, knows_status, last_contact, relevance,
facts, intents, promises, notes, reported_by, card_handle } | { error: "not_found" }."""
async def:pub person_detail(person_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_person_detail(person_id));
        return out;
    }
    data = await jacSpawn("PersonDetail", "", {"person_id": person_id});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""Brief(person_id, voice) -> { person_id, text, audio_b64, mime, based_on, fallback, voice_error }."""
async def:pub brief(person_id: str, voice: bool = True) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = _first_or_error(mock_brief(person_id, voice));
        return out;
    }
    data = await jacSpawn("Brief", "", {"person_id": person_id, "voice": voice});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""ListPromises() -> [{ promise, to: Person | null, source_note_id, span }], open first."""
async def:pub list_promises() -> list[dict] {
    rows: list[dict] = [];
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_promises();
        return rows;
    }
    result = root spawn ListPromises();
    rows = result.reports as list[dict];
    return rows;
}

"""CompletePromise(promise_id, done) -> Promise | { error: "not_found" }."""
async def:pub complete_promise(promise_id: str, done: bool = True) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_complete_promise(promise_id, done));
        return out;
    }
    result = root spawn CompletePromise(promise_id=promise_id, done=done);
    out = _first_or_error(result.reports);
    return out;
}

"""DraftFollowUp(person_id, intent) -> { person_id, draft, based_on, fallback } | { error }.
A draft only — nothing sends."""
async def:pub draft_follow_up(person_id: str, intent: str = "") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = _first_or_error(mock_draft_follow_up(person_id, intent));
        return out;
    }
    result = root spawn DraftFollowUp(person_id=person_id, intent=intent);
    out = _first_or_error(result.reports);
    return out;
}

"""Forget(id) -> { deleted, id, retracted } | { error: "not_found" }. The Note is never deleted."""
async def:pub forget(node_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_forget(node_id));
        return out;
    }
    result = root spawn Forget(id=node_id);
    out = _first_or_error(result.reports);
    return out;
}

# ---------------------------------------------------------------- person sheet contact + archive (SOH-222)
# UpdatePerson's contact-field extension and ArchivePerson are new/changed shapes
# not on main yet (contracts/walkers.md appended, not yet built by A). Same
# "may not be on main yet" pattern as PersonDetail/Brief above: call by name
# through jacSpawn so this renders under `?mock=1` today and picks the live
# walker up the moment it exists, with no client change.

"""UpdatePerson(person_id, name, org, title, how_met, email, phone, location,
links: list[str]) -> [Person] | [{ error: "not_found" }]. Only NON-EMPTY
(stripped) args overwrite a field (same rule as the live 4-field form above);
`links` overwrites only when the caller sent a non-empty list."""
async def:pub update_person_contact(
    person_id: str, name: str, org: str, title: str, how_met: str,
    email: str, phone: str, location: str, links: list[str]
) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(
            mock_update_person(person_id, name, org, title, how_met, email, phone, location, links)
        );
        return out;
    }
    try {
        data = await jacSpawn(
            "UpdatePerson", "",
            {
                "person_id": person_id, "name": name, "org": org, "title": title, "how_met": how_met,
                "email": email, "phone": phone, "location": location, "links": links
            }
        );
        out = _first_or_error(data["reports"] if data else []);
    } except Exception {
        out = {"error": "failed"};
    }
    return out;
}

"""ArchivePerson(person_id) -> [Person] | [{ error: "not_found" }]. Soft delete:
`Person.archived = true`, hidden from lists/rankings, restorable from Settings —
unlike Forget, never retracts facts/intents/promises/edges."""
async def:pub archive_person(person_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_archive_person(person_id));
        return out;
    }
    try {
        data = await jacSpawn("ArchivePerson", "", {"person_id": person_id});
        out = _first_or_error(data["reports"] if data else []);
    } except Exception {
        out = {"error": "failed"};
    }
    return out;
}

# ---------------------------------------------------------------- Graph + photo (SOH-185/192)

"""GraphView(goal_id) -> { nodes: [{ id, kind, label, status, org, title }],
edges: [{ from, to, kind, label, strength }] }. `goal_id` "" = the active goal."""
async def:pub graph_view(goal_id: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_graph_view(goal_id);
        return out;
    }
    result = root spawn GraphView(goal_id=goal_id);
    out = _first(result, "GraphView") as dict;
    return out;
}

"""CaptureImage(image_b64, mime) -> the Capture report + { photo_ref, read:
{ name, org, title, email, phone, links, raw_text }, fallback, error }."""
async def:pub capture_image(image_b64: str, mime: str) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_capture_image(image_b64, mime);
        return out;
    }
    result = root spawn CaptureImage(image_b64=image_b64, mime=mime);
    out = _first(result, "CaptureImage") as dict;
    return out;
}

# ---------------------------------------------------------------- Settings data (SOH-222)
# `ExportGraph` is live (export.sv.jac, SOH-210) — `root spawn` below. `ListArchived` /
# `RestorePerson` / `DeleteMyData` land from a parallel server branch; until merged,
# go through `jacSpawn` (same POST /walker/<Name> call as PersonDetail/Brief above) —
# flip to `sv import` + `root spawn` once that branch is on main.
import from .mocks.data { mock_export_graph, mock_list_archived, mock_restore_person, mock_delete_my_data }
sv import from ..export { ExportGraph }

"""ExportGraph() -> the caller's whole graph as one JSON dict (contracts/walkers.md):
{ exported_at, me, goals, card, people, knows, reported, facts, intents, promises,
notes, counts: {people, facts, intents, promises, notes}, truncated }."""
async def:pub export_graph() -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = mock_export_graph();
        return out;
    }
    result = root spawn ExportGraph();
    out = _first(result, "ExportGraph") as dict;
    return out;
}

"""ListArchived() -> [Person] (archived == True), restorable."""
async def:pub list_archived() -> list[dict] {
    rows: list[dict] = [];
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_archived();
        return rows;
    }
    data = await jacSpawn("ListArchived", "", {});
    rows = (data["reports"] if data else []) as list[dict];
    return rows;
}

"""RestorePerson(person_id) -> [Person] (remaining archived people, after restoring this one)."""
async def:pub restore_person(person_id: str) -> list[dict] {
    rows: list[dict] = [];
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_restore_person(person_id);
        return rows;
    }
    data = await jacSpawn("RestorePerson", "", {"person_id": person_id});
    rows = (data["reports"] if data else []) as list[dict];
    return rows;
}

"""DeleteMyData(confirm) -> { deleted: {people, facts, intents, promises, notes,
goals, cards, circles, events}, ok } | { error }. Nothing recoverable after this —
the export is the only copy."""
async def:pub delete_my_data(confirm: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_DELAY_MS);
        out = mock_delete_my_data(confirm);
        return out;
    }
    data = await jacSpawn("DeleteMyData", "", {"confirm": confirm});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}
# ---------------------------------------------------------------- Circles + Events (SOH-222 A4)
# CreateCircle/RenameCircle/DeleteCircle/AddToCircle/RemoveFromCircle/ListCircles and
# CreateEvent/ListEvents/AddToEvent/RemoveFromEvent/EventPeople/UpdateEvent live on a
# parallel server branch (not on main yet) — call by name via `jacSpawn` (see
# `person_detail` above) until they land, then flip to `sv import` + `root spawn`.
# `list_people_scoped` reuses the same walker `list_people()` calls once its
# circle_id/event_id/include_archived params land on `ListPeople`; it also goes
# through jacSpawn for now so an unmatched arity here can't break the typed
# `sv import` of `ListPeople` used by `list_people()` above.
import from .mocks.circles {
    mock_create_circle, mock_rename_circle, mock_delete_circle, mock_add_to_circle,
    mock_remove_from_circle, mock_list_circles, mock_create_event, mock_update_event,
    mock_list_events, mock_add_to_event, mock_remove_from_event, mock_event_people,
    mock_list_people_scoped
}

"""CreateCircle(name) -> Circle | { error: "exists" }."""
async def:pub create_circle(name: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_create_circle(name));
        return out;
    }
    data = await jacSpawn("CreateCircle", "", {"name": name});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""RenameCircle(circle_id, name) -> Circle | { error: "not_found" }."""
async def:pub rename_circle(circle_id: str, name: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_rename_circle(circle_id, name));
        return out;
    }
    data = await jacSpawn("RenameCircle", "", {"circle_id": circle_id, "name": name});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""DeleteCircle(circle_id) -> { ok: true } | { error: "not_found" }. The circle
label only — people in it are untouched."""
async def:pub delete_circle(circle_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_delete_circle(circle_id));
        return out;
    }
    data = await jacSpawn("DeleteCircle", "", {"circle_id": circle_id});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""AddToCircle(person_id, circle_id) -> { ok: true } | { error: "not_found" }."""
async def:pub add_to_circle(person_id: str, circle_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_add_to_circle(person_id, circle_id));
        return out;
    }
    data = await jacSpawn("AddToCircle", "", {"person_id": person_id, "circle_id": circle_id});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""RemoveFromCircle(person_id, circle_id) -> { ok: true } | { error }."""
async def:pub remove_from_circle(person_id: str, circle_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_remove_from_circle(person_id, circle_id));
        return out;
    }
    data = await jacSpawn("RemoveFromCircle", "", {"person_id": person_id, "circle_id": circle_id});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""ListCircles() -> [{ circle: Circle, count: int }]."""
async def:pub list_circles() -> list[dict] {
    rows: list[dict] = [];
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_circles();
        return rows;
    }
    data = await jacSpawn("ListCircles", "", {});
    rows = (data["reports"] if data else []) as list[dict];
    return rows;
}

"""CreateEvent(name, date="", location="") -> Event."""
async def:pub create_event(name: str, date: str = "", location: str = "") -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_create_event(name, date, location));
        return out;
    }
    data = await jacSpawn("CreateEvent", "", {"name": name, "date": date, "location": location});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""UpdateEvent(event_id, name, date, location) -> Event | { error: "not_found" }."""
async def:pub update_event(event_id: str, name: str, date: str, location: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_update_event(event_id, name, date, location));
        return out;
    }
    data = await jacSpawn("UpdateEvent", "", {"event_id": event_id, "name": name, "date": date, "location": location});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""ListEvents() -> [{ event: Event, count: int }]. The caller sorts newest-date-first."""
async def:pub list_events() -> list[dict] {
    rows: list[dict] = [];
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_events();
        return rows;
    }
    data = await jacSpawn("ListEvents", "", {});
    rows = (data["reports"] if data else []) as list[dict];
    return rows;
}

"""AddToEvent(person_id, event_id) -> { ok: true } | { error: "not_found" }."""
async def:pub add_to_event(person_id: str, event_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_add_to_event(person_id, event_id));
        return out;
    }
    data = await jacSpawn("AddToEvent", "", {"person_id": person_id, "event_id": event_id});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""RemoveFromEvent(person_id, event_id) -> { ok: true } | { error }."""
async def:pub remove_from_event(person_id: str, event_id: str) -> dict {
    out: dict = {};
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        out = _first_or_error(mock_remove_from_event(person_id, event_id));
        return out;
    }
    data = await jacSpawn("RemoveFromEvent", "", {"person_id": person_id, "event_id": event_id});
    out = _first_or_error(data["reports"] if data else []);
    return out;
}

"""EventPeople(event_id) -> [Person] — who I met there."""
async def:pub event_people(event_id: str) -> list[dict] {
    rows: list[dict] = [];
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_event_people(event_id);
        return rows;
    }
    data = await jacSpawn("EventPeople", "", {"event_id": event_id});
    rows = (data["reports"] if data else []) as list[dict];
    return rows;
}

"""ListPeople(circle_id="", event_id="", include_archived=False) -> [Person], scoped."""
async def:pub list_people_scoped(circle_id: str = "", event_id: str = "", include_archived: bool = False) -> list[dict] {
    rows: list[dict] = [];
    data: any = None;
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        rows = mock_list_people_scoped(circle_id, event_id, include_archived);
        return rows;
    }
    data = await jacSpawn("ListPeople", "", {"circle_id": circle_id, "event_id": event_id, "include_archived": include_archived});
    rows = (data["reports"] if data else []) as list[dict];
    return rows;
}
