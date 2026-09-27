"""Mocks for bulk import (SOH-181; server half SOH-180 in `imports.sv.jac`).

`ImportPeople`, `ConfirmPerson`, `SkipPerson` — exact contract shapes
(contracts/walkers.md). State lives in `MOCK_IMPORT_STATE` so a Confirm or a
Skip against a person this call created survives across calls for the
session, same idiom as `mocks/circles.cl.jac`'s `MOCK_CIRCLES`.
"""

glob MOCK_IMPORT_STATE: dict[str, any] = {"people": {}, "next": 1};

"""Read `row[key]` as a string; missing key, or a None value, is "" — mirrors
`imports.sv.jac`'s `row_str` (avoids `dict.get(key, default)`, E1054 here too)."""
def _mock_row_str(row: dict[str, any], key: str) -> str {
    if key in row {
        val = row[key];
        if val is None {
            return "";
        }
        return str(val);
    }
    return "";
}

def _mock_drop_key(d: dict[str, any], key: str) -> dict[str, any] {
    out: dict[str, any] = {};
    for k in list(d.keys()) {
        if k != key {
            out[k] = d[k];
        }
    }
    return out;
}

"""ImportPeople(rows, source) -> { note_id, imported: [{person, is_new}], skipped: [{name, reason}] }.
Same dedupe-by-lowercase-name / reuse / 500-row-bound rules as the live walker."""
def:pub mock_import_people(rows: list[dict[str, any]], source: str = "csv") -> dict[str, any] {
    people: dict[str, any] = MOCK_IMPORT_STATE["people"] as dict[str, any];
    known_by_key: dict[str, any] = {};
    for pid in list(people.keys()) {
        p: dict[str, any] = people[pid] as dict[str, any];
        known_by_key[(p["name"] as str).strip().lower()] = p;
    }

    total: int = len(rows);
    bounded: list[dict[str, any]] = rows[:500];
    overflow: list[dict[str, any]] = rows[500:] if total > 500 else [];

    seen_in_batch: list[str] = [];
    row_order: list[str] = [];
    row_data: dict[str, any] = {};
    skipped: list[dict[str, any]] = [];

    for row in bounded {
        raw_name: str = _mock_row_str(row, "name");
        name: str = raw_name.strip();
        if len(name) == 0 {
            skipped.append({"name": raw_name, "reason": "empty_name"});
            continue;
        }
        key: str = name.lower();
        if key in seen_in_batch {
            skipped.append({"name": raw_name, "reason": "duplicate_in_batch"});
            continue;
        }
        seen_in_batch.append(key);
        row_order.append(key);
        row_data[key] = row;
    }

    for row in overflow {
        skipped.append({"name": _mock_row_str(row, "name"), "reason": "over_limit"});
    }

    imported: list[dict[str, any]] = [];
    next_id: int = MOCK_IMPORT_STATE["next"] as int;

    for key in row_order {
        row: dict[str, any] = row_data[key] as dict[str, any];
        name: str = _mock_row_str(row, "name").strip();
        org: str = _mock_row_str(row, "org");
        title: str = _mock_row_str(row, "title");
        how_met: str = _mock_row_str(row, "how_met");
        email: str = _mock_row_str(row, "email");

        if key in known_by_key {
            p: dict[str, any] = known_by_key[key] as dict[str, any];
            if len((p["org"] as str).strip()) == 0 and len(org) > 0 {
                p["org"] = org;
            }
            if len((p["title"] as str).strip()) == 0 and len(title) > 0 {
                p["title"] = title;
            }
            if len((p["email"] as str).strip()) == 0 and len(email) > 0 {
                p["email"] = email;
            }
            people[p["_jac_id"] as str] = p;
            imported.append({"person": p, "is_new": False});
        } else {
            pid: str = "mock-import-" + str(next_id);
            next_id = next_id + 1;
            effective_how_met: str = how_met.strip() or ("imported from " + source);
            p: dict[str, any] = {
                "_jac_id": pid, "name": name, "org": org, "title": title,
                "status": "proposed", "email": email, "phone": "", "location": "",
                "how_met": effective_how_met
            };
            people[pid] = p;
            known_by_key[key] = p;
            imported.append({"person": p, "is_new": True});
        }
    }

    MOCK_IMPORT_STATE["next"] = next_id;
    MOCK_IMPORT_STATE["people"] = people;

    return {
        "note_id": "mock-import-note-" + str(next_id),
        "imported": imported,
        "skipped": skipped
    };
}

"""ConfirmPerson(person_id, how_met) -> [Person] | [{error: "not_found"}]."""
def:pub mock_confirm_person(person_id: str, how_met: str = "") -> list[any] {
    people: dict[str, any] = MOCK_IMPORT_STATE["people"] as dict[str, any];
    if person_id not in people {
        return [{"error": "not_found"}];
    }
    p: dict[str, any] = people[person_id] as dict[str, any];
    p["status"] = "confirmed";
    if len(how_met.strip()) > 0 {
        p["how_met"] = how_met;
    }
    people[person_id] = p;
    MOCK_IMPORT_STATE["people"] = people;
    return [p];
}

"""ConfirmPeople(person_ids, how_met) -> { confirmed: [id], not_found: [id],
count: int } — mock always confirms every id it knows about (SOH-235)."""
def:pub mock_confirm_people(person_ids: list[str], how_met: str = "") -> dict[str, any] {
    people: dict[str, any] = MOCK_IMPORT_STATE["people"] as dict[str, any];
    confirmed: list[str] = [];
    not_found: list[str] = [];
    for pid in person_ids {
        if pid in people {
            p: dict[str, any] = people[pid] as dict[str, any];
            p["status"] = "confirmed";
            if len(how_met.strip()) > 0 {
                p["how_met"] = how_met;
            }
            people[pid] = p;
            confirmed.append(pid);
        } else {
            not_found.append(pid);
        }
    }
    MOCK_IMPORT_STATE["people"] = people;
    return {"confirmed": confirmed, "not_found": not_found, "count": len(confirmed)};
}

"""SkipPeople(person_ids) -> { skipped: [id], not_found: [id], count: int }
(SOH-236) — mock skips every id it knows about that's still `proposed`, same
idiom as `mock_confirm_people`."""
def:pub mock_skip_people(person_ids: list[str]) -> dict[str, any] {
    people: dict[str, any] = MOCK_IMPORT_STATE["people"] as dict[str, any];
    skipped: list[str] = [];
    not_found: list[str] = [];
    for pid in person_ids {
        if pid in people {
            p: dict[str, any] = people[pid] as dict[str, any];
            if (p["status"] as str) == "proposed" {
                people = _mock_drop_key(people, pid);
                skipped.append(pid);
            } else {
                not_found.append(pid);
            }
        } else {
            not_found.append(pid);
        }
    }
    MOCK_IMPORT_STATE["people"] = people;
    return {"skipped": skipped, "not_found": not_found, "count": len(skipped)};
}

"""SkipPerson(person_id) -> ["skipped"] | [{error: "not_proposed"|"not_found"}]."""
def:pub mock_skip_person(person_id: str) -> list[any] {
    people: dict[str, any] = MOCK_IMPORT_STATE["people"] as dict[str, any];
    if person_id not in people {
        return [{"error": "not_found"}];
    }
    p: dict[str, any] = people[person_id] as dict[str, any];
    if (p["status"] as str) != "proposed" {
        return [{"error": "not_proposed"}];
    }
    MOCK_IMPORT_STATE["people"] = _mock_drop_key(people, person_id);
    return ["skipped"];
}
