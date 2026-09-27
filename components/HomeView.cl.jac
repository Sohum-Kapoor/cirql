"""Logged-in home, split over a bottom tab bar (SOH-213). OWNER: Person B.

  Home   — goal picker, who can help with the active goal (GoalRank; the first
           RANK_PREVIEW rows, "See all (N)" expands in place), gaps for this goal
           (GapFinder) with *Ask my network*. Nothing else.
  Inbox  — (SOH-224, was "Asks") "Your agent found": AgentActions from RunAgent /
           ListAgentActions (components/agent), then "Needs your OK" (friends'
           asks, ListIncomingRequests; an ask an `answer_ask` card already
           covers is left out here) and "Your asks" (ListMyRequests). Dev "Act
           as friend" toggle under ?mock=1.
  People — the people you know, SK's graph toggle (GraphView) and Today's
           promises, exactly as they rendered on the old single page.
The header (Cirql + overflow menu), the person sheet and the tab bar with its
Capture action are shared by all three. The shell owns `tab` (remembered for
the session, and set by deep links: Capture -> Done lands on Home, back from an
ask / request lands on Inbox).

Switching goals only swaps the ranked list: the shell keeps GoalRank results per
goal_id for the session, and a goal that isn't cached yet shows a loading state
on the list alone — the header and picker stay put.
"""

import from .ui.button { Button, buttonVariants }
import from .ui.skeleton { Skeleton }
import from .ui.badge { Badge }
import from .ui.dropdown_menu {
    DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem,
    DropdownMenuSeparator
}
import from .ui.icons { MoreIcon, ChevronRightIcon, ChevronDownIcon, PlusIcon }
import from .settings.AppearanceSheet { AppearanceSheet }
import from .ui.tabs { Tabs, TabsList, TabsTrigger, TabsContent }
import from react { useEffect }
import from .person.PersonSheet { PersonSheet }
import from .promises.Today { Today }
import from .graph.GraphView { GraphView }
import from .goals.GoalPicker { GoalPicker }
import from .goals.RankList { RankList, RankSkeleton, is_partial }
import from .home.PromisesDue { PromisesDue }
import from .home.ReachOutRow { ReachOutList }
import from .exchange.GapAlert { GapSingle }
import from .exchange.Requests { RequestsSection }
import from .exchange.Inbox { AsksSection }
import from .agent.AgentInbox { AgentInbox }
import from .nav.TabBar { TabBar }
import from .search.SearchBox { SearchBox }
import from .circles.Circles { Circles }
import from .events.Events { Events }
import from .notes.Timeline { Timeline }
import from .people.ImportPeople { ImportPeople }
import from ..lib.text { join_with }
import from ..lib.utils { cn }
import from .agent.common { since_iso }
sv import from ..schema { Person }

glob RANK_PREVIEW: int = 3;
glob MONTH_ABBR: list[str] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
];
glob NINETY_DAYS_MS: int = 90 * 24 * 60 * 60 * 1000;

"""SOH-226: "Quiet for 90 days" is a display-only filter (relationships never
decay — AGENTS.md). A person counts as quiet when `Knows.last_contact` is
empty or unparseable (nothing captured yet) or older than 90 days. Reads
`person["last_contact"]` defensively: `ListPeople` doesn't carry it yet
(contract note appended below asking A to add it), so today every row is
quiet until that lands — never a crash, never a score."""
def:pub is_quiet_person(person: any) -> bool {
    lc: str = (person["last_contact"] or "") as str;
    ms: int = since_iso(lc);
    if ms < 0 {
        return True;
    }
    return ms > NINETY_DAYS_MS;
}

"""`Knows.last_contact` (ISO-8601) -> "Mon D", or "" when empty/unparseable."""
def:pub format_last_contact(last_contact: str) -> str {
    lc: str = (last_contact or "").strip();
    if not lc {
        return "";
    }
    try {
        d: any = new(Date, lc);  # jac:ignore[W2001]
        t: any = d.getTime();  # jac:ignore[W2001]
        if isNaN(t) {  # jac:ignore[W2001]
            return "";
        }
        month_idx: int = d.getMonth() as int;  # jac:ignore[W2001]
        day: int = d.getDate() as int;  # jac:ignore[W2001]
        return MONTH_ABBR[month_idx] + " " + str(day);
    } except Exception as e {
        return "";
    }
}

