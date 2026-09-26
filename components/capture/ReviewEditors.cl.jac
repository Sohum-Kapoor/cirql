"""Inline editors for review rows (SOH-209). OWNER: Person B.

Each editor mounts when its row enters edit mode, so its `has` drafts start from
the row's current values. Stateless about the walker calls: Save / Remove go
back to Review, which calls components/api.cl.jac and updates the list in place.
"""

import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.textarea { Textarea }
import from ..ui.icons { TrashIcon }
import from .Chips { ChipGroup }

glob:pub INTENT_KINDS: list[list[str]] = [["need", "Need"], ["offer", "Offer"], ["open_to", "Open to"]];

def:pub EditorField(label: str, htmlFor: str, children: any = None) -> JsxElement {
    return
        <div className="flex flex-col gap-1">
            <label htmlFor={htmlFor} className="text-caption text-muted-foreground">{label}</label>
            {children}
        </div>;
}

"""Remove · Cancel · Save, plus the error line and an optional note."""
def:pub EditorFooter(
    busy: bool,
    error: str,
    can_save: bool,
    note: str,
    onSave: Callable[[], None],
    onCancel: Callable[[], None],
    onRemove: Callable[[], None] | None = None
) -> JsxElement {
    def handle_save(e: MouseEvent) {
        onSave();
    }

    def handle_cancel(e: MouseEvent) {
        onCancel();
    }

    def handle_remove(e: MouseEvent) {
        if onRemove {
            onRemove();
        }
    }

    return
        <div className="flex flex-col gap-2">
            {error and <p role="alert" className="text-caption text-destructive">{error}</p>}
            {note and <p className="text-caption text-muted-foreground">{note}</p>}
            <div className="flex items-center gap-2">
                {onRemove and
                    <Button size="sm" variant="ghost" className="-ml-2 text-destructive hover:text-destructive" disabled={busy} onClick={handle_remove}>
                        <TrashIcon />
                        Remove
                    </Button>}
                <span className="flex-1" />
                <Button size="sm" variant="ghost" disabled={busy} onClick={handle_cancel}>Cancel</Button>
                <Button size="sm" disabled={busy or not can_save} onClick={handle_save}>{"Saving…" if busy else "Save"}</Button>
            </div>
        </div>;
}

def:pub PersonEditor(
    person: dict,
    how_met: str,
    busy: bool,
    error: str,
    note: str,
    onSave: Callable[[str, str, str, str], None],
    onCancel: Callable[[], None],
    onRemove: Callable[[], None]
) -> JsxElement {
    pid: str = (person["_jac_id"] or "") as str;
    has name: str = (person["name"] or "") as str,
        org: str = (person["org"] or "") as str,
        title: str = (person["title"] or "") as str,
        met: str = how_met;

    def ch_name(e: ChangeEvent) {
        name = e.target.value;
    }

    def ch_org(e: ChangeEvent) {
        org = e.target.value;
    }

    def ch_title(e: ChangeEvent) {
        title = e.target.value;
    }

    def ch_met(e: ChangeEvent) {
        met = e.target.value;
    }

    def save() -> None {
        onSave(name.strip(), org.strip(), title.strip(), met.strip());
    }

    return
        <div className="flex flex-col gap-3">
            <EditorField label="Name" htmlFor={"pe-name-" + pid}>
                <Input id={"pe-name-" + pid} value={name} disabled={busy} autoComplete="off" onChange={ch_name} />
            </EditorField>
            <div className="grid grid-cols-2 gap-2">
                <EditorField label="Title" htmlFor={"pe-title-" + pid}>
                    <Input id={"pe-title-" + pid} value={title} disabled={busy} placeholder="e.g. PM" onChange={ch_title} />
                </EditorField>
                <EditorField label="Org" htmlFor={"pe-org-" + pid}>
                    <Input id={"pe-org-" + pid} value={org} disabled={busy} placeholder="e.g. UMich" onChange={ch_org} />
                </EditorField>
            </div>
            <EditorField label="How you met" htmlFor={"pe-met-" + pid}>
                <Input id={"pe-met-" + pid} value={met} disabled={busy} placeholder="e.g. coffee chat — Ross café" onChange={ch_met} />
            </EditorField>
            <EditorFooter
                busy={busy}
                error={error}
                can_save={bool(name.strip())}
                note={note}
                onSave={save}
                onCancel={onCancel}
                onRemove={onRemove}
            />
        </div>;
}

"""One text field (a fact) or text + kind chips (an intent)."""
def:pub TextEditor(
    row_id: str,
    label: str,
    text: str,
    kind: str,
    busy: bool,
    error: str,
    note: str,
    onSave: Callable[[str, str], None],
    onCancel: Callable[[], None],
    onRemove: Callable[[], None]
) -> JsxElement {
    has draft: str = text,
        draft_kind: str = kind;

    def ch_text(e: ChangeEvent) {
        draft = e.target.value;
    }

    def pick_kind(v: str) -> None {
        draft_kind = v;
    }

    def save() -> None {
        onSave(draft.strip(), draft_kind);
    }

    changed: bool = draft.strip() != text.strip() or draft_kind != kind;

    return
        <div className="flex flex-col gap-3">
            {kind and
                <ChipGroup label="Kind" options={INTENT_KINDS} value={draft_kind} onChange={pick_kind} disabled={busy} clearable={False} />}
            <EditorField label={label} htmlFor={"te-" + row_id}>
                <Textarea id={"te-" + row_id} rows={2} value={draft} disabled={busy} onChange={ch_text} />
            </EditorField>
            <EditorFooter
                busy={busy}
                error={error}
                can_save={bool(draft.strip()) and changed}
                note={note}
                onSave={save}
                onCancel={onCancel}
                onRemove={onRemove}
            />
        </div>;
}

def:pub PromiseEditor(
    promise: dict,
    busy: bool,
    error: str,
    note: str,
    onSave: Callable[[str, str], None],
    onCancel: Callable[[], None],
    onRemove: Callable[[], None]
) -> JsxElement {
    prid: str = (promise["_jac_id"] or "") as str;
    has text: str = (promise["text"] or "") as str,
        due: str = (promise["due"] or "") as str;

    def ch_text(e: ChangeEvent) {
        text = e.target.value;
    }

    def ch_due(e: ChangeEvent) {
        due = e.target.value;
    }

    def save() -> None {
        onSave(text.strip(), due.strip());
    }

    return
        <div className="flex flex-col gap-3">
            <EditorField label="What you promised" htmlFor={"pr-text-" + prid}>
                <Textarea id={"pr-text-" + prid} rows={2} value={text} disabled={busy} onChange={ch_text} />
            </EditorField>
            <EditorField label="Due" htmlFor={"pr-due-" + prid}>
                <Input id={"pr-due-" + prid} value={due} disabled={busy} placeholder="e.g. Friday or 2026-10-02" onChange={ch_due} />
            </EditorField>
            <EditorFooter
                busy={busy}
                error={error}
                can_save={bool(text.strip())}
                note={note}
                onSave={save}
                onCancel={onCancel}
                onRemove={onRemove}
            />
        </div>;
}
