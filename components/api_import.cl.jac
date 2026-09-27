"""ImportPeople / ConfirmPerson / SkipPerson wrappers (SOH-181; server half
SOH-180, `imports.sv.jac`, already wired into `main.jac`).

Kept OUT of `components/api.cl.jac` on purpose — SOH-181's note said other
branches are appending to that file tonight; this module is this screen's own
swap point, same `mocks_on()` idiom as the rest of `api.cl.jac`. Live path:
`sv import` + `root spawn`, matching `capture`/`onboard_me`/`goal_rank`.
"""

import from .mocks.import { mock_import_people, mock_confirm_person, mock_skip_person, mock_confirm_people, mock_skip_people }
import from .api { mocks_on }
sv import from ..imports { ImportPeople, ConfirmPerson, SkipPerson, ConfirmPeople, SkipPeople }

glob IMPORT_DELAY_MS: int = 500;

async def fake_delay_import(ms: int) {
    await new(Promise, lambda(resolve: any, reject: any) { setTimeout(resolve, ms); });
}

"""The first report of a list, or None."""
def _first_import_any(rows: any) -> any {
    found: list[any] = (rows or []) as list[any];
    if len(found) > 0 {
        return found[0];
    }
    return None;
}

"""The first report of a list, cast to a dict — or `{ error: "no_report" }`."""
def _first_import_or_error(rows: any) -> dict {
    first: any = _first_import_any(rows);
    if first is None {
        return {"error": "no_report"};
    }
    return first as dict;
}

"""ImportPeople(rows, source) -> { note_id, imported: [{person, is_new}], skipped: [{name, reason}] }.
`rows` are already parsed client-side into `{ name, org, title, how_met, email }`
dicts (contracts/walkers.md) — this screen's paste/CSV/vCard parsers do that."""
async def:pub import_people(rows: list[dict], source: str = "csv") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay_import(IMPORT_DELAY_MS);
        out = mock_import_people(rows, source);
        return out;
    }
    result = root spawn ImportPeople(rows=rows, source=source);
    first: any = _first_import_any(result.reports);
    if first is None {
        raise Exception("ImportPeople returned no report");
    }
    out = first as dict;
    return out;
}

"""ConfirmPerson(person_id, how_met) -> Person | { error: "not_found" }."""
async def:pub confirm_person(person_id: str, how_met: str = "") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay_import(IMPORT_DELAY_MS);
        out = _first_import_or_error(mock_confirm_person(person_id, how_met));
        return out;
    }
    result = root spawn ConfirmPerson(person_id=person_id, how_met=how_met);
    out = _first_import_or_error(result.reports);
    return out;
}

"""ConfirmPeople(person_ids, how_met) -> { confirmed: [id], not_found: [id],
count: int, optional skipped_over_limit: int } (SOH-235; server half in
`imports.sv.jac`) — one round trip for the whole "Confirm all" batch instead
of one `ConfirmPerson` per row. Errors come back as `{ "error": ... }` so
`ImportPeople.cl.jac`'s `confirm_all` can fall back to the sequential loop."""
async def:pub confirm_people(person_ids: list[str], how_met: str = "") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay_import(IMPORT_DELAY_MS);
        out = mock_confirm_people(person_ids, how_met);
        return out;
    }
    result = root spawn ConfirmPeople(person_ids=person_ids, how_met=how_met);
    first: any = _first_import_any(result.reports);
    if first is None {
        return {"error": "no_report"};
    }
    out = first as dict;
    return out;
}

"""SkipPerson(person_id) -> { ok: true } | { error: "not_proposed"|"not_found" }.
The walker reports the plain string "skipped" on success (contracts/walkers.md);
normalized here to a dict so callers only ever check `out["error"]`."""
async def:pub skip_person(person_id: str) -> dict {
    first: any = None;
    if mocks_on() {
        await fake_delay_import(IMPORT_DELAY_MS);
        first = _first_import_any(mock_skip_person(person_id));
    } else {
        result = root spawn SkipPerson(person_id=person_id);
        first = _first_import_any(result.reports);
    }
    if first is None {
        return {"error": "no_report"};
    }
    if first == "skipped" {
        return {"ok": True};
    }
    return first as dict;
}

"""SkipPeople(person_ids) -> { skipped: [id], not_found: [id], count: int }
(SOH-236; server half landing in parallel — walker not necessarily live yet).
One round trip for "Skip the rest" instead of one `SkipPerson` per row.
`result`/`reps` are typed `any` here on purpose: `SkipPeople` may not exist
in `..imports` yet, and an unresolved `sv import` name makes every typed
access on its result Unknown to the checker (E1032) unless the intermediate
locals stay untyped, same pattern used to bring in a walker ahead of its
landing. Raises (unresolved name, no report) when the walker isn't there yet
or the call otherwise fails, so `ImportPeople.cl.jac`'s `skip_the_rest` can
fall back to the sequential `skip_person` loop, same idiom `confirm_people`
gives `confirm_all` for `ConfirmPeople`."""
async def:pub skip_people(person_ids: list[str]) -> dict {
    if mocks_on() {
        await fake_delay_import(IMPORT_DELAY_MS);
        return mock_skip_people(person_ids);
    }
    result: any = root spawn SkipPeople(person_ids=person_ids);
    reps: list[any] = result.reports as list[any];
    if len(reps) == 0 {
        raise Exception("SkipPeople returned no report");
    }
    return reps[0] as dict;
}
