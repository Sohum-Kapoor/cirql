"""Onboarding step 1 — tell Cirql about yourself; Continue calls OnboardMe. OWNER: Person B.

Stateless: the shell owns `about`, `pending`, `error` and the OnboardMe call.
`onLogin` (SOH-236) logs the current session out and returns to the login
screen — for someone who already has an account and landed here by mistake
(a stale/reset session, or a new-account slip).
"""

import from "..ui.button" { Button }
import from "..ui.textarea" { Textarea }
import from "..ui.input" { Input }
import from "..ui.field" { Field, FieldLabel, FieldDescription }

def:pub AboutStep(
    name: str,
    about: str,
    pending: bool,
    error: str,
    onNameChange: Callable[[str], None],
    onAboutChange: Callable[[str], None],
    onContinue: Callable[[], None],
    onLogin: Callable[[], None]
) -> JsxElement {
    def handle_name_change(e: ChangeEvent) {
        onNameChange(e.target.value);
    }

    def handle_change(e: ChangeEvent) {
        onAboutChange(e.target.value);
    }

    def handle_continue(e: MouseEvent) {
        onContinue();
    }

    def handle_login(e: MouseEvent) {
        onLogin();
    }

    can_continue: bool = len(name.strip()) > 0 and len(about.strip()) > 0 and not pending;

    return
        <div className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
                <h2 className="text-card-title">About you</h2>
                <p className="text-body-sm text-muted-foreground">
                    Cirql drafts your goals and a card from this. You can edit everything next.
                </p>
            </div>
            <Field>
                <FieldLabel htmlFor="name">Your name</FieldLabel>
                <Input
                    id="name"
                    autoFocus={True}
                    autoComplete="name"
                    required={True}
                    value={name}
                    onChange={handle_name_change}
                    disabled={pending}
                    placeholder="Jesse Chang"
                />
            </Field>
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
                    placeholder="I'm a senior studying mechanical engineering and building…"
                />
                <FieldDescription>Only you can see this.</FieldDescription>
            </Field>
            {error and <p role="alert" className="text-body-sm text-destructive">{error}</p>}
            <Button className="w-full" size="lg" disabled={not can_continue} onClick={handle_continue}>
                {"Reading…" if pending else "Continue"}
            </Button>
            <p className="text-center text-body-sm text-muted-foreground">
                Already have an account?{" "}
                <button
                    type="button"
                    className="font-medium text-foreground underline underline-offset-2"
                    onClick={handle_login}
                >
                    Log in
                </button>
            </p>
        </div>;
}
