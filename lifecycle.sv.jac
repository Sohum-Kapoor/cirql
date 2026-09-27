"""Lifecycle — archive/restore people, delete my data, import a graph (SOH-220).

OWNER: Person A. Report shapes: contracts/walkers.md (SOH-220 block).
Every walker here is `:priv` (own root only, JWT required). No `by llm`.

- `ArchivePerson` / `RestorePerson` flip `Person.archived` (a soft delete:
  nothing is removed, every list and ranking skips the person, restore
  brings them back unchanged). `ListArchived` lists the archived ones.
- `DeleteMyData(confirm="DELETE")` removes every node the caller OWNS that
  is reachable from their root, plus the caller's own CardListing on the
  shared CardDirectory, plus upload files their Notes reference (only under
  `uploads/`, see `_upload_path_ok`). A shared-root edge the caller cannot
  delete is tolerated (silently left behind).
- `ImportGraph(data)` reads the `ExportGraph` shape (export.sv.jac) and
  rebuilds it on the caller's root through an old-id -> new-node map. Every
  claim keeps its provenance: a Fact/Intent/Promise is only created under
  its (imported) source Note with the same span; one whose source note is
  unknown is skipped and counted. Imported `audio_ref`s are kept only when
  they point under `uploads/<caller root>/`, so an import can never make a
  later DeleteMyData remove someone else's file.
"""

import os;
import from datetime { datetime }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Card, Circle, Event,
    Knows, Reported, Asserts, AssertsIntent, AssertsPromise, Mentions,
    FactAbout, IntentAbout, PromiseTo, HasGoal, HasIntent, HasCircle, InCircle,
    Introduction, Interest, ReplyPrivate, ClaimedIntro, MergeRecord,
    CardDirectory, CardListing
}
import from reads { my_node, owner_root }

glob IMPORT_CAP: int = 5000;

# ---------------------------------------------------------------- shared helpers

"""The caller's people who are not archived. Other modules may import this
instead of repeating `if p.archived { continue; }`."""
def active_people(me: Me) -> list[Person] {
    return [p for p in [me ->:Knows:->] if not p.archived];
}

"""An owned Person by id, or None (unknown id, other account, not a Person)."""
def my_person_by_id(person_id: str) -> Person | None {
    n = my_node(person_id);
    if n is not None and isinstance(n, Person) {
        return n as Person;
    }
    return None;
}

def _not_found() -> dict[str, str] {
    return {"error": "not_found"};
}

# ---------------------------------------------------------------- DeleteMyData

def empty_deleted() -> dict[str, int] {
    return {
        "people": 0, "facts": 0, "intents": 0, "promises": 0, "notes": 0,
        "goals": 0, "cards": 0, "circles": 0, "events": 0, "other": 0, "files": 0
    };
}

"""True only for a path that resolves inside `uploads/` either directly
(`uploads/<file>`, CaptureImage's photos) or inside the caller's own
`uploads/<root_id>/` directory (Transcribe's audio). No `..`, no absolute
path outside, no other account's directory."""
def _upload_path_ok(ref: str, root_id: str) -> bool {
    if not ref {
        return False;
    }
    base = os.path.realpath("uploads");
    full = os.path.realpath(ref);
    if not full.startswith(base + os.sep) {
        return False;
    }
    rel = os.path.relpath(full, base);
    parts = rel.split(os.sep);
    # Only files inside the caller's own uploads/<root>/ folder. Loose files
    # directly under uploads/ (badge photos) are left alone: another account
    # could reference the same name.
    return len(parts) == 2 and parts[0].replace("-", "") == root_id;
}

"""Every node reachable from the caller's root through outgoing edges that
the caller OWNS. A node owned by someone else (a Card granted read-only via
FromCard, anything shared) is neither collected nor walked past."""
def owned_reachable() -> list[any] {
    me_root = jid(root);
    out: list[any] = [];
    seen: list[str] = [];
    queue: list[any] = [x for x in [root -->]];
    idx = 0;
    while idx < len(queue) {
        n = queue[idx];
        idx += 1;
        k = jid(n);
        if k in seen {
            continue;
        }
        seen.append(k);
        if owner_root(n) != me_root {
            continue;
        }
        out.append(n);
        for nxt in [n -->] {
            if jid(nxt) not in seen {
                queue.append(nxt);
            }
        }
    }
    return out;
}

