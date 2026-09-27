"""Imports — LinkedIn export / phone contacts / vCard rows become proposed
people (SOH-180, server half of SOH-181).

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
  - No LLM in this module.
  - All walkers are `:priv`.

Node deletion (`jac guide jac-node-edge-patterns`): "Delete a node — cascades
to ALL its edges (in and out). Capture jid(n) BEFORE the del if you need to
report what was removed." `SkipPerson` deletes the Knows edge and the
Mentions edges explicitly first (per the contract's wording), then the
Person node itself — the explicit edge deletes make the intent obvious even
though the final `del p;` would cascade-delete any edges left over.
"""

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
        note = (root ++> Note(text=f"Imported {n} people from {self.source}", kind="import", captured_at=now))[0];

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
                p = (me +>:Knows(how_met=effective_how_met, status="proposed", source_note=jid(note)):+> Person(
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

# ---------------------------------------------------------------- ConfirmPerson / SkipPerson

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
        target_edge: Knows | None = None;
        for p in [me ->:Knows:->] {
            if jid(p) == self.person_id {
                target = p;
                matched = [edge me ->:Knows:-> p];
                if matched {
                    target_edge = matched[0];
                }
                break;
            }
        }

        if target is None or target_edge is None {
            report {"error": "not_found"};
            disengage;
        }

        p = target as Person;
        e = target_edge as Knows;

        p.status = "confirmed";
        e.status = "confirmed";
        if len(self.how_met.strip()) > 0 {
            e.how_met = self.how_met;
        }

        report p;
    }
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
        if p.status != "proposed" {
            report {"error": "not_proposed"};
            disengage;
        }

        for e in [edge me ->:Knows:-> p] {
            del e;
        }
        for e in [edge p <-:Mentions:<-] {
            del e;
        }
        del p;

        report "skipped";
    }
}
