"""GoalRank rows — shared by onboarding step 4 and the home screen. OWNER: Person B.

Relevance is a property of (person, goal), so nothing here is a person-level
score: each row shows a strength word (strong|medium|weak), a label
(known|route|cold), the one-line reason, `days_since_contact` as muted display
text only, and the drafted opener as plain text — nothing sends.

Every evidence item is a small chip ("fact · Sep 26"); tapping one quotes its
span (Review's SourceQuote). One chip open at a time across the whole list.
"""

import from ..ui.badge { Badge }
import from ..ui.button { Button }
import from ..ui.icons { QuoteIcon }
import from ..ui.skeleton { Skeleton }
import from ..capture.Review { SourceQuote }
import from ...lib.text { join_with, short_date }
import from ...lib.utils { cn }

glob _FALLBACK_PREFIXES: list[str] = ["Extraction unavailable", "Ranking unavailable", "No ranking returned"];

def:pub strength_variant(strength: str) -> str {
    if strength == "strong" {
        return "default";
    }
    if strength == "medium" {
        return "secondary";
    }
    return "outline";
}

"""True when any row came from GoalRank's deterministic fallback (Gemini down)."""
def:pub is_partial(rows: list[dict]) -> bool {
    for row in rows {
        reason: str = (row["reason"] or "") as str;
        for pre in _FALLBACK_PREFIXES {
            if reason.startswith(pre) {
                return True;
            }
        }
    }
    return False;
}

"""Display only: "last contact 12d ago" / "today"; "" when null or missing."""
def _contact_label(days: any) -> str {
    if days is None or not ((days as int) >= 0) {
        return "";
    }
    n: int = days as int;
    if n == 0 {
        return "last contact today";
    }
    return "last contact " + str(n) + "d ago";
}

def _chip_label(ev: dict) -> str {
    kind: str = (ev["kind"] or "note") as str;
    day: str = short_date((ev["observed_at"] or "") as str);
    return (kind + " · " + day) if day else kind;
}

def:pub EvidenceChip(
    chip_key: str,
    ev: dict,
    is_open: bool,
    onToggle: Callable[[str], None]
) -> JsxElement {
    def handle_toggle(e: MouseEvent) {
        onToggle(chip_key);
    }

    return
        <Button
            variant="chip"
            size="chip"
            aria-expanded={is_open}
            aria-label={("Hide " if is_open else "Show ") + "evidence: " + _chip_label(ev)}
            onClick={handle_toggle}
        >
            <QuoteIcon className="size-3" />
            <span>{_chip_label(ev)}</span>
        </Button>;
}

def:pub RankRow(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    person: dict = (row["person"] or {}) as dict;
    pid: str = (person["_jac_id"] or person["name"] or "") as str;
    sub: str = join_with([s for s in [(person["title"] or "") as str, (person["org"] or "") as str] if s], ", ");
    evidence: list[dict] = (row["evidence"] or []) as list[dict];
    contact: str = _contact_label(row["days_since_contact"]);
    opener: str = (row["opener"] or "") as str;
    open_span: str = "";
    for (i, ev) in enumerate(evidence) {
        if open_key == pid + ":" + str(i) {
            open_span = (ev["span"] or "") as str;
        }
    }
    has_open: bool = open_key.startswith(pid + ":");

    return
        <li className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
            <div className="flex items-start justify-between gap-2">
                <div className="flex min-w-0 flex-col">
                    <span className="truncate text-body font-medium">{person["name"] as str}</span>
                    {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                </div>
                <div className="flex shrink-0 gap-1">
                    <Badge variant={strength_variant(row["strength"] as str)}>{row["strength"] as str}</Badge>
                    <Badge variant="outline">{row["label"] as str}</Badge>
                </div>
            </div>
            <p className="text-body-sm text-ink-muted">{row["reason"] as str}</p>
            {contact and <span className="text-caption text-muted-foreground">{contact}</span>}
            {opener and <p className="text-caption italic text-muted-foreground">{"Opener: " + opener}</p>}
            {len(evidence) > 0 and
                <div className="flex flex-wrap gap-1.5 pt-0.5">
                    {for (i, ev) in enumerate(evidence) {
                        <EvidenceChip
                            key={pid + ":" + str(i)}
                            chip_key={pid + ":" + str(i)}
                            ev={ev}
                            is_open={open_key == pid + ":" + str(i)}
                            onToggle={onToggle}
                        />
                    }}
                </div>}
            {has_open and <SourceQuote span={open_span} note_text="" />}
        </li>;
}

"""The ranked list. Owns only which evidence chip is open."""
def:pub RankList(rows: list[dict], dim: bool = False) -> JsxElement {
    has open_key: str = "";

    def toggle(key: str) -> None {
        open_key = "" if open_key == key else key;
    }

    return
        <ul
            aria-busy={dim}
            className={cn(
                "flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge transition-opacity",
                "opacity-60" if dim else ""
            )}
        >
            {for (i, row) in enumerate(rows) {
                <RankRow
                    key={((row["person"] or {})["_jac_id"] or str(i)) as str}
                    row={row}
                    open_key={open_key}
                    onToggle={toggle}
                />
            }}
        </ul>;
}

"""Placeholder rows while a goal ranks for the first time (list only)."""
def:pub RankSkeleton() -> JsxElement {
    return
        <ul aria-hidden="true" className="flex flex-col divide-y divide-border rounded-lg border bg-card shadow-edge">
            {for i in range(3) {
                <li key={str(i)} className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
                    <div className="flex items-center justify-between gap-2">
                        <Skeleton className="h-4 w-32" />
                        <Skeleton className="h-5 w-20 rounded-full" />
                    </div>
                    <Skeleton className="h-3.5 w-full" />
                    <Skeleton className="h-3.5 w-2/3" />
                </li>
            }}
        </ul>;
}
