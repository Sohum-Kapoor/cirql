"""Extraction review after Capture — every row carries a source chip and can be
fixed or removed. OWNER: Person B (SOH-167, SOH-209).

Provenance rule: every claim shows where it came from. Each row's "source" chip
expands inline to the `span` the walker recorded; when the span is a literal
substring of the note the user typed (capture.sv.jac `safe_span` guarantees it
is, or falls back to a name / the note's first 80 chars) it is highlighted
inside a short excerpt of the note. One chip open at a time. A corrected fact /
intent's receipt is the correction itself, so its chip says "You corrected this".

Editing (SOH-209) — the pencil opens an inline editor; Remove sits behind an
alert-dialog confirm. The list updates in place via `onResult` (the shell owns
the Capture report); Done invalidates home's caches as before.
  Person  — name/org/title/how met -> UpdatePerson (Needs A: kept on this device,
            says so) · Remove -> Forget(person)
  Fact    — ApplyCorrection(person_id, text, replace_fact_id) (old one goes stale
            server-side) · Remove -> Forget
  Intent  — ApplyCorrection(person_id, text, kind) + Forget(old) (until
            `replace_intent_id` lands) · Remove -> Forget
  Promise — UpdatePromise (Needs A: on this device) · Remove -> Forget
  Tie     — no walker removes a single tie: no affordance.

`result` is the Capture report (contracts/walkers.md). person_ids resolve to
names via `result.people`, then the home people list (`known`) — ambiguous
matches usually point at people you already know, not ones in this report.
"""

import from ..ui.button { Button }
import from ..ui.badge { Badge }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogTitle, AlertDialogDescription,
    AlertDialogFooter, AlertDialogAction, AlertDialogCancel
}
import from ..ui.icons { QuoteIcon, PencilIcon }
import from .ReviewEditors { PersonEditor, TextEditor, PromiseEditor }
import from ..api { apply_correction, forget, update_person, update_promise }
import from ...lib.local_edits { local_drop, local_how_met }
import from ...lib.text { join_with }
sv import from ...schema { Person }

glob _CTX: int = 70,
     _INTENT_LABEL: dict[str, str] = {"need": "need", "offer": "offer", "open_to": "open to"};

glob:pub LOCAL_NOTE: str = "Saved on this device until the server update lands.";

"""[before, span, after, found] — `found` is "1" when span is a literal substring."""
def:pub span_excerpt(note: str, span: str) -> list[str] {
    if not span or not note or span not in note {
        return ["", span, "", ""];
    }
    idx: int = note.index(span);
    end: int = idx + len(span);
    start: int = (idx - _CTX) if idx > _CTX else 0;
    stop: int = (end + _CTX) if end + _CTX < len(note) else len(note);
    # Snap the context to word boundaries so the excerpt never cuts mid-word.
    while start > 0 and start < idx and note[start - 1] != " " {
        start = start + 1;
    }
    while stop < len(note) and stop > end and note[stop] != " " {
        stop = stop - 1;
    }
    before: str = ("…" if start > 0 else "") + note[start:idx];
    after: str = note[end:stop] + ("…" if stop < len(note) else "");
    return [before, span, after, "1"];
}

def:pub SourceQuote(span: str, note_text: str, corrected: bool = False) -> JsxElement {
    parts: list[str] = span_excerpt("" if corrected else note_text, span);
    found: bool = parts[3] == "1";
    label: str = "You corrected this" if corrected else ("From your note" if found else "Source");
    return
        <blockquote className="flex flex-col gap-1 rounded-md border-l-2 border-primary bg-secondary pt-2 pb-2 pl-3 pr-3">
            <span className="text-eyebrow text-muted-foreground">{label}</span>
            {if found {
                <p className="text-body-sm text-muted-foreground">
                    {parts[0]}
                    <mark className="rounded-xs bg-primary/20 pl-0.5 pr-0.5 text-foreground">{parts[1]}</mark>
                    {parts[2]}
                </p>
            } else {
                <p className="text-body-sm">{"“" + (span or "No quote recorded for this item.") + "”"}</p>
            }}
        </blockquote>;
}

