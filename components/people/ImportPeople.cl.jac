"""Bulk import / sort your people (SOH-181). OWNER: Person B (this pass: A,
authorized takeover — Jesse rate-limited).

Three steps, all client-side except the two writes:
  1. Paste  — a textarea ("Paste a list": `Name` / `Name, Org` /
     `Name, Org, Title` / `Name <email>`, one per line, or a CSV with a
     header row) or a file input for `.csv` / `.vcf`. Parsing is entirely
     local (`parse_pasted_text` / `parse_csv_text` / `parse_vcard_text`).
  2. Preview — parsed rows + a count + a "how you know them" default,
     then `ImportPeople(rows, source)` (`components/api_import.cl.jac`).
  3. Sort — the "sort your people" step: every imported/reused person as a
     row with Confirm (`ConfirmPerson`) / Skip (`SkipPerson`), plus a single
     "Confirm all" for the whole batch (`ImportPeople` reports no clusters
     per contracts/walkers.md — the batch itself is the one cluster) and the
     rows the server itself skipped (empty name / duplicate / over 500).

No `str.isalnum()` (no client-runtime polyfill, AGENTS.md) — header-token and
CSV-detection checks below use a fixed-charset membership scan instead.
"""

import from ..ui.button { Button }
import from ..ui.textarea { Textarea }
import from ..ui.input { Input }
import from ..ui.label { Label }
import from ..ui.badge { Badge }
import from ..ui.icons { CheckIcon, XIcon, ChevronLeftIcon }
import from ..api_import { import_people, confirm_person, skip_person }
import from ...lib.text { join_with, linkedin_how_met }
import from ...lib.toast { toast }

glob _NL: str = chr(10),
     _QUOTE: str = chr(34),
     _ALNUM: str = "abcdefghijklmnopqrstuvwxyz0123456789",
     _IMPORT_ROW_LIMIT: int = 500;

# ---------------------------------------------------------------- parsing helpers

"""Lowercase `tok`, keeping only ASCII letters/digits (fixed-charset scan —
no `str.isalnum()`, client gotcha) — collapses "How Met" / "how_met" /
"How-met:" to the same key for flexible header matching."""
def _normalize_header(tok: str) -> str {
    lowered: str = tok.strip().lower();
    out: str = "";
    i: int = 0;
    n: int = len(lowered);
    while i < n {
        ch: str = lowered[i];
        if ch in _ALNUM {
            out = out + ch;
        }
        i = i + 1;
    }
    return out;
}

"""A normalized header token -> one of "name"|"first_name"|"last_name"|"org"|
"title"|"email"|"how_met"|"connected_on"|"url", or "". The last two only show
up on a LinkedIn `Connections.csv` export ("First Name" / "Last Name" /
"Connected On" / "URL") — `url` is otherwise ignored (SOH-181: the row shape
`imports.sv.jac` accepts has no `links` field this weekend)."""
def _header_field(tok: str) -> str {
    key: str = _normalize_header(tok);
    if key in ["name", "fullname", "personname", "contact"] {
        return "name";
    }
    if key == "firstname" {
        return "first_name";
    }
    if key == "lastname" {
        return "last_name";
    }
    if key in ["org", "organization", "company", "employer"] {
        return "org";
    }
    if key in ["title", "role", "jobtitle", "position"] {
        return "title";
    }
    if key in ["email", "emailaddress"] {
        return "email";
    }
    if key in ["howmet", "howyoumet", "source", "met"] {
        return "how_met";
    }
    if key == "connectedon" {
        return "connected_on";
    }
    if key == "url" {
        return "url";
    }
    return "";
}

"""How many of the LinkedIn-export-shaped columns (first/last name, company,
position, connected-on, email address, url) a mapped header row hits."""
def _header_score(mapped: list[str]) -> int {
    score: int = 0;
    if "first_name" in mapped {
        score = score + 1;
    }
    if "last_name" in mapped {
        score = score + 1;
    }
    if "org" in mapped {
        score = score + 1;
    }
    if "title" in mapped {
        score = score + 1;
    }
    if "connected_on" in mapped {
        score = score + 1;
    }
    if "email" in mapped {
        score = score + 1;
    }
    if "url" in mapped {
        score = score + 1;
    }
    return score;
}

"""True when a mapped header row is usable: a single "name" column, a split
first/last name pair, or at least two of the LinkedIn-shaped columns (lets us
skip a `Notes:` / disclaimer preamble LinkedIn's export sometimes puts before
the real header row)."""
def _is_header_row(mapped: list[str]) -> bool {
    if "name" in mapped {
        return True;
    }
    if "first_name" in mapped and "last_name" in mapped {
        return True;
    }
    return _header_score(mapped) >= 2;
}