"""Quiet-90+ row caption: "last note <Mon D>" when there's a (stale) date, else "no notes yet"."""
def:pub quiet_row_label(person: any) -> str {
    label: str = format_last_contact((person["last_contact"] or "") as str);
    return ("last note " + label) if label else "no notes yet";
}

"""One tappable row of the People list -> the person sheet. (A small component:
lambda handlers inside a JSX `for` miscompile.) `quiet_label`, when set (the
Quiet 90+ filter), replaces the org/title line with "last note <Mon D>" /
"no notes yet" — SOH-226, display only."""
def:pub PeopleRow(person: any, onOpen: Callable[[str], None], quiet_label: str = "") -> JsxElement {
    pid: str = (person["_jac_id"] or "") as str;
    sub: str = join_with([s for s in [person["title"], person["org"]] if s], ", ");
    unconfirmed: bool = ((person["status"] or "") as str) == "proposed";

    def handle(e: MouseEvent) {
        if pid {
            onOpen(pid);
        }
    }

    return
        <li>
            <button
                type="button"
                onClick={handle}
                className="flex min-h-11 w-full items-center justify-between gap-2 pt-2.5 pb-2.5 pl-4 pr-3 text-left outline-none transition-colors hover:bg-secondary focus-visible:bg-secondary"
            >
                <span className="flex min-w-0 flex-col">
                    <span className="flex min-w-0 items-center gap-1.5">
                        <span className="truncate text-body-sm">{person["name"]}</span>
                        {unconfirmed and <Badge variant="outline" className="shrink-0">unconfirmed</Badge>}
                    </span>
                    {sub and <span className="truncate text-caption text-muted-foreground">{sub}</span>}
                    {quiet_label and <span className="truncate text-caption text-muted-foreground">{quiet_label}</span>}
                </span>
                <ChevronRightIcon className="size-4 shrink-0 text-muted-foreground" />
            </button>
        </li>;
}

def:pub EmptyNote(children: any = None) -> JsxElement {
    return
        <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
            {children}
        </p>;
}

