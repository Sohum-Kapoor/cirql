"""Merge — duplicate merge: propose, confirm, undo (SOH-195).

OWNER: Person A. See contracts/walkers.md for the exact report shapes and
AGENTS.md for the working rules this file must obey:
  - Never guesses: `ProposeMerges` only ever SUGGESTS a pair; nothing is
    merged until `MergePeople` is called explicitly with both ids.
  - Provenance survives a merge: every Fact/Intent/Promise/Note edge into or
    out of the removed person is re-pointed onto the kept person, never
    dropped (a `del` of the removed node without first moving these would
    cascade-delete them - AGENTS.md's node-delete-cascades rule -
    `jac guide jac-node-edge-patterns`). The Note itself is never touched.
  - Every merge is undoable: `MergePeople` records a `MergeRecord` (the
    removed person's own fields plus a description of every edge it moved)
    so `UndoMerge` can recreate the person and move the edges back.
  - All three walkers are `:priv` (own-root only). No `by llm` anywhere in
    this module - matching is pure deterministic name/org comparison.

Name-normalization idiom mirrored (not imported) from `capture.sv.jac`'s
`resolve_person`: strip/lowercase for exact-match, first-token comparison
for a bare first name against a full name. `capture.sv.jac` inlines this
logic directly inside `resolve_person` rather than exposing it as a
standalone function, so there is nothing importable there for this file's
different purpose (comparing two ALREADY-KNOWN people, never creating one);
re-implemented locally here so this module's only cross-file dependency is
`schema` (the same reasoning `forget.sv.jac` gives for mirroring
`reads.sv.jac`'s ownership idiom instead of importing it).

Ownership idiom (`_load`/`_owner_root`/`_readable`/`_my_node`) copied
verbatim from `forget.sv.jac` / `reads.sv.jac` for `UndoMerge`'s
`record_id` lookup and for re-resolving nodes named in a `MergeRecord.moved`
description. Edge re-pointing (`del` a typed edge by querying `[edge ...]`
first, then creating the same edge on the new endpoint) mirrors
`forget.sv.jac`'s `_prune_relevant_to_evidence` and `imports.sv.jac`'s
`SkipPerson`.

`MergeRecord.moved` entries are `"<Kind>:<primary_id>"` for edges that need
no extra data to reverse (`FactAbout`, `IntentAbout`, `PromiseTo`,
`Proposes`) - matching the contract's literal example - and
`"<Kind>:<primary_id>\\x1f<field>\\x1f<field>..."` (ASCII unit separator,
never appears in normal note/span text) for edges whose reversal needs more
than a jid: `Mentions` (span), `ReportedFrom`/`ReportedTo` (the other
person's jid, `source_note`, `span`), `RelevantTo` (goal jid, reason,
strength, opener, label, evidence joined by `,`), `FromCard` (card jid,
handle, received_at).
"""

import from jaclang { JacRuntime as Jac }
import from schema {
    Me, Person, Note, Fact, Intent, Promise, Goal, Introduction, Card,
    MergeRecord,
    Knows, Reported, Mentions, FactAbout, IntentAbout, PromiseTo,
    RelevantTo, Proposes, FromCard
}
import from datetime { datetime }
import from names { name_key, match_names }

# ---------------------------------------------------------------- ownership idiom
# Mirrored from forget.sv.jac / reads.sv.jac.

def _load(some_id: str) -> object {
    try {
        return jobj(some_id);
    } except Exception {
        return None;
    }
}

def _owner_root(n: object) -> str {
    return str(getattr(n, "__jac__").root).replace("-", "");
}

def _readable(n: object) -> bool {
    return bool(Jac.check_read_access(getattr(n, "__jac__")));  # jac:ignore[E1053]
}

def _my_node(some_id: str) -> object {
    n = _load(some_id);
    if n is None {
        return None;
    }
    if not _readable(n) {
        return None;
    }
    if _owner_root(n) != jid(root) {
        return None;
    }
    return n;
}