"""A mapped header row came from LinkedIn's own export shape when it has a
"Connected On" column — no other list we parse uses that header."""
def _is_linkedin_header(mapped: list[str]) -> bool {
    return "connected_on" in mapped;
}

"""One CSV line -> its fields, honoring quoted fields (`"a, b"` stays one
field; `""` inside a quoted field is a literal quote)."""
def parse_csv_line(line: str) -> list[str] {
    fields: list[str] = [];
    cur: str = "";
    in_quotes: bool = False;
    i: int = 0;
    n: int = len(line);
    while i < n {
        ch: str = line[i];
        if in_quotes {
            if ch == _QUOTE {
                if i + 1 < n and line[i + 1] == _QUOTE {
                    cur = cur + _QUOTE;
                    i = i + 2;
                } else {
                    in_quotes = False;
                    i = i + 1;
                }
            } else {
                cur = cur + ch;
                i = i + 1;
            }
        } elif ch == _QUOTE {
            in_quotes = True;
            i = i + 1;
        } elif ch == "," {
            fields.append(cur);
            cur = "";
            i = i + 1;
        } else {
            cur = cur + ch;
            i = i + 1;
        }
    }
    fields.append(cur);
    return fields;
}

"""CSV text with a header row -> `{ rows, error, skipped_no_name, is_linkedin }`.
`error` is "no_header" when no line in the first 15 rows maps to a usable
header (`_is_header_row`); this also skips a LinkedIn export's preamble
("Notes:" / a sentence about missing emails / a blank line) ahead of its real
header row. A LinkedIn header ("First Name" + "Last Name" -> `name`; "Company"
-> `org`; "Position" -> `title`; "Email Address" -> `email`; "URL" ignored
(no `links` field in the row shape this weekend); "Connected On" ->
`how_met` = "LinkedIn connection since <Mon YYYY>") is detected via
`_is_linkedin_header` and reported back as `is_linkedin` for the preview
chip. Rows with an empty (post-combine) name are dropped and counted in
`skipped_no_name`, never added to `rows`."""
def parse_csv_text(text: str) -> dict {
    lines: list[str] = [ln for ln in text.split(_NL) if ln.strip() != ""];
    if len(lines) == 0 {
        return {"rows": [], "error": "empty", "skipped_no_name": 0, "is_linkedin": False};
    }
    header_idx: int = -1;
    mapped: list[str] = [];
    scan_limit: int = len(lines) if len(lines) < 15 else 15;
    i: int = 0;
    while i < scan_limit {
        candidate_fields: list[str] = parse_csv_line(lines[i]);
        candidate: list[str] = [_header_field(h) for h in candidate_fields];
        if _is_header_row(candidate) {
            header_idx = i;
            mapped = candidate;
            break;
        }
        i = i + 1;
    }
    if header_idx < 0 {
        return {"rows": [], "error": "no_header", "skipped_no_name": 0, "is_linkedin": False};
    }
    is_linkedin: bool = _is_linkedin_header(mapped);
    rows: list[dict] = [];
    skipped_no_name: int = 0;
    for ln in lines[header_idx + 1:] {
        cells: list[str] = parse_csv_line(ln);
        row: dict = {"name": "", "org": "", "title": "", "email": "", "how_met": ""};
        first_name: str = "";
        last_name: str = "";
        connected_on: str = "";
        for (idx, field) in enumerate(mapped) {
            if not field or idx >= len(cells) {
                continue;
            }
            cell: str = cells[idx].strip();
            if field == "first_name" {
                first_name = cell;
            } elif field == "last_name" {
                last_name = cell;
            } elif field == "connected_on" {
                connected_on = cell;
            } elif field == "url" {
                continue;
            } else {
                row[field] = cell;
            }
        }
        if not row["name"] and (first_name or last_name) {
            row["name"] = join_with([p for p in [first_name, last_name] if p], " ");
        }
        if is_linkedin and connected_on and not row["how_met"] {
            row["how_met"] = linkedin_how_met(connected_on);
        }
        if row["name"] {
            rows.append(row);
        } else {
            skipped_no_name = skipped_no_name + 1;
        }
    }
    return {"rows": rows, "error": "", "skipped_no_name": skipped_no_name, "is_linkedin": is_linkedin};
}

