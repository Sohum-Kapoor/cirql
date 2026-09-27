"""The top of the Inbox tab: agent status + "Your agent found" (SOH-224). OWNER: Person B.

Header: "Agent ran 2 min ago · 3 new" (or a running line) and *Run agent now*.
Below it the open AgentActions as cards, filterable by kind with small pill tabs
(All · Asks · Routes · Follow-ups · Matches); while a run is in flight two
skeleton cards sit on top. Approve routes by kind:
  ask_network -> the existing *Ask my network* sheet (GapAlert's AskSheet),
                 prefilled from the payload; *Post request* = ResolveAgentAction
                 (approve, edited_draft=<need>), which posts it server-side
  answer_ask  -> the existing friend reply flow for that request
  otherwise   -> ResolveAgentAction(approve, edited draft)
The shell owns the rows and every resolve (optimistic, rolled back on error).
"""

import from ..ui.button { Button }
import from ..ui.skeleton { Skeleton }
import from ..ui.tabs { Tabs, TabsList, TabsTrigger }
import from ..exchange.GapAlert { AskSheet }
import from .ActionCard { ActionCard }
import from .common { FILTERS, in_filter, payload_of, ago_words, AgentIcon }
import from ...lib.utils { cn }

def:pub AgentSkeleton() -> JsxElement {
    return
        <li aria-hidden="true" className="flex flex-col gap-3 rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4 shadow-edge">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-4 w-3/4" />
            <Skeleton className="h-3.5 w-full" />
            <div className="flex gap-2">
                <Skeleton className="h-10 flex-1" />
                <Skeleton className="h-10 w-20" />
            </div>
        </li>;
}

"""Status line + Run agent now."""
def:pub AgentHeader(
    running: bool,
    last_run: dict,
    open_count: int,
    available: bool,
    error: str,
    onRun: Callable[[], None]
) -> JsxElement {
    def handle_run(e: MouseEvent) {
        onRun();
    }

    ran_ms: int = (last_run["ms"] or 0) as int;
    ago: str = ago_words((Date.now() as int) - ran_ms) if ran_ms > 0 else "";  # jac:ignore[W2001]
    n_new: int = (last_run["new"] or 0) as int;
    line: str = "";
    if running {
        line = "Reading your notes…";
    } elif not available {
        line = "Cirql isn't switched on for this account yet.";
    } elif ago {
        line = "Checked " + ago + " · " + (str(n_new) + " new" if n_new > 0 else "nothing new");
    } else {
        line = "Cirql hasn't checked yet this session.";
    }

    return
        <div className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-3">
                <p role="status" aria-live="polite" className="flex min-w-0 items-center gap-2 text-caption text-muted-foreground">
                    <span
                        aria-hidden="true"
                        className={cn("size-2 shrink-0 rounded-full", "animate-pulse bg-primary" if running else ("bg-success-text" if ago else "bg-border-strong"))}
                    />
                    <span data-agent-status="" className="min-w-0">{line}</span>
                </p>
                <Button size="sm" variant="outline" disabled={running or not available} onClick={handle_run} className="shrink-0">
                    <AgentIcon />
                    {"Running…" if running else "Check now"}
                </Button>
            </div>
            {error and <p role="alert" className="text-caption text-destructive">{error}</p>}
        </div>;
}

