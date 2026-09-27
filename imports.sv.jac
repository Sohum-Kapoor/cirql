"""Imports — LinkedIn export / phone contacts / vCard rows become proposed
people (SOH-180, server half of SOH-181). SOH-235: `ConfirmPeople` adds a
bulk "confirm all" — one call instead of `ConfirmPerson` once per row for a
300-row import. It shares `ConfirmPerson`'s exact per-person rule via the
extracted `confirm_one(me, p, how_met)`, so `ConfirmPerson`'s own behavior
is unchanged.

OWNER: Person A. See contracts/walkers.md for the exact report shapes.
Rows are parsed CLIENT-side (B's job); this module only ever sees
`list[dict]` rows shaped `{ name, org, title, how_met, email, phone,
location }` — unknown keys are ignored. SOH-216: `email`/`phone`/`location`
are now kept, stored on the user's own `Person` node (never crosses
accounts, same rule as every other contact field) — filled only when the
row has a value AND the target's existing field is still blank, same
fill-blank-on-reuse rule `org`/`title` already use.

Rules this file must obey (AGENTS.md):
  - Never guesses: an existing person with the same name (case-insensitive)
    is reused, not duplicated — same `[me ->:Knows:->]` lookup pattern as
    `capture.sv.jac`'s `resolve_person`, kept local here because the
    fill-blank-fields-on-reuse behavior on an exact-name match differs from
    `resolve_person`'s ambiguity/ties handling.
  - Every imported person carries provenance: one `Note(kind="import")` per
    `ImportPeople` call, with a `Mentions` edge from it to every person the
    call touches (new or reused).
  - SOH-226: a NEW `Knows` edge (the person wasn't already known) gets
    `last_contact=now` — display only, same as `capture.sv.jac`/`vision.sv.jac`/
    `handshake.sv.jac` — so a person imported a minute ago never reads as
    quiet 90+ days. An existing edge being enriched keeps its own
    `last_contact` untouched; this is not "relationships never decay" wiring,
    just the same display field every other capture path already sets.
  - No LLM in this module.
  - All walkers are `:priv`.

Node deletion (`jac guide jac-node-edge-patterns`): "Delete a node — cascades
to ALL its edges (in and out). Capture jid(n) BEFORE the del if you need to
report what was removed." `SkipPerson` deletes the Knows edge and the
Mentions edges explicitly first (per the contract's wording), then the
Person node itself — the explicit edge deletes make the intent obvious even
though the final `del p;` would cascade-delete any edges left over.
"""

import from jaclang { JacRuntime as Jac }
import from schema { Me, Person, Note, Knows, Mentions }
import from identity { refresh_person_tokens }
import from datetime { datetime }

# ---------------------------------------------------------------- row helpers

"""Read `row[key]` as a string; missing key, or a None value, is "".
Avoids `dict.get(key, default)` (E1054 on some dict shapes — AGENTS.md
gotcha); plain `if key in row` is unambiguous here."""
def row_str(row: dict[str, any], key: str) -> str {
    if key in row {
        val = row[key];
        if val is None {
            return "";
        }
        return str(val);
    }
    return "";
}

"""SOH-232: display-friendly source name for the import Note's text - the
raw `source` param ("csv"/"linkedin"/"paste"/"vcard", set by the client)
reads as broken product copy spliced into a sentence ("Imported 3 people
from csv."). Known sources get a proper display form; anything else passes
through unchanged."""
def source_display(source: str) -> str {
    low = (source or "").strip().lower();
    if low == "csv" {
        return "CSV";
    }
    if low == "linkedin" {
        return "LinkedIn";
    }
    if low == "paste" {
        return "a pasted list";
    }
    if low == "vcard" {
        return "a vCard file";
    }
    return source;
}

# ---------------------------------------------------------------- ImportPeople

