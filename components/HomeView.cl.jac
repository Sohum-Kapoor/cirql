"""Logged-in home: asks from friends (Exchange inbox), goal picker, who can
help with the active goal (GoalRank), gap alerts (GapFinder) with *Ask my
network*, your asks (ListMyRequests), then the people you know (collapsed).
Capture stays pinned at the bottom.
Stateless apart from the picker's own UI state. OWNER: Person B.

Switching goals only swaps the ranked list: the shell keeps GoalRank results per
goal_id for the session, and a goal that isn't cached yet shows a loading state
on the list alone — the header, picker and people list stay put.
"""

import from .ui.button { Button, buttonVariants }
import from .ui.skeleton { Skeleton }
import from .ui.collapsible { Collapsible, CollapsibleTrigger, CollapsibleContent }
import from .ui.dropdown_menu {
    DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuGroup, DropdownMenuItem,
    DropdownMenuSeparator
}
import from .ui.icons { MoreIcon, ChevronRightIcon }
import from .settings.AppearanceSheet { AppearanceSheet }
import from .ui.tabs { Tabs, TabsList, TabsTrigger, TabsContent }
import from .person.PersonSheet { PersonSheet }
import from .promises.Today { Today }
import from .graph.GraphView { GraphView }
import from .goals.GoalPicker { GoalPicker }
import from .goals.RankList { RankList, RankSkeleton, is_partial }
import from .exchange.GapAlert { GapAlerts }
import from .exchange.Requests { RequestsSection }
import from .exchange.Inbox { AsksSection }
import from ..lib.text { join_with }
import from ..lib.utils { cn }
sv import from ..schema { Person }

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
    onAsk: Callable[[str, str], None] | None = None,
    onRetryGaps: Callable[[], None] | None = None,
    onOpenRequest: Callable[[str], None] | None = None,
    onOpenAsk: Callable[[str], None] | None = None,
    onToggleFriend: Callable[[], None] | None = None
) -> JsxElement {
    def handle_capture(e: MouseEvent) {
        onCapture();
    }

    has appearance_open: bool = False,
        home_tab: str = "home",
        sheet_person_id: str = "",
        sheet_open: bool = False,
        today_key: int = 0,
        forgotten_ids: list[str] = [],
        view_tab: str = "list";

    # Person sheet (SOH-207): opened from a ranked row or a Today promise.
    def open_person(pid: str) -> None {
        sheet_person_id = pid;
        sheet_open = True;
    }

    def close_person() -> None {
        sheet_open = False;
        today_key = today_key + 1;
    }

    def person_forgotten(pid: str) -> None {
        forgotten_ids = forgotten_ids + [pid];
        onRefresh();
    }

    def set_home_tab(v: str) -> None {
        home_tab = v;
    }

    def set_view_tab(v: str) -> None {
        view_tab = v;
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

    def do_ask(need: str, about_line: str) -> None {
        if onAsk {
            onAsk(need, about_line);
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

    has_active: bool = len([g for g in goals if g["active"]]) > 0;
    partial: bool = is_partial(rank_rows);
    active_id: str = "";
    for g in goals {
        if g["active"] {
            active_id = g["_jac_id"] as str;
        }
    }
    shown_rows: list[dict] = [r for r in rank_rows if ((r["person"] or {})["_jac_id"] or "") not in forgotten_ids];

    return
        <div className="flex flex-col gap-6 pb-24">
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
                            <DropdownMenuItem onSelect={open_appearance}>Appearance</DropdownMenuItem>
                        </DropdownMenuGroup>
                        <DropdownMenuSeparator />
                        <DropdownMenuGroup>
                            <DropdownMenuItem onSelect={handle_logout}>Log out</DropdownMenuItem>
                        </DropdownMenuGroup>
                    </DropdownMenuContent>
                </DropdownMenu>
            </header>
            <AppearanceSheet open={appearance_open} onOpenChange={set_appearance} />
            {mock_mode and
                <div className="flex items-center justify-between gap-2 rounded-lg border border-dashed border-border-strong pt-2 pb-2 pl-3 pr-2 text-caption text-muted-foreground">
                    <span>{"Dev mock · your own asks " + ("also show as a friend's" if as_friend else "stay yours only")}</span>
                    <Button size="xs" variant="outline" onClick={handle_toggle_friend}>
                        {"Stop acting as friend" if as_friend else "Act as friend"}
                    </Button>
                </div>}
            <PersonSheet person_id={sheet_person_id} open={sheet_open} on_close={close_person} on_forgotten={person_forgotten} />
            <Tabs value={home_tab} onValueChange={set_home_tab} className="gap-6">
            <TabsList aria-label="View" className="w-full">
                <TabsTrigger value="home">Home</TabsTrigger>
                <TabsTrigger value="today">Today</TabsTrigger>
            </TabsList>
            <TabsContent value="today">
                <Today on_open_person={open_person} refresh_key={today_key} />
            </TabsContent>
            <TabsContent value="home" className="flex flex-col gap-6">
            <AsksSection incoming={incoming} friend={friend} onOpen={do_open_ask} />
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
            <Tabs value={view_tab} onValueChange={set_view_tab} className="gap-6">
                <TabsList aria-label="Home view" className="w-full">
                    <TabsTrigger value="list">List</TabsTrigger>
                    <TabsTrigger value="graph">Graph</TabsTrigger>
                </TabsList>
                <TabsContent value="list" className="flex flex-col gap-6">
                    {has_active and
                        <section aria-label="Who can help" className="flex flex-col gap-3">
                            <div className="flex items-center justify-between gap-2">
                                <h2 className="text-eyebrow text-muted-foreground">Who can help</h2>
                                <div className="flex items-center gap-2">
                                    {rank_pending and
                                        <span role="status" className="text-caption text-muted-foreground">Walking your graph…</span>}
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
                                <RankList rows={shown_rows} dim={rank_pending} on_open_person={open_person} />
                            } elif rank_pending or not rank_cached {
                                <RankSkeleton />
                            } elif not rank_error {
                                <p className="rounded-lg border border-dashed border-border-strong pt-4 pb-4 pl-4 pr-4 text-body-sm text-muted-foreground">
                                    {"No one yet — "}
                                    <Button variant="link" size="inline" onClick={handle_capture}>capture a conversation</Button>
                                    {" to start."}
                                </p>
                            }}
                        </section>}
                    {has_active and not (rank_pending and len(rank_rows) == 0) and
                        <GapAlerts
                            gaps={gaps}
                            pending={gaps_pending}
                            error={gaps_error}
                            asked={asked}
                            default_about={default_about}
                            busy={ask_busy}
                            ask_error={ask_error}
                            onAsk={do_ask}
                            onRetry={do_retry_gaps}
                        />}
                    <RequestsSection mine={mine} claims={claims} onOpen={do_open_request} />
                    <Collapsible className="overflow-hidden rounded-lg border bg-card shadow-edge">
                        <CollapsibleTrigger
                            className={cn(
                                buttonVariants().call(None, {"variant": "ghost", "size": "row"}),
                                "flex-row items-center justify-between rounded-none [&[data-state=open]>span>svg]:rotate-90"
                            )}
                        >
                            <span className="flex items-center gap-1.5 text-body-sm font-medium">
                                <ChevronRightIcon className="size-4 text-muted-foreground transition-transform" />
                                People you know
                            </span>
                            <span className="text-caption tabular-nums text-muted-foreground">{str(len(people))}</span>
                        </CollapsibleTrigger>
                        <CollapsibleContent>
                            {if len(people) == 0 {
                                <p className="border-t pt-3 pb-3 pl-4 pr-4 text-body-sm text-muted-foreground">
                                    {"No one yet — "}
                                    <Button variant="link" size="inline" onClick={handle_capture}>capture a conversation</Button>
                                    {" to start."}
                                </p>
                            } else {
                                <ul className="flex flex-col divide-y divide-border border-t">
                                    {for (idx, p) in enumerate(people) {
                                        <li key={str(idx)} className="flex flex-col pt-2.5 pb-2.5 pl-4 pr-4">
                                            <span className="text-body-sm">{p.name}</span>
                                            {(p.title or p.org) and
                                                <span className="text-caption text-muted-foreground">
                                                    {join_with([s for s in [p.title, p.org] if s], ", ")}
                                                </span>}
                                        </li>
                                    }}
                                </ul>
                            }}
                        </CollapsibleContent>
                    </Collapsible>
                </TabsContent>
                <TabsContent value="graph">
                    <GraphView goal_id={active_id} on_open_person={open_person} />
                </TabsContent>
            </Tabs>
            </TabsContent>
            </Tabs>
            {status and <p className="text-caption text-muted-foreground">{status}</p>}
            <div className="fixed inset-x-0 bottom-0 z-10 border-t bg-background/85 backdrop-blur">
                <div className="mx-auto w-full max-w-md pt-3 pl-4 pr-4 pb-[max(16px,env(safe-area-inset-bottom))]">
                    <Button className="w-full" size="lg" onClick={handle_capture}>Capture a conversation</Button>
                </div>
            </div>
        </div>;
}
