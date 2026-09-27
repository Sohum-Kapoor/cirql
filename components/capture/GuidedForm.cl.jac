"""Guided capture — a short, structured debrief. OWNER: Person B (SOH-209).

Stateless: the shell owns the `guided` dict (components/capture/guided.cl.jac)
and gets every change through `onField(field, value)`.

Progressive disclosure, phone first: Who · How you met · When · What you talked
about · Next step are on screen; why they're interesting / how they reacted /
anything promised sit in "More detail"; "What Cirql will read" shows the composed
prose and lets you fix it (a mis-heard name, "UMESH" -> "UMich") before extraction.
"""

import from ..ui.button { Button, buttonVariants }
import from ..ui.input { Input }
import from ..ui.textarea { Textarea }
import from ..ui.collapsible { Collapsible, CollapsibleTrigger, CollapsibleContent }
import from ..ui.icons { ChevronRightIcon, PlusIcon, XIcon }
import from .Chips { ChipGroup }
import from .guided {
    MET_OPTIONS, WHEN_OPTIONS, NEXT_OPTIONS, DUE_OPTIONS, MAX_PEOPLE, empty_person, compose_guided
}
import from ...lib.utils { cn }

def:pub SectionLabel(text: str, hint: str = "", htmlFor: str = "") -> JsxElement {
    return
        <div className="flex items-baseline justify-between gap-2">
            <label htmlFor={htmlFor or None} className="text-eyebrow text-muted-foreground">{text}</label>
            {hint and <span className="text-caption text-muted-foreground">{hint}</span>}
        </div>;
}

"""A collapsible block with a row-style trigger (same look as home's People list)."""
def:pub Disclosure(title: str, hint: str, defaultOpen: bool, id: str, children: any = None) -> JsxElement {
    return
        <Collapsible defaultOpen={defaultOpen} className="overflow-hidden rounded-lg border bg-card shadow-edge">
            <CollapsibleTrigger
                id={id}
                className={cn(
                    buttonVariants().call(None, {"variant": "ghost", "size": "row"}),
                    "flex-row items-center justify-between rounded-none [&[data-state=open]>span>svg]:rotate-90"
                )}
            >
                <span className="flex items-center gap-1.5 text-body-sm font-medium">
                    <ChevronRightIcon className="size-4 text-muted-foreground transition-transform" />
                    {title}
                </span>
                {hint and <span className="text-caption text-muted-foreground">{hint}</span>}
            </CollapsibleTrigger>
            <CollapsibleContent>
                <div className="flex flex-col gap-4 border-t pt-4 pb-4 pl-4 pr-4">{children}</div>
            </CollapsibleContent>
        </Collapsible>;
}

"""Name + optional role/org for one person; a remove control from the second on."""
def:pub PersonFields(
    index: int,
    person: dict,
    canRemove: bool,
    disabled: bool,
    onChange: Callable[[int, str, str], None],
    onRemove: Callable[[int], None]
) -> JsxElement {
    n: str = str(index + 1);

    def handle_name(e: ChangeEvent) {
        onChange(index, "name", e.target.value);
    }

    def handle_role(e: ChangeEvent) {
        onChange(index, "role", e.target.value);
    }

    def handle_remove(e: MouseEvent) {
        onRemove(index);
    }

    return
        <div className="flex flex-col gap-2">
            <div className="flex items-center gap-2">
                <Input
                    id={"guided-name-" + n}
                    aria-label={"Person " + n + " name"}
                    placeholder={"Their name" if index == 0 else "Another person's name"}
                    autoComplete="off"
                    value={(person["name"] or "") as str}
                    disabled={disabled}
                    onChange={handle_name}
                />
                {canRemove and
                    <Button
                        size="icon"
                        variant="ghost"
                        disabled={disabled}
                        aria-label={"Remove person " + n}
                        className="text-muted-foreground"
                        onClick={handle_remove}
                    >
                        <XIcon />
                    </Button>}
            </div>
            <Input
                aria-label={"Person " + n + " role and org"}
                placeholder="Role, org: optional (e.g. Prof., UMich)"
                autoComplete="off"
                value={(person["role"] or "") as str}
                disabled={disabled}
                onChange={handle_role}
            />
        </div>;
}

