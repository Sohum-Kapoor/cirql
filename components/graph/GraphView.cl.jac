"""Force-directed view of your own graph (SOH-185): Me, the people you know, and
the chosen goal, from `GraphView(goal_id)`.

Visual rules: `knows` confirmed = solid line, proposed = dashed; `reported` =
thin and lighter; `relevant_to` runs person -> goal, coloured by strength
(strong / medium / weak = primary / success / ink-tertiary tokens). Me is the
largest node, a person's radius follows its relevance to the goal, the goal is
a ring. Drag to move, wheel / pinch to zoom, tap a person -> `on_open_person`.
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

def noop() -> None {
    return;
}

"""Lay out and draw `graph` into `svg_el`; returns the effect cleanup."""
def draw(svg_el: any, graph: dict, open_cb: any) -> any {
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
    for e in (graph["edges"] or []) as list[dict] {
        if ids[e["from"]] and ids[e["to"]] {
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
        if d["kind"] == "person" and open_cb {
            open_cb.call(None, d["id"]);
        }
    });

    zoom_behavior: any = zoom()
        .scaleExtent([0.3, 4])
        .on("zoom", lambda(event: any) { layer.attr("transform", event.transform); });
    svg.call(zoom_behavior).on("dblclick.zoom", None);

    return lambda {
        sim.stop();
        svg.on(".zoom", None);
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

def:pub GraphView(goal_id: str = "", on_open_person: Callable[[str], None] | None = None) -> JsxElement {
    has graph: dict = {},
        loading: bool = True,
        error: str = "",
        svgRef: Ref[any] = Ref(),
        reqRef: Ref[str] = Ref("");

    async can with [goal_id] entry {
        token: str = goal_id + ":" + str(Date.now());  # jac:ignore[W2001]
        reqRef.current = token;
        loading = True;
        error = "";
        out: dict = {};
        try {
            out = await graph_view(goal_id);
        } except Exception as e {
            if reqRef.current == token {
                error = "Couldn't load your graph. " + str(e);
                loading = False;
            }
            return;
        }
        if reqRef.current == token {
            graph = out;
            loading = False;
        }
    }

    useEffect(lambda {
        return draw(svgRef.current, graph, on_open_person);
    }, [graph]);

    all_nodes: list[dict] = (graph["nodes"] or []) as list[dict];
    people: int = len([n for n in all_nodes if n["kind"] == "person"]);
    has_goal: bool = len([n for n in all_nodes if n["kind"] == "goal"]) > 0;

    return
        <section aria-label="Your graph" className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-2">
                <h2 className="text-eyebrow text-muted-foreground">Your graph</h2>
                <span className="text-caption tabular-nums text-muted-foreground">
                    {("Loading…" if loading else str(people) + (" person" if people == 1 else " people") + ("" if has_goal else " · no goal"))}
                </span>
            </div>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            <div className="relative ml-[calc(50%_-_min(50vw_-_16px,600px))] h-[440px] w-[min(calc(100vw_-_32px),1200px)] overflow-hidden rounded-lg border bg-card shadow-edge md:h-[560px] lg:h-[70vh]">
                {if loading and not graph["nodes"] {
                    <div role="status" aria-label="Loading your graph" className="flex h-full flex-col items-center justify-center gap-3">
                        <Skeleton className="size-10 rounded-full" />
                        <Skeleton className="h-3 w-40" />
                    </div>
                } elif not loading and people == 0 and not error {
                    <div className="flex h-full flex-col items-center justify-center gap-1 pl-6 pr-6 text-center">
                        <p className="text-body-sm">No people in your graph yet.</p>
                        <p className="text-caption text-muted-foreground">Capture a conversation and the people in it show up here.</p>
                    </div>
                } else {
                    <svg
                        ref={svgRef}
                        role="img"
                        aria-label={"Graph of you, " + str(people) + " people" + (" and your goal" if has_goal else "")}
                        className={"block h-full w-full touch-none select-none" + (" opacity-60" if loading else "")}
                    />
                    <GraphLegend corner={True} />
                }}
            </div>
            {people > 0 and <GraphLegend />}
            {people > 0 and <p className="text-caption text-muted-foreground">Drag to move · scroll or pinch to zoom · tap a person to open them.</p>}
        </section>;
}