def:pub AgentInbox(
    rows: list[dict],
    loaded: bool,
    running: bool,
    last_run: dict,
    available: bool,
    run_error: str,
    pending: dict,
    errors: dict,
    default_about: str,
    ask_busy: bool,
    ask_error: str,
    onRun: Callable[[], None],
    onResolve: Callable[[str, str, str], None],
    onPostAsk: Callable[[str, str, str], None],
    onAnswerAsk: Callable[[str, str], None],
    onOpenPerson: Callable[[str], None]
) -> JsxElement {
    has filt: str = "all",
        ask_aid: str = "",
        posted: bool = False,
        need: str = "",
        about_line: str = "",
        ask_kind: str = "";

    def find_row(aid: str) -> dict {
        for r in rows {
            if (r["action"] or {})["_jac_id"] == aid {
                return r;
            }
        }
        return {};
    }

    def approve(aid: str, draft: str) -> None {
        act: dict = (find_row(aid)["action"] or {}) as dict;
        kind: str = (act["kind"] or "") as str;
        if kind == "ask_network" {
            pl: dict = payload_of(act);
            ask_aid = aid;
            posted = False;
            need = ((draft or pl["need"] or act["title"] or "") as str);
            about_line = ((pl["about_line"] or default_about or "") as str);
            ask_kind = ((pl["kind"] or "someone who can help") as str);
            return;
        }
        if kind == "answer_ask" and act["request_id"] {
            onAnswerAsk(aid, act["request_id"] as str);
            return;
        }
        onResolve(aid, "approve", draft);
    }

    def dismiss(aid: str) -> None {
        onResolve(aid, "dismiss", "");
    }

    def snooze(aid: str) -> None {
        onResolve(aid, "snooze", "");
    }

    def post() -> None {
        posted = True;
        onPostAsk(ask_aid, need.strip(), about_line.strip());
    }

    def set_sheet(v: bool) -> None {
        if not v {
            ask_aid = "";
            posted = False;
        }
    }

    def set_filter(v: str) -> None {
        filt = v;
    }

    def run_now() -> None {
        filt = "all";
        onRun();
    }

    open_rows: list[dict] = [r for r in rows if ((r["action"] or {})["status"] or "open") == "open"];
    shown: list[dict] = [r for r in rows if in_filter(((r["action"] or {})["kind"] or "") as str, filt)];
    counts: dict = {};
    for (key, label) in FILTERS {
        n: int = 0;
        for r in open_rows {
            if in_filter(((r["action"] or {})["kind"] or "") as str, key) {
                n = n + 1;
            }
        }
        counts[key] = n;
    }
    # The sheet closes itself once the post lands (busy -> idle with no error).
    sheet_open: bool = ask_aid != "" and not (posted and not ask_busy and not ask_error);

    return
        <section aria-label="What Cirql found" className="flex flex-col gap-3">
            <AgentHeader
                running={running}
                last_run={last_run}
                open_count={len(open_rows)}
                available={available}
                error={run_error}
                onRun={run_now}
            />
            <div className="flex items-center justify-between gap-2 pt-1">
                <h2 className="text-eyebrow text-muted-foreground">What Cirql found</h2>
                <span className="text-caption tabular-nums text-muted-foreground">{str(len(open_rows))}</span>
            </div>
            {len(rows) > 0 and
                <Tabs value={filt} onValueChange={set_filter} className="gap-0">
                    <TabsList aria-label="Filter by kind" className="-ml-4 -mr-4 w-[calc(100%+2rem)] justify-start overflow-x-auto rounded-none border-0 bg-transparent pl-4 pr-4 [scrollbar-width:none]">
                        {for f in FILTERS {
                            <TabsTrigger key={f[0]} value={f[0]} className="flex-none border-border pl-3 pr-3 text-caption">
                                {f[1]}
                                {(counts[f[0]] or 0) > 0 and f[0] != "all" and
                                    <span className="tabular-nums text-ink-tertiary">{str(counts[f[0]])}</span>}
                            </TabsTrigger>
                        }}
                    </TabsList>
                </Tabs>}
            {if not loaded and not running {
                <ul aria-label="Loading your suggestions" className="flex flex-col gap-3">
                    <AgentSkeleton />
                </ul>
            } elif len(rows) == 0 and not running {
                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                    Capture a conversation and Cirql will look for introductions, gaps and follow-ups — you approve everything. Nothing sends on its own.
                </p>
            } else {
                <ul className="flex flex-col gap-3" aria-busy={running}>
                    {running and <AgentSkeleton key="sk-1" />}
                    {running and <AgentSkeleton key="sk-2" />}
                    {for r in shown {
                        <ActionCard
                            key={((r["action"] or {})["_jac_id"] or "") as str}
                            row={r}
                            pending={True if pending[(r["action"] or {})["_jac_id"]] else False}
                            error={(errors[(r["action"] or {})["_jac_id"]] or "") as str}
                            onApprove={approve}
                            onDismiss={dismiss}
                            onSnooze={snooze}
                            onOpenPerson={onOpenPerson}
                        />
                    }}
                    {if len(shown) == 0 and not running {
                        <li className="rounded-lg border border-dashed border-border-strong pt-3 pb-3 pl-4 pr-4 text-body-sm text-muted-foreground">
                            Nothing of this kind right now.
                        </li>
                    }}
                </ul>
            }}
            <AskSheet
                open={sheet_open}
                kind={ask_kind}
                need={need}
                about_line={about_line}
                busy={ask_busy}
                error={ask_error if posted else ""}
                onNeed={lambda v: str { need = v; }}
                onAbout={lambda v: str { about_line = v; }}
                onPost={post}
                onOpenChange={set_sheet}
                about_locked={True}
                audience_locked={True}
            />
        </section>;
}
