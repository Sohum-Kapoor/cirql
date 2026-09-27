"""edits.sv.jac — UpdatePerson and UpdatePromise (SOH-166, B's "Needs A").

OWNER: Person A. See contracts/walkers.md for the exact report shapes and
AGENTS.md for the working rules this file must obey:
  - Both walkers are `:priv` (own-root only, JWT required).
  - Only NON-EMPTY (stripped) args overwrite a field; an omitted/blank arg
    leaves the existing value alone. Exception: `links` (SOH-216) REPLACES
    the whole list when the caller passes a non-empty list — there is no
    per-item "blank means unchanged" for a list argument.
  - `UpdatePerson` never touches `Person.status`, `Knows.last_contact`, or
    any edge other than the caller's own `Knows` edge to that person (and
    only its `how_met` field, at that).
  - SOH-216 adds contact fields (`email`, `phone`, `links`, `location`) to
    `UpdatePerson`, all optional, all landing on the `Person` node itself
    (never crosses accounts — same rule as `org`/`title`). After any of
    them changes, `refresh_person_tokens(p)` (SOH-215's `identity.sv.jac`)
    is called IF that module exists on `main` at rebase time; it doesn't
    yet, so this is a `# TODO(SOH-215)` for now.
  - No `by llm` in this module.

`person_id` is resolved directly among `[me ->:Knows:->]` — same idiom
`person.sv.jac`'s `PersonDetail` and `drafts.sv.jac`'s `DraftFollowUp` use: a
person only ever reaches that traversal if this account's own Capture/
Import/Confirm flow created the Knows edge, which is exactly "belongs to the
caller". A person id that isn't found there (unknown, or belongs to someone
else's graph) reports `not_found`. The lookup+mutate logic is pulled out
into `update_person_for(me, ...)` — same reason `person.sv.jac`'s
`person_detail_for` takes `me`/`person` as arguments rather than resolving
"the" `Me` via `[root --> [?:Me]][0]` inside the helper itself: that
resolution is ambiguous once more than one test (in this file, or an
earlier `jac test` run) has created a `Me` under the shared, persisted test
root, so `edits.test.jac`'s success-path tests call `update_person_for`
directly on a `me`/`p` pair they just built, never through
`root spawn UpdatePerson(...)`.

`promise_id` ownership uses `reads.sv.jac`'s `my_node` helper (imported, not
reimplemented) — the same jobj/check_read_access/owner_root idiom
`CompletePromise` uses: resolves ANY id but only returns a node that is both
readable AND owned by the caller's own root. `my_node` doesn't depend on
which `Me` exists, so `UpdatePromise`'s tests run through
`root spawn UpdatePromise(...)` directly without that ambiguity.
"""

import from schema { Me, Person, Promise, Knows }
import from reads { my_node }
import from identity { refresh_person_tokens }

def _not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

# ---------------------------------------------------------------- UpdatePerson

"""Find `person_id` among `[me ->:Knows:->]`; on a match, overwrite every
non-empty (stripped) of `name`/`org`/`title`/`email`/`phone`/`location` on
the `Person` node, REPLACE `links` when the caller passes a non-empty list,
and set `how_met` on the caller's own `Knows` edge to them, then return the
(mutated, same) `Person`. Never touches `status`/`last_contact`/any other
edge. Returns `{"error": "not_found"}` when `person_id` doesn't match."""
def update_person_for(
    me: Me, person_id: str, name: str, org: str, title: str, how_met: str,
    email: str = "", phone: str = "", links: list[str] | None = None, location: str = ""
) -> object {
    effective_links: list[str] = links if links is not None else [];
    target: Person | None = None;
    target_edge: Knows | None = None;
    for p in [me ->:Knows:->] {
        if jid(p) == person_id {
            target = p;
            matched = [edge me ->:Knows:-> p];
            if matched {
                target_edge = matched[0];
            }
            break;
        }
    }

    if target is None {
        return _not_found();
    }

    p = target as Person;

    stripped_name = name.strip();
    if stripped_name {
        p.name = stripped_name;
    }
    stripped_org = org.strip();
    if stripped_org {
        p.org = stripped_org;
    }
    stripped_title = title.strip();
    if stripped_title {
        p.title = stripped_title;
    }

    stripped_email = email.strip();
    if stripped_email {
        p.email = stripped_email;
    }
    stripped_phone = phone.strip();
    if stripped_phone {
        p.phone = stripped_phone;
    }
    if effective_links {
        p.links = effective_links;
    }
    stripped_location = location.strip();
    if stripped_location {
        p.location = stripped_location;
    }
    refresh_person_tokens(p);  # SOH-215: name/org/contact changes re-derive the blinded tokens

    stripped_how_met = how_met.strip();
    if stripped_how_met and target_edge is not None {
        e = target_edge as Knows;
        e.how_met = stripped_how_met;
    }

    return p;
}

walker:priv UpdatePerson {
    """Overwrite non-empty (stripped) fields on one of the caller's own
    people. `name`/`org`/`title`/`email`/`phone`/`location` land on the
    `Person` node (`links` REPLACES when the caller passes a non-empty
    list); `how_met` lands on the caller's own `Knows` edge to that person.
    Never touches `status`, `last_contact`, or any other edge. Reports
    `[Person]`, or `[{error: "not_found"}]` when `person_id` isn't one of
    the caller's own `[me ->:Knows:->]` people."""
    has person_id: str;
    has name: str = "";
    has org: str = "";
    has title: str = "";
    has how_met: str = "";
    has email: str = "";
    has phone: str = "";
    has links: list[str] = [];
    has location: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            report _not_found();
            disengage;
        }
        me = existing_me[0];

        result = update_person_for(
            me, self.person_id, self.name, self.org, self.title, self.how_met,
            self.email, self.phone, self.links, self.location
        );
        report result;
    }
}

# ---------------------------------------------------------------- UpdatePromise

walker:priv UpdatePromise {
    """Overwrite non-empty (stripped) `text`/`due` on one of the caller's own
    Promises. Ownership check identical to `reads.sv.jac`'s
    `CompletePromise` (`my_node`). Reports `[Promise]`, or
    `[{error: "not_found"}]` when `promise_id` doesn't resolve to a Promise
    owned by the caller."""
    has promise_id: str;
    has text: str = "";
    has due: str = "";
    has reports: list[object] = [];

    can run with Root entry {
        n = my_node(self.promise_id);
        if n is None or not isinstance(n, Promise) {
            report _not_found();
            disengage;
        }
        pr = n as Promise;

        text = self.text.strip();
        if text {
            pr.text = text;
        }
        due = self.due.strip();
        if due {
            pr.due = due;
        }

        report pr;
    }
}

# ---------------------------------------------------------------- DevAddPromise (test seeding)

walker:priv DevAddPromise {
    """Dev/test helper: create a Promise directly under root, owned by the
    caller, with no Note/AssertsPromise provenance (this file's tests need a
    bare Promise to exercise `my_node` ownership, not a full capture flow).
    Never used outside `edits.test.jac`."""
    has text: str;
    has due: str = "";
    has reports: list[Promise] = [];

    can add with Root entry {
        pr = (root ++> Promise(text=self.text, due=self.due))[0];
        report pr;
    }
}