"""One review row: content (children) + source chip (+ pencil when editable).
While `editing`, the row shows `editor` instead."""
def:pub ReviewRow(
    row_key: str,
    is_open: bool,
    span: str,
    note_text: str,
    onToggle: Callable[[str], None],
    children: any = None,
    corrected: bool = False,
    local: bool = False,
    editing: bool = False,
    editor: any = None,
    edit_label: str = "",
    onEdit: Callable[[str], None] | None = None
) -> JsxElement {
    def handle_toggle(e: MouseEvent) {
        onToggle(row_key);
    }

    def handle_edit(e: MouseEvent) {
        if onEdit {
            onEdit(row_key);
        }
    }

    if editing {
        return
            <li data-row={row_key} className="flex flex-col gap-2 bg-secondary/60 pt-3 pb-3 pl-4 pr-4">{editor}</li>;
    }

    return
        <li data-row={row_key} className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
            <div className="flex items-start justify-between gap-2">
                <div className="flex min-w-0 flex-1 flex-col gap-0.5">
                    {children}
                    {local and <span className="text-caption text-muted-foreground">{LOCAL_NOTE}</span>}
                </div>
                <div className="-mr-2 flex shrink-0 items-center gap-0.5">
                    <Button
                        variant="chip"
                        size="chip"
                        aria-expanded={is_open}
                        aria-label={"Show source" if not is_open else "Hide source"}
                        onClick={handle_toggle}
                    >
                        <QuoteIcon className="size-3" />
                        <span>{"fixed" if corrected else "source"}</span>
                    </Button>
                    {onEdit and
                        <Button size="icon-sm" variant="ghost" aria-label={edit_label or "Edit"} className="text-muted-foreground" onClick={handle_edit}>
                            <PencilIcon className="size-3.5" />
                        </Button>}
                </div>
            </div>
            {is_open and <SourceQuote span={span} note_text={note_text} corrected={corrected} />}
        </li>;
}

def:pub ReviewSection(title: str, count: int, children: any = None) -> JsxElement {
    return
        <section aria-label={title} className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between">
                <h2 className="text-eyebrow text-muted-foreground">{title}</h2>
                <span className="text-caption tabular-nums text-muted-foreground">{str(count)}</span>
            </div>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">{children}</ul>
        </section>;
}

def _id_of(x: any) -> str {
    if not x {
        return "";
    }
    return (x["_jac_id"] or "") as str;
}

"""The guided how-met line applies only to people the form was about (first names match)."""
def:pub hint_for(person_name: str, met_names: list[str], hint: str) -> str {
    if not hint or not person_name {
        return "";
    }
    first: str = person_name.strip().split(" ")[0].lower();
    for n in met_names {
        if n.strip() and n.strip().split(" ")[0].lower() == first {
            return hint;
        }
    }
    return "";
}

def _name(names: dict[str, str], pid: str) -> str {
    return names[pid] or "someone";
}

"""Shared per-row edit plumbing, so each item component stays small."""
def:pub row_state(key: str, edit_key: str, busy_key: str, err_key: str, err_msg: str) -> dict {
    return {
        "editing": edit_key == key,
        "busy": busy_key == key,
        "error": err_msg if err_key == key else ""
    };
}