"""Same shape as `_my_node`, but for a node that may already have been
deleted (an id recorded in a `MergeRecord.moved` description, or a
`kept_id`) - unknown/foreign/unreadable all collapse to None, meaning
'skip this one, its node no longer exists' per the UndoMerge contract."""
def _still_there(some_id: str) -> object {
    if len(some_id.strip()) == 0 {
        return None;
    }
    return _my_node(some_id);
}

def _find_known(me: Me, person_id: str) -> Person | None {
    for p in [me ->:Knows:->] {
        if jid(p) == person_id {
            return p;
        }
    }
    return None;
}

def _find_known_edge(me: Me, p: Person) -> Knows | None {
    matched = [edge me ->:Knows:-> p];
    if matched {
        return matched[0];
    }
    return None;
}

# ---------------------------------------------------------------- ProposeMerges matching

def _norm(s: str) -> str {
    return " ".join(s.strip().lower().split());
}

def _tokens(s: str) -> list[str] {
    normed = _norm(s);
    if len(normed) == 0 {
        return [];
    }
    return normed.split(" ");
}

"""A single-letter token, with or without a trailing period: "M" or "M."."""
def _is_initial_token(tok: str) -> bool {
    stripped = tok.rstrip(".");
    return len(stripped) == 1;
}

"""Deterministic pairwise match, in priority order (first hit wins):
same_name (exact, normalized) > first_name_only_vs_full (a bare first name
vs a full name sharing that first token) > same_first_last_initial ("M.
Okafor" vs "Maya Okafor" - one side's first token is an initial, the other's
is a full word starting with the same letter, both share the same last
token) > same_org_similar_name (same non-empty org, one name a prefix of
the other). Returns None when no rule matches."""
def _match_pair(a: Person, b: Person) -> dict[str, str] | None {
    na = _norm(a.name);
    nb = _norm(b.name);
    if len(na) == 0 or len(nb) == 0 {
        return None;
    }

    if na == nb {
        return {"reason": "same_name", "confidence": "high"};
    }

    # SOH-212: the shared names.sv.jac rule (honorifics and parentheticals
    # stripped; "Helen" vs "Dr. Helen Marsh-Whitcombe", "Maya O." vs
    # "Maya Okafor"). Same wording as capture's resolve_person.
    verdict = match_names(a.name, b.name);
    if verdict == "same" {
        return {"reason": "same_name", "confidence": "high"};
    }
    if verdict == "ambiguous" {
        ka = name_key(a.name);
        kb = name_key(b.name);
        if len(ka["last"]) == 0 or len(kb["last"]) == 0 {
            return {"reason": "first_name_only_vs_full", "confidence": "medium"};
        }
        return {"reason": "same_first_last_initial", "confidence": "medium"};
    }

    ta = _tokens(a.name);
    tb = _tokens(b.name);

    if len(ta) == 1 and len(tb) > 1 and ta[0] == tb[0] {
        return {"reason": "first_name_only_vs_full", "confidence": "medium"};
    }
    if len(tb) == 1 and len(ta) > 1 and tb[0] == ta[0] {
        return {"reason": "first_name_only_vs_full", "confidence": "medium"};
    }

    if len(ta) >= 2 and len(tb) >= 2 and ta[-1] == tb[-1] {
        if _is_initial_token(ta[0]) and not _is_initial_token(tb[0]) and ta[0].rstrip(".")[:1] == tb[0][:1] {
            return {"reason": "same_first_last_initial", "confidence": "medium"};
        }
        if _is_initial_token(tb[0]) and not _is_initial_token(ta[0]) and tb[0].rstrip(".")[:1] == ta[0][:1] {
            return {"reason": "same_first_last_initial", "confidence": "medium"};
        }
    }

    oa = a.org.strip().lower();
    ob = b.org.strip().lower();
    if len(oa) > 0 and oa == ob {
        if na.startswith(nb) or nb.startswith(na) {
            return {"reason": "same_org_similar_name", "confidence": "medium"};
        }
    }

    return None;
}