"""One free-form line -> a row. Forms: `Name`, `Name, Org`, `Name, Org,
Title`, `Name <email>`."""
def parse_free_line(line: str) -> dict {
    trimmed: str = line.strip();
    row: dict = {"name": "", "org": "", "title": "", "email": "", "how_met": ""};
    if not trimmed {
        return row;
    }
    lt: int = trimmed.find("<");
    gt: int = trimmed.find(">");
    remainder: str = trimmed;
    email: str = "";
    if lt >= 0 and gt > lt {
        email = trimmed[lt + 1:gt].strip();
        remainder = (trimmed[:lt] + trimmed[gt + 1:]).strip();
    }
    parts: list[str] = [p.strip() for p in remainder.split(",") if p.strip() != ""];
    if len(parts) > 0 {
        row["name"] = parts[0];
    }
    if len(parts) > 1 {
        row["org"] = parts[1];
    }
    if len(parts) > 2 {
        row["title"] = parts[2];
    }
    row["email"] = email;
    return row;
}

def parse_free_text(text: str) -> list[dict] {
    rows: list[dict] = [];
    for ln in text.split(_NL) {
        if ln.strip() == "" {
            continue;
        }
        row: dict = parse_free_line(ln);
        if row["name"] {
            rows.append(row);
        }
    }
    return rows;
}

"""Pasted textarea content -> `{ rows, source, error, skipped_no_name }`. A
CSV-shaped header (recognizable name column, or a LinkedIn-shaped one) found
within the first 5 lines is treated as CSV (`source` "linkedin" when it's a
LinkedIn header, else "csv"); everything else is one person per line."""
def parse_pasted_text(text: str) -> dict {
    lines: list[str] = [ln for ln in text.split(_NL) if ln.strip() != ""];
    if len(lines) == 0 {
        return {"rows": [], "source": "paste", "error": "empty", "skipped_no_name": 0};
    }
    scan_limit: int = len(lines) if len(lines) < 5 else 5;
    looks_like_csv: bool = False;
    i: int = 0;
    while i < scan_limit {
        header_fields: list[str] = parse_csv_line(lines[i]);
        mapped: list[str] = [_header_field(h) for h in header_fields];
        if len(header_fields) > 1 and _is_header_row(mapped) {
            looks_like_csv = True;
            break;
        }
        i = i + 1;
    }
    if looks_like_csv {
        parsed: dict = parse_csv_text(text);
        src: str = "linkedin" if parsed["is_linkedin"] else "csv";
        return {"rows": parsed["rows"], "source": src, "error": parsed["error"], "skipped_no_name": parsed["skipped_no_name"]};
    }
    rows: list[dict] = parse_free_text(text);
    if len(rows) == 0 {
        return {"rows": [], "source": "paste", "error": "empty", "skipped_no_name": 0};
    }
    return {"rows": rows, "source": "paste", "error": "", "skipped_no_name": 0};
}

"""vCard text (one or many `BEGIN:VCARD`…`END:VCARD` blocks) -> rows, reading
FN/ORG/TITLE/EMAIL. No line folding support (rare in exported contact files)."""
def parse_vcard_text(text: str) -> list[dict] {
    rows: list[dict] = [];
    cur: dict = {};
    active: bool = False;
    for raw_line in text.split(_NL) {
        line: str = raw_line.strip();
        if line == "" {
            continue;
        }
        upper: str = line.upper();
        if upper.startswith("BEGIN:VCARD") {
            cur = {"name": "", "org": "", "title": "", "email": "", "how_met": ""};
            active = True;
            continue;
        }
        if upper.startswith("END:VCARD") {
            if active and cur["name"] {
                rows.append(cur);
            }
            active = False;
            cur = {};
            continue;
        }
        if not active {
            continue;
        }
        colon: int = line.find(":");
        if colon < 0 {
            continue;
        }
        raw_key: str = line[:colon];
        value: str = line[colon + 1:].strip();
        key: str = raw_key.split(";")[0].strip().upper();
        if key == "FN" {
            cur["name"] = value;
        } elif key == "ORG" {
            cur["org"] = value.split(";")[0].strip();
        } elif key == "TITLE" {
            cur["title"] = value;
        } elif key == "EMAIL" and not cur["email"] {
            cur["email"] = value;
        }
    }
    return rows;
}

"""A FileReader read, as text, wrapped in a Promise (same idiom as
`PhotoCapture.cl.jac`'s `read_as_data_url`, `readAsText` instead)."""
def read_as_text(file: any) -> any {
    return new(Promise, lambda(resolve: any, reject: any) {
        reader: any = new(FileReader);  # jac:ignore[W2001,E1053]
        reader.onload = lambda { resolve.call(None, reader.result); };
        reader.onerror = lambda { reject.call(None, reader.error); };
        reader.readAsText(file);
    });
}

"""`n` skipped rows -> "1 row skipped: no name" / "2 rows skipped: no name"."""
def _skipped_no_name_label(n: int) -> str {
    return str(n) + (" row skipped: no name" if n == 1 else " rows skipped: no name");
}

