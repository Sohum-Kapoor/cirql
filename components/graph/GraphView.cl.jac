"""Force-directed view of your own graph (SOH-185): Me, the people you know, and
the chosen goal, from `GraphView(goal_id)`.

Visual rules: `knows` confirmed = solid line, proposed = dashed; `reported` =
thin and lighter; `relevant_to` runs person -> goal, coloured by strength
(strong / medium / weak = primary / success / ink-tertiary tokens). Me is the
largest node, a person's radius follows its relevance to the goal, the goal is
a ring. Drag to move, wheel / pinch to zoom. Tap a node to focus it: it and its
direct neighbours stay lit, everything else dims, and the edges touching it show
their labels; tap the focused person again (or "Details") -> `on_open_person`;
tap empty canvas to clear. `height` (any CSS length) overrides the default box.
d3 only lays out and draws inside the ref'd <svg>; every colour is a CSS token
from assets/main.css, so light and dark follow the theme with no redraw.
"""

import from react { useEffect }
import from "d3" {
    forceSimulation, forceLink, forceManyBody, forceCenter, forceCollide, forceX, forceY,
    select, zoom, drag
}
import from ..api { graph_view }
import from ..ui.skeleton { Skeleton }
import from ..ui.button { Button }
import from ...lib.text { join_with }

glob STRENGTH_COLOR: dict[str, str] = {
         "strong": "var(--primary)",
         "medium": "var(--success)",
         "weak": "var(--ink-tertiary)"
     },
     PERSON_RADIUS: dict[str, int] = {"strong": 15, "medium": 12, "weak": 10};

def strength_color(strength: str) -> str {
    if strength == "strong" or strength == "medium" or strength == "weak" {
        return STRENGTH_COLOR[strength];
    }
    return "var(--border-tertiary)";
}

"""Me 20, goal 16, a person 15/12/10 by relevance strength, 7 with none."""
def radius_for(kind: str, strength: str) -> int {
    if kind == "me" {
        return 20;
    }
    if kind == "goal" {
        return 16;
    }
    if strength == "strong" or strength == "medium" or strength == "weak" {
        return PERSON_RADIUS[strength];
    }
    return 7;
}

def edge_stroke(e: any) -> str {
    if e["kind"] == "relevant_to" {
        return strength_color(e["strength"] as str);
    }
    return "var(--ink-tertiary)";
}

def edge_width(e: any) -> float {
    if e["kind"] == "relevant_to" {
        return 2.25;
    }
    if e["kind"] == "reported" {
        return 0.75;
    }
    return 1.5;
}

def edge_dash(e: any) -> str {
    if e["kind"] == "knows" and e["strength"] == "proposed" {
        return "5 4";
    }
    return "none";
}

def edge_opacity(e: any) -> float {
    if e["kind"] == "reported" {
        return 0.45;
    }
    if e["kind"] == "relevant_to" {
        return 0.9;
    }
    return 0.7;
}

def edge_distance(e: any) -> int {
    if e["kind"] == "relevant_to" {
        return 110;
    }
    if e["kind"] == "reported" {
        return 70;
    }
    return 90;
}

def node_fill(n: any) -> str {
    if n["kind"] == "me" {
        return "var(--foreground)";
    }
    if n["kind"] == "goal" {
        return "var(--background)";
    }
    return strength_color(n["rel"] as str) if n["rel"] else "var(--muted-foreground)";
}

def node_stroke(n: any) -> str {
    if n["kind"] == "goal" {
        return "var(--primary)";
    }
    return "var(--background)";
}

def node_tip(n: any) -> str {
    bits: list[str] = [];
    for part in [n["title"], n["org"]] {
        if part {
            bits = bits + [part as str];
        }
    }
    sub: str = "";
    for (i, b) in enumerate(bits) {
        sub = sub + (", " if i > 0 else "") + b;
    }
    label: str = n["label"] as str;
    if n["status"] == "proposed" {
        label = label + " (proposed)";
    }
    return label + (" — " + sub if sub else "");
}

def short_label(n: any) -> str {
    label: str = (n["label"] or "") as str;
    limit: int = 28 if n["kind"] == "goal" else 18;
    return label[:limit - 1] + "…" if len(label) > limit else label;
}

"""What an edge says when its node is focused: how_met / "reported" / strength."""
def edge_label(e: any) -> str {
    text: str = "";
    if e["kind"] == "relevant_to" {
        text = ((e["strength"] or e["label"] or "relevant") as str) + " for the goal";
    } elif e["kind"] == "reported" {
        text = "reported";
    } else {
        text = (e["label"] or "knows") as str;
        if e["strength"] == "proposed" {
            text = text + " · proposed";
        }
    }
    return text[:31] + "…" if len(text) > 32 else text;
}

