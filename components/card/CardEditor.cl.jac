"""CardEditor (SOH-179): "My-card editor + what a friend sees." OWNER: Person B.

The one screen where the caller writes their own Card: headline, about,
looking for / can offer / links (one per line), contact preference, display
name, and the visibility choice that actually matters — `link` (granted
read-only to anyone with the handle) vs `handshake_only` (isolated by
construction until handed over). Loads via `my_card()` (a pure read —
`ExportGraph`'s own `card` field, see `components/api_card.cl.jac`'s
docstring for why neither `PublishCard` nor `get_card` is safe to read with),
saves via `publish_card_full(...)`. Live preview underneath is `CardPreview`,
fed the CURRENT (possibly unsaved) form state — same shape `get_card` would
hand a friend.

Mounted from `components/settings/AppearanceSheet.cl.jac` as a "My card"
section. Owns only its own form/save state.
"""

import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter }
import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.textarea { Textarea }
import from ..ui.label { Label }
import from ..ui.tabs { Tabs, TabsList, TabsTrigger }
import from ..ui.skeleton { Skeleton }
import from .CardPreview { CardPreview }
import from .CardQR { CardQR }  # SOH-228: one import + one JSX mount, fed this editor's own live handle/visibility
import from ...lib.text { join_lines, split_lines }
import from ..api_card { my_card, publish_card_full }
import from ...lib.toast { toast }

def _visibility_state(v: str) -> str {
    return "anyone with the link" if v == "link" else "only people you hand it to";
}

"""Non-blank, trimmed lines only — an editor textarea with a trailing blank
line (or all blank) should never turn into `[""]` on save."""
def _clean_lines(text: str) -> list[str] {
    out: list[str] = [];
    for line in split_lines(text) {
        t: str = line.strip();
        if t {
            out.append(t);
        }
    }
    return out;
}

def _visibility_label(v: str) -> str {
    return "Anyone with the link" if v == "link" else "Only people I hand it to";
}