"""A People row: name, title/org, new|known badge, how met, and an ambiguity hint.
`onOpenPerson` (optional, unused unless passed): SOH-207's person sheet hook."""
def:pub PersonItem(
    row: dict,
    names: dict[str, str],
    spans: list[str],
    open_key: str,
    note_text: str,
    st: dict,
    how_met_hint: str,
    onToggle: Callable[[str], None],
    onEdit: Callable[[str], None],
    onCancel: Callable[[], None],
    onSave: Callable[[dict, str, str, str, str], None],
    onRemove: Callable[[str, str, str, str], None],
    onOpenPerson: Callable[[str], None] | None = None
) -> JsxElement {
    person: dict = row["person"] as dict;
    pid: str = _id_of(person);
    row_key: str = "p-" + pid;
    sub: str = join_with([s for s in [person["title"] as str, person["org"] as str] if s], ", ");
    maybe: list[str] = [names[a] for a in ((row["ambiguous_with"] or []) as list[str]) if names[a] and a != pid];
    how_met: str = local_how_met(pid, ((row["how_met"] or how_met_hint) or "") as str);

    def save(name: str, org: str, title: str, met: str) -> None {
        onSave(row, name, org, title, met);
    }

    def remove() -> None {
        onRemove(row_key, "person", pid, person["name"] as str);
    }

    def handle_open(e: MouseEvent) {
        if onOpenPerson {
            onOpenPerson(pid);
        }
    }

    return
        <ReviewRow
            row_key={row_key}
            is_open={open_key == row_key}
            span={_person_span(((row["orig_name"] or person["name"]) or "") as str, spans, note_text)}
            note_text={note_text}
            onToggle={onToggle}
            local={bool(row["local"])}
            editing={st["editing"] as bool}
            edit_label={"Edit " + (person["name"] as str)}
            onEdit={onEdit}
            editor={<PersonEditor
                person={person}
                how_met={how_met}
                busy={st["busy"] as bool}
                error={st["error"] as str}
                note="Name, org, title and how you met are kept on this device until the server update lands."
                onSave={save}
                onCancel={onCancel}
                onRemove={remove}
            /> if st["editing"] else None}
        >
            <div className="flex items-center gap-2">
                {if onOpenPerson {
                    <Button variant="link" size="inline" className="truncate text-body font-medium text-foreground" onClick={handle_open}>
                        {person["name"]}
                    </Button>
                } else {
                    <span className="truncate text-body font-medium">{person["name"]}</span>
                }}
                <Badge variant={"success" if row["is_new"] else "outline"}>{"new" if row["is_new"] else "known"}</Badge>
            </div>
            {sub and <span className="break-words text-caption text-muted-foreground">{sub}</span>}
            {row["local"] and how_met and <span className="text-caption text-muted-foreground">{"Met: " + how_met}</span>}
            {len(maybe) > 0 and
                <span className="text-caption text-muted-foreground">{"Might be the same as " + join_with(maybe, " or ")}</span>}
        </ReviewRow>;
}

def:pub FactItem(
    row: dict,
    names: dict[str, str],
    open_key: str,
    note_text: str,
    st: dict,
    onToggle: Callable[[str], None],
    onEdit: Callable[[str], None],
    onCancel: Callable[[], None],
    onSave: Callable[[dict, str, str], None],
    onRemove: Callable[[str, str, str, str], None]
) -> JsxElement {
    fact: dict = row["fact"] as dict;
    fid: str = _id_of(fact);
    row_key: str = "f-" + fid;

    def save(text: str, kind: str) -> None {
        onSave(row, text, "fact");
    }

    def remove() -> None {
        onRemove(row_key, "fact", fid, fact["text"] as str);
    }

    return
        <ReviewRow
            row_key={row_key}
            is_open={open_key == row_key}
            span={row["span"] as str}
            note_text={note_text}
            onToggle={onToggle}
            corrected={bool(row["corrected"])}
            editing={st["editing"] as bool}
            edit_label="Edit fact"
            onEdit={onEdit}
            editor={<TextEditor
                row_id={fid}
                label={"Fact about " + _name(names, row["about"] as str)}
                text={fact["text"] as str}
                kind=""
                busy={st["busy"] as bool}
                error={st["error"] as str}
                note="Saving keeps the old version as stale — nothing is silently overwritten."
                onSave={save}
                onCancel={onCancel}
                onRemove={remove}
            /> if st["editing"] else None}
        >
            <span className="text-body-sm">{fact["text"]}</span>
            <span className="text-caption text-muted-foreground">{"about " + _name(names, row["about"] as str)}</span>
        </ReviewRow>;
}