walker:priv ImportPeople {
    """Get-or-create Me; create one `Note(kind="import")`; for every row
    with a non-empty stripped name (deduped within the batch by lowercase
    name, bounded at 500 rows), reuse an existing `[me ->:Knows:->]` person
    with the same lowercase name (filling blank org/title/email/phone/
    location, never changing status) or create a new
    `Person(status="proposed")` with a `Knows` edge `status="proposed"`.
    Every imported person gets one Mentions edge from the note. Reports one
    dict (contracts/walkers.md)."""
    has rows: list[dict[str, any]];
    has source: str = "csv";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if existing_me {
            me = existing_me[0];
        } else {
            me = (root ++> Me(name="me"))[0];
        }

        known: list[Person] = [me ->:Knows:->];
        known_by_key: dict[str, Person] = {};
        for p in known {
            known_by_key[p.name.strip().lower()] = p;
        }

        total = len(self.rows);
        bounded = self.rows[:500];
        overflow = self.rows[500:] if total > 500 else [];

        # First pass: validate + dedupe within the batch. No graph writes
        # yet — `n` (the note text) depends on how many rows survive this.
        seen_in_batch: list[str] = [];
        row_order: list[str] = [];
        row_data: dict[str, dict[str, any]] = {};
        skipped: list[dict[str, any]] = [];

        for row in bounded {
            raw_name = row_str(row, "name");
            name = raw_name.strip();
            if len(name) == 0 {
                skipped.append({"name": raw_name, "reason": "empty_name"});
                continue;
            }
            key = name.lower();
            if key in seen_in_batch {
                skipped.append({"name": raw_name, "reason": "duplicate_in_batch"});
                continue;
            }
            seen_in_batch.append(key);
            row_order.append(key);
            row_data[key] = row;
        }

        for row in overflow {
            skipped.append({"name": row_str(row, "name"), "reason": "over_limit"});
        }

        n = len(row_order);
        now = datetime.now().isoformat();
        note = (root ++> Note(text=f"Imported {n} people from {source_display(self.source)}", kind="import", captured_at=now))[0];

        imported: list[dict[str, any]] = [];

        for key in row_order {
            row = row_data[key];
            name = row_str(row, "name").strip();
            org = row_str(row, "org");
            title = row_str(row, "title");
            how_met = row_str(row, "how_met");
            email = row_str(row, "email");
            phone = row_str(row, "phone");
            location = row_str(row, "location");

            if key in known_by_key {
                p = known_by_key[key];
                if len(p.org.strip()) == 0 and len(org) > 0 {
                    p.org = org;
                }
                if len(p.title.strip()) == 0 and len(title) > 0 {
                    p.title = title;
                }
                if len(p.email.strip()) == 0 and len(email) > 0 {
                    p.email = email;
                }
                if len(p.phone.strip()) == 0 and len(phone) > 0 {
                    p.phone = phone;
                }
                if len(p.location.strip()) == 0 and len(location) > 0 {
                    p.location = location;
                }
                is_new = False;
            } else {
                effective_how_met = how_met.strip() or f"imported from {self.source}";
                # SOH-226: last_contact=now on the NEW edge only — a person imported
                # a minute ago must not read as quiet-90+-days (display-only, same
                # as every other capture path; nothing here lowers or ranks on it).
                p = (me +>:Knows(how_met=effective_how_met, status="proposed", source_note=jid(note), last_contact=now):+> Person(
                    name=name, org=org, title=title, status="proposed",
                    email=email, phone=phone, location=location
                ))[0];
                is_new = True;
            }

            note +>:Mentions(span=name):+> p;
            refresh_person_tokens(p);  # SOH-215
            imported.append({"person": p, "is_new": is_new});
        }

        report {
            "note_id": jid(note),
            "imported": imported,
            "skipped": skipped
        };
    }
}

# ---------------------------------------------------------------- ConfirmPerson / ConfirmPeople / SkipPerson

"""Shared per-person confirm logic — `ConfirmPerson` and `ConfirmPeople` both
call this once `p` has been resolved to a `[me ->:Knows:->]` person of the
caller. Sets `Person.status` and the matching `Knows` edge `status` both to
"confirmed"; `how_met` is overwritten only when non-empty. Returns
`{"ok": True}` on success, `{"ok": False}` when `p` is not actually one of
`me`'s `Knows` neighbors (no matching edge) — the same "not_found" condition
`ConfirmPerson` already reported, now centralized so behavior can't drift
between the single and bulk walkers."""
def confirm_one(me: Me, p: Person, how_met: str) -> dict[str, any] {
    matched = [edge me ->:Knows:-> p];
    if not matched {
        return {"ok": False};
    }
    e = matched[0] as Knows;

    p.status = "confirmed";
    e.status = "confirmed";
    if len(how_met.strip()) > 0 {
        e.how_met = how_met;
    }

    return {"ok": True};
}