def end_id(end: any) -> str {
    return (end["id"] if end and end["id"] else end) as str;
}

"""Text form of every tie touching `nid`: "Maya Okafor — knows · proposed"."""
def tie_lines(nid: str, by_id: dict, edges: list[dict]) -> list[str] {
    out: list[str] = [];
    for e in edges {
        other: str = "";
        if e["from"] == nid {
            other = e["to"] as str;
        } elif e["to"] == nid {
            other = e["from"] as str;
        }
        if other {
            on: dict = (by_id[other] or {}) as dict;
            out = out + [((on["label"] or "someone") as str) + " — " + edge_label(e)];
        }
    }
    return out;
}

"""One row of the text alternative to the canvas: the person as a button, their ties under it."""
def:pub GraphTieRow(item: dict, ties: list[str], onOpen: Callable[[str], None] | None = None) -> JsxElement {
    label: str = (item["label"] or "") as str;
    def open_row(e: MouseEvent) {
        if onOpen and item["kind"] == "person" {
            onOpen(item["id"] as str);
        }
    }
    return
        <li className="flex flex-col gap-0.5">
            {if item["kind"] == "person" {
                <button type="button" onClick={open_row} aria-label={"Open " + label} className="self-start rounded-sm text-left text-body-sm font-medium underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">{label}</button>
            } else {
                <span className="text-body-sm font-medium">{label}</span>
            }}
            {len(ties) > 0 and <span className="text-caption text-muted-foreground">{join_with(ties, "; ")}</span>}
            {len(ties) == 0 and <span className="text-caption text-muted-foreground">no ties yet</span>}
        </li>;
}

def noop() -> None {
    return;
}