def:pub IntentItem(
    row: dict,
    names: dict[str, str],
    open_key: str,
    note_text: str,
    st: dict,
    onToggle: Callable[[str], None],
    onEdit: Callable[[str], None],
    onCancel: Callable[[], None],
    onSave: Callable[[dict, str, str], None],
    onRemove: Callable[[str, str, str, str], None]
) -> JsxElement {
    intent: dict = row["intent"] as dict;
    iid: str = _id_of(intent);
    row_key: str = "i-" + iid;
    kind: str = (intent["kind"] or "need") as str;

    def save(text: str, new_kind: str) -> None {
        onSave(row, text, new_kind);
    }

    def remove() -> None {
        onRemove(row_key, "intent", iid, intent["text"] as str);
    }

    return
        <ReviewRow
            row_key={row_key}
            is_open={open_key == row_key}
            span={row["span"] as str}
            note_text={note_text}
            onToggle={onToggle}
            corrected={bool(row["corrected"])}
            editing={st["editing"] as bool}
            edit_label="Edit intent"
            onEdit={onEdit}
            editor={<TextEditor
                row_id={iid}
                label={_name(names, row["about"] as str) + " —"}
                text={intent["text"] as str}
                kind={kind}
                busy={st["busy"] as bool}
                error={st["error"] as str}
                note=""
                onSave={save}
                onCancel={onCancel}
                onRemove={remove}
            /> if st["editing"] else None}
        >
            <div className="flex items-start gap-2">
                <Badge variant={"default" if kind == "need" else "secondary"}>{_INTENT_LABEL[kind] or kind}</Badge>
                <span className="text-body-sm">{intent["text"]}</span>
            </div>
            <span className="text-caption text-muted-foreground">{_name(names, row["about"] as str)}</span>
        </ReviewRow>;
}

def:pub PromiseItem(
    row: dict,
    names: dict[str, str],
    open_key: str,
    note_text: str,
    st: dict,
    onToggle: Callable[[str], None],
    onEdit: Callable[[str], None],
    onCancel: Callable[[], None],
    onSave: Callable[[dict, str, str], None],
    onRemove: Callable[[str, str, str, str], None]
) -> JsxElement {
    promise: dict = row["promise"] as dict;
    prid: str = _id_of(promise);
    row_key: str = "pr-" + prid;
    due: str = (promise["due"] or "") as str;

    def save(text: str, new_due: str) -> None {
        onSave(row, text, new_due);
    }

    def remove() -> None {
        onRemove(row_key, "promise", prid, promise["text"] as str);
    }

    return
        <ReviewRow
            row_key={row_key}
            is_open={open_key == row_key}
            span={row["span"] as str}
            note_text={note_text}
            onToggle={onToggle}
            local={bool(row["local"])}
            editing={st["editing"] as bool}
            edit_label="Edit promise"
            onEdit={onEdit}
            editor={<PromiseEditor
                promise={promise}
                busy={st["busy"] as bool}
                error={st["error"] as str}
                note="Kept on this device until the server update lands."
                onSave={save}
                onCancel={onCancel}
                onRemove={remove}
            /> if st["editing"] else None}
        >
            <span className="text-body-sm">{promise["text"]}</span>
            <span className="text-caption text-muted-foreground">
                {join_with([s for s in ["to " + _name(names, row["to"] as str), ("due " + due) if due else ""] if s], " · ")}
            </span>
        </ReviewRow>;
}

"""People rows carry no span in the Capture report, so show the sentence of the
note that names them (a literal substring, so it highlights). Fallback: the
first span of any item about them, then the name itself."""
def _person_span(person_name: str, spans: list[str], note: str) -> str {
    if person_name and note and person_name in note {
        return sentence_around(note, note.index(person_name));
    }
    if len(spans) > 0 {
        return spans[0];
    }
    return person_name;
}