"""Delete the caller's CardListing pointers on every shared CardDirectory.
Returns how many were removed. Only listings the caller owns are touched."""
def delete_my_listings() -> int {
    me_root = jid(root);
    count = 0;
    for d in [x for x in [root.shared -->] if isinstance(x, CardDirectory)] {
        mine: list[CardListing] = [];
        for x in [d -->] {
            if isinstance(x, CardListing) and owner_root(x) == me_root {
                mine.append(x as CardListing);
            }
        }
        for l in mine {
            try {
                del l;
                count += 1;
            } except Exception {
                continue;   # a shared-root object we cannot delete stays
            }
        }
    }
    return count;
}

def delete_my_data() -> dict[str, any] {
    deleted = empty_deleted();
    root_id = jid(root);
    nodes = owned_reachable();

    files: list[str] = [];
    for n in nodes {
        if isinstance(n, Note) {
            ref = (n as Note).audio_ref;
            if _upload_path_ok(ref, root_id) and ref not in files {
                files.append(ref);
            }
        }
    }

    deleted["other"] = delete_my_listings();

    for n in nodes {
        if isinstance(n, Person) {
            deleted["people"] = deleted["people"] + 1;
        } elif isinstance(n, Fact) {
            deleted["facts"] = deleted["facts"] + 1;
        } elif isinstance(n, Intent) {
            deleted["intents"] = deleted["intents"] + 1;
        } elif isinstance(n, Promise) {
            deleted["promises"] = deleted["promises"] + 1;
        } elif isinstance(n, Note) {
            deleted["notes"] = deleted["notes"] + 1;
        } elif isinstance(n, Goal) {
            deleted["goals"] = deleted["goals"] + 1;
        } elif isinstance(n, Card) {
            deleted["cards"] = deleted["cards"] + 1;
        } elif isinstance(n, Circle) {
            deleted["circles"] = deleted["circles"] + 1;
        } elif isinstance(n, Event) {
            deleted["events"] = deleted["events"] + 1;
        } else {
            deleted["other"] = deleted["other"] + 1;
        }
    }

    for n in nodes {
        try {
            del n;
        } except Exception {
            continue;
        }
    }

    for ref in files {
        try {
            if os.path.isfile(ref) {
                os.remove(ref);
                deleted["files"] = deleted["files"] + 1;
            }
        } except Exception {
            continue;
        }
    }

    return {"deleted": deleted, "ok": True};
}

# ---------------------------------------------------------------- ImportGraph helpers

"""`d[key]` as a string; missing or None is "" (no dict.get, AGENTS.md)."""
def dstr(d: dict[str, any], key: str) -> str {
    if key in d {
        v = d[key];
        if v is None {
            return "";
        }
        return str(v);
    }
    return "";
}

def dbool(d: dict[str, any], key: str, dflt: bool) -> bool {
    if key in d {
        v = d[key];
        if isinstance(v, bool) {
            return bool(v);
        }
    }
    return dflt;
}

def dstrs(d: dict[str, any], key: str) -> list[str] {
    out: list[str] = [];
    if key in d {
        v = d[key];
        if isinstance(v, list) {
            for x in v {
                if x is not None {
                    out.append(str(x));
                }
            }
        }
    }
    return out;
}

def dlist(d: dict[str, any], key: str) -> list[dict[str, any]] {
    out: list[dict[str, any]] = [];
    if key in d {
        v = d[key];
        if isinstance(v, list) {
            for x in v {
                if isinstance(x, dict) {
                    out.append(x);
                }
            }
        }
    }
    return out;
}

def clean_name(s: str) -> str {
    return " ".join(s.strip().lower().split());
}

def person_key(name: str, org: str) -> str {
    return clean_name(name) + "|" + clean_name(org);
}

"""An imported audio_ref survives only when it points under the caller's
own `uploads/<root_id>/` directory."""
def import_audio_ref(ref: str, root_id: str) -> str {
    if not ref {
        return "";
    }
    if not _upload_path_ok(ref, root_id) {
        return "";
    }
    rel = os.path.relpath(os.path.realpath(ref), os.path.realpath("uploads"));
    if len(rel.split(os.sep)) != 2 {
        return "";
    }
    return ref;
}

obj ImportState {
    has id_map: dict[str, any] = {};
    has budget: int = 5000;
    has skipped: int = 0;
    has imported: dict[str, int] = {};
    has created: list[str] = [];

    def take -> bool {
        if self.budget <= 0 {
            self.skipped += 1;
            return False;
        }
        self.budget -= 1;
        return True;
    }

    def bump(key: str) {
        self.imported[key] = self.imported[key] + 1;
    }
}

def empty_imported() -> dict[str, int] {
    return {"people": 0, "facts": 0, "intents": 0, "promises": 0, "notes": 0, "goals": 0, "circles": 0};
}

