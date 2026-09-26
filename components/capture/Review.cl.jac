"""Extraction review after Capture — every row carries a source chip. OWNER: Person B.

Provenance rule: every claim shows where it came from. Each row's "source" chip
expands inline to the `span` the walker recorded; when the span is a literal
substring of the note the user typed (capture.sv.jac `safe_span` guarantees it
is, or falls back to a name / the note's first 80 chars) it is highlighted
inside a short excerpt of the note. One chip open at a time.

`result` is the Capture report (contracts/walkers.md). person_ids resolve to
names via `result.people`, then the home people list (`known`) — ambiguous
matches usually point at people you already know, not ones in this report.
"""

import from "..ui.button" { Button }
import from "..ui.badge" { Badge }
import from "..ui.icons" { QuoteIcon }
import from ...lib.text { join_with }
import from ...lib.utils { cn }
sv import from ...schema { Person }

glob _CTX: int = 70,
     _INTENT_LABEL: dict[str, str] = {"need": "need", "offer": "offer", "open_to": "open to"};

"""[before, span, after, found] — `found` is "1" when span is a literal substring."""
def:pub span_excerpt(note: str, span: str) -> list[str] {
    if not span or not note or span not in note {
        return ["", span, "", ""];
    }
    idx: int = note.index(span);
    end: int = idx + len(span);
    start: int = (idx - _CTX) if idx > _CTX else 0;
    stop: int = (end + _CTX) if end + _CTX < len(note) else len(note);
    # Snap the context to word boundaries so the excerpt never cuts mid-word.
    while start > 0 and start < idx and note[start - 1] != " " {
        start = start + 1;
    }
    while stop < len(note) and stop > end and note[stop] != " " {
        stop = stop - 1;
    }
    before: str = ("…" if start > 0 else "") + note[start:idx];
    after: str = note[end:stop] + ("…" if stop < len(note) else "");
    return [before, span, after, "1"];
}

def:pub SourceQuote(span: str, note_text: str) -> JsxElement {
    parts: list[str] = span_excerpt(note_text, span);
    found: bool = parts[3] == "1";
    return
        <blockquote className="flex flex-col gap-1 rounded-md border-l-2 border-primary bg-secondary pt-2 pb-2 pl-3 pr-3">
            <span className="text-eyebrow text-muted-foreground">
                {"From your note" if found else "Source"}
            </span>
            {if found {
                <p className="text-body-sm text-muted-foreground">
                    {parts[0]}
                    <mark className="rounded-xs bg-primary/20 pl-0.5 pr-0.5 text-foreground">{parts[1]}</mark>
                    {parts[2]}
                </p>
            } else {
                <p className="text-body-sm">{"“" + (span or "No quote recorded for this item.") + "”"}</p>
            }}
        </blockquote>;
}

"""One review row: content (children) + a source chip that expands the quote."""
def:pub ReviewRow(
    row_key: str,
    is_open: bool,
    span: str,
    note_text: str,
    onToggle: Callable[[str], None],
    children: any = None
) -> JsxElement {
    def handle_toggle(e: MouseEvent) {
        onToggle(row_key);
    }

    return
        <li className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
            <div className="flex items-start justify-between gap-3">
                <div className="flex min-w-0 flex-1 flex-col gap-0.5">{children}</div>
                <Button
                    variant="chip"
                    size="chip"
                    aria-expanded={is_open}
                    aria-label={"Show source" if not is_open else "Hide source"}
                    onClick={handle_toggle}
                >
                    <QuoteIcon className="size-3" />
                    <span>source</span>
                </Button>
            </div>
            {is_open and <SourceQuote span={span} note_text={note_text} />}
        </li>;
}

def:pub ReviewSection(title: str, count: int, children: any = None) -> JsxElement {
    return
        <section className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between">
                <h2 className="text-eyebrow text-muted-foreground">{title}</h2>
                <span className="text-caption tabular-nums text-muted-foreground">{str(count)}</span>
            </div>
            <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">{children}</ul>
        </section>;
}

def _id_of(x: any) -> str {
    if not x {
        return "";
    }
    return (x["_jac_id"] or "") as str;
}

def _name(names: dict[str, str], pid: str) -> str {
    return names[pid] or "someone";
}