walker:priv ConfirmPerson {
    """Confirm a proposed person after the swipe: `Person.status` and the
    `Knows` edge `status` both become "confirmed"; `how_met` is overwritten
    only when non-empty. Reports `[Person]`, or `[{error: "not_found"}]`
    when `person_id` is not a `[me ->:Knows:->]` person of the caller."""
    has person_id: str;
    has how_met: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"error": "not_found"};
            disengage;
        }
        me = existing_me[0];

        target: Person | None = None;
        for p in [me ->:Knows:->] {
            if jid(p) == self.person_id {
                target = p;
                break;
            }
        }

        if target is None {
            report {"error": "not_found"};
            disengage;
        }

        p = target as Person;
        outcome = confirm_one(me, p, self.how_met);
        if not (outcome["ok"] as bool) {
            report {"error": "not_found"};
            disengage;
        }

        report p;
    }
}

walker:priv ConfirmPeople {
    """Bulk confirm for the import "Confirm all" swipe (SOH-235) — one call
    instead of `ConfirmPerson` once per row. Same per-person rule as
    `ConfirmPerson` (via the shared `confirm_one`): `Person.status` and the
    matching `Knows` edge `status` both become "confirmed"; `how_met` is
    overwritten only when non-empty, applied identically to every id in the
    batch. Reports exactly one dict:
        { confirmed: list[str], not_found: list[str], count: int,
          skipped_over_limit: int (present only when person_ids > 1000) }
    `confirmed` preserves `person_ids` order and includes ids that were
    already confirmed (re-confirming is idempotent, not an error). An id
    that doesn't resolve, isn't readable, isn't owned by this root, or isn't
    a `[me ->:Knows:->]` person of the caller lands in `not_found` — nothing
    outside the caller's own graph is ever read or written (`jobj` never
    authorizes; `Jac.check_read_access` plus an exact owner-root match is
    the actual gate, same idiom as `reads.sv.jac`/`goals.sv.jac`). Ids past
    the first 1000 are not processed at all; their count rides on
    `skipped_over_limit`."""
    has person_ids: list[str];
    has how_met: str = "";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"confirmed": [], "not_found": self.person_ids, "count": 0};
            disengage;
        }
        me = existing_me[0];

        limit = 1000;
        ids = self.person_ids;
        over_limit = 0;
        if len(ids) > limit {
            over_limit = len(ids) - limit;
            ids = ids[:limit];
        }

        confirmed: list[str] = [];
        not_found: list[str] = [];

        for pid in ids {
            try {
                resolved = jobj(pid);
            } except Exception {
                resolved = None;
            }
            if resolved is None {
                not_found.append(pid);
                continue;
            }
            if not Jac.check_read_access(getattr(resolved, "__jac__")) {  # jac:ignore[E1053]
                not_found.append(pid);
                continue;
            }
            owner = str(getattr(resolved, "__jac__").root).replace("-", "");
            if owner != jid(root) {
                not_found.append(pid);
                continue;
            }
            if not isinstance(resolved, Person) {
                not_found.append(pid);
                continue;
            }
            p = resolved as Person;
            outcome = confirm_one(me, p, self.how_met);
            if not (outcome["ok"] as bool) {
                not_found.append(pid);
                continue;
            }
            confirmed.append(pid);
        }

        rep: dict[str, any] = {"confirmed": confirmed, "not_found": not_found, "count": len(confirmed)};
        if over_limit > 0 {
            rep["skipped_over_limit"] = over_limit;
        }
        report rep;
    }
}