def _reason_rank(reason: str) -> int {
    if reason == "same_name" {
        return 0;
    }
    if reason == "first_name_only_vs_full" {
        return 1;
    }
    if reason == "same_first_last_initial" {
        return 2;
    }
    return 3;
}

def _confidence_rank(confidence: str) -> int {
    if confidence == "high" {
        return 0;
    }
    return 1;
}

"""Sort key: best confidence first, then rule priority; sorted() is stable,
so ties keep the original (i-major, j-minor) discovery order."""
def _candidate_sort_key(c: dict[str, any]) -> tuple[int, int] {
    confidence = c["confidence"] as str;
    reason = c["reason"] as str;
    return (_confidence_rank(confidence), _reason_rank(reason));
}

"""Every candidate pair over `known`, i<j, matched deterministically.
Does not touch the graph."""
def _find_candidates(known: list[Person]) -> list[dict[str, any]] {
    candidates: list[dict[str, any]] = [];
    n = len(known);
    for i in range(n) {
        for j in range(i + 1, n) {
            m = _match_pair(known[i], known[j]);
            if m is not None {
                candidates.append({
                    "a": known[i], "b": known[j],
                    "reason": m["reason"], "confidence": m["confidence"]
                });
            }
        }
    }
    return candidates;
}

"""Greedily select from best-ranked candidates first, skipping any pair
touching an already-used person, capped at 20 pairs total."""
def _select_pairs(candidates: list[dict[str, any]]) -> list[dict[str, any]] {
    ranked = sorted(candidates, key=_candidate_sort_key);
    used: list[str] = [];
    selected: list[dict[str, any]] = [];
    for c in ranked {
        if len(selected) >= 20 {
            break;
        }
        a = c["a"] as Person;
        b = c["b"] as Person;
        if jid(a) in used or jid(b) in used {
            continue;
        }
        used.append(jid(a));
        used.append(jid(b));
        selected.append(c);
    }
    return selected;
}

# ---------------------------------------------------------------- walker: ProposeMerges

walker:priv ProposeMerges {
    """Over the caller's own `[me ->:Knows:->]` people, propose (never
    perform) up to 20 likely-duplicate pairs, each person in at most one
    pair. Reports `[{ a: Person, b: Person, reason: str, confidence: str }]`
    - see the module docstring / contracts/walkers.md for the exact
    matching rules."""
    has reports: list[dict[str, any]] = [];

    can run with Root entry {
        existing_me = [root --> [?:Me]];
        if not existing_me {
            disengage;
        }
        me = existing_me[0];
        known: list[Person] = [me ->:Knows:->];

        candidates = _find_candidates(known);
        selected = _select_pairs(candidates);

        for s in selected {
            report {
                "a": s["a"] as Person,
                "b": s["b"] as Person,
                "reason": s["reason"] as str,
                "confidence": s["confidence"] as str
            };
        }
    }
}

# ---------------------------------------------------------------- MergePeople edge re-pointing

"""Every Fact whose ONLY (or first) FactAbout target is `remove` gets a new
FactAbout edge to `keep` (skipped if keep already has one) and the old edge
to `remove` deleted. Appends one `"FactAbout:<jid>"` moved-description per
Fact, and returns the count."""
def _move_fact_about(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for f in [remove <-:FactAbout:<-] {
        existing = [edge f ->:FactAbout:-> keep];
        if not existing {
            f +>:FactAbout:+> keep;
        }
        for e in [edge f ->:FactAbout:-> remove] {
            del e;
        }
        moved.append(f"FactAbout:{jid(f)}");
        count += 1;
    }
    return count;
}