def mapped_note(st: ImportState, old_id: str) -> Note | None {
    if old_id and old_id in st.id_map {
        n = st.id_map[old_id];
        if isinstance(n, Note) {
            return n as Note;
        }
    }
    return None;
}

def mapped_person(st: ImportState, old_id: str) -> Person | None {
    if old_id and old_id in st.id_map {
        n = st.id_map[old_id];
        if isinstance(n, Person) {
            return n as Person;
        }
    }
    return None;
}

def import_notes(st: ImportState, data: dict[str, any], root_id: str) {
    existing: dict[str, Note] = {};
    for n in [root --> [?:Note]] {
        existing[n.text + "|" + n.captured_at] = n;
    }
    for row in dlist(data, "notes") {
        old = dstr(row, "id");
        text = dstr(row, "text");
        if not old or not text {
            st.skipped += 1;
            continue;
        }
        captured = dstr(row, "captured_at") or datetime.now().isoformat();
        key = text + "|" + captured;
        if key in existing {
            st.id_map[old] = existing[key];
            continue;
        }
        if not st.take() {
            continue;
        }
        note = (root ++> Note(
            text=text, kind=dstr(row, "kind") or "import", captured_at=captured,
            audio_ref=import_audio_ref(dstr(row, "audio_ref"), root_id)
        ))[0];
        existing[key] = note;
        st.id_map[old] = note;
        st.bump("notes");
    }
}

def import_people(st: ImportState, data: dict[str, any], me: Me) {
    by_key: dict[str, Person] = {};
    by_token: dict[str, Person] = {};
    me_root = jid(root);
    for p in [me ->:Knows:->] {
        if p.archived or owner_root(p) != me_root {
            continue;  # never map an import onto an archived or foreign person
        }
        by_key[person_key(p.name, p.org)] = p;
        for t in p.identity_tokens {
            by_token[t] = p;
        }
    }
    for row in dlist(data, "people") {
        old = dstr(row, "id");
        name = " ".join(dstr(row, "name").strip().split());
        if not old or not name {
            st.skipped += 1;
            continue;
        }
        org = dstr(row, "org").strip();
        tokens = dstrs(row, "identity_tokens");
        found: Person | None = None;
        for t in tokens {
            if found is None and t in by_token {
                found = by_token[t];
            }
        }
        k = person_key(name, org);
        if found is None and k in by_key {
            found = by_key[k];
        }
        if found is not None {
            st.id_map[old] = found;
            continue;
        }
        if not st.take() {
            continue;
        }
        p = (me +>:Knows(how_met="imported", status="reported"):+> Person(
            name=name, org=org, title=dstr(row, "title"),
            status=dstr(row, "status") or "confirmed",
            email=dstr(row, "email"), phone=dstr(row, "phone"),
            links=dstrs(row, "links"), location=dstr(row, "location"),
            identity_tokens=tokens, archived=dbool(row, "archived", False)
        ))[0];
        st.created.append(jid(p));
        st.id_map[old] = p;
        by_key[k] = p;
        for t in tokens {
            by_token[t] = p;
        }
        st.bump("people");
    }
}

"""Knows rows from the export, remapped onto the Knows edge each NEW person
got in `import_people` (a reused person keeps the edge the caller already
had). last_contact is copied verbatim as display data; nothing reads it."""
def import_knows(st: ImportState, data: dict[str, any], me: Me) {
    for row in dlist(data, "knows") {
        if not st.take() {
            break;  # edge budget: take() already records the truncation
        }
        p = mapped_person(st, dstr(row, "to"));
        if p is None {
            st.skipped += 1;
            continue;
        }
        person = p as Person;
        if jid(person) not in st.created {
            continue;
        }
        edges = [edge me ->:Knows:-> person];
        if not edges {
            continue;
        }
        ke = edges[0];
        src = mapped_note(st, dstr(row, "source_note"));
        ke.how_met = dstr(row, "how_met");
        ke.last_contact = dstr(row, "last_contact");
        ke.status = dstr(row, "status") or "reported";
        ke.source_note = jid(src as Note) if src is not None else "";
        span = dstr(row, "span");
        if src is not None and span {
            nn = src as Note;
            if not [edge nn ->:Mentions:-> person] {
                nn +>:Mentions(span=span):+> person;
            }
        }
    }
}

