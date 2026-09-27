"""CardQR (SOH-228): the scannable, no-login link to a published Card.
OWNER: Person B.

Mounted from `AppearanceSheet` right under `CardEditor`'s own preview, fed
the SAME handle/visibility the editor just loaded/saved — never re-reads the
card itself. Only meaningful when `visibility == "link"` (the public
`get_card` walker refuses anything else, so a `handshake_only` card has no
URL to encode yet); the `handshake_only` branch below explains that instead
of rendering a QR nobody could open.

URL building (`_public_origin`): `window.location.origin` when it's an
http(s) origin (the normal web case). On iOS the Capacitor WebView's origin
is `capacitor://localhost`, which isn't reachable from outside the app, so we
fall back to `globalThis.__JAC_API_BASE_URL__` (the backend base URL
`jac-client` bakes in at build time via `JAC_CLIENT_API_BASE_URL` — see
`jac-cl-js-interop` and the AGENTS.md iOS gotchas) when THAT is itself an
http(s) URL. If neither is usable (no origin, or a build with no API base
set), there is no absolute URL to encode or copy — the whole block explains
that instead of showing a broken QR/link, per SOH-228.

The QR itself always renders on a literal white tile with a literal black
foreground, regardless of app theme — a QR's quiet zone and contrast are a
scanner-hardware requirement, not a design-token color choice, so this is the
one place client Jac hardcodes `#fff`/`#000` on purpose.
"""

import from "qrcode.react" { QRCodeSVG }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ...lib.toast { toast }

"""The web origin when it's http(s); otherwise the build-time backend base
URL (Capacitor's `capacitor://localhost` origin isn't reachable from outside
the app) when THAT is http(s); otherwise ""."""
def _public_origin() -> str {
    loc_origin: str = str(window.location.origin);  # jac:ignore[E1053]
    if loc_origin.startswith("http://") or loc_origin.startswith("https://") {
        return loc_origin;
    }
    api_base: any = globalThis.__JAC_API_BASE_URL__;  # jac:ignore[W2001,E1053,E1032]
    base: str = str(api_base) if api_base else "";
    if base.startswith("http://") or base.startswith("https://") {
        return base;
    }
    return "";
}

def:pub CardQR(handle: str, visibility: str) -> JsxElement {
    has copied: bool = False;

    origin: str = _public_origin();
    url: str = (origin + "/card/" + handle) if (origin and handle) else "";

    async def do_copy(e: Event) {
        ok: bool = True;
        try {
            await navigator.clipboard.writeText(url);  # jac:ignore[E1030]
        } except Exception {
            ok = False;
        }
        copied = ok;
        if ok {
            toast("Link copied", "success");
        }
    }

    if not handle {
        return <div className="hidden" />;
    }

    if visibility != "link" {
        return
            <Card>
                <CardHeader>
                    <CardTitle>Share by QR</CardTitle>
                    <CardDescription>
                        A QR code needs "Anyone with the link" turned on above. Right now this card is only handed over one at a time.
                    </CardDescription>
                </CardHeader>
            </Card>;
    }

    if not url {
        return
            <Card>
                <CardHeader>
                    <CardTitle>Share by QR</CardTitle>
                    <CardDescription>
                        Open Cirql on the web to get a shareable QR for this card. This app session has no reachable web link.
                    </CardDescription>
                </CardHeader>
            </Card>;
    }

    return
        <Card>
            <CardHeader>
                <CardTitle>Share by QR</CardTitle>
                <CardDescription>Anyone who scans this opens your card. No login needed.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col items-center gap-3">
                <div className="rounded-md p-3" style={{"backgroundColor": "#ffffff"}}>
                    <QRCodeSVG value={url} size={176} fgColor="#000000" bgColor="#ffffff" level="M" />
                </div>
                <span className="w-full truncate text-center text-body-sm text-muted-foreground">{url}</span>
                <Button size="sm" variant="outline" className="w-full" onClick={do_copy}>
                    {"Copied" if copied else "Copy link"}
                </Button>
            </CardContent>
        </Card>;
}