def _move_intent_about(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for it in [remove <-:IntentAbout:<-] {
        existing = [edge it ->:IntentAbout:-> keep];
        if not existing {
            it +>:IntentAbout:+> keep;
        }
        for e in [edge it ->:IntentAbout:-> remove] {
            del e;
        }
        moved.append(f"IntentAbout:{jid(it)}");
        count += 1;
    }
    return count;
}

def _move_promise_to(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for pr in [remove <-:PromiseTo:<-] {
        existing = [edge pr ->:PromiseTo:-> keep];
        if not existing {
            pr +>:PromiseTo:+> keep;
        }
        for e in [edge pr ->:PromiseTo:-> remove] {
            del e;
        }
        moved.append(f"PromiseTo:{jid(pr)}");
        count += 1;
    }
    return count;
}

def _move_mentions(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for note in [remove <-:Mentions:<-] {
        matched = [edge note ->:Mentions:-> remove];
        span = matched[0].span if matched else "";
        existing = [edge note ->:Mentions:-> keep];
        if not existing {
            note +>:Mentions(span=span):+> keep;
        }
        for e in matched {
            del e;
        }
        moved.append(f"Mentions:{jid(note)}\x1f{span}");
        count += 1;
    }
    return count;
}

"""Both directions of Reported touching `remove`, re-pointed onto `keep`.
A Reported tie directly between `keep` and `remove` (pre-merge) is dropped
rather than turned into a self-loop; it is still deleted and still logged
(so an undo can, in principle, restore it) but never recreated on `keep`."""
def _move_reported(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for other in [remove ->:Reported:->] {
        matched = [edge remove ->:Reported:-> other];
        e0 = matched[0] if matched else None;
        source_note = e0.source_note if e0 else "";
        span = e0.span if e0 else "";
        if jid(other) != jid(keep) {
            existing = [edge keep ->:Reported:-> other];
            if not existing {
                keep +>:Reported(source_note=source_note, span=span):+> other;
            }
        }
        for e in matched {
            del e;
        }
        moved.append(f"ReportedFrom:{jid(other)}\x1f{source_note}\x1f{span}");
        count += 1;
    }
    for other in [remove <-:Reported:<-] {
        matched = [edge other ->:Reported:-> remove];
        e0 = matched[0] if matched else None;
        source_note = e0.source_note if e0 else "";
        span = e0.span if e0 else "";
        if jid(other) != jid(keep) {
            existing = [edge other ->:Reported:-> keep];
            if not existing {
                other +>:Reported(source_note=source_note, span=span):+> keep;
            }
        }
        for e in matched {
            del e;
        }
        moved.append(f"ReportedTo:{jid(other)}\x1f{source_note}\x1f{span}");
        count += 1;
    }
    return count;
}

def _move_relevant_to(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for g in [remove ->:RelevantTo:->] {
        matched = [edge remove ->:RelevantTo:-> g];
        e0 = matched[0] if matched else None;
        reason = e0.reason if e0 else "";
        strength = e0.strength if e0 else "weak";
        evidence = e0.evidence if e0 else [];
        opener = e0.opener if e0 else "";
        label = e0.label if e0 else "cold";
        existing = [edge keep ->:RelevantTo:-> g];
        if not existing {
            keep +>:RelevantTo(reason=reason, strength=strength, evidence=evidence, opener=opener, label=label):+> g;
        }
        for e in matched {
            del e;
        }
        evidence_csv = ",".join(evidence);
        moved.append(f"RelevantTo:{jid(g)}\x1f{reason}\x1f{strength}\x1f{opener}\x1f{label}\x1f{evidence_csv}");
        count += 1;
    }
    return count;
}

def _move_proposes(remove: Person, keep: Person, moved: list[str]) -> int {
    count = 0;
    for intro in [remove <-:Proposes:<-] {
        existing = [edge intro ->:Proposes:-> keep];
        if not existing {
            intro +>:Proposes:+> keep;
        }
        for e in [edge intro ->:Proposes:-> remove] {
            del e;
        }
        moved.append(f"Proposes:{jid(intro)}");
        count += 1;
    }
    return count;
}