"""Reported ties need both people and a mapped source note (provenance)."""
def import_reported(st: ImportState, data: dict[str, any]) {
    for row in dlist(data, "reported") {
        if not st.take() {
            break;  # edge budget: take() already records the truncation
        }
        a = mapped_person(st, dstr(row, "from"));
        b = mapped_person(st, dstr(row, "to"));
        src = mapped_note(st, dstr(row, "source_note"));
        if a is None or b is None or src is None {
            st.skipped += 1;
            continue;
        }
        pa = a as Person;
        pb = b as Person;
        if [edge pa ->:Reported:-> pb] {
            continue;
        }
        pa +>:Reported(source_note=jid(src as Note), span=dstr(row, "span")):+> pb;
    }
}

def import_facts(st: ImportState, data: dict[str, any]) {
    for row in dlist(data, "facts") {
        src = mapped_note(st, dstr(row, "source_note"));
        about_old = dstr(row, "about");
        about = mapped_person(st, about_old);
        text = dstr(row, "text");
        if src is None or not text or (about_old and about is None) {
            st.skipped += 1;
            continue;
        }
        note = src as Note;
        if [f for f in [note ->:Asserts:->] if f.text == text] {
            continue;
        }
        if not st.take() {
            continue;
        }
        f = (note +>:Asserts(span=dstr(row, "span")):+> Fact(
            text=text, observed_at=dstr(row, "observed_at") or note.captured_at,
            valid_to=dstr(row, "valid_to"), status=dstr(row, "status") or "reported",
            source_kind=dstr(row, "source_kind") or "reported", source_url=dstr(row, "source_url")
        ))[0];
        if about is not None {
            f +>:FactAbout:+> (about as Person);
        }
        st.id_map[dstr(row, "id")] = f;
        st.bump("facts");
    }
}

def import_intents(st: ImportState, data: dict[str, any], me: Me, old_me_id: str) {
    for row in dlist(data, "intents") {
        src = mapped_note(st, dstr(row, "source_note"));
        about_old = dstr(row, "about");
        is_self = bool(about_old) and about_old == old_me_id;
        about = mapped_person(st, about_old);
        text = dstr(row, "text");
        if src is None or not text or (about_old and not is_self and about is None) {
            st.skipped += 1;
            continue;
        }
        note = src as Note;
        kind = dstr(row, "kind") or "need";
        if [i for i in [note ->:AssertsIntent:->] if i.text == text and i.kind == kind] {
            continue;
        }
        if not st.take() {
            continue;
        }
        it = (note +>:AssertsIntent(span=dstr(row, "span")):+> Intent(
            kind=kind, text=text, expires_at=dstr(row, "expires_at"),
            source_kind=dstr(row, "source_kind") or "reported"
        ))[0];
        if about is not None {
            it +>:IntentAbout:+> (about as Person);
        } elif is_self {
            me +>:HasIntent:+> it;
        }
        st.id_map[dstr(row, "id")] = it;
        st.bump("intents");
    }
}

def import_promises(st: ImportState, data: dict[str, any]) {
    for row in dlist(data, "promises") {
        src = mapped_note(st, dstr(row, "source_note"));
        to_old = dstr(row, "to");
        to = mapped_person(st, to_old);
        text = dstr(row, "text");
        if src is None or not text or (to_old and to is None) {
            st.skipped += 1;
            continue;
        }
        note = src as Note;
        if [x for x in [note ->:AssertsPromise:->] if x.text == text] {
            continue;
        }
        if not st.take() {
            continue;
        }
        pr = (note +>:AssertsPromise(span=dstr(row, "span")):+> Promise(
            text=text, due=dstr(row, "due"), done=dbool(row, "done", False)
        ))[0];
        if to is not None {
            pr +>:PromiseTo:+> (to as Person);
        }
        st.id_map[dstr(row, "id")] = pr;
        st.bump("promises");
    }
}

"""Goals come in inactive, except the first goal the export marked active
when the caller has no active goal yet (SetGoal keeps at most one)."""
def import_goals(st: ImportState, data: dict[str, any], me: Me) {
    existing: list[Goal] = [me ->:HasGoal:->];
    has_active = len([g for g in existing if g.active]) > 0;
    texts = [g.text for g in existing];
    for row in dlist(data, "goals") {
        text = dstr(row, "text");
        if not text {
            st.skipped += 1;
            continue;
        }
        if text in texts {
            continue;
        }
        if not st.take() {
            continue;
        }
        active = False;
        if dbool(row, "active", False) and not has_active {
            active = True;
            has_active = True;
        }
        g = (me +>:HasGoal:+> Goal(text=text, created_at=datetime.now().isoformat(), active=active))[0];
        texts.append(text);
        st.id_map[dstr(row, "id")] = g;
        st.bump("goals");
    }
}

