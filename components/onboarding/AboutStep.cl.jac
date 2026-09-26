"""Onboarding step 1 — tell Cirql about yourself; Continue calls OnboardMe. OWNER: Person B.

Stateless: the shell owns `about`, `pending`, `error` and the OnboardMe call.
"""

import from "..ui.button" { Button }
import from "..ui.textarea" { Textarea }
import from "..ui.field" { Field, FieldLabel, FieldDescription }

def:pub AboutStep(
    about: str,
    pending: bool,
    error: str,
    onAboutChange: Callable[[str], None],
    onContinue: Callable[[], None]
) -> JsxElement {
    def handle_change(e: ChangeEvent) {
        onAboutChange(e.target.value);
    }

    def handle_continue(e: MouseEvent) {
        onContinue();
    }

    can_continue: bool = len(about.strip()) > 0 and not pending;

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-lg font-semibold tracking-tight">About you</h2>
                <p className="text-sm text-muted-foreground">
                    Cirql drafts your goals and a card from this. You can edit everything next.
                </p>
            </div>
            <Field>
                <FieldLabel htmlFor="about">
                    Tell Cirql about yourself: what you do, what you're working toward, what you could help with
                </FieldLabel>
                <Textarea
                    id="about"
                    rows={7}
                    value={about}
                    onChange={handle_change}
                    disabled={pending}
                    placeholder="I'm a senior studying mechanical engineering and building..."
                />
                <FieldDescription>Stays on your account's graph — isolated by construction.</FieldDescription>
            </Field>
            {error and <p className="text-sm text-destructive/80">{error}</p>}
            <Button className="w-full" disabled={not can_continue} onClick={handle_continue}>
                {"Reading…" if pending else "Continue"}
            </Button>
        </div>;
}
