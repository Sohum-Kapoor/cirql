"""Person sheet (SOH-207): everything you know about one person, with receipts.

Opened from a GoalRank row or a Today promise. Header (name, org · title, the
known|route|cold label for the active goal, how you met), the relevance reason,
then collapsible sections — Facts (with age), Wants/Offers, Promises (tick to
complete, optimistic), Notes — each row with a source chip that quotes its span.
Actions: Draft follow-up (a draft to copy; nothing sends), Brief me (spoken
recap; audio plays when the server sent any, text always shows), Forget
(confirmed, then the sheet closes and the caller refreshes).

The caller owns `open` and `person_id`; this owns what it loaded.
"""

import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody }
import from ..ui.badge { Badge }
import from ..ui.button { Button, buttonVariants }
import from ..ui.skeleton { Skeleton }
import from ..ui.textarea { Textarea }
import from ..ui.input { Input }
import from ..ui.icons { ChevronRightIcon, PencilIcon, MoreIcon }
import from ..ui.collapsible { Collapsible, CollapsibleTrigger, CollapsibleContent }
import from ..ui.dropdown_menu { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogFooter, AlertDialogTitle,
    AlertDialogDescription, AlertDialogAction, AlertDialogCancel
}
import from ..capture.Review { ReviewRow }
import from ..capture.ReviewEditors { EditorField, EditorFooter }
import from ..goals.RankList { strength_variant }
import from ..api { person_detail, brief, complete_promise, draft_follow_up, forget, update_person_contact, archive_person }
import from ...lib.text { join_with, short_date }
import from ...lib.utils { cn }

glob _INTENT_LABEL: dict[str, str] = {"need": "wants", "offer": "offers", "open_to": "open to"};

"""Display only: 0 -> "today", 1 -> "1 day ago", 45 -> "1 month ago", 400 -> "1 year ago"."""
def:pub age_label(days: any) -> str {
    if days is None or not ((days as int) >= 0) {
        return "";
    }
    n: int = days as int;
    if n == 0 {
        return "today";
    }
    unit: str = "day";
    count: int = n;
    if n >= 365 {
        unit = "year";
        count = int(n / 365);
    } elif n >= 30 {
        unit = "month";
        count = int(n / 30);
    }
    return str(count) + " " + unit + ("" if count == 1 else "s") + " ago";
}

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

"""One collapsible section; the trigger mirrors HomeView's "People you know"."""
def:pub PersonSection(title: str, count: int, default_open: bool = False, children: any = None) -> JsxElement {
    return
        <Collapsible defaultOpen={default_open} className="overflow-hidden rounded-lg border bg-card shadow-edge">
            <CollapsibleTrigger
                aria-label={title + " — expand or collapse"}
                className={cn(
                    buttonVariants().call(None, {"variant": "ghost", "size": "row"}),
                    "flex-row items-center justify-between rounded-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50 [&[data-state=open]>span>svg]:rotate-90"
                )}
            >
                <span className="flex items-center gap-1.5 text-body-sm font-medium">
                    <ChevronRightIcon className="size-4 text-muted-foreground transition-transform" />
                    {title}
                </span>
                <span className="text-caption tabular-nums text-muted-foreground">{str(count)}</span>
            </CollapsibleTrigger>
            <CollapsibleContent>
                <ul className="flex flex-col divide-y divide-border border-t">{children}</ul>
            </CollapsibleContent>
        </Collapsible>;
}

