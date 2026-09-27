"""SearchBox (SOH-222 A5): find a person, a fact, a want/offer, a promise, or a
note across your own graph, and ask a plain-English question of it.

An input with a 250ms debounce calls `Search(query, limit=25)` on every
keystroke and renders the results grouped People -> Facts -> Wants/offers ->
Promises -> Notes, each row with a kind badge, the matched text (query tokens
highlighted), the person's name as a link (`on_open_person`), and a source
chip quoting the `span` it came from. When the query looks like a question
(ends in "?", or starts with who/what/when/.../how), an "Ask your graph" card
also appears; Enter calls `Recall(question)` and renders its answer plus
citation chips.

Keyboard: Enter runs Recall when the query looks like a question, otherwise
opens the highlighted result's person; Escape clears everything; Up/Down move
a roving `active_index` through the flat, grouped result order (results sit
in a `role="listbox"`, `aria-activedescendant` follows the active row).

Recall's citations (contracts/walkers.md) carry a person NAME, not an id -
`on_open_person` needs an id, so a citation chip is only clickable when that
name matches a `person_name` already seen in this query's own Search results
(best-effort; unresolved names still render, just not as a link).
"""

import from ..ui.button { Button }
import from ..ui.badge { Badge }
import from ..ui.input { Input }
import from ..ui.skeleton { Skeleton }
import from ..ui.icons { XIcon }
import from ..promises.Today { TodayGroup }
import from ..api { search, recall }
import from ...lib.text { short_date }
import from ...lib.utils { cn }

glob _KIND_LABEL: dict[str, str] = {
    "person": "Person", "fact": "Fact", "intent": "Want/Offer",
    "promise": "Promise", "note": "Note"
};

glob _GROUP_TITLE: dict[str, str] = {
    "person": "People", "fact": "Facts", "intent": "Wants / offers",
    "promise": "Promises", "note": "Notes"
};

glob _QUESTION_STARTERS: list[str] = [
    "who", "what", "when", "where", "which", "did", "do", "is", "are", "how"
];

glob _SPAN_CAP: int = 64;

def _s(d: dict, key: str) -> str {
    return (d[key] or "") as str;
}

def _looks_like_question(q: str) -> bool {
    trimmed: str = q.strip();
    if not trimmed {
        return False;
    }
    if trimmed.endswith("?") {
        return True;
    }
    words: list[str] = trimmed.lower().split();
    first_word: str = words[0] if words else "";
    return first_word in _QUESTION_STARTERS;
}

def _kind_rank(kind: str) -> int {
    order: dict[str, int] = {"person": 0, "fact": 1, "intent": 2, "promise": 3, "note": 4};
    if kind in order {
        return order[kind];
    }
    return 5;
}

def _row_group_rank(row: dict) -> int {
    return _kind_rank(_s(row, "kind"));
}

def _truncate(text: str, n: int) -> str {
    if len(text) <= n {
        return text;
    }
    return text[:n] + "…";
}

"""Every occurrence of every non-empty token in `text`, case-insensitive,
merged where they overlap - so a multi-token query highlights cleanly even
when tokens overlap or repeat."""
def _match_spans(text_l: str, tokens: list[str]) -> list[list[int]] {
    raw: list[list[int]] = [];
    for tok in tokens {
        if not tok {
            continue;
        }
        start = 0;
        while True {
            idx = text_l.find(tok, start);
            if idx < 0 {
                break;
            }
            raw.append([idx, idx + len(tok)]);
            start = idx + len(tok);
        }
    }
    if not raw {
        return [];
    }
    ranked = sorted(raw, key=_span_start);
    merged: list[list[int]] = [];
    for sp in ranked {
        if merged and sp[0] <= merged[len(merged) - 1][1] {
            if sp[1] > merged[len(merged) - 1][1] {
                merged[len(merged) - 1][1] = sp[1];
            }
        } else {
            merged.append(sp);
        }
    }
    return merged;
}

def _span_start(sp: list[int]) -> int {
    return sp[0];
}

def:pub Highlighted(text: str, tokens: list[str]) -> JsxElement {
    spans = _match_spans(text.lower(), tokens);
    if not spans {
        return <span>{text}</span>;
    }
    pieces: list[any] = [];
    pos = 0;
    idx = 0;
    for sp in spans {
        start = sp[0];
        stop = sp[1];
        if start > pos {
            pieces.append(<span key={"t" + str(idx)}>{text[pos:start]}</span>);
            idx = idx + 1;
        }
        pieces.append(
            <mark key={"m" + str(idx)} className="rounded-xs bg-primary/20 pl-0.5 pr-0.5 text-foreground">
                {text[start:stop]}
            </mark>
        );
        idx = idx + 1;
        pos = stop;
    }
    if pos < len(text) {
        pieces.append(<span key={"t" + str(idx)}>{text[pos:]}</span>);
    }
    return <span>{pieces}</span>;
}

