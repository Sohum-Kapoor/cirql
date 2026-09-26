"""Onboarding step 2 — preview of the drafted Card, goals and interests. OWNER: Person B.

Edits are local only (PublishCard is Tier 1). List fields are edited one item per
line. The shell owns `card` and applies `onFieldChange(field, value)`.
"""

import from "..ui.button" { Button }
import from "..ui.input" { Input }
import from "..ui.textarea" { Textarea }
import from "..ui.badge" { Badge }
import from "..ui.field" { Field, FieldLabel, FieldGroup }
import from "...lib.utils" { cn }
import from "...lib.text" { join_lines, split_lines }

def:pub CardStep(
    card: dict,
    goals: list[dict],
    interests: list[dict],
    onFieldChange: Callable[[str, any], None],
    onContinue: Callable[[], None]
) -> JsxElement {
    def handle_continue(e: MouseEvent) {
        onContinue();
    }

    def text_field(field: str, label: str, placeholder: str) -> JsxElement {
        return
            <Field>
                <FieldLabel htmlFor={"card-" + field}>{label}</FieldLabel>
                <Input
                    id={"card-" + field}
                    value={card[field] or ""}
                    placeholder={placeholder}
                    onChange={lambda e: ChangeEvent { onFieldChange(field, e.target.value); }}
                />
            </Field>;
    }

    def list_field(field: str, label: str) -> JsxElement {
        items: list[str] = (card[field] or []) as list[str];
        return
            <Field>
                <FieldLabel htmlFor={"card-" + field}>{label}</FieldLabel>
                <Textarea
                    id={"card-" + field}
                    rows={3}
                    value={join_lines(items)}
                    placeholder="One per line"
                    onChange={lambda e: ChangeEvent { onFieldChange(field, split_lines(e.target.value)); }}
                />
            </Field>;
    }

    return
        <div className="flex flex-col gap-6">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">Your card</h2>
                <p className="text-body-sm text-muted-foreground">
                    Preview — you'll publish it later. A card is the only thing that can be granted read-only to someone else.
                </p>
            </div>

            <section className="flex flex-col gap-2">
                <h3 className="text-eyebrow text-muted-foreground">Goals</h3>
                <ul className="flex flex-col gap-2">
                    {for g in goals {
                        <li
                            key={g["_jac_id"]}
                            className={cn(
                                "flex items-start justify-between gap-2 rounded-lg border pt-2.5 pb-2.5 pl-4 pr-3 text-body-sm",
                                "border-border-strong bg-secondary text-foreground" if g["active"] else "bg-card text-muted-foreground"
                            )}
                        >
                            <span>{g["text"]}</span>
                            {g["active"] and <Badge>Active</Badge>}
                        </li>
                    }}
                </ul>
            </section>

            <section className="flex flex-col gap-2">
                <h3 className="text-eyebrow text-muted-foreground">Interests</h3>
                <div className="flex flex-wrap gap-2">
                    {for it in interests {
                        <Badge key={it["_jac_id"]} variant="secondary">{it["topic"]}</Badge>
                    }}
                </div>
            </section>

            <section className="flex flex-col gap-4 rounded-lg border bg-card pt-4 pb-4 pl-4 pr-4 shadow-edge">
                <FieldGroup>
                    {text_field("handle", "Handle", "your-handle")}
                    {text_field("headline", "Headline", "What you do, in one line")}
                    <Field>
                        <FieldLabel htmlFor="card-about">About</FieldLabel>
                        <Textarea
                            id="card-about"
                            rows={3}
                            value={card["about"] or ""}
                            onChange={lambda e: ChangeEvent { onFieldChange("about", e.target.value); }}
                        />
                    </Field>
                    {list_field("looking_for", "Looking for")}
                    {list_field("can_offer", "Can offer")}
                    {text_field("contact_pref", "Contact preference", "Email first")}
                </FieldGroup>
            </section>

            <Button className="w-full" size="lg" onClick={handle_continue}>Continue</Button>
        </div>;
}
