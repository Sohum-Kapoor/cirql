"""Compact "who to reach out to" row for Home's Today surface (SOH-226).

The collapsed view of a GoalRank row: an initials circle, the name, one
reason line (clamped to two lines) and a strength badge. Tapping the row
opens the person sheet, same target the full `RankList` row opens — that
full row (evidence chips, opener, contact line) only appears once "See all"
expands the section.
"""

import from ..ui.badge { Badge }
import from ..goals.RankList { strength_variant }
import from ...lib.text { join_with }

def:pub ReachOutRow(row: dict, on_open_person: Callable[[str], None] | None = None) -> JsxElement {
    person: dict = (row["person"] or {}) as dict;
    pid: str = (person["_jac_id"] or "") as str;
    name: str = (person["name"] or "") as str;
    reason: str = (row["reason"] or "") as str;
    strength: str = (row["strength"] or "") as str;
    initials: str = join_with([w[0] for w in name.split(" ") if w][:2], "");

    def handle(e: MouseEvent) {
        if pid and on_open_person {
            on_open_person(pid);
        }
    }

    return
        <li>
            <button
                type="button"
                onClick={handle}
                className="flex min-h-11 w-full items-start gap-2.5 pt-2.5 pb-2.5 pl-4 pr-3 text-left outline-none transition-colors hover:bg-secondary focus-visible:bg-secondary"
            >
                <span aria-hidden="true" className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-secondary text-caption font-medium text-ink-muted">
                    {initials}
                </span>
                <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="truncate text-body-sm font-medium">{name}</span>
                    {reason and <span className="line-clamp-2 text-caption text-muted-foreground">{reason}</span>}
                </span>
                <Badge variant={strength_variant(strength)} className="mt-0.5 shrink-0">{strength}</Badge>
            </button>
        </li>;
}

def:pub ReachOutList(rows: list[dict], on_open_person: Callable[[str], None] | None = None) -> JsxElement {
    return
        <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
            {for (i, row) in enumerate(rows) {
                <ReachOutRow key={((row["person"] or {})["_jac_id"] or str(i)) as str} row={row} on_open_person={on_open_person} />
            }}
        </ul>;
}