"""A People row: name, title/org, new|known badge, and an ambiguity hint."""
def:pub PersonItem(
    row: dict,
    names: dict[str, str],
    spans: list[str],
    open_key: str,
    note_text: str,
    onToggle: Callable[[str], None]
) -> JsxElement {
    person: dict = row["person"] as dict;
    pid: str = _id_of(person);
    row_key: str = "p-" + pid;
    sub: str = join_with([s for s in [person["title"] as str, person["org"] as str] if s], ", ");
    maybe: list[str] = [names[a] for a in ((row["ambiguous_with"] or []) as list[str]) if names[a] and a != pid];
    return
        <ReviewRow
            row_key={row_key}
            is_open={open_key == row_key}
            span={_person_span(person["name"] as str, spans, note_text)}
            note_text={note_text}
            onToggle={onToggle}
        >
            <div className="flex items-center gap-2">
                <span className="truncate text-body font-medium">{person["name"]}</span>
                <Badge variant={"success" if row["is_new"] else "outline"}>{"new" if row["is_new"] else "known"}</Badge>
            </div>
            {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
            {len(maybe) > 0 and
                <span className="text-caption text-muted-foreground">{"Might be the same as " + join_with(maybe, " or ")}</span>}
        </ReviewRow>;
}

"""People rows carry no span in the Capture report, so show the sentence of the
note that names them (a literal substring, so it highlights). Fallback: the
first span of any item about them, then the name itself."""
def _person_span(person_name: str, spans: list[str], note: str) -> str {
    if person_name and note and person_name in note {
        return sentence_around(note, note.index(person_name));
    }
    if len(spans) > 0 {
        return spans[0];
    }
    return person_name;
}

"""The sentence of `note` containing position `pos` (split on . ! ? and newlines)."""
def:pub sentence_around(note: str, pos: int) -> str {
    stops: str = ".!?" + chr(10);
    start: int = pos;
    while start > 0 and note[start - 1] not in stops {
        start = start - 1;
    }
    end: int = pos;
    while end < len(note) and note[end] not in stops {
        end = end + 1;
    }
    if end < len(note) and note[end] != chr(10) {
        end = end + 1;
    }
    return note[start:end].strip();
}

"""Spans of every fact/intent/promise/tie that involves person `pid`."""
def _spans_about(pid: str, result: dict) -> list[str] {
    out: list[str] = [];
    for r in (result["facts"] or []) as list[dict] {
        if r["about"] == pid { out = out + [r["span"] as str]; }
    }
    for r in (result["intents"] or []) as list[dict] {
        if r["about"] == pid { out = out + [r["span"] as str]; }
    }
    for r in (result["promises"] or []) as list[dict] {
        if r["to"] == pid { out = out + [r["span"] as str]; }
    }
    for r in (result["ties"] or []) as list[dict] {
        if r["from"] == pid or r["to"] == pid { out = out + [r["span"] as str]; }
    }
    return out;
}

def:pub Review(
    result: dict,
    note_text: str,
    known: list[Person],
    onDone: Callable[[], None],
    onRetry: Callable[[], None]
) -> JsxElement {
    has open_key: str = "";

    def toggle(key: str) -> None {
        open_key = "" if open_key == key else key;
    }

    def handle_done(e: MouseEvent) {
        onDone();
    }

    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    people: list[dict] = (result["people"] or []) as list[dict];
    facts: list[dict] = (result["facts"] or []) as list[dict];
    intents: list[dict] = (result["intents"] or []) as list[dict];
    promises: list[dict] = (result["promises"] or []) as list[dict];
    ties: list[dict] = (result["ties"] or []) as list[dict];
    total: int = len(people) + len(facts) + len(intents) + len(promises) + len(ties);

    names: dict[str, str] = {};
    for k in known {
        names[_id_of(k)] = k.name;
    }
    for row in people {
        names[_id_of(row["person"])] = row["person"]["name"] as str;
    }

    return
        <div className="flex flex-col gap-6 pb-6">
            <header className="flex flex-col gap-1 pt-2">
                <h1 className="text-card-title">
                    {"Here's what Cirql read" if total > 0 else "Note saved"}
                </h1>
                {total > 0 and
                    <p className="text-body-sm text-muted-foreground">
                        Saved to your graph. Tap source on any row to see the words it came from.
                    </p>}
            </header>
            {if total == 0 {
                <div className="flex flex-col gap-3">
                    <p role="status" className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm">
                        Saved your note. Cirql couldn't pull out people this time — it's kept, and you can try again.
                    </p>
                    <SourceQuote span={note_text} note_text="" />
                    <Button variant="secondary" className="w-full" onClick={handle_retry}>Try again</Button>
                </div>
            }}
            {if len(people) > 0 {
                <ReviewSection title="People" count={len(people)}>
                    {for row in people {
                        <PersonItem
                            key={"p-" + _id_of(row["person"])}
                            row={row}
                            names={names}
                            spans={_spans_about(_id_of(row["person"]), result)}
                            open_key={open_key}
                            note_text={note_text}
                            onToggle={toggle}
                        />
                    }}
                </ReviewSection>
            }}
            {if len(facts) > 0 {
                <ReviewSection title="Facts" count={len(facts)}>
                    {for (i, row) in enumerate(facts) {
                        <ReviewRow
                            key={"f-" + str(i)}
                            row_key={"f-" + str(i)}
                            is_open={open_key == "f-" + str(i)}
                            span={row["span"] as str}
                            note_text={note_text}
                            onToggle={toggle}
                        >
                            <span className="text-body-sm">{row["fact"]["text"]}</span>
                            <span className="text-caption text-muted-foreground">{"about " + _name(names, row["about"] as str)}</span>
                        </ReviewRow>
                    }}
                </ReviewSection>
            }}
            {if len(intents) > 0 {
                <ReviewSection title="Intents" count={len(intents)}>
                    {for (i, row) in enumerate(intents) {
                        <ReviewRow
                            key={"i-" + str(i)}
                            row_key={"i-" + str(i)}
                            is_open={open_key == "i-" + str(i)}
                            span={row["span"] as str}
                            note_text={note_text}
                            onToggle={toggle}
                        >
                            <div className="flex items-start gap-2">
                                <Badge variant={"default" if row["intent"]["kind"] == "need" else "secondary"}>
                                    {_INTENT_LABEL[row["intent"]["kind"] as str] or (row["intent"]["kind"] as str)}
                                </Badge>
                                <span className="text-body-sm">{row["intent"]["text"]}</span>
                            </div>
                            <span className="text-caption text-muted-foreground">{_name(names, row["about"] as str)}</span>
                        </ReviewRow>
                    }}
                </ReviewSection>
            }}
            {if len(promises) > 0 {
                <ReviewSection title="Promises" count={len(promises)}>
                    {for (i, row) in enumerate(promises) {
                        <ReviewRow
                            key={"pr-" + str(i)}
                            row_key={"pr-" + str(i)}
                            is_open={open_key == "pr-" + str(i)}
                            span={row["span"] as str}
                            note_text={note_text}
                            onToggle={toggle}
                        >
                            <span className="text-body-sm">{row["promise"]["text"]}</span>
                            <span className="text-caption text-muted-foreground">
                                {join_with(
                                    [s for s in ["to " + _name(names, row["to"] as str), ("due " + (row["promise"]["due"] as str)) if row["promise"]["due"] else ""] if s],
                                    " · "
                                )}
                            </span>
                        </ReviewRow>
                    }}
                </ReviewSection>
            }}
            {if len(ties) > 0 {
                <ReviewSection title="Ties" count={len(ties)}>
                    {for (i, row) in enumerate(ties) {
                        <ReviewRow
                            key={"t-" + str(i)}
                            row_key={"t-" + str(i)}
                            is_open={open_key == "t-" + str(i)}
                            span={row["span"] as str}
                            note_text={note_text}
                            onToggle={toggle}
                        >
                            <span className="text-body-sm">
                                {_name(names, row["from"] as str) + " ↔ " + _name(names, row["to"] as str)}
                            </span>
                            <span className="text-caption text-muted-foreground">know each other</span>
                        </ReviewRow>
                    }}
                </ReviewSection>
            }}
            <Button className="w-full" size="lg" onClick={handle_done}>Done</Button>
        </div>;
}
