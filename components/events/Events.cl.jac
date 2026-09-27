"""Events (SOH-222 A4): where people were met — name, date, location, never a score.

List of events with counts (ListEvents), sorted newest date first; create inline
(name + date + location); edit via a per-row overflow menu (UpdateEvent — no
delete, the walker contract has none); tap an event to see "Who I met there"
(EventPeople) with an "Add people" picker (searchable, AddToEvent) and a remove
control per row. Skeleton, empty state, error line throughout.
"""

import from ..ui.button { Button, buttonVariants }
import from ..ui.input { Input }
import from ..ui.badge { Badge }
import from ..ui.skeleton { Skeleton }
import from ..ui.icons { ChevronRightIcon, MoreIcon, PlusIcon, PencilIcon, XIcon }
import from ..ui.dropdown_menu { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem }
import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody }
import from ..api { create_event, update_event, list_events, add_to_event, remove_from_event, event_people, list_people }
import from ...lib.text { join_with, short_date }
import from ...lib.utils { cn }
sv import from ...schema { Person }

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

"""Sort key: events with no date sort last; ISO dates sort lexicographically
(newest first via `reverse=True`)."""
def _event_sort_key(row: dict) -> str {
    date: str = _s((row["event"] or {}) as dict, "date");
    return date or "0000-00-00";
}