def _reason_label(reason: str) -> str {
    if reason == "empty_name" {
        return "No name";
    }
    if reason == "duplicate_in_batch" {
        return "Duplicate in this batch";
    }
    if reason == "over_limit" {
        return "Over the 500-row limit";
    }
    return reason;
}

def _pid_of(row_entry: dict) -> str {
    person: dict = (row_entry["person"] or {}) as dict;
    return (person["_jac_id"] or "") as str;
}

"""The imported person's display name, looked up by id (for a toast after
confirm/skip, which only gets the id back)."""
def _name_for(entries: list[dict], person_id: str) -> str {
    for entry in entries {
        if _pid_of(entry) == person_id {
            person: dict = (entry["person"] or {}) as dict;
            return (person["name"] or "") as str;
        }
    }
    return "";
}

def _drop_str_key(d: dict, key: str) -> dict {
    out: dict = {};
    for k in list(d.keys()) {
        if k != key {
            out[k] = d[k];
        }
    }
    return out;
}

"""Rows past `_IMPORT_ROW_LIMIT` (the same bound `imports.sv.jac` enforces
server-side) never leave the browser — the client caps up front so the
preview count, the "how many people" text, and the actual import all agree,
and the user gets a plain "run it again" nudge instead of a silent server-side
`over_limit` skip list."""
def _cap_rows(rows: list[dict]) -> dict {
    if len(rows) > _IMPORT_ROW_LIMIT {
        return {"rows": rows[:_IMPORT_ROW_LIMIT], "capped": True};
    }
    return {"rows": rows, "capped": False};
}

# ---------------------------------------------------------------- small components

def:pub EmptyState(children: any = None) -> JsxElement {
    return
        <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
            {children}
        </p>;
}