"""Shared per-person skip logic (SOH-236) — `SkipPerson` and `SkipPeople`
both call this once `p` has been resolved to a `[me ->:Knows:->]` person of
the caller. Only a proposed person can be skipped: deletes the caller's
Knows edge to them, their Mentions edges, and the Person node itself.
Returns `{"ok": True}` on success, `{"ok": False, "reason": "not_found"}`
when `p` is not one of `me`'s `Knows` neighbors, or
`{"ok": False, "reason": "not_proposed"}` on an already-confirmed person —
the same two conditions `SkipPerson` already reported, now centralized so
behavior can't drift between the single and bulk walkers."""
def skip_one(me: Me, p: Person) -> dict[str, any] {
    matched = [edge me ->:Knows:-> p];
    if not matched {
        return {"ok": False, "reason": "not_found"};
    }
    if p.status != "proposed" {
        return {"ok": False, "reason": "not_proposed"};
    }

    for e in [edge me ->:Knows:-> p] {
        del e;
    }
    for e in [edge p <-:Mentions:<-] {
        del e;
    }
    del p;

    return {"ok": True};
}

walker:priv SkipPerson {
    """Only a proposed person can be skipped: deletes the caller's Knows
    edge to them, their Mentions edges, and the Person node itself.
    Reports `["skipped"]`; `[{error: "not_proposed"}]` on a confirmed
    person; `[{error: "not_found"}]` when `person_id` is unknown."""
    has person_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"error": "not_found"};
            disengage;
        }
        me = existing_me[0];

        target: Person | None = None;
        for p in [me ->:Knows:->] {
            if jid(p) == self.person_id {
                target = p;
                break;
            }
        }

        if target is None {
            report {"error": "not_found"};
            disengage;
        }

        p = target as Person;
        outcome = skip_one(me, p);
        if not (outcome["ok"] as bool) {
            report {"error": outcome["reason"] as str};
            disengage;
        }

        report "skipped";
    }
}

walker:priv SkipPeople {
    """Bulk skip for the import "skip all" swipe (SOH-236) — one call
    instead of `SkipPerson` once per row. Same per-person rule as
    `SkipPerson` (via the shared `skip_one`): only a proposed person can be
    skipped, deleting their Knows edge, Mentions edges, and the Person node
    itself. Reports exactly one dict:
        { skipped: list[str], not_found: list[str], count: int,
          skipped_over_limit: int (present only when person_ids > 1000) }
    `skipped` preserves `person_ids` order. An id that doesn't resolve,
    isn't readable, isn't owned by this root, isn't a `[me ->:Knows:->]`
    person of the caller, or is already confirmed (not "proposed") lands in
    `not_found` — nothing outside the caller's own graph is ever read or
    written (`jobj` never authorizes; `Jac.check_read_access` plus an exact
    owner-root match is the actual gate, same idiom as `ConfirmPeople`).
    Ids past the first 1000 are not processed at all; their count rides on
    `skipped_over_limit`."""
    has person_ids: list[str];
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"skipped": [], "not_found": self.person_ids, "count": 0};
            disengage;
        }
        me = existing_me[0];

        limit = 1000;
        ids = self.person_ids;
        over_limit = 0;
        if len(ids) > limit {
            over_limit = len(ids) - limit;
            ids = ids[:limit];
        }

        skipped: list[str] = [];
        not_found: list[str] = [];

        for pid in ids {
            try {
                resolved = jobj(pid);
            } except Exception {
                resolved = None;
            }
            if resolved is None {
                not_found.append(pid);
                continue;
            }
            if not Jac.check_read_access(getattr(resolved, "__jac__")) {  # jac:ignore[E1053]
                not_found.append(pid);
                continue;
            }
            owner = str(getattr(resolved, "__jac__").root).replace("-", "");
            if owner != jid(root) {
                not_found.append(pid);
                continue;
            }
            if not isinstance(resolved, Person) {
                not_found.append(pid);
                continue;
            }
            p = resolved as Person;
            outcome = skip_one(me, p);
            if not (outcome["ok"] as bool) {
                not_found.append(pid);
                continue;
            }
            skipped.append(pid);
        }

        rep: dict[str, any] = {"skipped": skipped, "not_found": not_found, "count": len(skipped)};
        if over_limit > 0 {
            rep["skipped_over_limit"] = over_limit;
        }
        report rep;
    }
}