"""One event row: name, date · location, count; tap to open; overflow menu to edit."""
def:pub EventRow(
    row: dict,
    is_editing: bool,
    edit_name: str,
    edit_date: str,
    edit_location: str,
    edit_busy: bool,
    onOpen: Callable[[str, str], None],
    onStartEdit: Callable[[str, str, str, str], None],
    onEditNameChange: Callable[[str], None],
    onEditDateChange: Callable[[str], None],
    onEditLocationChange: Callable[[str], None],
    onSaveEdit: Callable[[], None],
    onCancelEdit: Callable[[], None]
) -> JsxElement {
    event: dict = (row["event"] or {}) as dict;
    eid: str = _s(event, "_jac_id");
    name: str = _s(event, "name");
    date: str = _s(event, "date");
    location: str = _s(event, "location");
    count: int = (row["count"] or 0) as int;
    sub: str = join_with([s for s in [short_date(date) or date, location] if s], " · ");

    def handle_open(e: MouseEvent) {
        onOpen(eid, name);
    }

    def handle_edit_click() {
        onStartEdit(eid, name, date, location);
    }

    def handle_name_input(e: ChangeEvent) {
        onEditNameChange(e.target.value);
    }

    def handle_date_input(e: ChangeEvent) {
        onEditDateChange(e.target.value);
    }

    def handle_location_input(e: ChangeEvent) {
        onEditLocationChange(e.target.value);
    }

    return
        <li className="flex items-center gap-1 pl-4 pr-2">
            {if is_editing {
                <div className="flex flex-1 flex-col gap-2 py-3">
                    <Input value={edit_name} onChange={handle_name_input} aria-label="Event name" placeholder="Event name" />
                    <div className="flex gap-2">
                        <Input type="date" value={edit_date} onChange={handle_date_input} aria-label="Event date" className="flex-1" />
                        <Input value={edit_location} onChange={handle_location_input} aria-label="Event location" placeholder="Location" className="flex-1" />
                    </div>
                    <div className="flex justify-end gap-2">
                        <Button size="sm" variant="ghost" disabled={edit_busy} onClick={onCancelEdit}>Cancel</Button>
                        <Button size="sm" variant="secondary" disabled={edit_busy} onClick={onSaveEdit}>
                            {"Saving…" if edit_busy else "Save"}
                        </Button>
                    </div>
                </div>
            } else {
                <button
                    type="button"
                    onClick={handle_open}
                    className="flex min-h-11 flex-1 items-center justify-between gap-2 py-2.5 text-left outline-none transition-colors hover:bg-secondary focus-visible:bg-secondary focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50"
                >
                    <span className="flex min-w-0 flex-col">
                        <span className="truncate text-body-sm">{name}</span>
                        {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                    </span>
                    <span className="flex items-center gap-2">
                        <span className="text-caption tabular-nums text-muted-foreground">{str(count)}</span>
                        <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />
                    </span>
                </button>
                <DropdownMenu modal={False}>
                    <DropdownMenuTrigger
                        aria-label={"More for " + name}
                        className={cn(buttonVariants().call(None, {"variant": "ghost", "size": "icon-lg"}), "text-muted-foreground focus-visible:ring-inset")}
                    >
                        <MoreIcon />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                        <DropdownMenuItem onSelect={handle_edit_click}>
                            <PencilIcon /> Edit
                        </DropdownMenuItem>
                    </DropdownMenuContent>
                </DropdownMenu>
            }}
        </li>;
}

"""One member row in an event's detail view: tap opens the person, X removes them."""
def:pub AttendeeRow(person: any, busy: bool, onOpen: Callable[[str], None], onRemove: Callable[[str], None]) -> JsxElement {
    pid: str = _s(person, "_jac_id");
    sub: str = join_with([s for s in [_s(person, "title"), _s(person, "org")] if s], ", ");

    def handle_open(e: MouseEvent) {
        if pid {
            onOpen(pid);
        }
    }

    def handle_remove(e: MouseEvent) {
        e.stopPropagation();
        onRemove(pid);
    }

    return
        <li className="flex items-center gap-1">
            <button
                type="button"
                onClick={handle_open}
                className="flex min-h-11 flex-1 items-center justify-between gap-2 py-2.5 pl-4 pr-2 text-left outline-none transition-colors hover:bg-secondary focus-visible:bg-secondary focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50"
            >
                <span className="flex min-w-0 flex-col">
                    <span className="truncate text-body-sm">{_s(person, "name")}</span>
                    {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                </span>
                <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />
            </button>
            <Button
                variant="ghost"
                size="icon-lg"
                disabled={busy}
                aria-label={"Remove " + (_s(person, "name") or "this person")}
                className="mr-2 shrink-0 text-muted-foreground focus-visible:ring-inset"
                onClick={handle_remove}
            >
                <XIcon />
            </Button>
        </li>;
}

"""One row in the add-people picker: Add / already-Added."""
def:pub EventPickerRow(person: any, already_member: bool, busy: bool, onAdd: Callable[[str], None]) -> JsxElement {
    pid: str = _s(person, "_jac_id");
    sub: str = join_with([s for s in [_s(person, "title"), _s(person, "org")] if s], ", ");

    def handle_add(e: MouseEvent) {
        onAdd(pid);
    }

    return
        <li className="flex items-center justify-between gap-2 py-2 pl-4 pr-4">
            <span className="flex min-w-0 flex-col">
                <span className="truncate text-body-sm">{_s(person, "name")}</span>
                {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
            </span>
            {if already_member {
                <Badge variant="secondary">Added</Badge>
            } else {
                <Button size="sm" variant="outline" disabled={busy} onClick={handle_add}>
                    {"Adding…" if busy else "Add"}
                </Button>
            }}
        </li>;
}

def:pub Events(on_open_person: Callable[[str], None]) -> JsxElement {
    has events: list[dict] = [],
        loaded: bool = False,
        load_error: str = "",
        create_name: str = "",
        create_date: str = "",
        create_location: str = "",
        create_busy: bool = False,
        create_error: str = "",
        edit_id: str = "",
        edit_name: str = "",
        edit_date: str = "",
        edit_location: str = "",
        edit_busy: bool = False,
        detail_id: str = "",
        detail_name: str = "",
        detail_people: list[dict] = [],
        detail_loaded: bool = False,
        detail_error: str = "",
        member_busy_id: str = "",
        picker_open: bool = False,
        picker_people: list[Person] = [],
        picker_loaded: bool = False,
        picker_error: str = "",
        picker_query: str = "";

    async can with entry {
        await refresh();
    }

    async def refresh -> None {
        load_error = "";
        got: list[dict] = [];
        try {
            got = await list_events();
            events = got;
        } except Exception as err {
            load_error = "Couldn't load your events. " + str(err);
        }
        loaded = True;
    }

    def edit_create_name(e: ChangeEvent) {
        create_name = e.target.value;
        create_error = "";
    }

    def edit_create_date(e: ChangeEvent) {
        create_date = e.target.value;
    }

    def edit_create_location(e: ChangeEvent) {
        create_location = e.target.value;
    }

    async def handle_create -> None {
        name: str = create_name.strip();
        if not name {
            return;
        }
        create_busy = True;
        create_error = "";
        reply: dict = {};
        try {
            reply = await create_event(name, create_date, create_location);
            if reply["error"] {
                create_error = "Couldn't create that event.";
            } else {
                create_name = "";
                create_date = "";
                create_location = "";
                await refresh();
            }
        } except Exception as err {
            create_error = "Couldn't create that event. " + str(err);
        }
        create_busy = False;
    }

    def start_edit(event_id: str, name: str, date: str, location: str) {
        edit_id = event_id;
        edit_name = name;
        edit_date = date;
        edit_location = location;
    }

    def cancel_edit() {
        edit_id = "";
    }

    def change_edit_name(text: str) {
        edit_name = text;
    }

    def change_edit_date(text: str) {
        edit_date = text;
    }

    def change_edit_location(text: str) {
        edit_location = text;
    }

    async def save_edit -> None {
        name: str = edit_name.strip();
        if not name {
            return;
        }
        edit_busy = True;
        reply: dict = {};
        try {
            reply = await update_event(edit_id, name, edit_date, edit_location);
            if not reply["error"] {
                edit_id = "";
                await refresh();
            }
        } except Exception {
            edit_busy = False;
        }
        edit_busy = False;
    }

    async def open_detail(event_id: str, name: str) -> None {
        detail_id = event_id;
        detail_name = name;
        detail_loaded = False;
        detail_error = "";
        detail_people = [];
        got: list[dict] = [];
        try {
            got = await event_people(event_id);
            detail_people = got;
        } except Exception as err {
            detail_error = "Couldn't load who you met there. " + str(err);
        }
        detail_loaded = True;
    }

    def retry_detail(e: MouseEvent) {
        open_detail(detail_id, detail_name);
    }

    def close_detail() {
        detail_id = "";
        detail_name = "";
    }

    def handle_detail_open_change(v: bool) -> None {
        if not v {
            close_detail();
        }
    }

    async def remove_member(person_id: str) -> None {
        member_busy_id = person_id;
        before: list[dict] = detail_people;
        detail_people = [p for p in before if _s(p, "_jac_id") != person_id];
        reply: dict = {};
        try {
            reply = await remove_from_event(person_id, detail_id);
            if reply["error"] {
                detail_people = before;
            }
        } except Exception {
            detail_people = before;
        }
        member_busy_id = "";
        await refresh();
    }

    async def open_picker -> None {
        picker_open = True;
        picker_error = "";
        picker_query = "";
        picker_loaded = False;
        got: list[Person] = [];
        try {
            got = await list_people();
            picker_people = got;
        } except Exception as err {
            picker_error = "Couldn't load people. " + str(err);
        }
        picker_loaded = True;
    }

    def set_picker_open(v: bool) -> None {
        picker_open = v;
    }

    def edit_picker_query(e: ChangeEvent) {
        picker_query = e.target.value;
    }

    async def add_member(person_id: str) -> None {
        member_busy_id = person_id;
        reply: dict = {};
        try {
            reply = await add_to_event(person_id, detail_id);
            if not reply["error"] {
                got: list[dict] = await event_people(detail_id);
                detail_people = got;
                await refresh();
            }
        } except Exception {
            member_busy_id = "";
        }
        member_busy_id = "";
    }

    sorted_events: list[dict] = sorted(events, key=_event_sort_key, reverse=True);
    member_ids: list[str] = [_s(p, "_jac_id") for p in detail_people];
    query: str = picker_query.strip().lower();
    filtered_picker: list[Person] = [p for p in picker_people if not query or query in _s(p, "name").lower()];

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-3 pr-3 shadow-edge">
                <Input
                    value={create_name}
                    onChange={edit_create_name}
                    placeholder="New event — where you met people"
                    aria-label="New event name"
                />
                <div className="flex gap-2">
                    <Input type="date" value={create_date} onChange={edit_create_date} aria-label="Event date" className="flex-1" />
                    <Input value={create_location} onChange={edit_create_location} placeholder="Location" aria-label="Event location" className="flex-1" />
                </div>
                <Button disabled={create_busy or not create_name.strip()} onClick={handle_create} className="self-end">
                    <PlusIcon /> {"Adding…" if create_busy else "Add event"}
                </Button>
            </div>
            {create_error and <p role="alert" className="text-body-sm text-destructive">{create_error}</p>}
            {load_error and
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{load_error}</p>
                    <Button size="sm" variant="outline" onClick={refresh}>Retry</Button>
                </div>}
            {if not loaded {
                <div role="status" aria-label="Loading your events" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-3 w-1/3" />
                </div>
            } elif len(sorted_events) == 0 and not load_error {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    Events are where you met people — a hackathon, a pitch night, a panel. Never a score.
                </p>
            } else {
                <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                    {for row in sorted_events {
                        <EventRow
                            key={_s(row["event"], "_jac_id")}
                            row={row}
                            is_editing={edit_id == _s(row["event"], "_jac_id")}
                            edit_name={edit_name}
                            edit_date={edit_date}
                            edit_location={edit_location}
                            edit_busy={edit_busy}
                            onOpen={open_detail}
                            onStartEdit={start_edit}
                            onEditNameChange={change_edit_name}
                            onEditDateChange={change_edit_date}
                            onEditLocationChange={change_edit_location}
                            onSaveEdit={save_edit}
                            onCancelEdit={cancel_edit}
                        />
                    }}
                </ul>
            }}
            <Sheet open={detail_id != ""} onOpenChange={handle_detail_open_change}>
                <SheetContent aria-label="Event">
                    <SheetHeader>
                        <SheetTitle>{detail_name}</SheetTitle>
                        <SheetDescription>Who I met there</SheetDescription>
                    </SheetHeader>
                    <SheetBody className="gap-3">
                        <Button variant="secondary" onClick={open_picker}>Add people</Button>
                        {detail_error and
                            <div className="flex items-center gap-2">
                                <p role="alert" className="flex-1 text-body-sm text-destructive">{detail_error}</p>
                                <Button size="sm" variant="outline" onClick={retry_detail}>Retry</Button>
                            </div>}
                        {if not detail_loaded {
                            <div role="status" aria-label="Loading event" className="flex flex-col gap-2">
                                <Skeleton className="h-3.5 w-full" />
                                <Skeleton className="h-3.5 w-2/3" />
                            </div>
                        } elif len(detail_people) == 0 and not detail_error {
                            <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                                No one logged for this event yet. Add people from your graph.
                            </p>
                        } else {
                            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                                {for p in detail_people {
                                    <AttendeeRow
                                        key={_s(p, "_jac_id")}
                                        person={p}
                                        busy={member_busy_id == _s(p, "_jac_id")}
                                        onOpen={on_open_person}
                                        onRemove={remove_member}
                                    />
                                }}
                            </ul>
                        }}
                    </SheetBody>
                </SheetContent>
            </Sheet>
            <Sheet open={picker_open} onOpenChange={set_picker_open}>
                <SheetContent aria-label="Add people">
                    <SheetHeader>
                        <SheetTitle>Add people</SheetTitle>
                        <SheetDescription>{("to " + detail_name) if detail_name else ""}</SheetDescription>
                    </SheetHeader>
                    <SheetBody className="gap-3">
                        <Input
                            value={picker_query}
                            onChange={edit_picker_query}
                            placeholder="Search people…"
                            aria-label="Search people"
                        />
                        {picker_error and
                            <div className="flex items-center gap-2">
                                <p role="alert" className="flex-1 text-body-sm text-destructive">{picker_error}</p>
                                <Button size="sm" variant="outline" onClick={open_picker}>Retry</Button>
                            </div>}
                        {if not picker_loaded {
                            <div role="status" aria-label="Loading people" className="flex flex-col gap-2">
                                <Skeleton className="h-3.5 w-full" />
                                <Skeleton className="h-3.5 w-2/3" />
                            </div>
                        } elif len(filtered_picker) == 0 and not picker_error {
                            <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                                No one matches.
                            </p>
                        } else {
                            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                                {for p in filtered_picker {
                                    <EventPickerRow
                                        key={_s(p, "_jac_id")}
                                        person={p}
                                        already_member={_s(p, "_jac_id") in member_ids}
                                        busy={member_busy_id == _s(p, "_jac_id")}
                                        onAdd={add_member}
                                    />
                                }}
                            </ul>
                        }}
                    </SheetBody>
                </SheetContent>
            </Sheet>
        </div>;
}