"""One parsed row in the preview table — no actions, just what will be sent.
`how_met` (e.g. a LinkedIn "since Apr 2023" line) shows as its own caption
line when the row already carries one."""
def:pub PreviewRow(row: dict) -> JsxElement {
    name: str = (row["name"] or "") as str;
    sub: str = join_with([s for s in [(row["title"] or "") as str, (row["org"] or "") as str] if s], ", ");
    email: str = (row["email"] or "") as str;
    how_met: str = (row["how_met"] or "") as str;
    return
        <li className="flex flex-col gap-0.5 py-2.5 pl-4 pr-4">
            <span className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 flex-col">
                    <span className="truncate text-body-sm">{name}</span>
                    {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                </span>
                {email and <span className="shrink-0 max-w-[40%] truncate text-caption text-muted-foreground">{email}</span>}
            </span>
            {how_met and <span className="truncate text-caption text-muted-foreground">{how_met}</span>}
        </li>;
}

"""One row in the "sort your people" step: tap the name to open the person,
Confirm / Skip below (44px targets); swaps to a status line once decided."""
def:pub ImportedRow(
    row_entry: dict,
    decision: str,
    busy: bool,
    error: str,
    onConfirm: Callable[[str], None],
    onSkip: Callable[[str], None],
    onOpen: Callable[[str], None]
) -> JsxElement {
    person: dict = (row_entry["person"] or {}) as dict;
    pid: str = (person["_jac_id"] or "") as str;
    name: str = (person["name"] or "") as str;
    sub: str = join_with([s for s in [(person["title"] or "") as str, (person["org"] or "") as str] if s], ", ");
    is_new: bool = True if row_entry["is_new"] else False;

    def handle_open(e: MouseEvent) {
        if pid {
            onOpen(pid);
        }
    }

    def handle_confirm(e: MouseEvent) {
        onConfirm(pid);
    }

    def handle_skip(e: MouseEvent) {
        onSkip(pid);
    }

    return
        <li className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
            <button
                type="button"
                onClick={handle_open}
                aria-label={"Open " + (name or "this person")}
                className="flex min-h-11 w-full items-center justify-between gap-2 text-left outline-none"
            >
                <span className="flex min-w-0 flex-col">
                    <span className="truncate text-body-sm">{name}</span>
                    {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                </span>
                <Badge variant="outline">{"New" if is_new else "Already knew"}</Badge>
            </button>
            {if decision == "confirmed" {
                <span role="status" className="flex items-center gap-1 text-caption text-success-text">
                    <CheckIcon className="size-3.5" /> Confirmed
                </span>
            } elif decision == "skipped" {
                <span role="status" className="text-caption text-muted-foreground">Skipped</span>
            } else {
                <div className="flex items-center gap-2">
                    <Button
                        size="sm"
                        variant="outline"
                        disabled={busy}
                        aria-label={"Confirm " + (name or "this person")}
                        className="h-11 flex-1"
                        onClick={handle_confirm}
                    >
                        <CheckIcon /> {"Confirming…" if busy else "Confirm"}
                    </Button>
                    <Button
                        size="sm"
                        variant="ghost"
                        disabled={busy}
                        aria-label={"Skip " + (name or "this person")}
                        className="h-11 flex-1"
                        onClick={handle_skip}
                    >
                        <XIcon /> Skip
                    </Button>
                </div>
            }}
            {error and <p role="alert" className="text-caption text-destructive">{error}</p>}
        </li>;
}

# ---------------------------------------------------------------- screen

def:pub ImportPeople(
    on_open_person: Callable[[str], None],
    onDone: Callable[[], None] | None = None,
    onChanged: Callable[[], None] | None = None
) -> JsxElement {
    has step: str = "paste",
        paste_text: str = "",
        how_met_default: str = "",
        parsed_rows: list[dict] = [],
        source: str = "paste",
        parse_error: str = "",
        preview_skipped_no_name: int = 0,
        cap_notice: str = "",
        fileRef: Ref[any] = Ref(),
        file_busy: bool = False,
        file_error: str = "",
        import_busy: bool = False,
        import_error: str = "",
        result: dict = {},
        decisions: dict = {},
        row_busy: dict = {},
        row_error: dict = {},
        confirm_all_busy: bool = False,
        # SOH-232: Confirm/Skip never resolved on screen (row stuck
        # "Confirming…", "N left" never decrementing) even though the server
        # had already confirmed — `has` fields compile to `useState`, and a
        # handler's closure over `decisions`/`row_error`/`row_busy` is frozen
        # at the render the click happened in (`jac-cl-components`: "the
        # closure stays stale until the next render"). Two decisions in
        # flight at once (rapid Confirm/Skip taps, or `confirm_all`'s own
        # await loop) each built their update from that SAME stale snapshot,
        # so whichever resolved last silently overwrote the other's change.
        # These three refs are the ground truth instead: `.current` mutates
        # in place, so every in-flight call reads the latest merged value
        # regardless of which render closed over it (same idiom as
        # `exchange/common.cl.jac`'s `Poller` `latest` ref) — the plain
        # `has` fields above stay purely for rendering, copied from the ref
        # after every mutation.
        decisions_ref: Ref[any] = Ref({}),
        row_error_ref: Ref[any] = Ref({}),
        row_busy_ref: Ref[any] = Ref({});

    def edit_paste(e: ChangeEvent) {
        paste_text = e.target.value;
        parse_error = "";
    }

    def edit_how_met(e: ChangeEvent) {
        how_met_default = e.target.value;
    }

    def do_parse_paste(e: MouseEvent) {
        parsed: dict = parse_pasted_text(paste_text);
        err: str = (parsed["error"] or "") as str;
        if err {
            parse_error = "Paste at least one name: one person per line, or a CSV with a name column.";
            return;
        }
        capped: dict = _cap_rows(parsed["rows"] as list[dict]);
        parsed_rows = capped["rows"] as list[dict];
        cap_notice = "Imported the first " + str(_IMPORT_ROW_LIMIT) + "; run it again for the rest." if (capped["capped"] as bool) else "";
        source = (parsed["source"] or "paste") as str;
        preview_skipped_no_name = (parsed["skipped_no_name"] or 0) as int;
        parse_error = "";
        step = "preview";
    }

    def open_file_picker(e: MouseEvent) {
        if fileRef.current {
            fileRef.current.click();
        }
    }

    async def handle_file(e: ChangeEvent) -> None {
        input_el: any = e.target;
        files: any = input_el.files;
        file: any = files[0] if files and (files.length as int) > 0 else None;
        input_el.value = "";
        if not file {
            return;
        }
        file_error = "";
        file_busy = True;
        fname: str = (file.name or "") as str;
        lower_name: str = fname.lower();
        text: any = None;
        try {
            text = await read_as_text(file);
        } except Exception as err {
            file_busy = False;
            file_error = "Couldn't read that file. " + str(err);
            return;
        }
        file_busy = False;
        content: str = str(text);
        if lower_name.endswith(".vcf") {
            vrows: list[dict] = parse_vcard_text(content);
            if len(vrows) == 0 {
                file_error = "No contacts found in that file.";
                return;
            }
            capped_v: dict = _cap_rows(vrows);
            parsed_rows = capped_v["rows"] as list[dict];
            cap_notice = "Imported the first " + str(_IMPORT_ROW_LIMIT) + "; run it again for the rest." if (capped_v["capped"] as bool) else "";
            source = "vcf";
            preview_skipped_no_name = 0;
            parse_error = "";
            step = "preview";
            return;
        }
        parsed: dict = parse_csv_text(content);
        if (parsed["error"] as str) == "no_header" {
            file_error = "That CSV needs a header row with a name column.";
            return;
        }
        crows: list[dict] = parsed["rows"] as list[dict];
        if len(crows) == 0 {
            file_error = "No rows found in that file.";
            return;
        }
        capped_c: dict = _cap_rows(crows);
        parsed_rows = capped_c["rows"] as list[dict];
        cap_notice = "Imported the first " + str(_IMPORT_ROW_LIMIT) + "; run it again for the rest." if (capped_c["capped"] as bool) else "";
        source = "linkedin" if (parsed["is_linkedin"] as bool) else "csv";
        preview_skipped_no_name = (parsed["skipped_no_name"] or 0) as int;
        parse_error = "";
        step = "preview";
    }

    def back_to_paste(e: MouseEvent) {
        step = "paste";
        import_error = "";
        preview_skipped_no_name = 0;
        cap_notice = "";
    }

    """`busy` on/off for one row — always reads/writes `row_busy_ref.current`
    (never the `has row_busy` snapshot) so two rows in flight at once never
    clobber each other (SOH-232)."""
    def _set_row_busy(person_id: str, busy: bool) -> None {
        next_busy: dict = {**row_busy_ref.current};
        if busy {
            next_busy[person_id] = True;
        } else {
            next_busy = _drop_str_key(next_busy, person_id);
        }
        row_busy_ref.current = next_busy;
        row_busy = next_busy;
    }

    """One row's error line, or clears it (`message == ""`) — same
    ref-is-truth pattern as `_set_row_busy` (SOH-232)."""
    def _set_row_error(person_id: str, message: str) -> None {
        next_err: dict = {**row_error_ref.current};
        if message {
            next_err[person_id] = message;
        } else {
            next_err = _drop_str_key(next_err, person_id);
        }
        row_error_ref.current = next_err;
        row_error = next_err;
    }

    """Records one row's Confirm/Skip decision. Reads `decisions_ref.current`
    (never the `has decisions` snapshot) so `confirm_all`'s own await loop,
    and any other row's overlapping Confirm/Skip, always merge onto the
    latest state instead of each other's stale one (SOH-232 — the bug
    survived a solo click because there was nothing to race against; it
    showed reliably as soon as two rows were in flight together)."""
    def _set_decision(person_id: str, decision: str) -> None {
        next_dec: dict = {**decisions_ref.current};
        next_dec[person_id] = decision;
        decisions_ref.current = next_dec;
        decisions = next_dec;
    }

    async def do_import() -> None {
        import_busy = True;
        import_error = "";
        typed_how_met: str = how_met_default.strip();
        how_met_value: str = typed_how_met if typed_how_met != "" else "from my contacts";
        rows_out: list[dict] = [];
        for row in parsed_rows {
            r: dict = {**row};
            if not (r["how_met"] or "") {
                r["how_met"] = how_met_value;
            }
            rows_out.append(r);
        }
        out: dict = {};
        try {
            out = await import_people(rows_out, source);
        } except Exception as err {
            import_busy = False;
            import_error = "Couldn't import right now. " + str(err);
            return;
        }
        import_busy = False;
        if out["error"] {
            import_error = "Couldn't import right now.";
            return;
        }
        result = out;
        decisions = {};
        decisions_ref.current = {};
        row_error = {};
        row_error_ref.current = {};
        row_busy = {};
        row_busy_ref.current = {};
        step = "sort";
        imported_count: int = len((out["imported"] or []) as list[dict]);
        toast(str(imported_count) + " people imported", "success");
    }

    def handle_import_click(e: MouseEvent) {
        do_import();
    }

    def retry_import(e: MouseEvent) {
        do_import();
    }

    async def confirm_row(person_id: str) -> None {
        _set_row_busy(person_id, True);
        _set_row_error(person_id, "");
        out: dict = {};
        try {
            out = await confirm_person(person_id, "");
        } except Exception as err {
            _set_row_busy(person_id, False);
            _set_row_error(person_id, "Couldn't confirm. " + str(err));
            return;
        }
        _set_row_busy(person_id, False);
        if out["error"] {
            _set_row_error(person_id, "Couldn't confirm that person.");
            return;
        }
        _set_decision(person_id, "confirmed");
        confirmed_name: str = _name_for((result["imported"] or []) as list[dict], person_id);
        toast((confirmed_name if confirmed_name else "Person") + " confirmed", "success");
        if onChanged {
            onChanged();
        }
    }

    async def skip_row(person_id: str) -> None {
        _set_row_busy(person_id, True);
        _set_row_error(person_id, "");
        out: dict = {};
        try {
            out = await skip_person(person_id);
        } except Exception as err {
            _set_row_busy(person_id, False);
            _set_row_error(person_id, "Couldn't skip. " + str(err));
            return;
        }
        _set_row_busy(person_id, False);
        if out["error"] {
            reason: str = (out["error"] or "") as str;
            _set_row_error(person_id, "Already confirmed. Can't skip." if reason == "not_proposed" else "Couldn't skip that person.");
            return;
        }
        _set_decision(person_id, "skipped");
        skipped_name: str = _name_for((result["imported"] or []) as list[dict], person_id);
        toast((skipped_name if skipped_name else "Person") + " skipped");
        if onChanged {
            onChanged();
        }
    }

    async def confirm_all(e: MouseEvent) -> None {
        confirm_all_busy = True;
        imported: list[dict] = (result["imported"] or []) as list[dict];
        for entry in imported {
            pid: str = _pid_of(entry);
            if not pid or pid in decisions_ref.current {
                continue;
            }
            await confirm_row(pid);
        }
        confirm_all_busy = False;
    }

    def start_over(e: MouseEvent) {
        step = "paste";
        paste_text = "";
        parsed_rows = [];
        source = "paste";
        preview_skipped_no_name = 0;
        cap_notice = "";
        parse_error = "";
        file_error = "";
        import_error = "";
        result = {};
        decisions = {};
        decisions_ref.current = {};
        row_error = {};
        row_error_ref.current = {};
        row_busy = {};
        row_busy_ref.current = {};
    }

    def handle_done(e: MouseEvent) {
        if onDone {
            onDone();
        } else {
            start_over(e);
        }
    }

    # SOH-232: the sort step's outer div below carries `pb-20` — the fixed
    # bottom "N people imported" toast (and every later Confirm/Skip toast,
    # `lib/toast.cl.jac`, rendered above the bottom tab bar) otherwise sits
    # directly on top of "Import more"/"Done" whenever this step's content
    # is short enough not to scroll.
    imported_rows: list[dict] = (result["imported"] or []) as list[dict];
    skipped_rows: list[dict] = (result["skipped"] or []) as list[dict];
    pending_count: int = 0;
    for entry in imported_rows {
        pid: str = _pid_of(entry);
        if pid and pid not in decisions {
            pending_count = pending_count + 1;
        }
    }

    return
        <div className="flex flex-col gap-4">
            {if step == "paste" {
                <div key="import-paste" className="flex flex-col gap-4">
                    <div className="flex flex-col gap-1">
                        <h2 className="text-eyebrow text-muted-foreground">Import people</h2>
                        <p className="text-caption text-muted-foreground">
                            Paste a list, one person per line: "Name", "Name, Org", "Name, Org, Title", or "Name &lt;email&gt;", or a CSV with a header row. You can also upload a .csv or .vcf export from your contacts. Or drop in the Connections.csv from LinkedIn's data export (Settings → Data privacy → Get a copy of your data).
                        </p>
                    </div>
                    <Textarea
                        value={paste_text}
                        onChange={edit_paste}
                        placeholder={"e.g. Maya Chen, Stripe Climate, Carbon removal lead"}
                        rows={7}
                        aria-label="Paste a list of people"
                        className="min-h-40"
                    />
                    {parse_error and <p role="alert" className="text-body-sm text-destructive">{parse_error}</p>}
                    <div className="flex flex-wrap items-center gap-2">
                        <Button
                            variant="default"
                            className="h-11"
                            disabled={paste_text.strip() == ""}
                            onClick={do_parse_paste}
                        >
                            Continue
                        </Button>
                        <input
                            ref={fileRef}
                            type="file"
                            accept=".csv,.vcf,text/csv,text/vcard"
                            className="sr-only"
                            tabIndex={-1}
                            aria-hidden="true"
                            onChange={handle_file}
                        />
                        <Button
                            variant="outline"
                            className="h-11"
                            disabled={file_busy}
                            aria-label="Upload a CSV or vCard file"
                            onClick={open_file_picker}
                        >
                            {"Reading…" if file_busy else "Upload .csv / .vcf"}
                        </Button>
                        <Button variant="ghost" className="h-11 text-muted-foreground" onClick={handle_done}>
                            Cancel
                        </Button>
                    </div>
                    {file_error and <p role="alert" className="text-body-sm text-destructive">{file_error}</p>}
                </div>
            } elif step == "preview" {
                <div key="import-preview" className="flex flex-col gap-4">
                    <div className="flex items-center justify-between gap-2">
                        <Button variant="ghost" size="sm" className="-ml-2 h-9" aria-label="Back to paste" onClick={back_to_paste}>
                            <ChevronLeftIcon className="size-4" /> Back
                        </Button>
                        <span className="text-caption tabular-nums text-muted-foreground">{str(len(parsed_rows)) + " people"}</span>
                    </div>
                    {source == "linkedin" and
                        <Badge variant="secondary" className="self-start">{"LinkedIn export · " + str(len(parsed_rows)) + " connections"}</Badge>}
                    {preview_skipped_no_name > 0 and
                        <p className="text-caption text-muted-foreground">{_skipped_no_name_label(preview_skipped_no_name)}</p>}
                    {cap_notice and <p className="text-caption text-muted-foreground">{cap_notice}</p>}
                    <div className="flex flex-col gap-2">
                        <Label htmlFor="import-how-met">How you know them</Label>
                        <Input
                            id="import-how-met"
                            value={how_met_default}
                            onChange={edit_how_met}
                            placeholder="from my contacts"
                            className="h-11"
                        />
                        <p className="text-caption text-muted-foreground">Used for anyone in this list whose row doesn't already say.</p>
                    </div>
                    {if len(parsed_rows) == 0 {
                        <EmptyState>No rows to import.</EmptyState>
                    } else {
                        <ul className="flex max-h-80 flex-col divide-y divide-border overflow-y-auto rounded-lg border bg-card shadow-edge">
                            {for (idx, row) in enumerate(parsed_rows) {
                                <PreviewRow key={str(idx)} row={row} />
                            }}
                        </ul>
                    }}
                    {import_error and
                        <div className="flex items-center justify-between gap-2 rounded-lg border border-dashed border-destructive/30 bg-destructive/5 pt-3 pb-3 pl-3 pr-3">
                            <p role="alert" className="text-body-sm text-destructive">{import_error}</p>
                            <Button size="sm" variant="outline" onClick={retry_import}>Retry</Button>
                        </div>}
                    <Button
                        className="h-11"
                        disabled={import_busy or len(parsed_rows) == 0}
                        onClick={handle_import_click}
                    >
                        {"Importing…" if import_busy else "Import " + str(len(parsed_rows)) + " people"}
                    </Button>
                </div>
            } else {
                <div key="import-sort" className="flex flex-col gap-4 pb-20">
                    <div className="flex items-center justify-between gap-2">
                        <h2 className="text-eyebrow text-muted-foreground">Confirm your people</h2>
                        <span className="text-caption tabular-nums text-muted-foreground">{str(pending_count) + " left"}</span>
                    </div>
                    {if len(imported_rows) == 0 {
                        <EmptyState>Nothing was imported from that batch.</EmptyState>
                    } else {
                        <div className="flex flex-col gap-3">
                            {pending_count > 1 and
                                <Button
                                    variant="default"
                                    size="sm"
                                    className="h-11 self-start"
                                    disabled={confirm_all_busy}
                                    onClick={confirm_all}
                                >
                                    {"Confirming…" if confirm_all_busy else "Confirm all (" + str(pending_count) + ")"}
                                </Button>}
                            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                                {for (idx, entry) in enumerate(imported_rows) {
                                    <ImportedRow
                                        key={_pid_of(entry) or str(idx)}
                                        row_entry={entry}
                                        decision={(decisions[_pid_of(entry)] or "") as str}
                                        busy={(row_busy[_pid_of(entry)] or False) as bool}
                                        error={(row_error[_pid_of(entry)] or "") as str}
                                        onConfirm={confirm_row}
                                        onSkip={skip_row}
                                        onOpen={on_open_person}
                                    />
                                }}
                            </ul>
                        </div>
                    }}
                    {len(skipped_rows) > 0 and
                        <section aria-label="Not imported" className="flex flex-col gap-2">
                            <h3 className="text-eyebrow text-muted-foreground">Not imported</h3>
                            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border border-dashed border-border-strong">
                                {for (idx2, s) in enumerate(skipped_rows) {
                                    <li key={str(idx2)} className="flex items-center justify-between gap-2 py-2 pl-4 pr-4 text-caption text-muted-foreground">
                                        <span className="truncate">{(s["name"] or "(no name)") as str}</span>
                                        <span>{_reason_label((s["reason"] or "") as str)}</span>
                                    </li>
                                }}
                            </ul>
                        </section>}
                    {if pending_count == 0 {
                        <Button className="h-11 self-start" onClick={handle_done}>
                            Done
                        </Button>
                    } else {
                        <div className="flex items-center gap-2">
                            <Button variant="ghost" className="h-11 text-muted-foreground" onClick={start_over}>
                                Import more
                            </Button>
                            <Button variant="outline" className="h-11" onClick={handle_done}>
                                Done
                            </Button>
                        </div>
                    }}
                </div>
            }}
        </div>;
}
