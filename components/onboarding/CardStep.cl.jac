"""Onboarding step 2 — preview of the drafted Card, goals and interests. OWNER: Person B.

Edits are local only (PublishCard is Tier 1). List fields are edited one item per
line. The shell owns `card` and applies `onFieldChange(field, value)`. Goals use
the shared GoalPicker (components/goals/GoalPicker.cl.jac — imported
here, never edited): with no active goal it's the "What are you working toward?"
prompt with an inline add; with one, tapping it opens a sheet to switch to
another extracted goal or add a new one — SetGoal underneath either way, so a
second goal OnboardMe extracted but didn't activate is never stranded.
"""

import from "..ui.button" { Button }
import from "..ui.input" { Input }
import from "..ui.textarea" { Textarea }
import from "..ui.badge" { Badge }
import from "..ui.field" { Field, FieldLabel, FieldGroup }
import from ..goals.GoalPicker { GoalPicker }
import from "...lib.text" { join_lines, split_lines }

def:pub CardStep(
    card: dict,
    goals: list[dict],
    interests: list[dict],
    goal_busy: bool,
    goal_error: str,
    onFieldChange: Callable[[str, any], None],
    onSwitchGoal: Callable[[str], None],
    onCreateGoal: Callable[[str], None],
    onCloseGoal: Callable[[str], None],
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

            <GoalPicker
                goals={goals}
                busy={goal_busy}
                error={goal_error}
                onSwitch={onSwitchGoal}
                onCreate={onCreateGoal}
                onClose={onCloseGoal}
            />

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