def _move_from_card(remove: Person, keep: Person, moved: list[str]) {
    for c in [remove ->:FromCard:->] {
        matched = [edge remove ->:FromCard:-> c];
        e0 = matched[0] if matched else None;
        handle = e0.handle if e0 else "";
        received_at = e0.received_at if e0 else "";
        existing = [edge keep ->:FromCard:-> c];
        if not existing {
            keep +>:FromCard(handle=handle, received_at=received_at):+> c;
        }
        for e in matched {
            del e;
        }
        moved.append(f"FromCard:{jid(c)}\x1f{handle}\x1f{received_at}");
    }
}

# ---------------------------------------------------------------- walker: MergePeople

walker:priv MergePeople {
    """Merge `remove_id` into `keep_id` (both must be one of the caller's
    own `[me ->:Knows:->]` people). Re-points every Fact/Intent/Promise/
    Mentions/Reported/RelevantTo/Proposes/FromCard edge touching `remove`
    onto `keep` (skipping an identical edge that already exists on `keep`);
    fills `keep.org`/`title` from `remove` when empty; confirms `keep`'s
    Knows edge when `remove` was confirmed and `keep` was only proposed;
    records a `MergeRecord` under root; deletes `remove`'s Knows edge and
    the `remove` node. Reports one
    `{ kept: Person, record_id: str, moved: {...} }`, or
    `[{error: "same_person"}]` when the two ids are identical, or
    `[{error: "not_found"}]` when either id is not one of the caller's own
    known people."""
    has keep_id: str;
    has remove_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        if self.keep_id == self.remove_id {
            report {"error": "same_person"};
            disengage;
        }

        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"error": "not_found"};
            disengage;
        }
        me = existing_me[0];

        keep_opt: Person | None = _find_known(me, self.keep_id);
        remove_opt: Person | None = _find_known(me, self.remove_id);
        if keep_opt is None or remove_opt is None {
            report {"error": "not_found"};
            disengage;
        }
        keep = keep_opt as Person;
        remove = remove_opt as Person;

        keep_edge_opt: Knows | None = _find_known_edge(me, keep);
        if keep_edge_opt is None {
            report {"error": "not_found"};
            disengage;
        }
        keep_edge = keep_edge_opt as Knows;

        moved: list[str] = [];
        facts_count = _move_fact_about(remove, keep, moved);
        intents_count = _move_intent_about(remove, keep, moved);
        promises_count = _move_promise_to(remove, keep, moved);
        mentions_count = _move_mentions(remove, keep, moved);
        reported_count = _move_reported(remove, keep, moved);
        relevant_count = _move_relevant_to(remove, keep, moved);
        introductions_count = _move_proposes(remove, keep, moved);
        _move_from_card(remove, keep, moved);

        if len(keep.org.strip()) == 0 and len(remove.org.strip()) > 0 {
            keep.org = remove.org;
        }
        if len(keep.title.strip()) == 0 and len(remove.title.strip()) > 0 {
            keep.title = remove.title;
        }

        if remove.status == "confirmed" and keep_edge.status == "proposed" {
            keep_edge.status = "confirmed";
            keep.status = "confirmed";
        }

        record = (root ++> MergeRecord(
            kept_id=jid(keep),
            removed_name=remove.name,
            removed_org=remove.org,
            removed_title=remove.title,
            removed_status=remove.status,
            moved=moved,
            created_at=datetime.now().isoformat(),
            undone=False
        ))[0];

        for e in [edge me ->:Knows:-> remove] {
            del e;
        }
        del remove;

        report {
            "kept": keep,
            "record_id": jid(record),
            "moved": {
                "facts": facts_count,
                "intents": intents_count,
                "promises": promises_count,
                "mentions": mentions_count,
                "reported": reported_count,
                "relevant_to": relevant_count,
                "introductions": introductions_count
            }
        };
    }
}

