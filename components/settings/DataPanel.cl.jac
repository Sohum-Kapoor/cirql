"""DataPanel (SOH-222/226): export, archived people, one Danger zone card.
OWNER: Person B.

Meant to live inside the settings sheet (mount: `<DataPanel onDeleted={logout}
/>`). (1) Export downloads the caller's whole graph as one JSON file via a
Blob + object URL — nothing leaves the browser; export contacts is the same
recipe for a .vcf. (2) Archived people lists soft-deleted people with a
Restore action; empty state reads "Nothing archived." (3) Danger zone is ONE
red card (SOH-226 — was two stacked red cards) with two destructive actions,
each gated behind typing DELETE: Delete my data (keeps the login, clears the
graph) and Delete account (also disables the login); on success either calls
`onDeleted` so the shell can log the user out. Never says
private/secure/encrypted — this graph is isolated by construction, granted
read-only to no one by default.

Owns only what it loaded and its own dialog/input state; the caller owns
`onDeleted`.
"""

import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter }
import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.label { Label }
import from ..ui.skeleton { Skeleton }
import from ..ui.separator { Separator }
import from ..ui.alert_dialog {
    AlertDialog, AlertDialogContent, AlertDialogHeader, AlertDialogFooter, AlertDialogTitle,
    AlertDialogDescription, AlertDialogAction, AlertDialogCancel
}
import from ..api { export_graph, export_contacts, list_archived, restore_person, delete_my_data, delete_account }
import from ...lib.text { join_with }
import from ...lib.utils { cn }
import from ...lib.toast { toast }

def _s(d: any, key: str) -> str {
    if not d {
        return "";
    }
    return (d[key] or "") as str;
}

def _n(d: any, key: str) -> int {
    if not d {
        return 0;
    }
    v: any = d[key];
    return (v as int) if v else 0;
}

"""Today, "YYYY-MM-DD" (local export-file fallback when the report carries no
usable `exported_at`)."""
def _today_str() -> str {
    d: any = new(Date);  # jac:ignore[W2001,E1053]
    iso: str = String(d.toISOString());  # jac:ignore[W2001]
    return iso[0:10];
}

""""2026-09-26T20:00:00Z" -> "2026-09-26"; "" when it isn't that shape."""
def _date_prefix(iso: str) -> str {
    if not iso or len(iso) < 10 or iso[4] != "-" or iso[7] != "-" {
        return "";
    }
    return iso[0:10];
}

"""Trigger a browser download of `data` as pretty-printed JSON named `filename`.
Object-URL recipe (jac-cl-js-interop): create, click a throwaway <a>, revoke."""
def _download_json(data: dict, filename: str) {
    text: str = String(JSON.stringify(data, None, 2));  # jac:ignore[W2001]
    blob: any = new(Blob, [text], {"type": "application/json"});  # jac:ignore[W2001,E1053,W1051]
    url: str = String(URL.createObjectURL(blob));  # jac:ignore[W2001,E1032]
    a: any = document.createElement("a");  # jac:ignore[W2001]
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);  # jac:ignore[W2001,E1030]
    a.click();
    document.body.removeChild(a);  # jac:ignore[W2001,E1030]
    URL.revokeObjectURL(url);  # jac:ignore[W2001,E1032]
}

"""Trigger a browser download of `text` as-is (no JSON encoding), named
`filename`, with mime type `mime`. Same object-URL recipe as `_download_json`
— used for the vCard export (SOH-226), which is already plain text."""
def _download_text(text: str, filename: str, mime: str) {
    blob: any = new(Blob, [text], {"type": mime});  # jac:ignore[W2001,E1053,W1051]
    url: str = String(URL.createObjectURL(blob));  # jac:ignore[W2001,E1032]
    a: any = document.createElement("a");  # jac:ignore[W2001]
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);  # jac:ignore[W2001,E1030]
    a.click();
    document.body.removeChild(a);  # jac:ignore[W2001,E1030]
    URL.revokeObjectURL(url);  # jac:ignore[W2001,E1032]
}

"""Pluralise a count: "1 fact", "2 facts" — `one` singular, `many` plural noun."""
def plural(n: int, one: str, many: str) -> str {
    return str(n) + " " + (one if n == 1 else many);
}