def:pub CardEditor() -> JsxElement {
    has loaded: bool = False,
        load_error: str = "",
        headline: str = "",
        about: str = "",
        looking_for_text: str = "",
        can_offer_text: str = "",
        links_text: str = "",
        interests_text: str = "",
        contact_pref: str = "",
        name: str = "",
        visibility: str = "link",
        saved_visibility: str = "link",
        handle: str = "",
        updated_at: str = "",
        saving: bool = False,
        save_error: str = "",
        save_state: str = "";

    def apply_card(card: dict) {
        headline = (card["headline"] or "") as str;
        about = (card["about"] or "") as str;
        looking_for_text = join_lines((card["looking_for"] or []) as list[str]);
        can_offer_text = join_lines((card["can_offer"] or []) as list[str]);
        links_text = join_lines((card["links"] or []) as list[str]);
        interests_text = join_lines((card["interests"] or []) as list[str]);
        contact_pref = (card["contact_pref"] or "") as str;
        name = (card["name"] or "") as str;
        visibility = (card["visibility"] or "link") as str;
        saved_visibility = visibility;
        handle = (card["handle"] or "") as str;
        updated_at = (card["updated_at"] or "") as str;
    }

    async def load_card -> None {
        load_error = "";
        loaded = False;
        try {
            card: dict | None = await my_card();
            if card is not None {
                apply_card(card as dict);
            }
        } except Exception {
            load_error = "Couldn't load your card. Check your connection and retry.";
        }
        loaded = True;
    }

    async can with entry {
        await load_card();
    }

    def edit_headline(e: ChangeEvent) {
        headline = e.target.value;
    }

    def edit_about(e: ChangeEvent) {
        about = e.target.value;
    }

    def edit_looking_for(e: ChangeEvent) {
        looking_for_text = e.target.value;
    }

    def edit_can_offer(e: ChangeEvent) {
        can_offer_text = e.target.value;
    }

    def edit_links(e: ChangeEvent) {
        links_text = e.target.value;
    }

    def edit_interests(e: ChangeEvent) {
        interests_text = e.target.value;
    }

    def edit_contact(e: ChangeEvent) {
        contact_pref = e.target.value;
    }

    def edit_name(e: ChangeEvent) {
        name = e.target.value;
    }

    def change_visibility(value: str) -> None {
        visibility = value;
        save_state = "";
    }

    async def do_save(e: MouseEvent) -> None {
        saving = True;
        save_error = "";
        save_state = "";
        try {
            card: dict = await publish_card_full(
                headline.strip(), about.strip(), _clean_lines(looking_for_text),
                _clean_lines(can_offer_text), _clean_lines(links_text), _clean_lines(interests_text),
                contact_pref.strip(), visibility, name.strip()
            );
            if card["error"] {
                save_error = "Couldn't save your card (" + str(card["error"]) + ").";
            } else {
                apply_card(card);
                save_state = "Card saved · " + _visibility_label(visibility);
                toast(save_state, "success");
            }
        } except Exception as err {
            save_error = "Couldn't save your card. " + str(err);
        }
        saving = False;
    }

    async def do_copy_handle -> None {
        ok: bool = True;
        try {
            await navigator.clipboard.writeText(handle);  # jac:ignore[E1030]
        } except Exception {
            ok = False;
        }
        if ok {
            toast("Handle copied", "success");
        }
    }

    preview_looking_for: list[str] = _clean_lines(looking_for_text);
    preview_can_offer: list[str] = _clean_lines(can_offer_text);
    preview_links: list[str] = _clean_lines(links_text);
    preview_interests: list[str] = _clean_lines(interests_text);

    if not loaded {
        return
            <div role="status" aria-label="Loading your card" className="flex flex-col gap-4">
                <div className="flex flex-col gap-1.5">
                    <Skeleton className="h-3.5 w-16" />
                    <Skeleton className="h-11 w-full" />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Skeleton className="h-3.5 w-20" />
                    <Skeleton className="h-11 w-full" />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Skeleton className="h-3.5 w-14" />
                    <Skeleton className="h-24 w-full" />
                </div>
                <div className="flex flex-col gap-1.5">
                    <Skeleton className="h-3.5 w-28" />
                    <Skeleton className="h-24 w-full" />
                </div>
            </div>;
    }

    return
        <div className="flex flex-col gap-4">
            {load_error and
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{load_error}</p>
                    <Button size="sm" variant="outline" onClick={load_card}>Retry</Button>
                </div>}

            <Card>
                <CardHeader>
                    <CardDescription>What you hand people when they ask what you're up to.</CardDescription>
                </CardHeader>
                <CardContent className="flex flex-col gap-3">
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-name">Name</Label>
                        <Input id="card-name" value={name} onChange={edit_name} placeholder="How your name shows up on the card" />
                        {name == "me" and
                            <p className="text-caption text-muted-foreground">Set your name: friends see this on your card.</p>}
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-headline">Headline</Label>
                        <Input id="card-headline" value={headline} onChange={edit_headline} placeholder="One line about what you're doing" />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-about">About</Label>
                        <Textarea id="card-about" value={about} onChange={edit_about} placeholder="A few sentences a friend could actually use" />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-looking-for">Looking for (one per line)</Label>
                        <Textarea id="card-looking-for" value={looking_for_text} onChange={edit_looking_for} placeholder={"a climate-tech VC\na founder who has raised for hardware"} />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-can-offer">Can offer (one per line)</Label>
                        <Textarea id="card-can-offer" value={can_offer_text} onChange={edit_can_offer} placeholder={"intros into decarbonization pilots\nfeedback on pitch decks"} />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-links">Links (one per line)</Label>
                        <Textarea id="card-links" value={links_text} onChange={edit_links} placeholder={"yoursite.com"} />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-interests">Interests (one per line)</Label>
                        <Textarea id="card-interests" value={interests_text} onChange={edit_interests} placeholder={"thermal storage\nstudent founders"} />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="card-contact">Contact preference</Label>
                        <Input id="card-contact" value={contact_pref} onChange={edit_contact} placeholder="e.g. email: you@example.com" />
                    </div>

                    <div className="flex flex-col gap-1.5">
                        <Label>Who can see this</Label>
                        <Tabs value={visibility} onValueChange={change_visibility}>
                            <TabsList aria-label="Visibility" className="w-full">
                                <TabsTrigger
                                    value="link"
                                    className="data-active:border-primary data-active:bg-primary data-active:text-primary-foreground"
                                >Anyone with the link</TabsTrigger>
                                <TabsTrigger
                                    value="handshake_only"
                                    className="data-active:border-primary data-active:bg-primary data-active:text-primary-foreground"
                                >Only people I hand it to</TabsTrigger>
                            </TabsList>
                        </Tabs>
                        {visibility == "link" and
                            <p className="text-caption text-muted-foreground">
                                Granted read-only to anyone who has your handle or link.
                            </p>}
                        {visibility == "handshake_only" and
                            <p className="text-caption text-muted-foreground">
                                Isolated by construction until you hand it to someone yourself. Nothing is granted yet.
                            </p>}
                        <p className="text-caption text-muted-foreground">{"Currently: " + _visibility_state(saved_visibility)}</p>
                    </div>

                    {handle and
                        <div className="flex items-center justify-between gap-2 rounded-md border bg-secondary pt-2 pb-2 pl-3 pr-3">
                            <div className="flex min-w-0 flex-col">
                                <span className="text-caption text-muted-foreground">Your handle</span>
                                <span className="truncate text-body-sm font-medium">{handle}</span>
                            </div>
                            <Button size="sm" variant="outline" onClick={do_copy_handle}>Copy</Button>
                        </div>}

                    {save_error and
                        <div className="flex items-center gap-2">
                            <p role="alert" className="flex-1 text-body-sm text-destructive">{save_error}</p>
                            <Button size="sm" variant="outline" onClick={do_save}>Retry</Button>
                        </div>}
                </CardContent>
                <CardFooter>
                    <Button className="w-full" disabled={saving} onClick={do_save}>
                        {"Saving…" if saving else "Save card"}
                    </Button>
                </CardFooter>
            </Card>

            {not load_error and
                <div className="flex flex-col gap-4">
                    <CardPreview
                        name={name}
                        handle={handle}
                        headline={headline}
                        about={about}
                        looking_for={preview_looking_for}
                        can_offer={preview_can_offer}
                        links={preview_links}
                        interests={preview_interests}
                        contact_pref={contact_pref}
                        updated_at={updated_at}
                        visibility={visibility}
                    />

                    <CardQR handle={handle} visibility={visibility} />
                </div>}
        </div>;
}