def:pub SearchResultRow(
    row: dict,
    tokens: list[str],
    index: int,
    is_active: bool,
    onOpenPerson: Callable[[str], None]
) -> JsxElement {
    kind: str = _s(row, "kind");
    text: str = _s(row, "text");
    pid: str = _s(row, "person_id");
    pname: str = _s(row, "person_name");
    span: str = _s(row, "span");
    date_label: str = short_date(_s(row, "observed_at"));
    is_person: bool = kind == "person";

    def handle_person(e: MouseEvent) {
        if pid {
            onOpenPerson(pid);
        }
    }

    return
        <li
            id={"search-result-" + str(index)}
            role="option"
            aria-selected={is_active}
            className={cn("flex flex-col gap-1 pt-2.5 pb-2.5 pl-3 pr-3", "bg-secondary" if is_active else "")}
        >
            <div className="flex items-center gap-1.5">
                <Badge variant={"default" if is_person else "secondary"}>{_KIND_LABEL[kind] or kind}</Badge>
                {date_label and <span className="text-caption text-muted-foreground">{date_label}</span>}
            </div>
            {if is_person {
                <Button variant="link" size="inline" className="h-auto justify-start p-0 text-body-sm" onClick={handle_person}>
                    {Highlighted(text, tokens)}
                </Button>
            } else {
                <p className="text-body-sm">{Highlighted(text, tokens)}</p>
            }}
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                {(not is_person) and pid and
                    <Button variant="link" size="inline" className="text-caption" onClick={handle_person}>{pname}</Button>}
                {span and <Badge variant="outline">{_truncate(span, _SPAN_CAP)}</Badge>}
            </div>
        </li>;
}

def:pub CitationChip(c: dict, name_to_id: dict, onOpenPerson: Callable[[str], None]) -> JsxElement {
    person: str = _s(c, "person");
    span: str = _s(c, "span");
    kind: str = _s(c, "kind");
    label: str = person if person else (_KIND_LABEL[kind] or kind);
    target_id: str = "";
    if person and person in name_to_id {
        target_id = name_to_id[person] as str;
    }

    def handle(e: MouseEvent) {
        if target_id {
            onOpenPerson(target_id);
        }
    }

    if target_id {
        return
            <button
                type="button"
                onClick={handle}
                title={span}
                className="inline-flex h-5 items-center rounded-full border border-transparent bg-primary/15 pt-0.5 pb-0.5 pl-2 pr-2 text-caption font-medium text-link transition-colors hover:bg-primary/25"
            >
                {label}
            </button>;
    }
    return <Badge variant="outline" title={span}>{label}</Badge>;
}

def:pub RecallCard(
    question: str,
    loading: bool,
    error: str,
    answer: dict,
    asked: str,
    name_to_id: dict,
    onOpenPerson: Callable[[str], None],
    onRetry: Callable[[], None]
) -> JsxElement {
    def handle_retry(e: MouseEvent) {
        onRetry();
    }

    has_answer: bool = bool(answer) and asked == question;
    citations: list[dict] = [];
    answer_text: str = "";
    if has_answer {
        citations = (answer["citations"] or []) as list[dict];
        answer_text = _s(answer, "answer");
    }

    return
        <div className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
            <div className="flex items-baseline justify-between">
                <h2 className="text-eyebrow text-muted-foreground">Ask your graph</h2>
                {(not has_answer) and (not loading) and (not error) and
                    <span className="text-caption text-muted-foreground">Press Enter to ask</span>}
            </div>
            {if loading {
                <div role="status" aria-label="Asking your graph" className="flex flex-col gap-2">
                    <Skeleton className="h-4 w-3/4" />
                    <Skeleton className="h-3 w-1/2" />
                </div>
            } elif error {
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{error}</p>
                    <Button size="sm" variant="outline" onClick={handle_retry}>Retry</Button>
                </div>
            } elif has_answer {
                <p className="text-body-sm">{answer_text}</p>
                if len(citations) > 0 {
                    <div className="flex flex-wrap items-center gap-1.5">
                        {for (i, c) in enumerate(citations) {
                            <CitationChip key={"c" + str(i)} c={c} name_to_id={name_to_id} onOpenPerson={onOpenPerson} />
                        }}
                    </div>
                }
            }}
        </div>;
}

