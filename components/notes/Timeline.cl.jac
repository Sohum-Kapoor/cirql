"""Notes timeline (SOH-222, client brief C notes): every note you've captured,
newest first, grouped by day ("Today", "Yesterday", "Sep 24").

Each row: a kind badge (debrief / pasted note / import / badge photo /
about-me), a 2-line preview that expands to the full text, people chips
(tap -> `on_open_person(id)`), a facts/intents/promises count line, a small
audio player when the note carries a voice memo, and Delete (confirmed via
AlertDialog: "Deletes this note and only the facts, wants and promises that
came from it alone. People stay.") -> `DeleteNote`, then the row is removed.
Chips along the top filter by kind. "Load older" pages by the oldest row's
`captured_at`.
"""

import from ..ui.badge { Badge }
import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..ui.icons { TrashIcon, MicIcon }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogFooter, AlertDialogTitle,
    AlertDialogDescription, AlertDialogAction, AlertDialogCancel
}
import from ..capture.guided { local_date }
import from ..api { list_notes, delete_note }
import from ...lib.text { join_with, short_date, kind_label }
import from ...lib.utils { cn }
import from ...lib.toast { toast }

glob _PAGE_SIZE: int = 50;

glob _FILTER_KINDS: list[str] = ["", "debrief", "paste", "import", "about_me"];

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

"""A note's kind badge text: "paste" + "Badge photo" text -> the photo label;
otherwise `kind_label(kind)` (SOH-226)."""
def _kind_badge(kind: str, text: str) -> str {
    if kind == "paste" and text.startswith("Badge photo") {
        return kind_label("photo");
    }
    return kind_label(kind);
}

def _count_line(counts: dict) -> str {
    facts: int = (counts["facts"] or 0) as int;
    intents: int = (counts["intents"] or 0) as int;
    promises: int = (counts["promises"] or 0) as int;
    parts: list[str] = [];
    if facts > 0 {
        parts = parts + [str(facts) + " fact" + ("" if facts == 1 else "s")];
    }
    if intents > 0 {
        parts = parts + [str(intents) + " want" + ("" if intents == 1 else "s")];
    }
    if promises > 0 {
        parts = parts + [str(promises) + " promise" + ("" if promises == 1 else "s")];
    }
    return join_with(parts, " · ");
}

def _is_word_char(ch: str) -> bool {
    return ch in "abcdefghijklmnopqrstuvwxyz0123456789";
}

"""Case-insensitive, whole-word replace of `word` with `replacement` inside
`text` - used only to capitalise a known source name for DISPLAY; the caller
never writes the result back to the Note."""
def _replace_whole_word(text: str, word: str, replacement: str) -> str {
    lower_text: str = text.lower();
    result: str = "";
    i = 0;
    n = len(text);
    wl = len(word);
    while i < n {
        matched = False;
        if i + wl <= n and lower_text[i:i + wl] == word {
            before_ok = (i == 0) or (not _is_word_char(text[i - 1]));
            after_ok = (i + wl >= n) or (not _is_word_char(lower_text[i + wl]));
            if before_ok and after_ok {
                matched = True;
            }
        }
        if matched {
            result = result + replacement;
            i = i + wl;
        } else {
            result = result + text[i];
            i = i + 1;
        }
    }
    return result;
}

"""Known import-source names capitalised for display ("from csv" -> "from
CSV") - the stored Note.text (server text) is never mutated."""
def _capitalize_sources(text: str) -> str {
    out: str = text;
    out = _replace_whole_word(out, "linkedin", "LinkedIn");
    out = _replace_whole_word(out, "csv", "CSV");
    out = _replace_whole_word(out, "paste", "Paste");
    return out;
}

""""YYYY-MM-DDTHH:MM:SSZ" -> "Today" | "Yesterday" | "Sep 24" (local calendar day)."""
def _day_label(captured_at: str) -> str {
    date_part: str = captured_at[0:10] if len(captured_at) >= 10 else "";
    if date_part and date_part == local_date(0) {
        return "Today";
    }
    if date_part and date_part == local_date(1) {
        return "Yesterday";
    }
    return short_date(captured_at) or date_part or captured_at;
}

"""Groups rows (already newest-first) into consecutive same-day buckets."""
def _group_by_day(rows: list[dict]) -> list[dict] {
    out: list[dict] = [];
    cur_label: str = "";
    cur_items: list[dict] = [];
    for row in rows {
        note: dict = (row["note"] or {}) as dict;
        label: str = _day_label(_s(note, "captured_at"));
        if label != cur_label and len(cur_items) > 0 {
            out = out + [{"label": cur_label, "items": cur_items}];
            cur_items = [];
        }
        cur_label = label;
        cur_items = cur_items + [row];
    }
    if len(cur_items) > 0 {
        out = out + [{"label": cur_label, "items": cur_items}];
    }
    return out;
}

