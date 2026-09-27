"""PublicCard (SOH-228): the public, no-login `/card/<handle>` screen a QR or
shared link opens. OWNER: Person B.

Mounted directly from `frontend.cl.jac` when `window.location.pathname`
starts with `/card/` — before the auth/onboarding/home switch, so an
anonymous visitor never sees (or needs) the login form. Fetches
`fetch_public_card(handle)` (`components/api_card.cl.jac`'s client wrapper
around the server's public `get_card`, no JWT) and, on a hit, renders it
through `CardPreview` unchanged: exactly the fields a friend would see,
nothing this screen adds. The server's `get_card` itself refuses a
`handshake_only` card by returning `found: false` (same as an unknown
handle), so every card this screen can show is already `visibility=="link"`.
"""

import from .CardPreview { CardPreview }
import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.button { Button }
import from ..api_card { fetch_public_card }

def:pub PublicCard(handle: str) -> JsxElement {
    has loaded: bool = False,
        found: bool = False,
        card: dict[str, any] = {};

    async def load {
        loaded = False;
        result: dict[str, any] = {};
        try {
            result = await fetch_public_card(handle);
        } except Exception {
            result = {"found": False};
        }
        found = True if result["found"] else False;
        card = result;
        loaded = True;
    }

    async can with entry {
        await load();
    }

    name: str = (card["name"] or "") as str;
    headline: str = (card["headline"] or "") as str;
    about: str = (card["about"] or "") as str;
    looking_for: list[str] = (card["looking_for"] or []) as list[str];
    can_offer: list[str] = (card["can_offer"] or []) as list[str];
    links: list[str] = (card["links"] or []) as list[str];
    interests: list[str] = (card["interests"] or []) as list[str];
    contact_pref: str = (card["contact_pref"] or "") as str;
    updated_at: str = (card["updated_at"] or "") as str;

    return
        <main className="mx-auto flex min-h-svh w-full max-w-md flex-col gap-6 pt-6 pb-10 pl-4 pr-4">
            <h1 className="text-display-md">Cirql</h1>
            {if not loaded {
                <p role="status" className="pt-10 text-body-sm text-muted-foreground">Opening this card…</p>
            } elif not found {
                <Card>
                    <CardHeader>
                        <CardTitle>Not shared</CardTitle>
                        <CardDescription>This card isn't shared by link.</CardDescription>
                    </CardHeader>
                    <CardContent>
                        <Button asChild variant="outline">
                            <a href="/">Open Cirql</a>
                        </Button>
                    </CardContent>
                </Card>
            } else {
                <CardPreview
                    name={name}
                    handle={handle}
                    headline={headline}
                    about={about}
                    looking_for={looking_for}
                    can_offer={can_offer}
                    links={links}
                    interests={interests}
                    contact_pref={contact_pref}
                    updated_at={updated_at}
                    visibility="link"
                />
                <div className="flex justify-center">
                    <Button asChild variant="outline">
                        <a href="/">Open Cirql</a>
                    </Button>
                </div>
            }}
        </main>;
}