"""Read-only contact block: email/phone (tappable), location, links (each opens
in a new tab, `rel=noopener`). "No contact details yet" when every field is
empty — the header pencil is still the way in."""
def:pub ContactSection(person: dict) -> JsxElement {
    email: str = _s(person, "email");
    phone: str = _s(person, "phone");
    location: str = _s(person, "location");
    links: list[str] = (person["links"] or []) as list[str];
    has_any: bool = bool(email or phone or location or len(links) > 0);
    return
        <div className="flex flex-col gap-1.5 rounded-lg border bg-card p-3 shadow-edge">
            <span className="text-eyebrow text-muted-foreground">Contact</span>
            {not has_any and <p className="text-body-sm text-muted-foreground">No contact details yet</p>}
            {email and
                <a href={"mailto:" + email} className="truncate text-body-sm text-link underline-offset-4 hover:underline">
                    {email}
                </a>}
            {phone and
                <a href={"tel:" + phone} className="truncate text-body-sm text-link underline-offset-4 hover:underline">
                    {phone}
                </a>}
            {location and <span className="text-body-sm text-foreground">{location}</span>}
            {for link in links {
                <a
                    key={link}
                    href={link}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="truncate text-body-sm text-link underline-offset-4 hover:underline"
                >
                    {link}
                </a>
            }}
        </div>;
}

"""Inline form for the sheet's pencil button: name/org/title/how_met (same
fields Review's PersonEditor edits) plus email/phone/location/links (one per
line). Save always sends the full set; the caller (PersonSheet) trims each
field to only the ones that actually changed before calling the walker."""
def:pub PersonContactEditor(
    person: dict,
    how_met: str,
    busy: bool,
    error: str,
    onSave: Callable[[str, str, str, str, str, str, str, list], None],
    onCancel: Callable[[], None]
) -> JsxElement {
    pid: str = (person["_jac_id"] or "") as str;
    orig_links: list[str] = (person["links"] or []) as list[str];
    has name: str = _s(person, "name"),
        org: str = _s(person, "org"),
        title: str = _s(person, "title"),
        met: str = how_met,
        email: str = _s(person, "email"),
        phone: str = _s(person, "phone"),
        location: str = _s(person, "location"),
        links_text: str = join_with(orig_links, "\n");

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

    def ch_email(e: ChangeEvent) {
        email = e.target.value;
    }

    def ch_phone(e: ChangeEvent) {
        phone = e.target.value;
    }

    def ch_location(e: ChangeEvent) {
        location = e.target.value;
    }

    def ch_links(e: ChangeEvent) {
        links_text = e.target.value;
    }

    def save() -> None {
        links: list[str] = [s.strip() for s in links_text.split("\n") if s.strip()];
        onSave(name.strip(), org.strip(), title.strip(), met.strip(), email.strip(), phone.strip(), location.strip(), links);
    }

    return
        <div className="flex flex-col gap-3 rounded-lg border bg-card p-3 shadow-edge">
            <EditorField label="Name" htmlFor={"ps-name-" + pid}>
                <Input id={"ps-name-" + pid} value={name} disabled={busy} autoComplete="off" onChange={ch_name} />
            </EditorField>
            <div className="grid grid-cols-2 gap-2">
                <EditorField label="Title" htmlFor={"ps-title-" + pid}>
                    <Input id={"ps-title-" + pid} value={title} disabled={busy} placeholder="e.g. PM" onChange={ch_title} />
                </EditorField>
                <EditorField label="Org" htmlFor={"ps-org-" + pid}>
                    <Input id={"ps-org-" + pid} value={org} disabled={busy} placeholder="e.g. UMich" onChange={ch_org} />
                </EditorField>
            </div>
            <EditorField label="How you met" htmlFor={"ps-met-" + pid}>
                <Input id={"ps-met-" + pid} value={met} disabled={busy} placeholder="e.g. coffee chat — Ross café" onChange={ch_met} />
            </EditorField>
            <div className="grid grid-cols-2 gap-2">
                <EditorField label="Email" htmlFor={"ps-email-" + pid}>
                    <Input id={"ps-email-" + pid} type="email" value={email} disabled={busy} onChange={ch_email} />
                </EditorField>
                <EditorField label="Phone" htmlFor={"ps-phone-" + pid}>
                    <Input id={"ps-phone-" + pid} type="tel" value={phone} disabled={busy} onChange={ch_phone} />
                </EditorField>
            </div>
            <EditorField label="Location" htmlFor={"ps-loc-" + pid}>
                <Input id={"ps-loc-" + pid} value={location} disabled={busy} placeholder="e.g. Ann Arbor, MI" onChange={ch_location} />
            </EditorField>
            <EditorField label="Links (one per line)" htmlFor={"ps-links-" + pid}>
                <Textarea id={"ps-links-" + pid} rows={3} value={links_text} disabled={busy} onChange={ch_links} />
            </EditorField>
            <EditorFooter
                busy={busy}
                error={error}
                can_save={bool(name.strip())}
                note=""
                onSave={save}
                onCancel={onCancel}
            />
        </div>;
}