def:pub NoteFilterChip(label: str, kind: str, active: bool, onSelect: Callable[[str], None]) -> JsxElement {
    def handle_click(e: MouseEvent) {
        onSelect(kind);
    }
    return
        <Button variant={"default" if active else "outline"} size="xs" aria-pressed={active} onClick={handle_click}>
            {label}
        </Button>;
}

def:pub NotePersonChip(person_id: str, name: str, onOpenPerson: Callable[[str], None]) -> JsxElement {
    def handle_click(e: MouseEvent) {
        if person_id {
            onOpenPerson(person_id);
        }
    }
    return
        <Button variant="chip" size="chip" onClick={handle_click}>{name}</Button>;
}

"""Tries `/uploads/<audio_ref>`; falls back to "voice memo" text when the
path isn't served (dev / mock)."""
def:pub NoteAudioPlayer(audio_ref: str) -> JsxElement {
    has failed: bool = False;

    def handle_error(e: Event) {
        failed = True;
    }

    return
        <div className="flex items-center gap-2">
            {if failed {
                <span className="flex items-center gap-1 text-caption text-muted-foreground">
                    <MicIcon className="size-3.5" />
                    voice memo
                </span>
            } else {
                <audio controls={True} src={"/uploads/" + audio_ref} onError={handle_error} className="h-8 max-w-[220px]" />
            }}
        </div>;
}

def:pub NoteDayGroup(label: str, children: any = None) -> JsxElement {
    return
        <section className="flex flex-col gap-2">
            <h2 className="text-eyebrow text-muted-foreground">{label}</h2>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">{children}</ul>
        </section>;
}

def:pub NoteRow(
    row: dict,
    expanded_map: dict,
    onToggleExpand: Callable[[str], None],
    onOpenPerson: Callable[[str], None],
    onDelete: Callable[[str], None]
) -> JsxElement {
    note: dict = (row["note"] or {}) as dict;
    nid: str = _s(note, "_jac_id");
    kind: str = _s(note, "kind");
    text: str = _s(note, "text");
    preview: str = ((row["text_preview"] or text) as str);
    audio_ref: str = _s(note, "audio_ref");
    people: list[dict] = (row["people"] or []) as list[dict];
    counts: dict = (row["counts"] or {}) as dict;
    count_line: str = _count_line(counts);
    flag: str = (expanded_map[nid] or "") as str;
    is_expanded: bool = flag == "1";
    can_expand: bool = bool(text) and preview != text;

    def handle_toggle(e: MouseEvent) {
        onToggleExpand(nid);
    }

    def handle_delete(e: MouseEvent) {
        onDelete(nid);
    }

    return
        <li data-row={nid} className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
            <div className="flex items-start justify-between gap-2">
                <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                    <Badge variant="secondary" className="self-start">{_kind_badge(kind, text)}</Badge>
                    <p className={cn("text-body-sm", "" if is_expanded else "line-clamp-2")}>
                        {_capitalize_sources(text) if is_expanded else _capitalize_sources(preview)}
                    </p>
                    {can_expand and
                        <Button variant="link" size="inline" className="self-start text-caption" onClick={handle_toggle}>
                            {"Less" if is_expanded else "More"}
                        </Button>}
                    {len(people) > 0 and
                        <div className="flex flex-wrap gap-1">
                            {for p in people {
                                <NotePersonChip key={_s(p, "id")} person_id={_s(p, "id")} name={_s(p, "name")} onOpenPerson={onOpenPerson} />
                            }}
                        </div>}
                    {count_line and <span className="text-caption text-muted-foreground">{count_line}</span>}
                    {audio_ref and <NoteAudioPlayer audio_ref={audio_ref} />}
                </div>
                <Button
                    variant="ghost"
                    size="icon-lg"
                    className="shrink-0 text-muted-foreground"
                    aria-label="Delete note"
                    onClick={handle_delete}
                >
                    <TrashIcon className="size-3.5" />
                </Button>
            </div>
        </li>;
}

