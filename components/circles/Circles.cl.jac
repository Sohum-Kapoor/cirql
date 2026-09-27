"""Circles (SOH-222 A4): the user's own labels for people — never a score.

List of circles with counts (ListCircles); create inline; rename/delete via a
per-row overflow menu (delete only removes the label — "Removes the circle
only. People stay."); tap a circle to drill into its people (ListPeople scoped
by circle_id) with an "Add people" picker (searchable, AddToCircle) and a
remove control per row. Skeleton, empty state, error line throughout; nothing
here ever shows a score or a worth number.
"""

import from ..ui.button { Button, buttonVariants }
import from ..ui.input { Input }
import from ..ui.badge { Badge }
import from ..ui.skeleton { Skeleton }
import from ..ui.icons { ChevronRightIcon, MoreIcon, PlusIcon, PencilIcon, TrashIcon, XIcon }
import from ..ui.dropdown_menu { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem }
import from ..ui.sheet { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription, SheetBody }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogFooter, AlertDialogTitle,
    AlertDialogDescription, AlertDialogAction, AlertDialogCancel
}
import from ..api { create_circle, rename_circle, delete_circle, add_to_circle, remove_from_circle, list_circles, list_people_scoped, list_people }
import from ...lib.text { join_with }
import from ...lib.utils { cn }
import from ...lib.toast { toast }
sv import from ...schema { Person }

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

"""The circle's own name, looked up by id from the `circles` rows (`{circle,
count}` each) — used for a toast after delete, which only has the id."""
def _circle_name(rows: list[dict], circle_id: str) -> str {
    for row in rows {
        circle: dict = (row["circle"] or {}) as dict;
        if _s(circle, "_jac_id") == circle_id {
            return _s(circle, "name");
        }
    }
    return "";
}

"""One circle row: name + count, tap to open; overflow menu for rename/delete;
swaps to an inline rename form in place when `is_renaming`."""
def:pub CircleRow(
    row: dict,
    is_renaming: bool,
    rename_text: str,
    rename_busy: bool,
    onOpen: Callable[[str, str], None],
    onStartRename: Callable[[str, str], None],
    onRenameChange: Callable[[str], None],
    onSaveRename: Callable[[], None],
    onCancelRename: Callable[[], None],
    onAskDelete: Callable[[str], None]
) -> JsxElement {
    circle: dict = (row["circle"] or {}) as dict;
    cid: str = _s(circle, "_jac_id");
    name: str = _s(circle, "name");
    count: int = (row["count"] or 0) as int;

    def handle_open(e: MouseEvent) {
        onOpen(cid, name);
    }

    def handle_rename_click() {
        onStartRename(cid, name);
    }

    def handle_delete_click() {
        onAskDelete(cid);
    }

    def handle_rename_input(e: ChangeEvent) {
        onRenameChange(e.target.value);
    }

    def handle_rename_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            onSaveRename();
        } elif e.key == "Escape" {
            onCancelRename();
        }
    }

    return
        <li className="flex items-center gap-1 pl-4 pr-2">
            {if is_renaming {
                <div className="flex flex-1 items-center gap-2 py-2">
                    <Input
                        autoFocus={True}
                        value={rename_text}
                        onChange={handle_rename_input}
                        onKeyDown={handle_rename_key}
                        aria-label={"Rename " + name}
                        className="h-9"
                    />
                    <Button size="sm" variant="secondary" disabled={rename_busy} onClick={onSaveRename}>
                        {"Saving…" if rename_busy else "Save"}
                    </Button>
                    <Button size="sm" variant="ghost" disabled={rename_busy} onClick={onCancelRename}>Cancel</Button>
                </div>
            } else {
                <button
                    type="button"
                    onClick={handle_open}
                    className="flex min-h-11 flex-1 items-center justify-between gap-2 py-2.5 text-left outline-none transition-colors hover:bg-secondary focus-visible:bg-secondary focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring/50"
                >
                    <span className="truncate text-body-sm">{name}</span>
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
                        <DropdownMenuItem onSelect={handle_rename_click}>
                            <PencilIcon /> Rename
                        </DropdownMenuItem>
                        <DropdownMenuItem variant="destructive" onSelect={handle_delete_click}>
                            <TrashIcon /> Delete
                        </DropdownMenuItem>
                    </DropdownMenuContent>
                </DropdownMenu>
            }}
        </li>;
}

