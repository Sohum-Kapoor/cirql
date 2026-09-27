"""Log in / sign up card. Stateless for email/password; the shell owns those
credentials and auth calls. SSO (SOH-237) is self-contained here: on mount this
probes `/sso/<platform>/login` with a manual-redirect fetch so an unconfigured
provider never shows a broken button (both buttons stay hidden while probing,
to avoid a flash), then `jacSsoLogin` on click. A successful SSO login reuses
the exact same success path as email login: frontend.cl.jac's mount ability
(`can with entry { if not public_handle and jacIsLoggedIn() { enter(); } }`)
already re-enters once a valid token is stored, so a full reload after
`jacSsoLogin` resolves true lands on the same `enter()` email login calls -
no new prop from the parent needed. OWNER: Person B."""

import from ".ui.button" { Button }
import from ".ui.input" { Input }
import from ".ui.field" { Field, FieldLabel, FieldGroup }
import from ".ui.card" { Card, CardContent }
import from ".ui.icons" { GoogleIcon, AppleIcon }
import from "@jac/runtime" { jacSsoLogin }
import from ..lib.toast { toast }

"""GET `/sso/<platform>/login` with a manual redirect so the browser never
actually follows it. A configured provider replies with a redirect (fetch's
`opaqueredirect` for a cross-origin Location, or a same-origin 3xx); an
unconfigured one 4xx/5xxs (jac-scale has no provider block to redirect to)."""
async def _sso_configured(platform: str) -> bool {
    ok: bool = False;
    try {
        resp: any = await fetch(
            "/sso/" + platform + "/login", {"method": "GET", "redirect": "manual"}
        );
        if resp.type == "opaqueredirect" {
            ok = True;
        } elif (resp.status as int) >= 300 and (resp.status as int) < 400 {
            ok = True;
        } else {
            ok = False;
        }
    } except Exception as e {
        ok = False;
    }
    return ok;
}

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
    has sso_probing: bool = True;
    has sso_google_ok: bool = False;
    has sso_apple_ok: bool = False;
    has sso_busy: str = "";
    has pw_error: str = "";

    async can with entry {
        google_ok: bool = False;
        apple_ok: bool = False;
        google_ok = await _sso_configured("google");
        apple_ok = await _sso_configured("apple");
        sso_google_ok = google_ok;
        sso_apple_ok = apple_ok;
        sso_probing = False;
    }

    def handle_submit(e: FormEvent) {
        e.preventDefault();
        onLogin();
    }

    """Create account only (login keeps accepting existing shorter passwords -
    this check never runs on the Log in path, which is a separate `type="submit"`
    button/handler). The password `<Input>` also carries `minLength={8}` for
    the native affordance; the form is `noValidate` so that attribute can never
    block the Log in submit for an existing account with a shorter password -
    this JS check is what actually gates Create account."""
    def handle_signup(e: MouseEvent) {
        if len(password) < 8 {
            pw_error = "At least 8 characters.";
            return;
        }
        pw_error = "";
        onSignup();
    }

    """Shared SSO click path for both providers. `jacSsoLogin` (jac-cl-auth)
    hands off to the provider and resolves true once the token lands; a full
    reload then re-runs the shell's mount `can with entry`, which sees
    `jacIsLoggedIn()` true and calls `enter()` - the same success path email
    login uses via `onLogin` -> `login()` -> `enter()`."""
    async def handle_sso(platform: str, label: str) -> None {
        ok: bool = False;
        sso_busy = platform;
        try {
            ok = await jacSsoLogin(platform);
        } except Exception as e {
            ok = False;
        }
        sso_busy = "";
        if not ok {
            toast(label + " sign-in is not set up yet", "error");
            return;
        }
        window.location.reload();  # jac:ignore[W2001,E1053]
    }

    async def handle_google -> None {
        await handle_sso("google", "Google");
    }

    async def handle_apple -> None {
        await handle_sso("apple", "Apple");
    }

    busy: bool = login_pending or signup_pending;
    sso_any_busy: bool = busy or sso_busy != "";
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
                        <form onSubmit={handle_submit} className="flex flex-col gap-5" noValidate={True}>
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
                                        minLength={8}
                                        value={password}
                                        onChange={lambda e: ChangeEvent { onPasswordChange(e.target.value); pw_error = ""; }}
                                    />
                                    <p className={"text-caption " + ("text-destructive" if pw_error else "text-muted-foreground")}>
                                        {pw_error if pw_error else "At least 8 characters."}
                                    </p>
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
                        {if not sso_probing and (sso_google_ok or sso_apple_ok) {
                            <div className="flex flex-col gap-3 pt-2">
                                <div className="flex items-center gap-3">
                                    <div className="h-px flex-1 bg-border" />
                                    <span className="text-caption text-muted-foreground">or</span>
                                    <div className="h-px flex-1 bg-border" />
                                </div>
                                {sso_google_ok and
                                    <Button
                                        type="button"
                                        size="lg"
                                        variant="secondary"
                                        className="w-full gap-2"
                                        disabled={sso_any_busy}
                                        onClick={handle_google}
                                    >
                                        <GoogleIcon />
                                        {"Connecting…" if sso_busy == "google" else "Continue with Google"}
                                    </Button>}
                                {sso_apple_ok and
                                    <Button
                                        type="button"
                                        size="lg"
                                        variant="secondary"
                                        className="w-full gap-2"
                                        disabled={sso_any_busy}
                                        onClick={handle_apple}
                                    >
                                        <AppleIcon />
                                        {"Connecting…" if sso_busy == "apple" else "Continue with Apple"}
                                    </Button>}
                            </div>
                        }}
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