def:pub FactItem(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    fact: dict = (row["fact"] or {}) as dict;
    key: str = "f-" + _s(fact, "_jac_id");
    url: str = _s(fact, "source_url");
    age: str = age_label(row["age_days"]);
    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <span className="text-body-sm">{_s(fact, "text")}</span>
            <span className="flex flex-wrap items-center gap-1.5 text-caption text-muted-foreground">
                {age and <span>{age}</span>}
                {_s(fact, "status") == "stale" and <Badge variant="outline">stale</Badge>}
                {url and
                    <a href={url} target="_blank" rel="noopener noreferrer" className="inline-flex">
                        <Badge variant="link">web</Badge>
                    </a>}
            </span>
        </ReviewRow>;
}

def:pub IntentItem(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    intent: dict = (row["intent"] or {}) as dict;
    key: str = "i-" + _s(intent, "_jac_id");
    kind: str = _s(intent, "kind");
    expired: bool = bool(row["expired"]);
    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <div className="flex flex-wrap items-center gap-1.5">
                <Badge variant={"default" if kind == "need" else "secondary"}>{_INTENT_LABEL[kind] or kind}</Badge>
                {expired and <Badge variant="outline">expired</Badge>}
            </div>
            <span className={cn("text-body-sm", "text-muted-foreground" if expired else "")}>{_s(intent, "text")}</span>
        </ReviewRow>;
}

def:pub PromiseItem(
    row: dict,
    is_done: bool,
    open_key: str,
    onToggle: Callable[[str], None],
    onCheck: Callable[[str, bool], None]
) -> JsxElement {
    promise: dict = (row["promise"] or {}) as dict;
    prid: str = _s(promise, "_jac_id");
    key: str = "p-" + prid;
    due: str = _s(promise, "due");

    def handle_check(e: ChangeEvent) {
        onCheck(prid, bool(e.target.checked));
    }

    return
        <ReviewRow row_key={key} is_open={open_key == key} span={_s(row, "span")} note_text="" onToggle={onToggle}>
            <label className="flex items-start gap-2.5">
                <input
                    type="checkbox"
                    checked={is_done}
                    onChange={handle_check}
                    className="mt-0.5 size-4 shrink-0 accent-primary"
                />
                <span className="flex flex-col gap-0.5">
                    <span className={cn("text-body-sm", "text-muted-foreground line-through" if is_done else "")}>
                        {_s(promise, "text")}
                    </span>
                    {due and <span className="text-caption text-muted-foreground">{"due " + (short_date(due) or due)}</span>}
                </span>
            </label>
        </ReviewRow>;
}

def:pub NoteItem(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    note: dict = (row["note"] or {}) as dict;
    key: str = "n-" + _s(note, "_jac_id");
    span: str = _s(row, "span");
    return
        <ReviewRow row_key={key} is_open={open_key == key} span={span} note_text={_s(note, "text")} onToggle={onToggle}>
            <span className="line-clamp-3 text-body-sm">{_s(note, "text") or span}</span>
            <span className="text-caption text-muted-foreground">
                {join_with([s for s in [_s(note, "kind"), short_date(_s(note, "captured_at"))] if s], " · ")}
            </span>
        </ReviewRow>;
}