"""One member row in a circle's detail view: tap opens the person, X removes them."""
def:pub MemberRow(person: dict, busy: bool, onOpen: Callable[[str], None], onRemove: Callable[[str], None]) -> JsxElement {
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
def:pub PickerRow(person: any, already_member: bool, busy: bool, onAdd: Callable[[str], None]) -> JsxElement {
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

def:pub Circles(on_open_person: Callable[[str], None]) -> JsxElement {
    has circles: list[dict] = [],
        loaded: bool = False,
        load_error: str = "",
        create_name: str = "",
        create_busy: bool = False,
        create_error: str = "",
        rename_id: str = "",
        rename_text: str = "",
        rename_busy: bool = False,
        confirm_delete_id: str = "",
        delete_busy: bool = False,
        delete_error: str = "",
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
            got = await list_circles();
            circles = got;
        } except Exception as err {
            load_error = "Couldn't load your circles. " + str(err);
        }
        loaded = True;
    }

    def edit_create(e: ChangeEvent) {
        create_name = e.target.value;
        create_error = "";
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
            reply = await create_circle(name);
            if reply["error"] {
                create_error = "A circle named \"" + name + "\" already exists.";
            } else {
                create_name = "";
                await refresh();
                toast("\"" + name + "\" created", "success");
            }
        } except Exception as err {
            create_error = "Couldn't create that circle. " + str(err);
        }
        create_busy = False;
    }

    def handle_create_key(e: KeyboardEvent) {
        if e.key == "Enter" {
            handle_create();
        }
    }

    def start_rename(circle_id: str, current: str) {
        rename_id = circle_id;
        rename_text = current;
    }

    def cancel_rename() {
        rename_id = "";
        rename_text = "";
    }

    def edit_rename(text: str) {
        rename_text = text;
    }

    async def save_rename -> None {
        name: str = rename_text.strip();
        if not name {
            return;
        }
        rename_busy = True;
        reply: dict = {};
        try {
            reply = await rename_circle(rename_id, name);
            if not reply["error"] {
                rename_id = "";
                rename_text = "";
                await refresh();
            }
        } except Exception {
            rename_busy = False;
        }
        rename_busy = False;
    }

    def ask_delete(circle_id: str) {
        delete_error = "";
        confirm_delete_id = circle_id;
    }

    def set_confirm_delete(v: bool) -> None {
        if not v {
            confirm_delete_id = "";
        }
    }

    async def do_delete(e: MouseEvent) -> None {
        e.preventDefault();
        delete_busy = True;
        delete_error = "";
        gone_id: str = confirm_delete_id;
        gone_name: str = _circle_name(circles, gone_id);
        reply: dict = {};
        try {
            reply = await delete_circle(gone_id);
            if reply["error"] {
                delete_error = "Couldn't delete this circle.";
            } else {
                confirm_delete_id = "";
                if detail_id == gone_id {
                    detail_id = "";
                    detail_name = "";
                }
                await refresh();
                toast((gone_name if gone_name else "Circle") + " deleted");
            }
        } except Exception as err {
            delete_error = "Couldn't delete right now. " + str(err);
        }
        delete_busy = False;
    }

    async def open_detail(circle_id: str, name: str) -> None {
        detail_id = circle_id;
        detail_name = name;
        detail_loaded = False;
        detail_error = "";
        detail_people = [];
        got: list[dict] = [];
        try {
            got = await list_people_scoped(circle_id, "", False);
            detail_people = got;
        } except Exception as err {
            detail_error = "Couldn't load this circle's people. " + str(err);
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
            reply = await remove_from_circle(person_id, detail_id);
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
            reply = await add_to_circle(person_id, detail_id);
            if not reply["error"] {
                got: list[dict] = await list_people_scoped(detail_id, "", False);
                detail_people = got;
                await refresh();
            }
        } except Exception {
            member_busy_id = "";
        }
        member_busy_id = "";
    }

    member_ids: list[str] = [_s(p, "_jac_id") for p in detail_people];
    query: str = picker_query.strip().lower();
    filtered_picker: list[Person] = [p for p in picker_people if not query or query in _s(p, "name").lower()];

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-3 pr-3 shadow-edge">
                <Input
                    value={create_name}
                    onChange={edit_create}
                    onKeyDown={handle_create_key}
                    placeholder="New circle: family, the robotics lab…"
                    aria-label="New circle name"
                />
                <Button disabled={create_busy or not create_name.strip()} onClick={handle_create} className="self-end">
                    <PlusIcon /> {"Adding…" if create_busy else "Add circle"}
                </Button>
            </div>
            {create_error and <p role="alert" className="text-body-sm text-destructive">{create_error}</p>}
            {load_error and
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{load_error}</p>
                    <Button size="sm" variant="outline" onClick={refresh}>Retry</Button>
                </div>}
            {if not loaded {
                <div role="status" aria-label="Loading your circles" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-3 w-1/3" />
                </div>
            } elif len(circles) == 0 and not load_error {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    Circles are your own labels: family, the robotics lab, investors. Group people however you think about them.
                </p>
            } else {
                <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                    {for row in circles {
                        <CircleRow
                            key={_s(row["circle"], "_jac_id")}
                            row={row}
                            is_renaming={rename_id == _s(row["circle"], "_jac_id")}
                            rename_text={rename_text}
                            rename_busy={rename_busy}
                            onOpen={open_detail}
                            onStartRename={start_rename}
                            onRenameChange={edit_rename}
                            onSaveRename={save_rename}
                            onCancelRename={cancel_rename}
                            onAskDelete={ask_delete}
                        />
                    }}
                </ul>
            }}
            <AlertDialog open={confirm_delete_id != ""} onOpenChange={set_confirm_delete}>
                <AlertDialogContent>
                    <AlertDialogHeader>
                        <AlertDialogTitle>Delete this circle?</AlertDialogTitle>
                        <AlertDialogDescription>Removes the circle only. People stay.</AlertDialogDescription>
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
            <Sheet open={detail_id != ""} onOpenChange={handle_detail_open_change}>
                <SheetContent aria-label="Circle">
                    <SheetHeader>
                        <SheetTitle>{detail_name}</SheetTitle>
                        <SheetDescription>Who's in this circle</SheetDescription>
                    </SheetHeader>
                    <SheetBody className="gap-3">
                        <Button variant="secondary" onClick={open_picker}>Add people</Button>
                        {detail_error and
                            <div className="flex items-center gap-2">
                                <p role="alert" className="flex-1 text-body-sm text-destructive">{detail_error}</p>
                                <Button size="sm" variant="outline" onClick={retry_detail}>Retry</Button>
                            </div>}
                        {if not detail_loaded {
                            <div role="status" aria-label="Loading circle" className="flex flex-col gap-2">
                                <Skeleton className="h-3.5 w-full" />
                                <Skeleton className="h-3.5 w-2/3" />
                            </div>
                        } elif len(detail_people) == 0 and not detail_error {
                            <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                                No one in this circle yet. Add people from your graph.
                            </p>
                        } else {
                            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                                {for p in detail_people {
                                    <MemberRow
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
                                    <PickerRow
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