def:pub GuidedForm(
    guided: dict,
    pending: bool,
    onField: Callable[[str, any], None]
) -> JsxElement {
    people: list[dict] = (guided["people"] or []) as list[dict];
    met: str = (guided["met"] or "") as str;
    composed: str = compose_guided(guided);
    edited: str = (guided["preview"] or "") as str;
    more_filled: bool = bool(guided["why"] or guided["reaction"] or guided["promise"]);

    def set_person(i: int, field: str, value: str) -> None {
        next_people: list[dict] = [];
        for (idx, p) in enumerate(people) {
            np: dict = {**p};
            if idx == i {
                np[field] = value;
            }
            next_people = next_people + [np];
        }
        onField("people", next_people);
    }

    def remove_person(i: int) -> None {
        next_people: list[dict] = [];
        for (idx, p) in enumerate(people) {
            if idx != i {
                next_people = next_people + [p];
            }
        }
        onField("people", next_people);
    }

    def add_person(e: MouseEvent) {
        onField("people", people + [empty_person()]);
    }

    def pick_met(v: str) -> None {
        onField("met", v);
    }

    def pick_when(v: str) -> None {
        onField("when", v or "today");
    }

    def pick_next(v: str) -> None {
        onField("next", v);
    }

    def pick_due(v: str) -> None {
        onField("promise_due", v);
    }

    def text_handler(field: str) -> any {
        return lambda(e: ChangeEvent) { onField(field, e.target.value); };
    }

    def handle_preview(e: ChangeEvent) {
        onField("preview", e.target.value);
    }

    def reset_preview(e: MouseEvent) {
        onField("preview", "");
    }

    detail_placeholder: str = (
        "Where: e.g. Ross café"
        if met == "coffee"
        else ("Which event: e.g. MHacks career fair" if met == "networking" or met == "conference" else "Where / which event: optional")
    );

    return
        <div className="flex flex-col gap-6">
            <section aria-label="Who" className="flex flex-col gap-2">
                <SectionLabel text="Who did you meet?" hint="required" htmlFor="guided-name-1" />
                {for (i, p) in enumerate(people) {
                    <PersonFields
                        key={"person-" + str(i)}
                        index={i}
                        person={p}
                        canRemove={i > 0}
                        disabled={pending}
                        onChange={set_person}
                        onRemove={remove_person}
                    />
                }}
                {len(people) < MAX_PEOPLE and
                    <Button variant="ghost" size="sm" className="-ml-2 w-fit text-muted-foreground" disabled={pending} onClick={add_person}>
                        <PlusIcon />
                        Add another person
                    </Button>}
            </section>
            <section aria-label="How you met" className="flex flex-col gap-2">
                <SectionLabel text="How did you meet?" hint="required" />
                <ChipGroup label="How you met" options={MET_OPTIONS} value={met} onChange={pick_met} disabled={pending} clearable={False} />
                {met and
                    <Input
                        id="guided-met-detail"
                        aria-label="Where or which event"
                        placeholder={detail_placeholder}
                        value={(guided["met_detail"] or "") as str}
                        disabled={pending}
                        onChange={text_handler("met_detail")}
                    />}
                {met == "intro" and
                    <Input
                        id="guided-intro-by"
                        aria-label="Introduced by"
                        placeholder="Introduced by: who?"
                        value={(guided["intro_by"] or "") as str}
                        disabled={pending}
                        onChange={text_handler("intro_by")}
                    />}
            </section>
            <section aria-label="When" className="flex flex-col gap-2">
                <SectionLabel text="When?" hint="optional" />
                <ChipGroup label="When" options={WHEN_OPTIONS} value={(guided["when"] or "today") as str} onChange={pick_when} disabled={pending} clearable={False} />
                {guided["when"] == "date" and
                    <Input
                        type="date"
                        aria-label="Date you met"
                        value={(guided["when_date"] or "") as str}
                        disabled={pending}
                        onChange={text_handler("when_date")}
                    />}
            </section>
            <section aria-label="What you talked about" className="flex flex-col gap-2">
                <SectionLabel text="What did you talk about?" hint="optional" htmlFor="guided-talked" />
                <Textarea
                    id="guided-talked"
                    rows={3}
                    placeholder="e.g. battery supply chains, her guest lecture at UMich"
                    value={(guided["talked"] or "") as str}
                    disabled={pending}
                    onChange={text_handler("talked")}
                />
            </section>
            <section aria-label="Next step" className="flex flex-col gap-2">
                <SectionLabel text="Next step" hint="optional" />
                <ChipGroup label="Next step" options={NEXT_OPTIONS} value={(guided["next"] or "") as str} onChange={pick_next} disabled={pending} />
            </section>
            <Disclosure id="guided-more" title="More detail" hint="optional" defaultOpen={more_filled}>
                <div className="flex flex-col gap-2">
                    <SectionLabel text="Why they're interesting to you" htmlFor="guided-why" />
                    <Textarea
                        id="guided-why"
                        rows={2}
                        placeholder="e.g. runs hardware deals at a seed fund"
                        value={(guided["why"] or "") as str}
                        disabled={pending}
                        onChange={text_handler("why")}
                    />
                </div>
                <div className="flex flex-col gap-2">
                    <SectionLabel text="How they reacted / what they're into" htmlFor="guided-reaction" />
                    <Textarea
                        id="guided-reaction"
                        rows={2}
                        placeholder="e.g. found my project interesting, wants to see the demo"
                        value={(guided["reaction"] or "") as str}
                        disabled={pending}
                        onChange={text_handler("reaction")}
                    />
                </div>
                <div className="flex flex-col gap-2">
                    <SectionLabel text="Anything you promised?" htmlFor="guided-promise" />
                    <Input
                        id="guided-promise"
                        placeholder="e.g. send my deck"
                        value={(guided["promise"] or "") as str}
                        disabled={pending}
                        onChange={text_handler("promise")}
                    />
                    {guided["promise"] and
                        <ChipGroup label="Promise due" options={DUE_OPTIONS} value={(guided["promise_due"] or "") as str} onChange={pick_due} disabled={pending} />}
                    {guided["promise"] and guided["promise_due"] == "date" and
                        <Input
                            type="date"
                            aria-label="Promise due date"
                            value={(guided["promise_date"] or "") as str}
                            disabled={pending}
                            onChange={text_handler("promise_date")}
                        />}
                </div>
            </Disclosure>
            <Disclosure id="guided-preview" title="What Cirql will read" hint={"edited" if edited else ""} defaultOpen={bool(edited)}>
                {if composed or edited {
                    <Textarea
                        id="guided-preview-text"
                        aria-label="Text Cirql will read"
                        rows={6}
                        value={edited or composed}
                        disabled={pending}
                        onChange={handle_preview}
                    />
                    <p className="text-caption text-muted-foreground">
                        Fix spellings here before Cirql reads it: a name, or “UMich” instead of what autocorrect guessed.
                    </p>
                    if edited {
                        <div className="flex items-center justify-between gap-2">
                            <span className="text-caption text-muted-foreground">Edited by you. Form changes won't update it.</span>
                            <Button size="xs" variant="outline" disabled={pending} onClick={reset_preview}>Reset to form</Button>
                        </div>
                    }
                } else {
                    <p className="text-body-sm text-muted-foreground">Add who you met to see the note Cirql will read.</p>
                }}
            </Disclosure>
        </div>;
}