# ---------------------------------------------------------------- UndoMerge edge re-pointing

"""Parse one `MergeRecord.moved` entry and move the edge it describes back
onto `restored`, off `keep` (when `keep` still exists and still holds it).
Any node the description names other than `keep`/`restored` that no longer
resolves to one of the caller's own nodes is treated as "no longer exists"
and the whole entry is skipped, per the UndoMerge contract."""
def _undo_one(desc: str, keep: Person | None, restored: Person) {
    parts = desc.split(":", 1);
    if len(parts) != 2 {
        return;
    }
    kind = parts[0];
    rest = parts[1];

    if kind == "FactAbout" {
        f = _still_there(rest);
        if f is None or not isinstance(f, Fact) {
            return;
        }
        fact = f as Fact;
        if keep is not None {
            for e in [edge fact ->:FactAbout:-> keep] {
                del e;
            }
        }
        existing_fact = [edge fact ->:FactAbout:-> restored];
        if not existing_fact {
            fact +>:FactAbout:+> restored;
        }
        return;
    }

    if kind == "IntentAbout" {
        it_obj = _still_there(rest);
        if it_obj is None or not isinstance(it_obj, Intent) {
            return;
        }
        it = it_obj as Intent;
        if keep is not None {
            for e in [edge it ->:IntentAbout:-> keep] {
                del e;
            }
        }
        existing_intent = [edge it ->:IntentAbout:-> restored];
        if not existing_intent {
            it +>:IntentAbout:+> restored;
        }
        return;
    }

    if kind == "PromiseTo" {
        pr_obj = _still_there(rest);
        if pr_obj is None or not isinstance(pr_obj, Promise) {
            return;
        }
        pr = pr_obj as Promise;
        if keep is not None {
            for e in [edge pr ->:PromiseTo:-> keep] {
                del e;
            }
        }
        existing_promise = [edge pr ->:PromiseTo:-> restored];
        if not existing_promise {
            pr +>:PromiseTo:+> restored;
        }
        return;
    }

    if kind == "Proposes" {
        intro_obj = _still_there(rest);
        if intro_obj is None or not isinstance(intro_obj, Introduction) {
            return;
        }
        intro = intro_obj as Introduction;
        if keep is not None {
            for e in [edge intro ->:Proposes:-> keep] {
                del e;
            }
        }
        existing_intro = [edge intro ->:Proposes:-> restored];
        if not existing_intro {
            intro +>:Proposes:+> restored;
        }
        return;
    }

    if kind == "Mentions" {
        fields = rest.split("\x1f");
        note_obj = _still_there(fields[0]);
        if note_obj is None or not isinstance(note_obj, Note) {
            return;
        }
        note = note_obj as Note;
        span = fields[1] if len(fields) > 1 else "";
        if keep is not None {
            for e in [edge note ->:Mentions:-> keep] {
                del e;
            }
        }
        existing_mentions = [edge note ->:Mentions:-> restored];
        if not existing_mentions {
            note +>:Mentions(span=span):+> restored;
        }
        return;
    }

    if kind == "ReportedFrom" {
        fields = rest.split("\x1f");
        other_obj = _still_there(fields[0]);
        if other_obj is None or not isinstance(other_obj, Person) {
            return;
        }
        other = other_obj as Person;
        source_note = fields[1] if len(fields) > 1 else "";
        span = fields[2] if len(fields) > 2 else "";
        if keep is not None {
            for e in [edge keep ->:Reported:-> other] {
                del e;
            }
        }
        existing_reported_from = [edge restored ->:Reported:-> other];
        if not existing_reported_from {
            restored +>:Reported(source_note=source_note, span=span):+> other;
        }
        return;
    }

    if kind == "ReportedTo" {
        fields = rest.split("\x1f");
        other_obj = _still_there(fields[0]);
        if other_obj is None or not isinstance(other_obj, Person) {
            return;
        }
        other = other_obj as Person;
        source_note = fields[1] if len(fields) > 1 else "";
        span = fields[2] if len(fields) > 2 else "";
        if keep is not None {
            for e in [edge other ->:Reported:-> keep] {
                del e;
            }
        }
        existing_reported_to = [edge other ->:Reported:-> restored];
        if not existing_reported_to {
            other +>:Reported(source_note=source_note, span=span):+> restored;
        }
        return;
    }

    if kind == "RelevantTo" {
        fields = rest.split("\x1f");
        goal_obj = _still_there(fields[0]);
        if goal_obj is None or not isinstance(goal_obj, Goal) {
            return;
        }
        goal = goal_obj as Goal;
        reason = fields[1] if len(fields) > 1 else "";
        strength = fields[2] if len(fields) > 2 else "weak";
        opener = fields[3] if len(fields) > 3 else "";
        label = fields[4] if len(fields) > 4 else "cold";
        evidence_csv = fields[5] if len(fields) > 5 else "";
        evidence = [x for x in evidence_csv.split(",") if len(x) > 0];
        if keep is not None {
            for e in [edge keep ->:RelevantTo:-> goal] {
                del e;
            }
        }
        existing_relevant = [edge restored ->:RelevantTo:-> goal];
        if not existing_relevant {
            restored +>:RelevantTo(reason=reason, strength=strength, evidence=evidence, opener=opener, label=label):+> goal;
        }
        return;
    }

    if kind == "FromCard" {
        fields = rest.split("\x1f");
        card_obj = _still_there(fields[0]);
        if card_obj is None or not isinstance(card_obj, Card) {
            return;
        }
        card = card_obj as Card;
        handle = fields[1] if len(fields) > 1 else "";
        received_at = fields[2] if len(fields) > 2 else "";
        if keep is not None {
            for e in [edge keep ->:FromCard:-> card] {
                del e;
            }
        }
        existing_from_card = [edge restored ->:FromCard:-> card];
        if not existing_from_card {
            restored +>:FromCard(handle=handle, received_at=received_at):+> card;
        }
        return;
    }
}