def:pub HomeView(
    people: list[Person],
    status: str,
    goals: list[dict],
    rank_rows: list[dict],
    rank_cached: bool,
    rank_pending: bool,
    rank_error: str,
    goals_loaded: bool,
    goal_busy: bool,
    goal_error: str,
    onRefresh: Callable[[], None],
    onLogout: Callable[[], None],
    onCapture: Callable[[], None],
    onSwitchGoal: Callable[[str], None],
    onCreateGoal: Callable[[str], None],
    onCloseGoal: Callable[[str], None],
    onRerank: Callable[[], None],
    tab: str = "home",
    onTab: Callable[[str], None] | None = None,
    inbox_badge: int = 0,
    gaps: list[dict] = [],
    gaps_pending: bool = False,
    gaps_error: str = "",
    asked: dict = {},
    default_about: str = "",
    ask_busy: bool = False,
    ask_error: str = "",
    mine: list[dict] = [],
    claims: dict = {},
    incoming: list[dict] = [],
    friend: dict = {},
    mock_mode: bool = False,
    as_friend: bool = False,
    onAsk: Callable[[str, str, str], None] | None = None,
    friends_count: int = 0,
    onRetryGaps: Callable[[], None] | None = None,
    onOpenRequest: Callable[[str], None] | None = None,
    onOpenAsk: Callable[[str], None] | None = None,
    onToggleFriend: Callable[[], None] | None = None,
    open_person_id: str = "",
    onPersonOpened: Callable[[], None] | None = None,
    agent: dict = {},
    agent_available: bool = False,
    onRunAgent: Callable[[], None] | None = None,
    onResolveAction: Callable[[str, str, str], None] | None = None,
    onPostAskAction: Callable[[str, str, str], None] | None = None,
    onAnswerAsk: Callable[[str, str], None] | None = None,
    onAsksChecked: Callable[[], None] | None = None
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    has appearance_open: bool = False,
        sheet_person_id: str = "",
        sheet_open: bool = False,
        today_key: int = 0,
        forgotten_ids: list[str] = [],
        view_tab: str = "list",
        more_choice: str = "circles",
        show_import: bool = False,
        quiet_only: bool = False,
        expanded_goal: str = "";

    # Person sheet (SOH-207): opened from a ranked row, a person row, the graph
    # or a Today promise — on any tab.
    def open_person(pid: str) -> None {
        sheet_person_id = pid;
        sheet_open = True;
    }

    # Review screen (SOH-209) hands a person id up through the shell.
    useEffect(lambda {
        if open_person_id {
            open_person(open_person_id);
            if onPersonOpened {
                onPersonOpened();
            }
        }
    }, [open_person_id]);

    # Every tab starts at the top.
    useEffect(lambda {
        try {
            window.scrollTo(0, 0);  # jac:ignore[W2001]
        } except Exception as e {
            return;
        }
    }, [tab]);

    def close_person() -> None {
        sheet_open = False;
        today_key = today_key + 1;
    }

    def person_forgotten(pid: str) -> None {
        forgotten_ids = forgotten_ids + [pid];
        onRefresh();
    }

    def pick_tab(v: str) -> None {
        if onTab {
            onTab(v);
        }
    }

    def go_home(e: MouseEvent) {
        pick_tab("home");
    }

    def set_view_tab(v: str) -> None {
        view_tab = v;
    }

    # SOH-226: People sub-tabs 7 -> 4 (List · Graph · Today · More). "More" is
    # a small segmented row (Circles · Events · Notes); `more_choice` is
    # remembered in component state for the session, same idiom as `view_tab`.
    def set_more_choice(v: str) -> None {
        more_choice = v;
    }

    def open_import(e: MouseEvent) {
        show_import = True;
    }

    def toggle_quiet(e: MouseEvent) {
        quiet_only = not quiet_only;
    }

    # Home's "Promises due" -> See all (SOH-226): same list, in People > Today.
    def go_promises_today() -> None {
        view_tab = "today";
        pick_tab("people");
    }

    # so a just-imported/confirmed person shows up without a manual refresh.

    # Import (SOH-181, moved to a "+" on List for SOH-226): Done switches the
    # People sub-tab back to the list and refreshes it — same refresh path as
    # the header's "Refresh" menu item — so a just-imported/confirmed person
    # shows up without a manual refresh.
    def import_done() -> None {
        view_tab = "list";
        show_import = False;
        onRefresh();
    }

    def handle_refresh(e: any) {
        onRefresh();
    }

    def handle_logout(e: any) {
        onLogout();
    }

    def open_appearance(e: any) {
        appearance_open = True;
    }

    def set_appearance(v: bool) -> None {
        appearance_open = v;
    }

    def handle_rerank(e: MouseEvent) {
        onRerank();
    }

    def handle_toggle_friend(e: MouseEvent) {
        if onToggleFriend {
            onToggleFriend();
        }
    }

    def do_ask(need: str, about_line: str, audience: str) -> None {
        if onAsk {
            onAsk(need, about_line, audience);
        }
    }

    def do_retry_gaps() -> None {
        if onRetryGaps {
            onRetryGaps();
        }
    }

    def do_open_request(rid: str) -> None {
        if onOpenRequest {
            onOpenRequest(rid);
        }
    }

    def do_open_ask(rid: str) -> None {
        if onOpenAsk {
            onOpenAsk(rid);
        }
    }

    def do_run_agent() -> None {
        if onRunAgent {
            onRunAgent();
        }
    }

    def do_resolve(aid: str, decision: str, draft: str) -> None {
        if onResolveAction {
            onResolveAction(aid, decision, draft);
        }
    }

    def do_post_ask_action(aid: str, need: str, about_line: str) -> None {
        if onPostAskAction {
            onPostAskAction(aid, need, about_line);
        }
    }

    def do_answer_ask(aid: str, rid: str) -> None {
        if onAnswerAsk {
            onAnswerAsk(aid, rid);
        }
    }

    has_active: bool = len([g for g in goals if g["active"]]) > 0;
    partial: bool = is_partial(rank_rows);
    active_id: str = "";
    for g in goals {
        if g["active"] {
            active_id = g["_jac_id"] as str;
        }
    }
    shown_rows: list[dict] = [r for r in rank_rows if ((r["person"] or {})["_jac_id"] or "") not in forgotten_ids];
    expanded: bool = expanded_goal != "" and expanded_goal == active_id;
    more: int = len(shown_rows) - RANK_PREVIEW;
    preview_rows: list[dict] = shown_rows if expanded or more <= 0 else shown_rows[:RANK_PREVIEW];

    def toggle_all(e: MouseEvent) {
        expanded_goal = "" if expanded else active_id;
    }

    known: list[Person] = [p for p in people if ((p["_jac_id"] or "") as str) not in forgotten_ids];
    quiet_known: list[Person] = [p for p in known if is_quiet_person(p)];
    quiet_count: int = len(quiet_known);
    shown_known: list[Person] = quiet_known if quiet_only else known;
    quiet_chip_label: str = ("Quiet 90+ days (" + str(quiet_count) + ")") if quiet_count > 0 else "Quiet 90+ days";
    friend_ids: list[str] = [rid for rid in Object.keys(friend) if (friend[rid] or {})["request"]];  # jac:ignore[W2001]
    has_friend_asks: bool = len(incoming) > 0 or len(friend_ids) > 0;

    return
        <div className="flex flex-col gap-6 pb-[calc(6rem+env(safe-area-inset-bottom))]">
            <header className="-mt-2 flex h-14 items-center justify-between gap-2">
                <h1 className="text-subhead font-semibold">Cirql</h1>
                <DropdownMenu modal={False}>
                    <DropdownMenuTrigger
                        aria-label="More"
                        className={buttonVariants().call(None, {"variant": "ghost", "size": "icon", "className": "-mr-2 text-muted-foreground"})}
                    >
                        <MoreIcon className="size-5" />
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                        <DropdownMenuGroup>
                            <DropdownMenuItem onSelect={handle_refresh}>Refresh</DropdownMenuItem>
                            <DropdownMenuItem onSelect={open_appearance}>Settings</DropdownMenuItem>
                        </DropdownMenuGroup>
                        <DropdownMenuSeparator />
                        <DropdownMenuGroup>
                            <DropdownMenuItem onSelect={handle_logout}>Log out</DropdownMenuItem>
                        </DropdownMenuGroup>
                    </DropdownMenuContent>
                </DropdownMenu>
            </header>
            <AppearanceSheet open={appearance_open} onOpenChange={set_appearance} onDeleted={onLogout} />
            <PersonSheet person_id={sheet_person_id} open={sheet_open} on_close={close_person} on_forgotten={person_forgotten} />
            {if tab == "inbox" {
                <div key="tab-inbox" className="flex flex-col gap-6">
                    <AgentInbox
                        rows={(agent["rows"] or []) as list[dict]}
                        loaded={True if agent["loaded"] else False}
                        running={True if agent["running"] else False}
                        last_run={(agent["last_run"] or {}) as dict}
                        available={agent_available}
                        run_error={(agent["error"] or "") as str}
                        pending={(agent["pending"] or {}) as dict}
                        errors={(agent["errors"] or {}) as dict}
                        default_about={default_about}
                        ask_busy={ask_busy}
                        ask_error={ask_error}
                        onRun={do_run_agent}
                        onResolve={do_resolve}
                        onPostAsk={do_post_ask_action}
                        onAnswerAsk={do_answer_ask}
                        onOpenPerson={open_person}
                    />
                    {mock_mode and
                        <div className="flex items-center justify-between gap-2 rounded-lg border border-dashed border-border-strong pt-2 pb-2 pl-3 pr-2 text-caption text-muted-foreground">
                            <span>{"Dev mock · your own asks " + ("also show as a friend's" if as_friend else "stay yours only")}</span>
                            <Button size="xs" variant="outline" onClick={handle_toggle_friend}>
                                {"Stop acting as friend" if as_friend else "Act as friend"}
                            </Button>
                        </div>}
                    {if has_friend_asks {
                        <AsksSection incoming={incoming} friend={friend} onOpen={do_open_ask} title="Needs your OK" onChecked={onAsksChecked} />
                    } else {
                        <section aria-label="Needs your OK" className="flex flex-col gap-3">
                            <h2 className="text-eyebrow text-muted-foreground">Needs your OK</h2>
                            <EmptyNote>
                                Nothing waiting. When someone on Cirql asks your network for help, it lands here — only a count and a strength are shared until you approve.
                            </EmptyNote>
                        </section>
                    }}
                    {if len(mine) > 0 {
                        <RequestsSection mine={mine} claims={claims} onOpen={do_open_request} />
                    } else {
                        <section aria-label="Your asks" className="flex flex-col gap-3">
                            <h2 className="text-eyebrow text-muted-foreground">Your asks</h2>
                            <EmptyNote>
                                {"You haven't asked your network yet. Asks start from a gap on "}
                                <Button variant="link" size="inline" onClick={go_home}>Home</Button>
                                {"."}
                            </EmptyNote>
                        </section>
                    }}
                </div>
            } elif tab == "people" {
                <div key="tab-people" className="flex flex-col gap-6">
                <SearchBox on_open_person={open_person} />
                <Tabs value={view_tab} onValueChange={set_view_tab} className="gap-6">
                    <TabsList aria-label="People view" className="w-full justify-start gap-0 overflow-x-auto [scrollbar-width:none] [&>button]:pl-1 [&>button]:pr-1">
                        <TabsTrigger value="list">List</TabsTrigger>
                        <TabsTrigger value="graph">Graph</TabsTrigger>
                        <TabsTrigger value="today">Today</TabsTrigger>
                        <TabsTrigger value="more">More</TabsTrigger>
                    </TabsList>
                    <TabsContent value="list" className="flex flex-col gap-3">
                        {if show_import {
                            <ImportPeople on_open_person={open_person} onDone={import_done} onChanged={onRefresh} />
                        } else {
                            <section aria-label="People you know" className="flex flex-col gap-3">
                                <div className="flex items-center justify-between gap-2">
                                    <h2 className="text-eyebrow text-muted-foreground">People you know</h2>
                                    <div className="flex items-center gap-2">
                                        <span className="text-caption tabular-nums text-muted-foreground">{str(len(known))}</span>
                                        <Button size="icon-sm" variant="ghost" aria-label="Add people" onClick={open_import}>
                                            <PlusIcon />
                                        </Button>
                                    </div>
                                </div>
                                <Button
                                    variant={"default" if quiet_only else "outline"}
                                    size="xs"
                                    aria-pressed={quiet_only}
                                    className="self-start"
                                    onClick={toggle_quiet}
                                >
                                    {quiet_chip_label}
                                </Button>
                                {if len(known) == 0 {
                                    <EmptyNote>
                                        {"No one yet — "}
                                        <Button variant="link" size="inline" onClick={handle_capture}>capture a conversation</Button>
                                        {" to start."}
                                    </EmptyNote>
                                } elif quiet_only and len(shown_known) == 0 {
                                    <EmptyNote>Nobody's overdue — everyone you know has a note from the last 90 days.</EmptyNote>
                                } else {
                                    <ul className="flex flex-col divide-y divide-border overflow-hidden rounded-lg border bg-card shadow-edge">
                                        {for (idx, p) in enumerate(shown_known) {
                                            <PeopleRow
                                                key={((p["_jac_id"] or "") as str) or str(idx)}
                                                person={p}
                                                onOpen={open_person}
                                                quiet_label={quiet_row_label(p) if quiet_only else ""}
                                            />
                                        }}
                                    </ul>
                                }}
                            </section>
                        }}
                    </TabsContent>
                    <TabsContent value="graph">
                        <GraphView goal_id={active_id} on_open_person={open_person} />
                    </TabsContent>
                    <TabsContent value="today">
                        <Today on_open_person={open_person} refresh_key={today_key} />
                    </TabsContent>
                    <TabsContent value="more" className="flex flex-col gap-4">
                        <Tabs value={more_choice} onValueChange={set_more_choice} className="gap-4">
                            <TabsList aria-label="More people views" className="w-full justify-start gap-0 overflow-x-auto [scrollbar-width:none] [&>button]:pl-1 [&>button]:pr-1">
                                <TabsTrigger value="circles">Circles</TabsTrigger>
                                <TabsTrigger value="events">Events</TabsTrigger>
                                <TabsTrigger value="notes">Notes</TabsTrigger>
                            </TabsList>
                            <TabsContent value="circles">
                                <Circles on_open_person={open_person} />
                            </TabsContent>
                            <TabsContent value="events">
                                <Events on_open_person={open_person} />
                            </TabsContent>
                            <TabsContent value="notes">
                                <Timeline on_open_person={open_person} />
                            </TabsContent>
                        </Tabs>
                    </TabsContent>
                </Tabs>
                </div>
            } else {
                <div key="tab-home" className="flex flex-col gap-6">
                    <PromisesDue
                        onOpenPerson={open_person}
                        onSeeAll={go_promises_today}
                        onCapture={onCapture}
                        refresh_key={today_key}
                    />
                    {if not goals_loaded {
                        <div role="status" aria-label="Loading your goals" className="flex flex-col gap-2 rounded-lg border bg-card pt-3 pb-3 pl-4 pr-4 shadow-edge">
                            <Skeleton className="h-3 w-12" />
                            <Skeleton className="h-4 w-3/4" />
                        </div>
                    } else {
                        <GoalPicker
                            goals={goals}
                            busy={goal_busy}
                            error={goal_error}
                            onSwitch={onSwitchGoal}
                            onCreate={onCreateGoal}
                            onClose={onCloseGoal}
                        />
                    }}
                    {has_active and
                        <section aria-label="Who to reach out to" className="flex flex-col gap-3">
                            <div className="flex items-center justify-between gap-2">
                                <h2 className="text-eyebrow text-muted-foreground">Who to reach out to</h2>
                                <div className="flex items-center gap-2">
                                    {rank_pending and
                                        <span role="status" className="text-caption text-muted-foreground">Reading your notes…</span>}
                                    <Button
                                        size="xs"
                                        variant="outline"
                                        disabled={rank_pending}
                                        aria-label="Re-rank for this goal"
                                        onClick={handle_rerank}
                                    >
                                        Re-rank
                                    </Button>
                                </div>
                            </div>
                            {rank_error and <p role="alert" className="text-body-sm text-destructive">{rank_error}</p>}
                            {partial and not rank_pending and
                                <p role="status" className="rounded-lg border border-dashed border-border-strong pt-2 pb-2 pl-3 pr-3 text-caption text-muted-foreground">
                                    Ranking is partial right now — tap Re-rank in a minute.
                                </p>}
                            {if len(shown_rows) > 0 {
                                if expanded {
                                    <RankList rows={preview_rows} dim={rank_pending} on_open_person={open_person} />
                                } else {
                                    <ReachOutList rows={preview_rows} on_open_person={open_person} />
                                }
                                if more > 0 {
                                    <Button
                                        variant="ghost"
                                        className="w-full text-muted-foreground"
                                        aria-expanded={expanded}
                                        onClick={toggle_all}
                                    >
                                        {"Show top " + str(RANK_PREVIEW) if expanded else "See all (" + str(len(shown_rows)) + ")"}
                                        {if expanded {
                                            <ChevronDownIcon className="size-4 rotate-180" />
                                        } else {
                                            <ChevronDownIcon className="size-4" />
                                        }}
                                    </Button>
                                }
                            } elif rank_pending or not rank_cached {
                                <RankSkeleton />
                            } elif not rank_error {
                                <EmptyNote>
                                    {"No one yet — "}
                                    <Button variant="link" size="inline" onClick={handle_capture}>capture a conversation</Button>
                                    {" to start."}
                                </EmptyNote>
                            }}
                        </section>}
                    {has_active and not (rank_pending and len(rank_rows) == 0) and
                        <GapSingle
                            gaps={gaps}
                            pending={gaps_pending}
                            error={gaps_error}
                            asked={asked}
                            default_about={default_about}
                            busy={ask_busy}
                            ask_error={ask_error}
                            onAsk={do_ask}
                            onRetry={do_retry_gaps}
                            friends_count={friends_count}
                        />}
                </div>
            }}
            {status and <p className="text-caption text-muted-foreground">{status}</p>}
            <TabBar tab={tab} onTab={pick_tab} onCapture={onCapture} inbox_badge={inbox_badge} />
        </div>;
}