"""Optional `circles: [{id, name, members?: [person ids]}]` and
`in_circle: [{person, circle}]` (tolerated when absent)."""
def import_circles(st: ImportState, data: dict[str, any], me: Me) {
    existing: dict[str, Circle] = {};
    for c in [me ->:HasCircle:->] {
        existing[clean_name(c.name)] = c;
    }
    pairs: list[dict[str, str]] = [];
    for row in dlist(data, "circles") {
        old = dstr(row, "id");
        name = dstr(row, "name").strip();
        if not old or not name {
            st.skipped += 1;
            continue;
        }
        k = clean_name(name);
        if k in existing {
            st.id_map[old] = existing[k];
        } else {
            if not st.take() {
                continue;
            }
            c = (me +>:HasCircle:+> Circle(name=name, created_at=datetime.now().isoformat()))[0];
            existing[k] = c;
            st.id_map[old] = c;
            st.bump("circles");
        }
        for m in dstrs(row, "members") {
            pairs.append({"person": m, "circle": old});
        }
    }
    for row in dlist(data, "in_circle") {
        if not st.take() {
            break;  # edge budget: take() already records the truncation
        }
        pairs.append({"person": dstr(row, "person"), "circle": dstr(row, "circle")});
    }
    for pr in pairs {
        p = mapped_person(st, pr["person"]);
        cid = pr["circle"];
        if p is None or cid not in st.id_map or not isinstance(st.id_map[cid], Circle) {
            st.skipped += 1;
            continue;
        }
        person = p as Person;
        circle = st.id_map[cid] as Circle;
        if not [edge person ->:InCircle:-> circle] {
            person +>:InCircle:+> circle;
        }
    }
}

def import_graph(data: dict[str, any], cap: int) -> dict[str, any] {
    st = ImportState(budget=cap, imported=empty_imported());
    root_id = jid(root);

    existing_me = [root --> [?:Me]];
    old_me_id = "";
    me_row: dict[str, any] = {};
    if "me" in data and isinstance(data["me"], dict) {
        me_row = data["me"];
        old_me_id = dstr(me_row, "id");
    }
    if existing_me {
        me = existing_me[0];
        if not me.about and dstr(me_row, "about") {
            me.about = dstr(me_row, "about");
        }
    } else {
        me = (root ++> Me(name=dstr(me_row, "name") or "me", about=dstr(me_row, "about")))[0];
    }
    if old_me_id {
        st.id_map[old_me_id] = me;
    }

    import_notes(st, data, root_id);
    import_people(st, data, me);
    import_knows(st, data, me);
    import_reported(st, data);
    import_facts(st, data);
    import_intents(st, data, me, old_me_id);
    import_promises(st, data);
    import_goals(st, data, me);
    import_circles(st, data, me);

    return {
        "imported": st.imported,
        "skipped": st.skipped,
        "id_map_size": len(st.id_map),
        "truncated": st.budget <= 0
    };
}

# ---------------------------------------------------------------- walkers

walker:priv ArchivePerson {
    """Soft-delete one of the caller's people: sets `archived = true`.
    Reports the Person, or `{error: "not_found"}`."""
    has person_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        p = my_person_by_id(self.person_id);
        if p is None {
            report _not_found();
            disengage;
        }
        person = p as Person;
        person.archived = True;
        report person;
    }
}

walker:priv RestorePerson {
    """Undo ArchivePerson: sets `archived = false`. Reports the Person, or
    `{error: "not_found"}`."""
    has person_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        p = my_person_by_id(self.person_id);
        if p is None {
            report _not_found();
            disengage;
        }
        person = p as Person;
        person.archived = False;
        report person;
    }
}

walker:priv ListArchived {
    """Every archived Person the caller knows, one report per person."""
    has reports: list[Person] = [];

    can run with Root entry {
        for p in [root --> [?:Me] ->:Knows:->] {
            if p.archived {
                report p;
            }
        }
    }
}

walker:priv DeleteMyData {
    """Remove everything the caller owns (see module docstring). Only runs
    when `confirm == "DELETE"`; otherwise reports zero counts and ok=false."""
    has confirm: str = "";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        if self.confirm != "DELETE" {
            report {"deleted": empty_deleted(), "ok": False};
            disengage;
        }
        report delete_my_data();
    }
}

walker:priv ImportGraph {
    """Rebuild an `ExportGraph` dict on the caller's own root (merge into
    what is there). Reports `{imported, skipped, id_map_size, truncated}`."""
    has data: dict[str, any] = {};
    has mode: str = "merge";
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        if self.mode != "merge" {
            report {"error": "bad_mode"};
            disengage;
        }
        report import_graph(self.data, IMPORT_CAP);
    }
}