"""Lay out and draw `graph` into `svg_el`; returns the effect cleanup."""
def draw(svg_el: any, graph: dict, open_ref: any, on_select: any) -> any {
    if not svg_el or not graph or not graph["nodes"] {
        return noop;
    }
    width: float = (svg_el.clientWidth or 360) as float;
    height: float = (svg_el.clientHeight or 440) as float;
    # Spread out on a laptop / projector; phone-sized boxes keep the base layout.
    k: float = min(max(Math.sqrt(width * height) / 440.0, 1.0), 2.2);  # jac:ignore[W2001]
    rel: dict = {};
    for e in (graph["edges"] or []) as list[dict] {
        if e["kind"] == "relevant_to" {
            rel[e["from"]] = e["strength"];
        }
    }
    nodes: list[dict] = [];
    ids: dict = {};
    for n in graph["nodes"] as list[dict] {
        c: dict = {**n};
        c["rel"] = (rel[n["id"]] or "") if n["kind"] == "person" else "";
        c["r"] = radius_for(n["kind"] as str, c["rel"] as str);
        if n["kind"] == "me" {
            c["fx"] = width / 2;
            c["fy"] = height / 2;
        }
        ids[n["id"]] = True;
        nodes = nodes + [c];
    }
    links: list[dict] = [];
    adj: dict = {};
    for e in (graph["edges"] or []) as list[dict] {
        if ids[e["from"]] and ids[e["to"]] {
            if not adj[e["from"]] {
                adj[e["from"]] = {};
            }
            if not adj[e["to"]] {
                adj[e["to"]] = {};
            }
            adj[e["from"]][e["to"]] = True;
            adj[e["to"]][e["from"]] = True;
            links = links + [{"source": e["from"], "target": e["to"], "kind": e["kind"], "strength": e["strength"], "label": e["label"]}];
        }
    }

    svg: any = select(svg_el);
    svg.selectAll("*").remove();
    layer: any = svg.append("g");
    link_sel: any = layer.append("g").selectAll("line").data(links).join("line")
        .style("stroke", edge_stroke)
        .style("stroke-width", edge_width)
        .style("stroke-dasharray", edge_dash)
        .style("stroke-linecap", "round")
        .style("opacity", edge_opacity);
    link_sel.append("title").text(lambda(d: any) -> str { return (d["label"] or d["kind"]) as str; });
    node_sel: any = layer.append("g").selectAll("g").data(nodes).join("g")
        .style("cursor", lambda(d: any) -> str { return "pointer" if d["kind"] == "person" else "grab"; });
    node_sel.append("circle")
        .attr("r", lambda(d: any) -> int { return d["r"] as int; })
        .style("fill", node_fill)
        .style("stroke", node_stroke)
        .style("stroke-width", lambda(d: any) -> float { return 3.0 if d["kind"] == "goal" else 1.5; });
    node_sel.filter(lambda(d: any) -> bool { return d["kind"] == "goal"; }).append("circle")
        .attr("r", 5)
        .style("fill", "var(--primary)");
    node_sel.filter(lambda(d: any) -> bool { return d["kind"] == "person" and d["status"] == "proposed"; })
        .select("circle")
        .style("fill-opacity", 0.55);
    node_sel.append("text")
        .text(short_label)
        .attr("y", lambda(d: any) -> int { return (d["r"] as int) + 13; })
        .attr("text-anchor", "middle")
        .style("font-size", lambda(d: any) -> str { return "12px" if d["kind"] != "person" else "11px"; })
        .style("font-weight", lambda(d: any) -> str { return "600" if d["kind"] != "person" else "500"; })
        .style("fill", "var(--foreground)")
        .style("paint-order", "stroke")
        .style("stroke", "var(--background)")
        .style("stroke-width", "3px")
        .style("pointer-events", "none");
    node_sel.append("title").text(node_tip);
    elabel_sel: any = layer.append("g").selectAll("text").data(links).join("text")
        .text(edge_label)
        .attr("text-anchor", "middle")
        .attr("dy", "-3")
        .style("display", "none")
        .style("font-size", "10px")
        .style("font-weight", "500")
        .style("fill", "var(--muted-foreground)")
        .style("paint-order", "stroke")
        .style("stroke", "var(--card)")
        .style("stroke-width", "3px")
        .style("pointer-events", "none");

    focus: dict = {"id": "", "node": None};

    def touches(d: any, fid: str) -> bool {
        return end_id(d["source"]) == fid or end_id(d["target"]) == fid;
    }

    def apply_focus(fid: str) -> None {
        focus["id"] = fid;
        near: dict = (adj[fid] or {}) as dict if fid else {};
        node_sel.style("opacity", lambda(d: any) -> float {
            return 1.0 if not fid or d["id"] == fid or near[d["id"]] else 0.2;
        });
        link_sel.style("opacity", lambda(d: any) -> float {
            return edge_opacity(d) if not fid or touches(d, fid) else 0.08;
        });
        elabel_sel.style("display", lambda(d: any) -> str {
            return "block" if fid and touches(d, fid) else "none";
        });
    }

    """Releases the previously-focused node's pin (never `me` - it stays fixed
    for the life of the graph) so it re-joins the simulation once focus moves
    on or clears."""
    def unpin_focused() -> None {
        prev: any = focus["node"];
        if prev and prev["kind"] != "me" {
            prev["fx"] = None;
            prev["fy"] = None;
        }
        focus["node"] = None;
    }

    sim: any = forceSimulation(nodes)
        .force(
            "link",
            forceLink(links)
                .id(lambda(d: any) -> str { return d["id"] as str; })
                .distance(lambda(d: any) -> float { return edge_distance(d) * k; })
                .strength(0.35)
        )
        .force("charge", forceManyBody().strength(-260.0 * k))
        .force("center", forceCenter(width / 2, height / 2))
        .force("collide", forceCollide().radius(lambda(d: any) -> int { return (d["r"] as int) + 16; }))
        .force("x", forceX(width / 2).strength(0.03))
        .force("y", forceY(height / 2).strength(0.07));

    sim.on("tick", lambda {
        link_sel
            .attr("x1", lambda(d: any) -> float { return d["source"]["x"] as float; })
            .attr("y1", lambda(d: any) -> float { return d["source"]["y"] as float; })
            .attr("x2", lambda(d: any) -> float { return d["target"]["x"] as float; })
            .attr("y2", lambda(d: any) -> float { return d["target"]["y"] as float; });
        node_sel.attr("transform", lambda(d: any) -> str { return "translate(" + str(d["x"]) + "," + str(d["y"]) + ")"; });
        elabel_sel
            .attr("x", lambda(d: any) -> float { return ((d["source"]["x"] as float) + (d["target"]["x"] as float)) / 2; })
            .attr("y", lambda(d: any) -> float { return ((d["source"]["y"] as float) + (d["target"]["y"] as float)) / 2; });
    });

    drag_behavior: any = drag()
        .on("start", lambda(event: any, d: any) {
            if not event.active {
                sim.alphaTarget(0.3).restart();
            }
            d["fx"] = d["x"];
            d["fy"] = d["y"];
        })
        .on("drag", lambda(event: any, d: any) {
            d["fx"] = event.x;
            d["fy"] = event.y;
        })
        .on("end", lambda(event: any, d: any) {
            if not event.active {
                sim.alphaTarget(0);
            }
            if d["kind"] != "me" {
                d["fx"] = None;
                d["fy"] = None;
            }
        });
    node_sel.call(drag_behavior);
    node_sel.on("click", lambda(event: any, d: any) {
        event.stopPropagation();
        if focus["id"] == d["id"] {
            open_cb: any = open_ref.current;
            if d["kind"] == "person" and open_cb {
                open_cb.call(None, d["id"]);
            }
            return;
        }
        # Pin the tapped node where it sits and only lightly reheat, so the
        # layout stops drifting under it and a quick second tap (opening the
        # sheet) lands on the same spot.
        unpin_focused();
        d["fx"] = d["x"];
        d["fy"] = d["y"];
        focus["node"] = d;
        apply_focus(d["id"] as str);
        sim.alpha(0.1).restart();
        on_select.call(None, {"id": d["id"], "kind": d["kind"], "label": d["label"]});
    });
    svg.on("click", lambda(event: any) {
        if focus["id"] {
            unpin_focused();
            apply_focus("");
            on_select.call(None, {});
        }
    });

    zoom_behavior: any = zoom()
        .scaleExtent([0.3, 4])
        .on("zoom", lambda(event: any) { layer.attr("transform", event.transform); });
    svg.call(zoom_behavior).on("dblclick.zoom", None);

    return lambda {
        sim.stop();
        svg.on(".zoom", None);
        svg.on("click", None);
        svg.selectAll("*").remove();
    };
}