# ---------------------------------------------------------------- walker: UndoMerge

walker:priv UndoMerge {
    """Undo a `MergePeople` call: recreate the removed Person (with the
    fields the `MergeRecord` captured) and a fresh `Knows` edge
    (`how_met="restored after merge"`, `status` = the recorded
    `removed_status`), move every edge listed in `moved` back onto the
    restored person (parsing each description; an entry whose non-`keep`
    node no longer exists is skipped), and mark the record `undone`.
    Reports `[{ restored: Person, record_id: str }]`, or
    `[{error: "not_found"}]` for an unknown/foreign id, or
    `[{error: "already_undone"}]` when the record was already undone."""
    has record_id: str;
    has reports: list[object] = [];

    can run with Root entry {
        n = _my_node(self.record_id);
        if n is None or not isinstance(n, MergeRecord) {
            report {"error": "not_found"};
            disengage;
        }
        record = n as MergeRecord;

        if record.undone {
            report {"error": "already_undone"};
            disengage;
        }

        existing_me = [root --> [?:Me]];
        if not existing_me {
            report {"error": "not_found"};
            disengage;
        }
        me = existing_me[0];

        keep_obj = _still_there(record.kept_id);
        keep: Person | None = None;
        if isinstance(keep_obj, Person) {
            keep = keep_obj as Person;
        }

        restored = (me +>:Knows(
            how_met="restored after merge",
            status=record.removed_status,
            source_note=""
        ):+> Person(
            name=record.removed_name,
            org=record.removed_org,
            title=record.removed_title,
            status=record.removed_status
        ))[0];

        for desc in record.moved {
            _undo_one(desc, keep, restored);
        }

        record.undone = True;

        report {"restored": restored, "record_id": jid(record)};
    }
}