"""The sentence of `note` containing position `pos` (split on . ! ? and newlines)."""
def:pub sentence_around(note: str, pos: int) -> str {
    stops: str = ".!?" + chr(10);
    start: int = pos;
    while start > 0 and note[start - 1] not in stops {
        start = start - 1;
    }
    end: int = pos;
    while end < len(note) and note[end] not in stops {
        end = end + 1;
    }
    if end < len(note) and note[end] != chr(10) {
        end = end + 1;
    }
    return note[start:end].strip();
}

"""Spans of every fact/intent/promise/tie that involves person `pid`."""
def _spans_about(pid: str, result: dict) -> list[str] {
    out: list[str] = [];
    for r in (result["facts"] or []) as list[dict] {
        if r["about"] == pid { out = out + [r["span"] as str]; }
    }
    for r in (result["intents"] or []) as list[dict] {
        if r["about"] == pid { out = out + [r["span"] as str]; }
    }
    for r in (result["promises"] or []) as list[dict] {
        if r["to"] == pid { out = out + [r["span"] as str]; }
    }
    for r in (result["ties"] or []) as list[dict] {
        if r["from"] == pid or r["to"] == pid { out = out + [r["span"] as str]; }
    }
    return out;
}

"""`rows` with the row whose `field` node has id `old_id` swapped for `new_row`."""
def _swap(rows: list[dict], field: str, old_id: str, new_row: dict) -> list[dict] {
    out: list[dict] = [];
    for r in rows {
        out = out + [new_row if _id_of(r[field]) == old_id else r];
    }
    return out;
}

def _without(rows: list[dict], field: str, drop_id: str) -> list[dict] {
    out: list[dict] = [];
    for r in rows {
        if _id_of(r[field]) != drop_id {
            out = out + [r];
        }
    }
    return out;
}

"""The report minus person `pid`, and every row only Forget(person) removes with them."""
def:pub drop_person(result: dict, pid: str) -> dict {
    nr: dict = {**result};
    nr["people"] = _without((result["people"] or []) as list[dict], "person", pid);
    facts: list[dict] = (result["facts"] or []) as list[dict];
    intents: list[dict] = (result["intents"] or []) as list[dict];
    promises: list[dict] = (result["promises"] or []) as list[dict];
    ties: list[dict] = (result["ties"] or []) as list[dict];
    nr["facts"] = [r for r in facts if r["about"] != pid];
    nr["intents"] = [r for r in intents if r["about"] != pid];
    nr["promises"] = [r for r in promises if r["to"] != pid];
    nr["ties"] = [r for r in ties if r["from"] != pid and r["to"] != pid];
    return nr;
}

def:pub edit_error_text(code: str) -> str {
    if code == "not_found" {
        return "Couldn't find that any more — it may already be gone.";
    }
    if code == "bad_kind" {
        return "That kind isn't allowed.";
    }
    return "Couldn't save that — try again. (" + code + ")";
}