def:pub PersonSheet(
    person_id: str,
    open: bool,
    on_close: Callable[[], None],
    on_forgotten: Callable[[str], None] | None = None
) -> JsxElement {
    has detail: dict = {},
        loaded_for: str = "",
        load_error: str = "",
        open_key: str = "",
        done_map: dict = {},
        draft_text: str = "",
        draft_busy: bool = False,
        draft_error: str = "",
        copied: bool = False,
        brief_text: str = "",
        brief_audio: str = "",
        brief_note: str = "",
        brief_busy: bool = False,
        confirm_open: bool = False,
        forget_busy: bool = False,
        forget_error: str = "",
        editing: bool = False,
        edit_busy: bool = False,
        edit_error: str = "",
        archive_confirm_open: bool = False,
        archive_busy: bool = False,
        archive_error: str = "";

    async can with [person_id, open] entry {
        if not open or not person_id {
            return;
        }
        detail = {};
        loaded_for = "";
        load_error = "";
        open_key = "";
        done_map = {};
        draft_text = "";
        draft_error = "";
        copied = False;
        brief_text = "";
        brief_audio = "";
        brief_note = "";
        forget_error = "";
        editing = False;
        edit_error = "";
        archive_error = "";
        got: dict = {};
        try {
            got = await person_detail(person_id);
            detail = got;
            loaded_for = person_id;
        } except Exception as err {
            load_error = "Couldn't load this person. " + str(err);
            loaded_for = person_id;
        }
    }

    def handle_open_change(v: bool) -> None {
        if not v {
            on_close();
        }
    }

    def toggle(key: str) -> None {
        open_key = "" if open_key == key else key;
    }

    async def check_promise(prid: str, done: bool) -> None {
        before: dict = {**done_map};
        after: dict = {**done_map};
        after[prid] = "1" if done else "0";
        done_map = after;
        reply: dict = {};
        try {
            reply = await complete_promise(prid, done);
            if reply["error"] {
                done_map = before;
            }
        } except Exception {
            done_map = before;
        }
    }

    async def run_draft -> None {
        draft_busy = True;
        draft_error = "";
        copied = False;
        reply: dict = {};
        try {
            reply = await draft_follow_up(person_id, "");
            if reply["error"] {
                draft_error = "Couldn't draft for this person.";
            } else {
                draft_text = (reply["draft"] or "") as str;
            }
        } except Exception as err {
            draft_error = "Couldn't draft right now. " + str(err);
        }
        draft_busy = False;
    }

    def edit_draft(e: ChangeEvent) {
        draft_text = e.target.value;
        copied = False;
    }

    async def copy_draft -> None {
        try {
            board: any = navigator.clipboard;
            await board.writeText(draft_text);
            copied = True;
        } except Exception {
            copied = False;
        }
    }

    async def run_brief -> None {
        brief_busy = True;
        brief_note = "";
        brief_audio = "";
        reply: dict = {};
        try {
            reply = await brief(person_id, True);
            if reply["error"] {
                brief_note = "Couldn't brief on this person.";
            } else {
                brief_text = (reply["text"] or "") as str;
                b64: str = (reply["audio_b64"] or "") as str;
                if b64 {
                    brief_audio = "data:" + ((reply["mime"] or "audio/mpeg") as str) + ";base64," + b64;
                } elif reply["voice_error"] {
                    brief_note = "Voice unavailable — text only.";
                }
            }
        } except Exception as err {
            brief_note = "Couldn't brief right now. " + str(err);
        }
        brief_busy = False;
    }

    def ask_forget(e: MouseEvent) {
        forget_error = "";
        confirm_open = True;
    }

    def set_confirm(v: bool) -> None {
        confirm_open = v;
    }

    async def do_forget(e: MouseEvent) -> None {
        e.preventDefault();
        forget_busy = True;
        forget_error = "";
        reply: dict = {};
        gone_id: str = person_id;
        try {
            reply = await forget(gone_id);
            if reply["error"] {
                forget_error = "Couldn't forget this person.";
            } else {
                confirm_open = False;
                on_close();
                if on_forgotten {
                    on_forgotten(gone_id);
                }
            }
        } except Exception as err {
            forget_error = "Couldn't forget right now. " + str(err);
        }
        forget_busy = False;
    }

    def start_edit(e: any) -> None {
        edit_error = "";
        editing = True;
    }

    def cancel_edit() -> None {
        editing = False;
        edit_error = "";
    }

    """UpdatePerson(person_id, name, org, title, how_met, email, phone, location,
    links) — only the fields that actually changed are sent non-empty (an
    unchanged field must not overwrite whatever the server already has).
    Optimistic: the sheet updates immediately and rolls back on error."""
    async def save_contact(
        name: str, org: str, title: str, how_met_v: str,
        email: str, phone: str, location: str, links: list[str]
    ) -> None {
        edit_busy = True;
        edit_error = "";
        cur_person: dict = (detail["person"] or {}) as dict;
        cur_how_met: str = _s(detail, "how_met");
        orig_links: list[str] = (cur_person["links"] or []) as list[str];
        send_name: str = name if name != _s(cur_person, "name") else "";
        send_org: str = org if org != _s(cur_person, "org") else "";
        send_title: str = title if title != _s(cur_person, "title") else "";
        send_met: str = how_met_v if how_met_v != cur_how_met else "";
        send_email: str = email if email != _s(cur_person, "email") else "";
        send_phone: str = phone if phone != _s(cur_person, "phone") else "";
        send_location: str = location if location != _s(cur_person, "location") else "";
        send_links: list[str] = links if join_with(links, "\n") != join_with(orig_links, "\n") else [];

        before: dict = {**detail};
        updated_person: dict = {**cur_person};
        updated_person["name"] = name;
        updated_person["org"] = org;
        updated_person["title"] = title;
        updated_person["email"] = email;
        updated_person["phone"] = phone;
        updated_person["location"] = location;
        updated_person["links"] = links;
        new_detail: dict = {**detail};
        new_detail["person"] = updated_person;
        new_detail["how_met"] = how_met_v;
        detail = new_detail;
        editing = False;

        out: dict = {};
        try {
            out = await update_person_contact(
                person_id, send_name, send_org, send_title, send_met,
                send_email, send_phone, send_location, send_links
            );
            if out["error"] {
                detail = before;
                edit_error = "Couldn't save — try again.";
                editing = True;
            }
        } except Exception as err {
            detail = before;
            edit_error = "Couldn't save right now. " + str(err);
            editing = True;
        }
        edit_busy = False;
    }

    def ask_archive(e: any) -> None {
        archive_error = "";
        archive_confirm_open = True;
    }

    def set_archive_confirm(v: bool) -> None {
        archive_confirm_open = v;
    }

    """ArchivePerson: hides them from lists/rankings (restorable), never touches
    facts/intents/promises/edges — unlike Forget. Same close-and-refresh
    callback (`on_forgotten`) as Forget uses, so the caller's list drops the row
    either way."""
    async def do_archive(e: any) -> None {
        e.preventDefault();
        archive_busy = True;
        archive_error = "";
        reply: dict = {};
        gone_id: str = person_id;
        try {
            reply = await archive_person(gone_id);
            if reply["error"] {
                archive_error = "Couldn't archive this person.";
            } else {
                archive_confirm_open = False;
                on_close();
                if on_forgotten {
                    on_forgotten(gone_id);
                }
            }
        } except Exception as err {
            archive_error = "Couldn't archive right now. " + str(err);
        }
        archive_busy = False;
    }

    ready: bool = loaded_for == person_id and loaded_for != "";
    missing: bool = ready and bool(detail["error"]);
    person: dict = (detail["person"] or {}) as dict;
    rel: dict = (detail["relevance"] or {}) as dict;
    facts: list[dict] = (detail["facts"] or []) as list[dict];
    intents: list[dict] = (detail["intents"] or []) as list[dict];
    promises: list[dict] = (detail["promises"] or []) as list[dict];
    notes: list[dict] = (detail["notes"] or []) as list[dict];
    how_met: str = _s(detail, "how_met");
    sub: str = join_with([s for s in [_s(person, "org"), _s(person, "title")] if s], " · ");
    done_of: dict = {};
    for row in promises {
        prid: str = _s(row["promise"], "_jac_id");
        flag: str = (done_map[prid] or "") as str;
        done_of[prid] = (flag == "1") if flag else bool(row["promise"]["done"]);
    }

    return
        <Sheet open={open} onOpenChange={handle_open_change}>
            <SheetContent aria-label="Person">
                {if not ready {
                    <SheetHeader>
                        <SheetTitle className="sr-only">Loading</SheetTitle>
                        <SheetDescription className="sr-only">Loading this person</SheetDescription>
                        <div role="status" aria-label="Loading" className="flex flex-col gap-2">
                            <Skeleton className="h-5 w-40" />
                            <Skeleton className="h-3.5 w-56" />
                        </div>
                    </SheetHeader>
                    <SheetBody>
                        <Skeleton className="h-3.5 w-full" />
                        <Skeleton className="h-12 w-full rounded-lg" />
                        <Skeleton className="h-12 w-full rounded-lg" />
                    </SheetBody>
                } elif load_error or missing {
                    <SheetHeader>
                        <SheetTitle>Not found</SheetTitle>
                        <SheetDescription>
                            {load_error or "This person isn't in your graph any more."}
                        </SheetDescription>
                    </SheetHeader>
                } else {
                    <SheetHeader>
                        <div className="flex flex-wrap items-center justify-between gap-2">
                            <div className="flex flex-wrap items-center gap-2">
                                <SheetTitle>{_s(person, "name")}</SheetTitle>
                                {rel and _s(rel, "label") and <Badge variant="outline">{_s(rel, "label")}</Badge>}
                                {rel and _s(rel, "strength") and
                                    <Badge variant={strength_variant(_s(rel, "strength"))}>{_s(rel, "strength")}</Badge>}
                            </div>
                            {not editing and
                                <Button
                                    size="icon-lg"
                                    variant="ghost"
                                    aria-label="Edit this person"
                                    className="shrink-0 text-muted-foreground"
                                    onClick={start_edit}
                                >
                                    <PencilIcon />
                                </Button>}
                        </div>
                        <SheetDescription>
                            {join_with([s for s in [sub, ("met: " + how_met) if how_met else ""] if s], " — ") or "No details yet"}
                        </SheetDescription>
                    </SheetHeader>
                    <SheetBody className="gap-4">
                        {rel and _s(rel, "reason") and
                            <p className="text-body-sm text-muted-foreground">{_s(rel, "reason")}</p>}
                        {(
                            <PersonContactEditor
                                person={person}
                                how_met={how_met}
                                busy={edit_busy}
                                error={edit_error}
                                onSave={save_contact}
                                onCancel={cancel_edit}
                            /> if editing else <ContactSection person={person} />
                        )}
                        <div className="grid grid-cols-2 gap-2">
                            <Button variant="secondary" disabled={draft_busy} onClick={run_draft}>
                                {"Drafting…" if draft_busy else "Draft follow-up"}
                            </Button>
                            <Button variant="secondary" disabled={brief_busy} onClick={run_brief}>
                                {"Briefing…" if brief_busy else "Brief me"}
                            </Button>
                        </div>
                        {draft_error and <p role="alert" className="text-body-sm text-destructive">{draft_error}</p>}
                        {draft_text and
                            <div className="flex flex-col gap-2">
                                <span className="text-eyebrow text-muted-foreground">Draft — copy it; nothing sends</span>
                                <Textarea aria-label="Follow-up draft" value={draft_text} onChange={edit_draft} />
                                <Button size="sm" variant="outline" className="self-end" onClick={copy_draft}>
                                    {"Copied" if copied else "Copy"}
                                </Button>
                            </div>}
                        {(brief_text or brief_note) and
                            <div className="flex flex-col gap-2 rounded-md border-l-2 border-primary bg-secondary pt-2 pb-2 pl-3 pr-3">
                                <span className="text-eyebrow text-muted-foreground">Brief</span>
                                {brief_audio and <audio controls={True} autoPlay={True} src={brief_audio} className="w-full" />}
                                {brief_text and <p className="text-body-sm">{brief_text}</p>}
                                {brief_note and <p className="text-caption text-muted-foreground">{brief_note}</p>}
                            </div>}
                        <PersonSection title="Facts" count={len(facts)} default_open={True}>
                            {for row in facts {
                                <FactItem key={_s(row["fact"], "_jac_id")} row={row} open_key={open_key} onToggle={toggle} />
                            }}
                        </PersonSection>
                        <PersonSection title="Wants / offers" count={len(intents)}>
                            {for row in intents {
                                <IntentItem key={_s(row["intent"], "_jac_id")} row={row} open_key={open_key} onToggle={toggle} />
                            }}
                        </PersonSection>
                        <PersonSection title="Promises" count={len(promises)} default_open={len(promises) > 0}>
                            {for row in promises {
                                <PromiseItem
                                    key={_s(row["promise"], "_jac_id")}
                                    row={row}
                                    is_done={bool(done_of[_s(row["promise"], "_jac_id")])}
                                    open_key={open_key}
                                    onToggle={toggle}
                                    onCheck={check_promise}
                                />
                            }}
                        </PersonSection>
                        <PersonSection title="Notes" count={len(notes)}>
                            {for row in notes {
                                <NoteItem key={_s(row["note"], "_jac_id")} row={row} open_key={open_key} onToggle={toggle} />
                            }}
                        </PersonSection>
                        <div className="flex items-center gap-2">
                            <Button variant="secondary" className="flex-1" onClick={ask_archive}>Archive</Button>
                            <DropdownMenu>
                                <DropdownMenuTrigger asChild={True}>
                                    <Button size="icon-lg" variant="outline" aria-label="More actions for this person">
                                        <MoreIcon />
                                    </Button>
                                </DropdownMenuTrigger>
                                <DropdownMenuContent align="end">
                                    <DropdownMenuItem variant="destructive" onSelect={ask_forget}>
                                        Forget permanently
                                    </DropdownMenuItem>
                                </DropdownMenuContent>
                            </DropdownMenu>
                        </div>
                    </SheetBody>
                    <AlertDialog open={archive_confirm_open} onOpenChange={set_archive_confirm}>
                        <AlertDialogContent>
                            <AlertDialogHeader>
                                <AlertDialogTitle>{"Archive " + (_s(person, "name") or "this person") + "?"}</AlertDialogTitle>
                                <AlertDialogDescription>
                                    Hides them from lists and rankings. Restore any time from Settings.
                                </AlertDialogDescription>
                            </AlertDialogHeader>
                            {archive_error and <p role="alert" className="text-body-sm text-destructive">{archive_error}</p>}
                            <AlertDialogFooter>
                                <AlertDialogCancel disabled={archive_busy}>Cancel</AlertDialogCancel>
                                <AlertDialogAction disabled={archive_busy} onClick={do_archive}>
                                    {"Archiving…" if archive_busy else "Archive"}
                                </AlertDialogAction>
                            </AlertDialogFooter>
                        </AlertDialogContent>
                    </AlertDialog>
                    <AlertDialog open={confirm_open} onOpenChange={set_confirm}>
                        <AlertDialogContent>
                            <AlertDialogHeader>
                                <AlertDialogTitle>{"Forget " + (_s(person, "name") or "this person") + "?"}</AlertDialogTitle>
                                <AlertDialogDescription>
                                    Removes them and everything only about them from your graph. Your notes stay.
                                </AlertDialogDescription>
                            </AlertDialogHeader>
                            {forget_error and <p role="alert" className="text-body-sm text-destructive">{forget_error}</p>}
                            <AlertDialogFooter>
                                <AlertDialogCancel disabled={forget_busy}>Cancel</AlertDialogCancel>
                                <AlertDialogAction variant="destructive" disabled={forget_busy} onClick={do_forget}>
                                    {"Forgetting…" if forget_busy else "Forget"}
                                </AlertDialogAction>
                            </AlertDialogFooter>
                        </AlertDialogContent>
                    </AlertDialog>
                }}
            </SheetContent>
        </Sheet>;
}
