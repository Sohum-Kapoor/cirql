"""Meet your people (SOH-231): one card at a time over the proposed
(unconfirmed) people from an import, or account-wide from the Today trickle
row. Most-recently-connected-first, then the rest (`list_proposed_people`,
`components/api_deck.cl.jac`).

Skip leaves the person proposed and moves to the next card (no API call —
"skip" here is "not now", never `SkipPerson`, which deletes). Shuffle
re-orders the remaining cards. "Say one thing about them" + Save calls
`Capture(kind="debrief", person_id, how_met)` then `ConfirmPerson`, toasts
"<name> added", and advances. "Done for now" closes the deck at any point.

Text-only (no hold-to-talk): `VoiceCapture.cl.jac`'s props (audio blob ->
`Transcribe` -> a parent-owned `has` for the transcript) assume a parent that
already threads `audio_ref`/an onboarding-style multi-step flow; wiring it
into this card's single-line "one thing" input within the time budget would
mean either duplicating its recorder state here or restructuring it to take
a callback, neither a safe change this pass. Shipping text-only.
"""

import from react { useEffect }
import from ..ui.button { Button }
import from ..ui.input { Input }
import from ..ui.avatar { Avatar }
import from ..api_import { confirm_person }
import from ..api_deck { list_proposed_people, capture_for_person }
import from ...lib.text { join_with }
import from ...lib.toast { toast }

"""Fisher-Yates over a copy of `rows` (Math.random — no `random` module in
client code, `jac-cl-js-interop`)."""
def _shuffled(rows: list[dict]) -> list[dict] {
    out: list[dict] = list(rows);
    i: int = len(out) - 1;
    while i > 0 {
        j: int = int(Math.random() * (i + 1));  # jac:ignore[W2001]
        tmp: dict = out[i];
        out[i] = out[j];
        out[j] = tmp;
        i = i - 1;
    }
    return out;
}

def:pub DeckCard(row: dict) -> JsxElement {
    name: str = (row["name"] or "") as str;
    sub: str = join_with([s for s in [(row["title"] or "") as str, (row["org"] or "") as str] if s], ", ");
    how_met: str = (row["how_met"] or "") as str;
    return
        <div className="flex flex-col items-center gap-3 rounded-lg border bg-card pt-8 pb-8 pl-6 pr-6 text-center shadow-edge">
            <Avatar name={name} size="lg" />
            <div className="flex flex-col gap-0.5">
                <span className="text-body-lg font-medium">{name or "(no name)"}</span>
                {sub and <span className="text-body-sm text-muted-foreground">{sub}</span>}
                {how_met and <span className="text-caption text-muted-foreground">{how_met}</span>}
            </div>
        </div>;
}

def:pub Deck(
    onClose: Callable[[], None],
    person_ids: list[str] = [],
    onChanged: Callable[[], None] | None = None
) -> JsxElement {
    has loading: bool = True,
        load_error: str = "",
        rows: list[dict] = [],
        idx: int = 0,
        note_text: str = "",
        busy: bool = False,
        save_error: str = "";

    async def load() -> None {
        loading = True;
        load_error = "";
        found: list[dict] = [];
        try {
            found = await list_proposed_people(person_ids);
        } except Exception as err {
            loading = False;
            load_error = "Couldn't load your people. " + str(err);
            return;
        }
        rows = found;
        idx = 0;
        loading = False;
    }

    useEffect(lambda { load(); }, []);

    def edit_note(e: ChangeEvent) {
        note_text = e.target.value;
    }

    def go_next() {
        note_text = "";
        save_error = "";
        idx = idx + 1;
    }

    def handle_skip(e: MouseEvent) {
        go_next();
    }

    def handle_shuffle(e: MouseEvent) {
        remaining: list[dict] = rows[idx:];
        done_rows: list[dict] = rows[:idx];
        rows = done_rows + _shuffled(remaining);
    }

    def handle_close(e: MouseEvent) {
        onClose();
    }

    async def handle_save(e: MouseEvent) -> None {
        if idx >= len(rows) {
            return;
        }
        current: dict = rows[idx];
        pid: str = (current["_jac_id"] or "") as str;
        name: str = (current["name"] or "") as str;
        how_met: str = (current["how_met"] or "") as str;
        text: str = note_text.strip();
        if not pid {
            return;
        }
        busy = True;
        save_error = "";
        try {
            if text {
                await capture_for_person(text, pid, how_met);
            }
            out: dict = await confirm_person(pid, "");
            if out["error"] {
                busy = False;
                save_error = "Couldn't add that person.";
                return;
            }
        } except Exception as err {
            busy = False;
            save_error = "Couldn't save that. " + str(err);
            return;
        }
        busy = False;
        toast((name if name else "Person") + " added", "success");
        if onChanged {
            onChanged();
        }
        go_next();
    }

    at_end: bool = idx >= len(rows);
    current_row: dict = rows[idx] if not at_end else {};
    remaining_count: int = len(rows) - idx if not at_end else 0;

    return
        <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between gap-2">
                <h2 className="text-eyebrow text-muted-foreground">Meet your people</h2>
                {not at_end and
                    <span className="text-caption tabular-nums text-muted-foreground">{str(remaining_count) + " left"}</span>}
            </div>
            {if loading {
                <p role="status" className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    Loading…
                </p>
            } elif load_error {
                <p role="alert" className="text-body-sm text-destructive">{load_error}</p>
            } elif len(rows) == 0 {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    Nobody left to place.
                </p>
            } elif at_end {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    That's everyone for now.
                </p>
            } else {
                <div className="flex flex-col gap-4">
                    <DeckCard row={current_row} />
                    <div className="flex flex-col gap-2">
                        <Input
                            value={note_text}
                            onChange={edit_note}
                            placeholder="Say one thing about them"
                            aria-label="Say one thing about them"
                            className="h-11"
                        />
                        {save_error and <p role="alert" className="text-caption text-destructive">{save_error}</p>}
                        <Button className="h-11" disabled={busy} onClick={handle_save}>
                            {"Saving…" if busy else "Save"}
                        </Button>
                    </div>
                    <div className="flex items-center gap-2">
                        <Button variant="outline" className="h-11 flex-1" disabled={busy} onClick={handle_skip}>
                            Skip
                        </Button>
                        <Button variant="ghost" className="h-11 flex-1" disabled={busy} onClick={handle_shuffle}>
                            Shuffle
                        </Button>
                    </div>
                </div>
            }}
            <Button variant="ghost" className="h-11 self-start text-muted-foreground" onClick={handle_close}>
                Done for now
            </Button>
        </div>;
}