def:pub Review(
    result: dict,
    note_text: str,
    known: list[Person],
    onDone: Callable[[], None],
    onRetry: Callable[[], None],
    onResult: Callable[[dict], None],
    how_met_hint: str = "",
    met_names: list[str] = [],
    onOpenPerson: Callable[[str], None] | None = None
) -> JsxElement {
    has open_key: str = "",
        edit_key: str = "",
        busy_key: str = "",
        err_key: str = "",
        err_msg: str = "",
        confirm: dict = {};

    def toggle(key: str) -> None {
        open_key = "" if open_key == key else key;
    }

    def start_edit(key: str) -> None {
        if busy_key {
            return;
        }
        edit_key = key;
        open_key = "";
        err_key = "";
        err_msg = "";
    }

    def cancel_edit() -> None {
        edit_key = "";
        err_key = "";
        err_msg = "";
    }

    def fail(key: str, msg: str) -> None {
        busy_key = "";
        err_key = key;
        err_msg = msg;
    }

    def done_editing() -> None {
        busy_key = "";
        edit_key = "";
        err_key = "";
        err_msg = "";
    }

    """Person -> UpdatePerson (device-only until the walker lands)."""
    async def save_person(row: dict, name: str, org: str, title: str, how_met: str) -> None {
        person: dict = row["person"] as dict;
        pid: str = _id_of(person);
        key: str = "p-" + pid;
        out: dict = {};
        busy_key = key;
        try {
            out = await update_person(person, name, org, title, how_met);
        } except Exception as e {
            fail(key, "Couldn't save that — try again.");
            return;
        }
        if out["error"] {
            fail(key, "Couldn't save that — try again.");
            return;
        }
        new_row: dict = {**row};
        new_row["person"] = out["person"];
        new_row["how_met"] = how_met;
        new_row["local"] = out["local"];
        new_row["orig_name"] = row["orig_name"] or person["name"];
        nr: dict = {**result};
        nr["people"] = _swap((result["people"] or []) as list[dict], "person", pid, new_row);
        onResult(nr);
        done_editing();
    }

    """Fact -> ApplyCorrection(replace_fact_id=old): a new confirmed fact; the old goes stale."""
    async def save_fact(row: dict, text: str, kind: str) -> None {
        fid: str = _id_of(row["fact"]);
        pid: str = (row["about"] or "") as str;
        key: str = "f-" + fid;
        out: dict = {};
        busy_key = key;
        try {
            out = await apply_correction(pid, text, fid, "fact");
        } except Exception as e {
            fail(key, "Couldn't save that — try again.");
            return;
        }
        if out["error"] or not out["fact"] {
            fail(key, edit_error_text((out["error"] or "failed") as str));
            return;
        }
        new_row: dict = {"fact": out["fact"], "about": pid, "span": text, "corrected": True};
        nr: dict = {**result};
        nr["facts"] = _swap((result["facts"] or []) as list[dict], "fact", fid, new_row);
        onResult(nr);
        done_editing();
    }

    """Intent -> ApplyCorrection(kind) + Forget(old) (no replace_intent_id yet)."""
    async def save_intent(row: dict, text: str, kind: str) -> None {
        iid: str = _id_of(row["intent"]);
        pid: str = (row["about"] or "") as str;
        key: str = "i-" + iid;
        out: dict = {};
        gone: dict = {};
        busy_key = key;
        try {
            out = await apply_correction(pid, text, "", kind);
        } except Exception as e {
            fail(key, "Couldn't save that — try again.");
            return;
        }
        if out["error"] or not out["intent"] {
            fail(key, edit_error_text((out["error"] or "failed") as str));
            return;
        }
        try {
            gone = await forget(iid);
        } except Exception as e {
            gone = {"error": "failed"};
        }
        new_row: dict = {"intent": out["intent"], "about": pid, "span": text, "corrected": True};
        nr: dict = {**result};
        nr["intents"] = _swap((result["intents"] or []) as list[dict], "intent", iid, new_row);
        onResult(nr);
        done_editing();
        if gone["error"] and gone["error"] != "not_found" {
            err_key = "i-" + _id_of(out["intent"]);
            err_msg = "Saved the new version, but the old one couldn't be removed.";
        }
    }

    """Promise -> UpdatePromise (device-only until the walker lands)."""
    async def save_promise(row: dict, text: str, due: str) -> None {
        promise: dict = row["promise"] as dict;
        prid: str = _id_of(promise);
        key: str = "pr-" + prid;
        out: dict = {};
        busy_key = key;
        try {
            out = await update_promise(promise, text, due);
        } except Exception as e {
            fail(key, "Couldn't save that — try again.");
            return;
        }
        if out["error"] {
            fail(key, "Couldn't save that — try again.");
            return;
        }
        new_row: dict = {**row};
        new_row["promise"] = out["promise"];
        new_row["local"] = out["local"];
        nr: dict = {**result};
        nr["promises"] = _swap((result["promises"] or []) as list[dict], "promise", prid, new_row);
        onResult(nr);
        done_editing();
    }

    def ask_remove(key: str, kind: str, node_id: str, label: str) -> None {
        confirm = {"key": key, "kind": kind, "id": node_id, "label": label};
    }

    def set_confirm_open(v: bool) -> None {
        if not v {
            confirm = {};
        }
    }

    """Remove -> Forget(id); the row (and, for a person, everything only about them) leaves the list."""
    async def do_remove(c: dict) -> None {
        key: str = (c["key"] or "") as str;
        kind: str = (c["kind"] or "") as str;
        nid: str = (c["id"] or "") as str;
        out: dict = {};
        if not nid {
            return;
        }
        busy_key = key;
        try {
            out = await forget(nid);
        } except Exception as e {
            fail(key, "Couldn't remove that — try again.");
            return;
        }
        if out["error"] and out["error"] != "not_found" {
            fail(key, edit_error_text(out["error"] as str));
            return;
        }
        nr: dict = {**result};
        if kind == "person" {
            nr = drop_person(result, nid);
            local_drop("person", nid);
        } elif kind == "fact" {
            nr["facts"] = _without((result["facts"] or []) as list[dict], "fact", nid);
        } elif kind == "intent" {
            nr["intents"] = _without((result["intents"] or []) as list[dict], "intent", nid);
        } elif kind == "promise" {
            nr["promises"] = _without((result["promises"] or []) as list[dict], "promise", nid);
            local_drop("promise", nid);
        }
        nr["removed"] = ((result["removed"] or 0) as int) + 1;
        onResult(nr);
        done_editing();
    }

    def handle_confirm(e: MouseEvent) {
        c: dict = {**confirm};
        confirm = {};
        do_remove(c);
    }

    def handle_done(e: MouseEvent) {
        onDone();
    }

    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    people: list[dict] = (result["people"] or []) as list[dict];
    facts: list[dict] = (result["facts"] or []) as list[dict];
    intents: list[dict] = (result["intents"] or []) as list[dict];
    promises: list[dict] = (result["promises"] or []) as list[dict];
    ties: list[dict] = (result["ties"] or []) as list[dict];
    total: int = len(people) + len(facts) + len(intents) + len(promises) + len(ties);
    removed: int = (result["removed"] or 0) as int;
    confirm_kind: str = (confirm["kind"] or "") as str;
    confirm_label: str = (confirm["label"] or "") as str;

    names: dict[str, str] = {};
    for k in known {
        names[_id_of(k)] = k.name;
    }
    for row in people {
        names[_id_of(row["person"])] = row["person"]["name"] as str;
    }

    return
        <div className="flex flex-col gap-6 pb-6">
            <header className="flex flex-col gap-1 pt-2">
                <h1 className="text-card-title">
                    {"Here's what Cirql read" if total > 0 else "Note saved"}
                </h1>
                {total > 0 and
                    <p className="text-body-sm text-muted-foreground">
                        Saved to your graph. Tap source to see the words it came from, or the pencil to fix anything.
                    </p>}
            </header>
            {if total == 0 and removed > 0 {
                <p role="status" className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm">
                    Everything from this note is removed. The note itself is kept as the receipt.
                </p>
            } elif total == 0 {
                <div className="flex flex-col gap-3">
                    <p role="status" className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm">
                        Saved your note. Cirql couldn't pull out people this time — it's kept, and you can try again.
                    </p>
                    <SourceQuote span={note_text} note_text="" />
                    <Button variant="secondary" className="w-full" onClick={handle_retry}>Try again</Button>
                </div>
            }}
            {if len(people) > 0 {
                <ReviewSection title="People" count={len(people)}>
                    {for row in people {
                        <PersonItem
                            key={"p-" + _id_of(row["person"])}
                            row={row}
                            names={names}
                            spans={_spans_about(_id_of(row["person"]), result)}
                            open_key={open_key}
                            note_text={note_text}
                            st={row_state("p-" + _id_of(row["person"]), edit_key, busy_key, err_key, err_msg)}
                            how_met_hint={hint_for(((row["orig_name"] or row["person"]["name"]) or "") as str, met_names, how_met_hint)}
                            onToggle={toggle}
                            onEdit={start_edit}
                            onCancel={cancel_edit}
                            onSave={save_person}
                            onRemove={ask_remove}
                            onOpenPerson={onOpenPerson}
                        />
                    }}
                </ReviewSection>
            }}
            {if len(facts) > 0 {
                <ReviewSection title="Facts" count={len(facts)}>
                    {for row in facts {
                        <FactItem
                            key={"f-" + _id_of(row["fact"])}
                            row={row}
                            names={names}
                            open_key={open_key}
                            note_text={note_text}
                            st={row_state("f-" + _id_of(row["fact"]), edit_key, busy_key, err_key, err_msg)}
                            onToggle={toggle}
                            onEdit={start_edit}
                            onCancel={cancel_edit}
                            onSave={save_fact}
                            onRemove={ask_remove}
                        />
                    }}
                </ReviewSection>
            }}
            {if len(intents) > 0 {
                <ReviewSection title="Intents" count={len(intents)}>
                    {for row in intents {
                        <IntentItem
                            key={"i-" + _id_of(row["intent"])}
                            row={row}
                            names={names}
                            open_key={open_key}
                            note_text={note_text}
                            st={row_state("i-" + _id_of(row["intent"]), edit_key, busy_key, err_key, err_msg)}
                            onToggle={toggle}
                            onEdit={start_edit}
                            onCancel={cancel_edit}
                            onSave={save_intent}
                            onRemove={ask_remove}
                        />
                    }}
                </ReviewSection>
            }}
            {if len(promises) > 0 {
                <ReviewSection title="Promises" count={len(promises)}>
                    {for row in promises {
                        <PromiseItem
                            key={"pr-" + _id_of(row["promise"])}
                            row={row}
                            names={names}
                            open_key={open_key}
                            note_text={note_text}
                            st={row_state("pr-" + _id_of(row["promise"]), edit_key, busy_key, err_key, err_msg)}
                            onToggle={toggle}
                            onEdit={start_edit}
                            onCancel={cancel_edit}
                            onSave={save_promise}
                            onRemove={ask_remove}
                        />
                    }}
                </ReviewSection>
            }}
            {if len(ties) > 0 {
                <ReviewSection title="Ties" count={len(ties)}>
                    {for (i, row) in enumerate(ties) {
                        <ReviewRow
                            key={"t-" + str(i)}
                            row_key={"t-" + str(i)}
                            is_open={open_key == "t-" + str(i)}
                            span={row["span"] as str}
                            note_text={note_text}
                            onToggle={toggle}
                        >
                            <span className="text-body-sm">
                                {_name(names, row["from"] as str) + " ↔ " + _name(names, row["to"] as str)}
                            </span>
                            <span className="text-caption text-muted-foreground">know each other</span>
                        </ReviewRow>
                    }}
                </ReviewSection>
            }}
            <Button className="w-full" size="lg" disabled={bool(busy_key)} onClick={handle_done}>Done</Button>
            <AlertDialog open={bool(confirm["key"])} onOpenChange={set_confirm_open}>
                <AlertDialogContent aria-label="Remove">
                    <AlertDialogHeader>
                        <AlertDialogTitle>
                            {("Remove " + confirm_label + "?") if confirm_kind == "person" else ("Remove this " + confirm_kind + "?")}
                        </AlertDialogTitle>
                        <AlertDialogDescription>
                            {(
                                "Cirql forgets them and every fact, intent and promise only about them. The note itself is kept."
                                if confirm_kind == "person"
                                else "“" + confirm_label + "” — Cirql forgets it. The note it came from is kept."
                            )}
                        </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                        <AlertDialogCancel>Keep it</AlertDialogCancel>
                        <AlertDialogAction variant="destructive" onClick={handle_confirm}>Remove</AlertDialogAction>
                    </AlertDialogFooter>
                </AlertDialogContent>
            </AlertDialog>
        </div>;
}