"""`corner`: floating in the graph's corner (md and up); else an inline row under it (phones)."""
def:pub GraphLegend(corner: bool = False) -> JsxElement {
    return
        <div
            className={(
                "pointer-events-none absolute bottom-2 left-2 hidden flex-col gap-1 rounded-md border bg-background/85 pt-2 pb-2 pl-2.5 pr-2.5 backdrop-blur md:flex"
                if corner
                else "flex flex-wrap gap-x-4 gap-y-1 md:hidden"
            ) + " text-caption text-muted-foreground"}
        >
            <span className="flex items-center gap-2">
                <svg aria-hidden="true" width="22" height="6"><line x1="1" y1="3" x2="21" y2="3" style={{"stroke": "var(--ink-tertiary)", "strokeWidth": 1.5}} /></svg>
                knows
            </span>
            <span className="flex items-center gap-2">
                <svg aria-hidden="true" width="22" height="6"><line x1="1" y1="3" x2="21" y2="3" style={{"stroke": "var(--ink-tertiary)", "strokeWidth": 1.5, "strokeDasharray": "5 4"}} /></svg>
                proposed
            </span>
            <span className="flex items-center gap-2">
                <svg aria-hidden="true" width="22" height="6"><line x1="1" y1="3" x2="21" y2="3" style={{"stroke": "var(--ink-tertiary)", "strokeWidth": 0.75, "opacity": 0.6}} /></svg>
                reported
            </span>
            <span className="flex items-center gap-2">
                <span className="flex w-[22px] items-center gap-0.5">
                    <span className="size-2 rounded-full bg-primary" />
                    <span className="size-2 rounded-full bg-success" />
                    <span className="size-2 rounded-full bg-ink-tertiary" />
                </span>
                strong · medium · weak for the goal
            </span>
        </div>;
}