def:pub SearchBox(
    on_open_person: Callable[[str], None],
    placeholder: str = "Find a person, a fact, a note…"
) -> JsxElement {
    has query: str = "",
        results: list[dict] = [],
        total: int = 0,
        searched: bool = False,
        loading: bool = False,
        error: str = "",
        active_index: int = -1,
        recall_answer: dict = {},
        recall_loading: bool = False,
        recall_error: str = "",
        recall_asked: str = "",
        debounceRef: Ref[any] = Ref(None);

    trimmed_query: str = query.strip();
    is_question: bool = _looks_like_question(query);
    tokens: list[str] = [t for t in trimmed_query.lower().split() if t];
    grouped: list[dict] = sorted(results, key=_row_group_rank);

    name_to_id: dict = {};
    for r in results {
        pid = _s(r, "person_id");
        pname = _s(r, "person_name");
        if pid and pname {
            name_to_id[pname] = pid;
        }
    }

    index_by_id: dict = {};
    for (i, row) in enumerate(grouped) {
        index_by_id[_s(row, "id")] = i;
    }
    person_rows: list[dict] = [r for r in grouped if _s(r, "kind") == "person"];
    fact_rows: list[dict] = [r for r in grouped if _s(r, "kind") == "fact"];
    intent_rows: list[dict] = [r for r in grouped if _s(r, "kind") == "intent"];
    promise_rows: list[dict] = [r for r in grouped if _s(r, "kind") == "promise"];
    note_rows: list[dict] = [r for r in grouped if _s(r, "kind") == "note"];

    def clear_all() {
        if debounceRef.current {
            clearTimeout(debounceRef.current);  # jac:ignore[W2001,E1053]
            debounceRef.current = None;
        }
        query = "";
        results = [];
        total = 0;
        searched = False;
        loading = False;
        error = "";
        active_index = -1;
        recall_answer = {};
        recall_error = "";
        recall_asked = "";
    }

    async def run_search(q: str) -> None {
        out: dict = {};
        try {
            out = await search(q, 25);
            results = (out["results"] or []) as list[dict];
            total = (out["total"] or 0) as int;
            error = "";
        } except Exception as err {
            error = "Couldn't search your graph. " + str(err);
            results = [];
            total = 0;
        }
        loading = False;
        searched = True;
        active_index = -1;
    }

    def handle_retry_search(e: MouseEvent) {
        if trimmed_query {
            loading = True;
            run_search(trimmed_query);
        }
    }

    def retry_recall() {
        if trimmed_query {
            run_recall(trimmed_query);
        }
    }

    async def run_recall(q: str) -> None {
        recall_loading = True;
        recall_error = "";
        out: dict = {};
        try {
            out = await recall(q);
            recall_answer = out;
        } except Exception as err {
            recall_error = "Couldn't ask your graph. " + str(err);
            recall_answer = {};
        }
        recall_loading = False;
        recall_asked = q;
    }

    def handle_change(e: ChangeEvent) {
        val: str = e.target.value;
        query = val;
        active_index = -1;
        recall_answer = {};
        recall_error = "";
        recall_asked = "";
        if debounceRef.current {
            clearTimeout(debounceRef.current);  # jac:ignore[W2001,E1053]
        }
        val_trimmed = val.strip();
        if not val_trimmed {
            results = [];
            total = 0;
            searched = False;
            loading = False;
            return;
        }
        loading = True;
        debounceRef.current = setTimeout(lambda { run_search(val); }, 250);
    }

    def handle_clear(e: MouseEvent) {
        clear_all();
    }

    def handle_key_down(e: KeyboardEvent) {
        if e.key == "Escape" {
            clear_all();
            return;
        }
        if e.key == "Enter" {
            if is_question and trimmed_query {
                run_recall(trimmed_query);
            } elif active_index >= 0 and active_index < len(grouped) {
                row = grouped[active_index];
                pid = _s(row, "person_id");
                if pid {
                    on_open_person(pid);
                }
            }
            return;
        }
        if e.key == "ArrowDown" {
            e.preventDefault();
            if active_index < len(grouped) - 1 {
                active_index = active_index + 1;
            }
            return;
        }
        if e.key == "ArrowUp" {
            e.preventDefault();
            if active_index > -1 {
                active_index = active_index - 1;
            }
            return;
        }
    }

    active_descendant: str = ("search-result-" + str(active_index)) if active_index >= 0 else "";
    show_empty: bool = searched and (not error) and len(grouped) == 0;

    return
        <div className="flex flex-col gap-2">
            <div className="relative">
                <svg
                    aria-hidden="true"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground"
                >
                    <circle cx="11" cy="11" r="7" />
                    <path d="m21 21-4.3-4.3" />
                </svg>
                <Input
                    type="text"
                    value={query}
                    onChange={handle_change}
                    onKeyDown={handle_key_down}
                    placeholder={placeholder}
                    role="combobox"
                    aria-expanded={len(grouped) > 0}
                    aria-controls="search-results-listbox"
                    aria-activedescendant={active_descendant}
                    aria-autocomplete="list"
                    aria-label="Search your graph"
                    className="pl-9 pr-9"
                />
                {query and
                    <button
                        type="button"
                        onClick={handle_clear}
                        aria-label="Clear search"
                        className="absolute top-1/2 right-0 flex min-h-11 min-w-11 -translate-y-1/2 items-center justify-center rounded-xs text-muted-foreground hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring/50"
                    >
                        <XIcon className="size-4" />
                    </button>}
            </div>

            {is_question and trimmed_query and
                <RecallCard
                    question={trimmed_query}
                    loading={recall_loading}
                    error={recall_error}
                    answer={recall_answer}
                    asked={recall_asked}
                    name_to_id={name_to_id}
                    onOpenPerson={on_open_person}
                    onRetry={retry_recall}
                />}

            {trimmed_query and
                <div id="search-results-listbox" role="listbox" aria-label="Search results" className="flex flex-col gap-3">
                    {if loading and not searched {
                        <div role="status" aria-label="Searching your graph" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                            <Skeleton className="h-4 w-3/4" />
                            <Skeleton className="h-3 w-1/3" />
                        </div>
                    } elif error {
                        <div className="flex items-center gap-2">
                            <p role="alert" className="flex-1 text-body-sm text-destructive">{error}</p>
                            <Button size="sm" variant="outline" onClick={handle_retry_search}>Retry</Button>
                        </div>
                    } elif show_empty {
                        <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                            Nothing matched. Try a first name, a company, or a word from the conversation.
                        </p>
                    } else {
                        if len(person_rows) > 0 {
                            <TodayGroup title="People" count={len(person_rows)}>
                                {for row in person_rows {
                                    <SearchResultRow
                                        key={_s(row, "id")}
                                        row={row}
                                        tokens={tokens}
                                        index={index_by_id[_s(row, "id")] as int}
                                        is_active={(index_by_id[_s(row, "id")] as int) == active_index}
                                        onOpenPerson={on_open_person}
                                    />
                                }}
                            </TodayGroup>
                        }
                        if len(fact_rows) > 0 {
                            <TodayGroup title="Facts" count={len(fact_rows)}>
                                {for row in fact_rows {
                                    <SearchResultRow
                                        key={_s(row, "id")}
                                        row={row}
                                        tokens={tokens}
                                        index={index_by_id[_s(row, "id")] as int}
                                        is_active={(index_by_id[_s(row, "id")] as int) == active_index}
                                        onOpenPerson={on_open_person}
                                    />
                                }}
                            </TodayGroup>
                        }
                        if len(intent_rows) > 0 {
                            <TodayGroup title="Wants / offers" count={len(intent_rows)}>
                                {for row in intent_rows {
                                    <SearchResultRow
                                        key={_s(row, "id")}
                                        row={row}
                                        tokens={tokens}
                                        index={index_by_id[_s(row, "id")] as int}
                                        is_active={(index_by_id[_s(row, "id")] as int) == active_index}
                                        onOpenPerson={on_open_person}
                                    />
                                }}
                            </TodayGroup>
                        }
                        if len(promise_rows) > 0 {
                            <TodayGroup title="Promises" count={len(promise_rows)}>
                                {for row in promise_rows {
                                    <SearchResultRow
                                        key={_s(row, "id")}
                                        row={row}
                                        tokens={tokens}
                                        index={index_by_id[_s(row, "id")] as int}
                                        is_active={(index_by_id[_s(row, "id")] as int) == active_index}
                                        onOpenPerson={on_open_person}
                                    />
                                }}
                            </TodayGroup>
                        }
                        if len(note_rows) > 0 {
                            <TodayGroup title="Notes" count={len(note_rows)}>
                                {for row in note_rows {
                                    <SearchResultRow
                                        key={_s(row, "id")}
                                        row={row}
                                        tokens={tokens}
                                        index={index_by_id[_s(row, "id")] as int}
                                        is_active={(index_by_id[_s(row, "id")] as int) == active_index}
                                        onOpenPerson={on_open_person}
                                    />
                                }}
                            </TodayGroup>
                        }
                    }}
                </div>}
        </div>;
}
