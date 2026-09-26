"""Log in / sign up card. Stateless; the shell owns credentials and auth calls. OWNER: Person B."""

import from ".ui.button" { Button }
import from ".ui.input" { Input }
import from ".ui.field" { Field, FieldLabel, FieldGroup }
import from ".ui.card" { Card, CardContent }

def:pub AuthCard(
    email: str,
    password: str,
    pending: bool,
    status: str,
    onEmailChange: Callable[[str], None],
    onPasswordChange: Callable[[str], None],
    onLogin: Callable[[], None],
    onSignup: Callable[[], None]
) -> JsxElement {
    def handle_submit(e: FormEvent) {
        e.preventDefault();
        onLogin();
    }

    def handle_signup(e: MouseEvent) {
        onSignup();
    }

    can_submit: bool = len(email) > 0 and len(password) > 0 and not pending;

    return
        <div className="flex flex-col gap-8 pt-10">
            <div className="flex flex-col gap-3">
                <h1 className="text-display-md">Cirql</h1>
                <p className="text-body-lg text-muted-foreground">
                    Other CRMs search your contacts. Cirql's agents walk your network.
                </p>
            </div>
            <Card>
                <CardContent>
                    <form onSubmit={handle_submit} className="flex flex-col gap-5">
                        <FieldGroup>
                            <Field>
                                <FieldLabel htmlFor="email">Email</FieldLabel>
                                <Input
                                    id="email"
                                    type="email"
                                    autoComplete="email"
                                    value={email}
                                    placeholder="you@example.com"
                                    onChange={lambda e: ChangeEvent { onEmailChange(e.target.value); }}
                                />
                            </Field>
                            <Field>
                                <FieldLabel htmlFor="password">Password</FieldLabel>
                                <Input
                                    id="password"
                                    type="password"
                                    autoComplete="current-password"
                                    value={password}
                                    onChange={lambda e: ChangeEvent { onPasswordChange(e.target.value); }}
                                />
                            </Field>
                        </FieldGroup>
                        <div className="flex flex-col gap-2">
                            <Button type="submit" size="lg" className="w-full" disabled={not can_submit}>
                                {"Working…" if pending else "Log in"}
                            </Button>
                            <Button type="button" size="lg" variant="secondary" className="w-full" disabled={not can_submit} onClick={handle_signup}>
                                Create account
                            </Button>
                        </div>
                    </form>
                </CardContent>
            </Card>
            {status and <p role="status" className="text-body-sm text-muted-foreground">{status}</p>}
            <p className="text-caption text-muted-foreground">Each account's graph is isolated by construction.</p>
        </div>;
}
