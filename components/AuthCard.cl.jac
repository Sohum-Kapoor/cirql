"""Log in / sign up card. Stateless; the shell owns credentials and auth calls. OWNER: Person B."""

import from ".ui.button" { Button }
import from ".ui.input" { Input }
import from ".ui.field" { Field, FieldLabel, FieldGroup }

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
        <div className="flex flex-col gap-6">
            <div className="flex flex-col gap-1">
                <h1 className="text-xl font-semibold tracking-tight">Cirql</h1>
                <p className="text-sm text-muted-foreground">
                    Other CRMs search your contacts. Cirql's agents walk your network.
                </p>
            </div>
            <form onSubmit={handle_submit} className="flex flex-col gap-4 rounded-md border bg-card pt-4 pb-4 pl-4 pr-4">
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
                    <Button type="submit" className="w-full" disabled={not can_submit}>
                        {"Working…" if pending else "Log in"}
                    </Button>
                    <Button type="button" variant="outline" className="w-full" disabled={not can_submit} onClick={handle_signup}>
                        Create account
                    </Button>
                </div>
            </form>
            {status and <p className="text-sm text-muted-foreground">{status}</p>}
            <p className="text-xs text-muted-foreground">Each account's graph is isolated by construction.</p>
        </div>;
}
