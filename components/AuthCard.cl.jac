"""Log in / sign up card. Stateless; the shell owns credentials and auth calls. OWNER: Person B."""

import from ".ui.button" { Button }
import from ".ui.input" { Input }
import from ".ui.field" { Field, FieldLabel, FieldGroup }
import from ".ui.card" { Card, CardContent }

def:pub AuthCard(
    email: str,
    password: str,
    login_pending: bool,
    signup_pending: bool,
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

    busy: bool = login_pending or signup_pending;
    can_submit: bool = len(email) > 0 and len(password) > 0 and not busy;
    # "logged out" is the after-logout status, not an error — replaced below
    # by the trust line (SOH-227); a real signup/login failure still shows.
    show_status: str = "" if status == "logged out" else status;

    return
        <div className="flex flex-1 flex-col justify-start gap-8 pt-6 [@media(min-height:768px)]:justify-center">
            <div className="flex flex-col gap-3">
                <h1 className="text-display-md">Cirql</h1>
                <p className="text-body-lg text-muted-foreground">
                    Other CRMs search your contacts. Cirql's agents walk your network.
                </p>
            </div>
            <div className="flex flex-col gap-3">
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
                                    {"Working…" if login_pending else "Log in"}
                                </Button>
                                <Button type="button" size="lg" variant="secondary" className="w-full" disabled={not can_submit} onClick={handle_signup}>
                                    {"Creating…" if signup_pending else "Create account"}
                                </Button>
                            </div>
                            <p className="text-caption text-muted-foreground">
                                New here? Fill in both fields and tap Create account.
                            </p>
                        </form>
                    </CardContent>
                </Card>
                {show_status and <p role="alert" className="text-body-sm text-destructive">{show_status}</p>}
            </div>
            <div className="flex flex-col gap-2">
                <p className="text-body-sm text-muted-foreground">
                    Your notes stay yours: export or delete them any time, and only a card you write is ever shared.
                </p>
                <p className="text-caption text-muted-foreground">
                    <a href="/static/site/index.html" className="underline underline-offset-2 hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-sm">What is Cirql?</a>
                    {" · Each account's graph is isolated by construction."}
                </p>
            </div>
        </div>;
}
