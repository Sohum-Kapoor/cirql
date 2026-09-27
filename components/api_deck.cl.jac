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

"""The filter/sort core of `list_proposed_people`, pulled out so a caller that
already has a people list in hand (`Deck.cl.jac`'s `people` prop, fed from
whatever the shell already fetched — SOH-236) can skip the `list_people()`
round trip entirely and just re-run this on what it's got."""
def:pub filter_proposed_people(people: list[dict], person_ids: list[str] = []) -> list[dict] {
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

"""Every proposed person from `list_people()`, most-recently-connected first
(by `Knows.last_contact`); rows with no last_contact keep their original order
and sort after every dated row. `person_ids`, when non-empty, restricts the
deck to just those ids (an in-progress import) — empty means every proposed
person account-wide (the Today trickle row)."""
async def:pub list_proposed_people(person_ids: list[str] = []) -> list[dict] {
    people: list[dict] = (await list_people()) as list[dict];
    return filter_proposed_people(people, person_ids);
}

"""Capture(text, kind="debrief", person_id, how_met) -> the walker's one report
(contracts/walkers.md's Capture shape; `person_id` (SOH-231) attaches the
debrief to this known person instead of extracting a new one).

`confirm` (SOH-236, server half landing in parallel): when true, asks the ONE
`Capture` call to also confirm `person_id`, so `Deck.cl.jac`'s save doesn't
need a second `ConfirmPerson` round trip. Sent via a `**kwargs` spread (not a
named argument) because the currently-checked-in `Capture` walker may not
declare `confirm` yet — a named `confirm=True` kwarg the walker doesn't
declare is a compile-time error (E1052), where an unknown key in a spread
dict is only a RUNTIME one; that lets this module still `jac check` clean
before the server half lands, same "code against it, expect it to still 404"
shape `SkipPeople` uses in `api_import.cl.jac`. `out["confirmed"]` tells the
caller whether the combined call actually confirmed the person (`true` only
when the walker understood `confirm`); the caller (`Deck.cl.jac`) falls back
to its own `ConfirmPerson` call when it's `false`."""
async def:pub capture_for_person(text: str, person_id: str, how_met: str = "", confirm: bool = False) -> dict {
    out: dict = {};
    if mocks_on() {
        await fake_delay_deck(300);
        out = mock_capture(text, "debrief");
        out["confirmed"] = confirm and bool(person_id);
        return out;
    }
    if confirm and person_id {
        kwargs: dict[str, any] = {
            "text": text, "kind": "debrief", "person_id": person_id,
            "how_met": how_met, "confirm": True
        };
        try {
            combined = root spawn Capture(**kwargs);
            reps: list[any] = combined.reports as list[any];
            if len(reps) > 0 {
                out = reps[0] as dict;
                out["confirmed"] = True;
                return out;
            }
        } except Exception {
            # the walker doesn't understand `confirm` yet (or the call
            # otherwise failed) — fall through to the plain call below and
            # let the caller confirm separately.
            out = {};
        }
    }
    result = root spawn Capture(text=text, kind="debrief", person_id=person_id, how_met=how_met);
    if not result.reports {
        raise Exception("Capture returned no report");
    }
    out = result.reports[0] as dict;
    out["confirmed"] = False;
    return out;
}
