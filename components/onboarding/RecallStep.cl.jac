"""Onboarding step 4 — first recall: GoalRank rows for the active goal. OWNER: Person B.

No scores: each row shows an initials avatar, a strength word (Strong|Medium|
Weak), a relevance label, the reason, evidence chips, and a drafted opener as
plain text — nothing sends. Rows render via this step's own `RecallList` (not
the shared `components/goals/RankList`, out of scope here per SOH-232): it
matches Home's avatar treatment, sentence-cases the pills, and reframes a weak
row's relevance label positively — the model's own `reason` text is never
touched.

With no active goal (skipped step 2, or OnboardMe's extraction never surfaced
one — see components/onboarding/CardStep.cl.jac) there is nothing to rank: this
shows a human prompt and the shared NewGoalForm (components/goals/GoalPicker.cl.jac)
instead of a bare "—" or a misleading "capture a conversation" line.
"""

import from "..ui.button" { Button }
import from ..ui.avatar { Avatar }
import from ..ui.badge { Badge }
import from ..capture.Review { SourceQuote }
import from ..goals.RankList { RankSkeleton, strength_variant, EvidenceChip }
import from ..goals.GoalPicker { NewGoalForm }
import from ...lib.text { join_with, short_date }

"""First letter capitalised, display only — never mutates the stored value."""
def _cap(s: str) -> str {
    if not s {
        return s;
    }
    return s[0].upper() + s[1:];
}

def _sub(person: dict) -> str {
    return join_with([s for s in [(person["title"] or "") as str, (person["org"] or "") as str] if s], ", ");
}

def _contact_label(days: any) -> str {
    if days is None or not ((days as int) >= 0) {
        return "";
    }
    n: int = days as int;
    if n == 0 {
        return "Last contact today";
    }
    return "Last contact " + str(n) + "d ago";
}

def _chip_label(ev: dict) -> str {
    kind: str = (ev["kind"] or "note") as str;
    day: str = short_date((ev["observed_at"] or "") as str);
    return (kind + " · " + day) if day else kind;
}

"""The small relevance label next to the strength pill. Reframed positively
for a weak row: "Not connected to this goal yet" instead of a bare "no path
yet" — only this label changes; `row["reason"]` (the model's own text) is
never touched."""
def _relevance_label(strength: str, label: str) -> str {
    if strength == "weak" {
        return "Not connected to this goal yet";
    }
    if label == "route" {
        return "Via a friend";
    }
    if label == "cold" {
        return "No path yet";
    }
    return "";
}

def:pub RecallRow(row: dict, open_key: str, onToggle: Callable[[str], None]) -> JsxElement {
    person: dict = (row["person"] or {}) as dict;
    pid: str = (person["_jac_id"] or person["name"] or "") as str;
    name: str = (person["name"] or "") as str;
    sub: str = _sub(person);
    strength: str = (row["strength"] or "") as str;
    evidence: list[dict] = (row["evidence"] or []) as list[dict];
    contact: str = _contact_label(row["days_since_contact"]);
    opener: str = (row["opener"] or "") as str;
    relevance_label: str = _relevance_label(strength, row["label"] as str);
    open_span: str = "";
    for (i, ev) in enumerate(evidence) {
        if open_key == pid + ":" + str(i) {
            open_span = (ev["span"] or "") as str;
        }
    }
    has_open: bool = open_key.startswith(pid + ":");

    return
        <li className="flex flex-col gap-2 pt-3 pb-3 pl-4 pr-4">
            <div className="flex items-start gap-2.5">
                <Avatar name={name} size="sm" />
                <div className="flex min-w-0 flex-1 flex-col">
                    <span className="truncate text-body font-medium">{name}</span>
                    {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                </div>
                <div className="flex shrink-0 flex-wrap justify-end gap-1">
                    <Badge variant={strength_variant(strength)}>{_cap(strength)}</Badge>
                    {relevance_label and <Badge variant="outline">{relevance_label}</Badge>}
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

"""The first-recall list. Owns only which evidence chip is open."""
def:pub RecallList(rows: list[dict]) -> JsxElement {
    has open_key: str = "";

    def toggle(key: str) -> None {
        open_key = "" if open_key == key else key;
    }

    return
        <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
            {for (i, row) in enumerate(rows) {
                <RecallRow
                    key={((row["person"] or {})["_jac_id"] or str(i)) as str}
                    row={row}
                    open_key={open_key}
                    onToggle={toggle}
                />
            }}
        </ul>;
}

def:pub RecallStep(
    goal_text: str,
    rows: list[dict],
    pending: bool,
    error: str,
    goal_busy: bool,
    onAddGoal: Callable[[str], None],
    onDone: Callable[[], None]
) -> JsxElement {
    has draft: str = "";

    def handle_done(e: MouseEvent) {
        onDone();
    }

    def set_draft(v: str) {
        draft = v;
    }

    def save_goal() -> None {
        text: str = draft.strip();
        if not text {
            return;
        }
        onAddGoal(text);
        draft = "";
    }

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">First recall</h2>
                {if goal_text {
                    <div className="flex flex-col gap-2">
                        <span className="text-eyebrow text-muted-foreground">For your goal</span>
                        <p className="text-body-lg text-foreground">{_cap(goal_text)}</p>
                        <span className="text-caption text-muted-foreground">Here's who you already know</span>
                    </div>
                } else {
                    <p className="text-body-sm text-muted-foreground">
                        Add a goal to see who can help.
                    </p>
                }}
            </div>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            {if not goal_text {
                <NewGoalForm draft={draft} busy={goal_busy} autoFocus={False} onDraft={set_draft} onSave={save_goal} />
            } elif pending {
                <div className="flex flex-col gap-2">
                    <span role="status" className="text-caption text-muted-foreground">Reading your notes…</span>
                    <RankSkeleton />
                </div>
            } elif len(rows) == 0 and not error {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    No one yet, capture a conversation to start.
                </p>
            } else {
                <RecallList rows={rows} />
            }}
            <Button className="w-full" size="lg" disabled={pending} onClick={handle_done}>Done</Button>
        </div>;
}