def:pub GraphView(
    goal_id: str = "",
    on_open_person: Callable[[str], None] | None = None,
    height: str = ""
) -> JsxElement {
    has graph: dict = {},
        selected: dict = {},
        openRef: Ref[any] = Ref(None),
        loading: bool = True,
        error: str = "",
        svgRef: Ref[any] = Ref(),
        reqRef: Ref[str] = Ref("");

    async can with [goal_id] entry {
        await load_graph();
    }

    async def load_graph -> None {
        token: str = goal_id + ":" + str(Date.now());  # jac:ignore[W2001]
        reqRef.current = token;
        loading = True;
        error = "";
        out: dict = {};
        try {
            out = await graph_view(goal_id);
        } except Exception as e {
            if reqRef.current == token {
                error = "Couldn't load your people. " + str(e);
                loading = False;
            }
            return;
        }
        if reqRef.current == token {
            graph = out;
            loading = False;
        }
    }

    openRef.current = on_open_person;

    def set_selected(sel: dict) -> None {
        selected = sel;
    }

    def open_selected(e: MouseEvent) {
        pid: str = (selected["id"] or "") as str;
        if pid and on_open_person {
            on_open_person(pid);
        }
    }

    useEffect(lambda {
        selected = {};
        return draw(svgRef.current, graph, openRef, set_selected);
    }, [graph]);

    all_nodes: list[dict] = (graph["nodes"] or []) as list[dict];
    people: int = len([n for n in all_nodes if n["kind"] == "person"]);
    has_goal: bool = len([n for n in all_nodes if n["kind"] == "goal"]) > 0;
    all_edges: list[dict] = (graph["edges"] or []) as list[dict];
    by_id: dict = {};
    for n in all_nodes {
        by_id[n["id"] as str] = n;
    }
    listed: list[dict] = [n for n in all_nodes if n["kind"] != "goal"];

    breakout_cls: str = (
        "ml-[calc(50%_-_min(50vw_-_16px,600px))] w-[min(calc(100vw_-_32px),1200px)]"
        if height else
        "ml-[calc(50%_-_min(50vw_-_16px,600px))] w-[min(calc(100vw_-_32px),1200px)]"
        + " md:ml-[calc(50%_-_min(50vw_-_16px,424px))] md:w-[min(calc(100vw_-_32px),848px)]"
    );

    return
        <section aria-label="Your people" className="flex flex-col gap-2 pb-24">
            <div className="flex items-center justify-between gap-2">
                <h2 className="text-eyebrow text-muted-foreground">Your people</h2>
                <span className="text-caption tabular-nums text-muted-foreground">
                    {("Loading…" if loading else str(people) + (" person" if people == 1 else " people") + ("" if has_goal else " · no goal"))}
                </span>
            </div>
            {error and
                <div className="flex items-center gap-2">
                    <p role="alert" className="flex-1 text-body-sm text-destructive">{error}</p>
                    <Button size="sm" variant="outline" onClick={load_graph}>Retry</Button>
                </div>}
            <div
                className={"relative " + breakout_cls + " overflow-hidden rounded-lg border bg-card shadow-edge" + ("" if height else " h-[440px] md:h-[560px] lg:h-[70vh]")}
                style={{"height": height} if height else {}}
            >
                {if loading and not graph["nodes"] {
                    <div role="status" aria-label="Loading your people" className="flex h-full flex-col items-center justify-center gap-3">
                        <Skeleton className="size-10 rounded-full" />
                        <Skeleton className="h-3 w-40" />
                    </div>
                } elif not loading and people == 0 and not error {
                    <div className="flex h-full flex-col items-center justify-center gap-1 pl-6 pr-6 text-center">
                        <p className="text-body-sm">No people yet.</p>
                        <p className="text-caption text-muted-foreground">Capture a conversation and the people in it show up here.</p>
                    </div>
                } else {
                    <svg
                        ref={svgRef}
                        role="img"
                        aria-label={"Graph of you, " + str(people) + " people" + (" and your goal" if has_goal else "") + ". The same ties are listed as text below."}
                        className={"block h-full w-full touch-none select-none" + (" opacity-60" if loading else "")}
                    />
                    <GraphLegend corner={True} />
                    if selected["id"] {
                        <div className="absolute top-2 right-2 flex max-w-[calc(100%_-_16px)] items-center gap-2 rounded-md border bg-background/90 pt-1.5 pb-1.5 pl-3 pr-1.5 shadow-edge backdrop-blur">
                            <span className="truncate text-caption font-medium">{selected["label"] as str}</span>
                            {selected["kind"] == "person" and
                                <Button size="xs" variant="outline" onClick={open_selected}>Details</Button>}
                        </div>
                    }
                }}
            </div>
            {people > 0 and <GraphLegend />}
            {people > 0 and
                <details className="rounded-md border bg-card pt-1.5 pb-1.5 pl-3 pr-3 shadow-edge">
                    <summary className="cursor-pointer select-none rounded-sm text-caption font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                        {"Ties as a list · " + str(len(all_edges)) + (" tie" if len(all_edges) == 1 else " ties")}
                    </summary>
                    <ul aria-label="People and their ties" className="mt-2 flex flex-col gap-2">
                        {for n in listed {
                            <GraphTieRow key={n["id"] as str} item={n} ties={tie_lines(n["id"] as str, by_id, all_edges)} onOpen={on_open_person} />
                        }}
                    </ul>
                </details>}
            {people > 0 and <p className="text-caption text-muted-foreground">Drag to move · scroll or pinch to zoom · tap a node to focus it, tap it again to open · tap empty space to clear.</p>}
        </section>;
}