"""counts: {people, facts, intents, promises, notes} -> "24 people · 58 facts · …"."""
def _counts_line(counts: dict) -> str {
    parts: list[str] = [];
    if _n(counts, "people") > 0 {
        parts.append(plural(_n(counts, "people"), "person", "people"));
    }
    if _n(counts, "facts") > 0 {
        parts.append(plural(_n(counts, "facts"), "fact", "facts"));
    }
    if _n(counts, "intents") > 0 {
        parts.append(plural(_n(counts, "intents"), "intent", "intents"));
    }
    if _n(counts, "promises") > 0 {
        parts.append(plural(_n(counts, "promises"), "promise", "promises"));
    }
    if _n(counts, "notes") > 0 {
        parts.append(plural(_n(counts, "notes"), "note", "notes"));
    }
    if _n(counts, "goals") > 0 {
        parts.append(plural(_n(counts, "goals"), "goal", "goals"));
    }
    if _n(counts, "cards") > 0 {
        parts.append(plural(_n(counts, "cards"), "card", "cards"));
    }
    if _n(counts, "circles") > 0 {
        parts.append(plural(_n(counts, "circles"), "circle", "circles"));
    }
    if _n(counts, "events") > 0 {
        parts.append(plural(_n(counts, "events"), "event", "events"));
    }
    if len(parts) == 0 {
        return "Nothing yet.";
    }
    return join_with(parts, " · ");
}

