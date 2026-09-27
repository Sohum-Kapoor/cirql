"""Meet your people (SOH-231): one card at a time over the proposed
(unconfirmed) people from an import, or account-wide from the Today trickle
row. Most-recently-connected-first, then the rest (`list_proposed_people`,
`components/api_deck.cl.jac`).

Skip leaves the person proposed and moves to the next card (no API call —
"skip" here is "not now", never `SkipPerson`, which deletes). Shuffle
re-orders the remaining cards. "Say one thing about them" + Save advances to
the NEXT card immediately (SOH-236) — the actual save (`Capture(kind=
"debrief", person_id, how_met, confirm=True)`, falling back to `Capture` then
`ConfirmPerson` if the walker doesn't understand `confirm` yet) runs in the
background; a small status line tracks the most recent card's "Saving…" then
"Saved" (or an error toast with a Retry action). "Done for now" closes the
deck at any point and is the one place this screen calls `onChanged` — not
after every card, so opening/using the deck no longer re-fetches the whole
people list once per save.

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
import from ..api_deck { list_proposed_people, filter_proposed_people, capture_for_person }
import from ...lib.text { join_with }
import from ...lib.toast { toast }
sv import from ...schema { Person }

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
    onChanged: Callable[[], None] | None = None,
    people: list[Person] = []
) -> JsxElement {
    has loading: bool = True,
        load_error: str = "",
        rows: list[dict] = [],
        idx: int = 0,
        note_text: str = "",
        # SOH-236: keyed by person id, so more than one card's save can be
        # in flight at once (a fast Save-Save-Save) without clobbering each
        # other's status — the `.current`-is-truth idiom `ImportPeople.cl
        # .jac`'s `row_busy_ref`/`decisions_ref` use, since a handler's
        # closure over a plain `has` dict is frozen at the render the click
        # happened in.
        save_status: dict = {},
        save_names: dict = {},
        save_status_ref: Ref[any] = Ref({}),
        save_names_ref: Ref[any] = Ref({}),
        last_action_pid: str = "",
        dispatched_ref: Ref[any] = Ref({}),
        changed_ref: Ref[any] = Ref(False);

    async def load() -> None {
        loading = True;
        load_error = "";
        found: list[dict] = [];
        try {
            if len(people) > 0 {
                found = filter_proposed_people(people as list[dict], person_ids);
            } else {
                found = await list_proposed_people(person_ids);
            }
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

    def _set_save_status(pid: str, name: str, status: str) -> None {
        next_status: dict = {**save_status_ref.current};
        next_names: dict = {**save_names_ref.current};
        next_status[pid] = status;
        next_names[pid] = name;
        save_status_ref.current = next_status;
        save_names_ref.current = next_names;
        save_status = next_status;
        save_names = next_names;
        last_action_pid = pid;
    }

    def edit_note(e: ChangeEvent) {
        note_text = e.target.value;
    }

    def go_next() {
        note_text = "";
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
        if changed_ref.current and onChanged {
            onChanged();
            changed_ref.current = False;
        }
        onClose();
    }

    """The actual save for one card, kicked off in the background (never
    awaited by the click handler) — one `Capture(..., confirm=True)` when
    there's a note, else a bare `ConfirmPerson`; falls back to `Capture` then
    `ConfirmPerson` when the combined call didn't confirm (walker doesn't
    know `confirm` yet, or it errored)."""
    async def do_save(pid: str, name: str, how_met: str, text: str) -> None {
        _set_save_status(pid, name, "saving");
        ok: bool = True;
        try {
            if text {
                cap_out: dict = await capture_for_person(text, pid, how_met, True);
                confirmed: bool = (cap_out["confirmed"] or False) as bool;
                if not confirmed {
                    conf_out: dict = await confirm_person(pid, "");
                    if conf_out["error"] {
                        ok = False;
                    }
                }
            } else {
                conf_out2: dict = await confirm_person(pid, "");
                if conf_out2["error"] {
                    ok = False;
                }
            }
        } except Exception {
            ok = False;
        }
        if ok {
            _set_save_status(pid, name, "saved");
            changed_ref.current = True;
            toast((name if name else "Person") + " added", "success");
        } else {
            _set_save_status(pid, name, "error");
            def do_retry() {
                do_save(pid, name, how_met, text);
            }
            toast("Couldn't save " + (name if name else "that person") + ".", "error", do_retry);
        }
    }

    """Save advances to the next card immediately; the network call above
    runs in the background (SOH-236) instead of blocking the click."""
    def handle_save(e: MouseEvent) {
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
        if pid in dispatched_ref.current {
            go_next();
            return;
        }
        next_dispatched: dict = {**dispatched_ref.current};
        next_dispatched[pid] = True;
        dispatched_ref.current = next_dispatched;
        do_save(pid, name, how_met, text);
        go_next();
    }

    at_end: bool = idx >= len(rows);
    current_row: dict = rows[idx] if not at_end else {};
    remaining_count: int = len(rows) - idx if not at_end else 0;
    last_status: str = (save_status[last_action_pid] or "") as str;
    last_name: str = (save_names[last_action_pid] or "") as str;
    last_label: str = last_name if last_name else "that person";

    return
        <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between gap-2">
                <h2 className="text-eyebrow text-muted-foreground">Meet your people</h2>
                {not at_end and
                    <span className="text-caption tabular-nums text-muted-foreground">{str(remaining_count) + " left"}</span>}
            </div>
            {last_status == "saving" and
                <p role="status" className="text-caption text-muted-foreground">{"Saving " + last_label + "…"}</p>}
            {last_status == "saved" and
                <p role="status" className="text-caption text-success-text">{"Saved " + last_label}</p>}
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
                        <Button className="h-11" onClick={handle_save}>
                            Save
                        </Button>
                    </div>
                    <div className="flex items-center gap-2">
                        <Button variant="outline" className="h-11 flex-1" onClick={handle_skip}>
                            Skip
                        </Button>
                        <Button variant="ghost" className="h-11 flex-1" onClick={handle_shuffle}>
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
