"""Wrappers for the "Meet your people" deck (SOH-231). OWNER: Person B.

Kept OUT of `components/api.cl.jac` on purpose (same idiom `api_import.cl.jac`
uses) — this screen's own swap point. `Capture`/`ConfirmPerson`/`ListPeople`
are all already live server-side (contracts/walkers.md), so this module calls
them directly with `root spawn` rather than adding a mock path; `mocks_on()`
(imported from `.api`) still gates the one place a deterministic stand-in is
cheap to give (the debrief capture itself), so `?mock=1` never spends a
Gemini call.
"""

import from .api { mocks_on, list_people }
import from .mocks.capture { mock_capture }
sv import from ..capture { Capture }

async def fake_delay_deck(ms: int) {
    await new(Promise, lambda(resolve: any, reject: any) { setTimeout(resolve, ms); });
}

"""`Knows.last_contact` (ISO-8601, or "") -> epoch ms, or -1 when empty/unparseable
(sorts to the back, same idiom `HomeView.cl.jac`'s `since_iso` follows)."""
def _last_contact_ms(last_contact: str) -> int {
    lc: str = (last_contact or "").strip();
    if not lc {
        return -1;
    }
    try {
        d: any = new(Date, lc);  # jac:ignore[W2001]
        t: any = d.getTime();  # jac:ignore[W2001]
        if isNaN(t) {  # jac:ignore[W2001]
            return -1;
        }
        return t as int;
    } except Exception as e {
        return -1;
    }
}

def _recency_key(p: dict) -> int {
    return _last_contact_ms((p["last_contact"] or "") as str);
}

"""Every proposed person from `list_people()`, most-recently-connected first
(by `Knows.last_contact`); rows with no last_contact keep their original order
and sort after every dated row. `person_ids`, when non-empty, restricts the
deck to just those ids (an in-progress import) — empty means every proposed
person account-wide (the Today trickle row)."""
async def:pub list_proposed_people(person_ids: list[str] = []) -> list[dict] {
    people: list[dict] = (await list_people()) as list[dict];
    proposed: list[dict] = [p for p in people if ((p["status"] or "") as str) == "proposed"];
    if person_ids {
        proposed = [p for p in proposed if ((p["_jac_id"] or "") as str) in person_ids];
    }
    dated: list[dict] = [];
    undated: list[dict] = [];
    for p in proposed {
        ms: int = _last_contact_ms((p["last_contact"] or "") as str);
        if ms >= 0 {
            dated.append(p);
        } else {
            undated.append(p);
        }
    }
    dated_sorted: list[dict] = sorted(dated, key=_recency_key, reverse=True);
    return dated_sorted + undated;
}

"""Capture(text, kind="debrief", person_id, how_met) -> the walker's one report
(contracts/walkers.md's Capture shape; `person_id` (SOH-231) attaches the
debrief to this known person instead of extracting a new one)."""
async def:pub capture_for_person(text: str, person_id: str, how_met: str = "") -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay_deck(300);
        out = mock_capture(text, "debrief");
        return out;
    }
    result = root spawn Capture(text=text, kind="debrief", person_id=person_id, how_met=how_met);
    if not result.reports {
        raise Exception("Capture returned no report");
    }
    out = result.reports[0];
    return out;
}