def:pub Timeline(on_open_person: Callable[[str], None]) -> JsxElement {
    has rows: list[dict] = [],
        loaded: bool = False,
        load_error: str = "",
        loading_more: bool = False,
        has_more: bool = True,
        kind_filter: str = "",
        expanded: dict = {},
        confirm_id: str = "",
        delete_busy: bool = False,
        delete_error: str = "",
        retry_tick: int = 0;

    async can with [kind_filter, retry_tick] entry {
        load_error = "";
        loaded = False;
        has_more = True;
        got: list[dict] = [];
        try {
            got = await list_notes(_PAGE_SIZE, "", kind_filter);
            rows = got;
            has_more = len(got) >= _PAGE_SIZE;
        } except Exception as err {
            load_error = "Couldn't load your notes. " + str(err);
            rows = [];
            has_more = False;
        }
        loaded = True;
    }

    def retry_load() {
        retry_tick = retry_tick + 1;
    }

    def set_filter(kind: str) {
        expanded = {};
        kind_filter = kind;
    }

    def toggle_expand(note_id: str) {
        before: dict = {**expanded};
        flag: str = (before[note_id] or "") as str;
        after: dict = {**expanded};
        after[note_id] = "" if flag == "1" else "1";
        expanded = after;
    }

    async def load_more -> None {
        if len(rows) == 0 or loading_more or not has_more {
            return;
        }
        oldest: dict = (rows[len(rows) - 1]["note"] or {}) as dict;
        oldest_at: str = _s(oldest, "captured_at");
        loading_more = True;
        got: list[dict] = [];
        try {
            got = await list_notes(_PAGE_SIZE, oldest_at, kind_filter);
            rows = rows + got;
            has_more = len(got) >= _PAGE_SIZE;
        } except Exception {
            has_more = False;
        }
        loading_more = False;
    }

    def ask_delete(note_id: str) {
        delete_error = "";
        confirm_id = note_id;
    }

    def set_confirm(v: bool) {
        if not v {
            confirm_id = "";
        }
    }

    async def do_delete(e: MouseEvent) -> None {
        e.preventDefault();
        gone_id: str = confirm_id;
        delete_busy = True;
        delete_error = "";
        reply: dict = {};
        try {
            reply = await delete_note(gone_id);
            if reply["error"] {
                delete_error = "Couldn't delete this note.";
            } else {
                rows = [r for r in rows if _s(r["note"], "_jac_id") != gone_id];
                confirm_id = "";
                facts_gone: int = ((reply["deleted"] or {}) as dict)["facts"] as int;
                toast("Note deleted · " + str(facts_gone) + " facts retracted", "success");
            }
        } except Exception as err {
            delete_error = "Couldn't delete right now. " + str(err);
        }
        delete_busy = False;
    }

    groups: list[dict] = _group_by_day(rows);

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filter notes by kind">
                {for fk in _FILTER_KINDS {
                    <NoteFilterChip
                        key={fk}
                        label={"All" if fk == "" else kind_label(fk)}
                        kind={fk}
                        active={kind_filter == fk}
                        onSelect={set_filter}
                    />
                }}
            </div>
            {load_error and
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{load_error}</p>
                    <Button size="sm" variant="outline" onClick={retry_load}>Retry</Button>
                </div>}
            {if not loaded {
                <div role="status" aria-label="Loading your notes" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-3 w-1/2" />
                    <Skeleton className="h-3 w-1/3" />
                </div>
            } elif len(rows) == 0 and not load_error {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    No notes yet. Capture a conversation and it lands here.
                </p>
            } else {
                for group in groups {
                    <NoteDayGroup key={group["label"] as str} label={group["label"] as str}>
                        {for row in (group["items"] as list[dict]) {
                            <NoteRow
                                key={_s(row["note"], "_jac_id")}
                                row={row}
                                expanded_map={expanded}
                                onToggleExpand={toggle_expand}
                                onOpenPerson={on_open_person}
                                onDelete={ask_delete}
                            />
                        }}
                    </NoteDayGroup>
                }
                if has_more {
                    <Button variant="outline" className="w-full" disabled={loading_more} onClick={load_more}>
                        {"Loading…" if loading_more else "Load older"}
                    </Button>
                }
            }}
            <AlertDialog open={confirm_id != ""} onOpenChange={set_confirm}>
                <AlertDialogContent>
                    <AlertDialogHeader>
                        <AlertDialogTitle>Delete this note?</AlertDialogTitle>
                        <AlertDialogDescription>
                            Deletes this note and only the facts, wants and promises that came from it alone. People stay.
                        </AlertDialogDescription>
                    </AlertDialogHeader>
                    {delete_error and <p role="alert" className="text-body-sm text-destructive">{delete_error}</p>}
                    <AlertDialogFooter>
                        <AlertDialogCancel disabled={delete_busy}>Cancel</AlertDialogCancel>
                        <AlertDialogAction variant="destructive" disabled={delete_busy} onClick={do_delete}>
                            {"Deleting…" if delete_busy else "Delete"}
                        </AlertDialogAction>
                    </AlertDialogFooter>
                </AlertDialogContent>
            </AlertDialog>
        </div>;
}