def:pub ArchivedRow(person: dict, busy: bool, onRestore: Callable[[str], None]) -> JsxElement {
    pid: str = _s(person, "_jac_id");
    org: str = _s(person, "org");
    title: str = _s(person, "title");
    sub: str = (org + " · " + title) if (org and title) else (org or title);

    def handle_restore(e: MouseEvent) {
        onRestore(pid);
    }

    return
        <li className="flex items-center justify-between gap-3 pt-3 pb-3 pl-4 pr-4">
            <span className="flex min-w-0 flex-col">
                <span className="truncate text-body-sm font-medium">{_s(person, "name") or "Unnamed"}</span>
                {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
            </span>
            <Button variant="outline" size="sm" disabled={busy} onClick={handle_restore}>
                {"Restoring…" if busy else "Restore"}
            </Button>
        </li>;
}

def:pub DataPanel(onDeleted: Callable[[], None]) -> JsxElement {
    has account_open: bool = False,
        account_text: str = "",
        account_busy: bool = False,
        account_error: str = "",
        export_busy: bool = False,
        export_error: str = "",
        export_counts: dict = {},
        contacts_busy: bool = False,
        contacts_error: str = "",
        contacts_count: int = -1,
        archived: list[dict] = [],
        archived_loaded: bool = False,
        archived_error: str = "",
        restoring_id: str = "",
        delete_open: bool = False,
        delete_text: str = "",
        delete_busy: bool = False,
        delete_error: str = "",
        delete_result: dict = {};

    async can with entry {
        await load_archived();
    }

    async def load_archived -> None {
        archived_error = "";
        archived_loaded = False;
        got: list[dict] = [];
        try {
            got = await list_archived();
            archived = got;
        } except Exception as err {
            archived_error = "Couldn't load archived people. " + str(err);
        }
        archived_loaded = True;
    }

    async def run_export(e: MouseEvent) -> None {
        export_busy = True;
        export_error = "";
        try {
            data: dict = await export_graph();
            counts: dict = (data["counts"] or {}) as dict;
            export_counts = counts;
            stamp: str = _date_prefix((data["exported_at"] or "") as str) or _today_str();
            _download_json(data, "cirql-export-" + stamp + ".json");
            toast("Export ready", "success");
        } except Exception as err {
            export_error = "Couldn't export right now. " + str(err);
        }
        export_busy = False;
    }

    async def run_export_contacts(e: MouseEvent) -> None {
        contacts_busy = True;
        contacts_error = "";
        try {
            data: dict = await export_contacts();
            vcf: str = _s(data, "vcf");
            count: int = _n(data, "count");
            contacts_count = count;
            _download_text(vcf, "cirql-contacts.vcf", "text/vcard");
            toast(str(count) + " contacts exported", "success");
        } except Exception as err {
            contacts_error = "Couldn't export contacts right now. " + str(err);
        }
        contacts_busy = False;
    }

    async def do_restore(person_id: str) -> None {
        restoring_id = person_id;
        try {
            left: list[dict] = await restore_person(person_id);
            archived = left;
        } except Exception {
            archived_error = "Couldn't restore that person. Try again.";
        }
        restoring_id = "";
    }

    def ask_delete(e: MouseEvent) {
        delete_error = "";
        delete_result = {};
        delete_text = "";
        delete_open = True;
    }

    def set_delete_open(v: bool) -> None {
        delete_open = v;
        if not v {
            delete_text = "";
            delete_error = "";
        }
    }

    def edit_delete_text(e: ChangeEvent) {
        delete_text = e.target.value;
    }

    def ask_account(e: MouseEvent) {
        account_text = "";
        account_error = "";
        account_open = True;
    }

    def set_account_open(v: bool) {
        account_open = v;
    }

    def edit_account_text(e: ChangeEvent) {
        account_text = e.target.value;
    }

    async def do_delete_account(e: MouseEvent) -> None {
        e.preventDefault();
        if account_text != "DELETE" {
            return;
        }
        account_busy = True;
        account_error = "";
        try {
            reply: dict = await delete_account("DELETE");
            if reply["error"] {
                account_error = "Couldn't delete your account right now. Try again.";
            } elif not reply["ok"] and reply["deleted"] and not reply["identity_disabled"] {
                account_error = "Your data was removed, but the login could not be disabled. Try again; if it keeps failing, write to us from the privacy page.";
            } elif not reply["ok"] {
                account_error = "Couldn't delete your account right now. Try again.";
            } else {
                account_open = False;
                onDeleted();
            }
        } except Exception as err {
            account_error = "Couldn't delete your account right now. " + str(err);
        }
        account_busy = False;
    }

    async def do_delete(e: MouseEvent) -> None {
        e.preventDefault();
        if delete_text != "DELETE" {
            return;
        }
        delete_busy = True;
        delete_error = "";
        try {
            reply: dict = await delete_my_data("DELETE");
            if reply["error"] {
                delete_error = "Couldn't delete your data right now. Try again.";
            } else {
                delete_result = (reply["deleted"] or {}) as dict;
                delete_open = False;
                onDeleted();
            }
        } except Exception as err {
            delete_error = "Couldn't delete your data right now. " + str(err);
        }
        delete_busy = False;
    }

    return
        <div className="flex flex-col gap-4">
            <Card>
                <CardHeader>
                    <CardTitle>Export my data</CardTitle>
                    <CardDescription>
                        Download everything about your people as one JSON file: every person, fact,
                        intent, promise, and note, with where it came from.
                    </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-2">
                    {export_error and <p role="alert" className="text-body-sm text-destructive">{export_error}</p>}
                    {Boolean(len(list(export_counts.keys())) if export_counts else 0) and (
                        <p className="text-caption text-muted-foreground">{_counts_line(export_counts)}</p>
                    )}
                    <Button variant="outline" disabled={export_busy} onClick={run_export} className="w-full focus-visible:ring-inset">
                        {"Exporting…" if export_busy else "Export my data"}
                    </Button>
                    {contacts_error and
                        <div className="flex items-center gap-2">
                            <p role="alert" className="flex-1 text-body-sm text-destructive">{contacts_error}</p>
                            <Button size="sm" variant="outline" onClick={run_export_contacts}>Retry</Button>
                        </div>}
                    {(contacts_count >= 0) and (
                        <p className="text-caption text-muted-foreground">{str(contacts_count) + " contacts exported"}</p>
                    )}
                    <Button
                        variant="outline"
                        disabled={contacts_busy}
                        onClick={run_export_contacts}
                        className="w-full focus-visible:ring-inset"
                    >
                        {"Exporting…" if contacts_busy else "Export contacts"}
                    </Button>
                    <p className="text-caption text-muted-foreground">A .vcf file every phone imports</p>
                </CardContent>
            </Card>

            <Card>
                <CardHeader>
                    <CardTitle>Archived people</CardTitle>
                    <CardDescription>Hidden from lists and rankings. Restore brings them back.</CardDescription>
                </CardHeader>
                <CardContent>
                    {archived_error and
                        <div className="flex items-center gap-2">
                            <p role="alert" className="flex-1 text-body-sm text-destructive">{archived_error}</p>
                            <Button size="sm" variant="outline" onClick={load_archived}>Retry</Button>
                        </div>}
                    {if not archived_loaded {
                        <div role="status" aria-label="Loading archived people" className="flex flex-col gap-2">
                            <Skeleton className="h-4 w-3/4" />
                            <Skeleton className="h-4 w-1/2" />
                        </div>
                    } elif len(archived) == 0 and not archived_error {
                        <p className="text-body-sm text-muted-foreground">Nothing archived.</p>
                    } else {
                        <ul className="-mx-4 flex flex-col divide-y divide-border">
                            {for person in archived {
                                <ArchivedRow
                                    key={_s(person, "_jac_id")}
                                    person={person}
                                    busy={restoring_id == _s(person, "_jac_id")}
                                    onRestore={do_restore}
                                />
                            }}
                        </ul>
                    }}
                </CardContent>
            </Card>

            <h3 className="text-eyebrow text-muted-foreground">Danger zone</h3>
            <Card className="border-destructive/30">
                <CardContent className="flex flex-col gap-4">
                    <div className="flex flex-col gap-2">
                        <p className="text-caption text-muted-foreground">
                            Removes everything: your people, notes and card. Your export is the only copy after this.
                        </p>
                        {Boolean(len(list(delete_result.keys())) if delete_result else 0) and (
                            <p className="text-body-sm text-muted-foreground">{"Deleted " + _counts_line(delete_result) + "."}</p>
                        )}
                        <Button variant="destructive" className="w-full focus-visible:ring-inset" onClick={ask_delete}>Delete my data</Button>
                    </div>
                    <Separator />
                    <div className="flex flex-col gap-2">
                        <p className="text-caption text-muted-foreground">
                            Removes your people and disables this login. Your username is freed up;
                            nothing is kept on the server.
                        </p>
                        <Button variant="destructive" className="w-full focus-visible:ring-inset" onClick={ask_account}>Delete account</Button>
                    </div>
                </CardContent>
            </Card>

            <AlertDialog open={account_open} onOpenChange={set_account_open}>
                <AlertDialogContent>
                    <AlertDialogHeader>
                        <AlertDialogTitle>Delete your account?</AlertDialogTitle>
                        <AlertDialogDescription>
                            Removes everything: your people, notes and card and disables this login. You
                            will be signed out. Export first if you want a copy.
                        </AlertDialogDescription>
                    </AlertDialogHeader>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="account-confirm">Type DELETE to confirm</Label>
                        <Input
                            id="account-confirm"
                            value={account_text}
                            onChange={edit_account_text}
                            placeholder="DELETE"
                            autoComplete="off"
                            disabled={account_busy}
                        />
                    </div>
                    {account_error and <p role="alert" className="text-body-sm text-destructive">{account_error}</p>}
                    <AlertDialogFooter>
                        <AlertDialogCancel disabled={account_busy}>Cancel</AlertDialogCancel>
                        <AlertDialogAction
                            variant="destructive"
                            disabled={account_busy or account_text != "DELETE"}
                            onClick={do_delete_account}
                        >
                            {"Deleting…" if account_busy else "Delete account"}
                        </AlertDialogAction>
                    </AlertDialogFooter>
                </AlertDialogContent>
            </AlertDialog>

            <AlertDialog open={delete_open} onOpenChange={set_delete_open}>
                <AlertDialogContent>
                    <AlertDialogHeader>
                        <AlertDialogTitle>Delete all your data?</AlertDialogTitle>
                        <AlertDialogDescription>
                            Removes everything: your people, notes and card. Your export is the only
                            copy after this.
                        </AlertDialogDescription>
                    </AlertDialogHeader>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="delete-confirm">Type DELETE to confirm</Label>
                        <Input
                            id="delete-confirm"
                            value={delete_text}
                            onChange={edit_delete_text}
                            placeholder="DELETE"
                            autoComplete="off"
                            disabled={delete_busy}
                        />
                    </div>
                    {delete_error and <p role="alert" className="text-body-sm text-destructive">{delete_error}</p>}
                    <AlertDialogFooter>
                        <AlertDialogCancel disabled={delete_busy}>Cancel</AlertDialogCancel>
                        <AlertDialogAction
                            variant="destructive"
                            disabled={delete_busy or delete_text != "DELETE"}
                            onClick={do_delete}
                        >
                            {"Deleting…" if delete_busy else "Delete my data"}
                        </AlertDialogAction>
                    </AlertDialogFooter>
                </AlertDialogContent>
            </AlertDialog>
        </div>;
}
