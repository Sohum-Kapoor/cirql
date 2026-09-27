"""Card editor read/write wrappers (SOH-179): "My-card editor + what a friend
sees". NEW file — kept separate from `components/api.cl.jac` so tonight's
work never touches it. That file's own `publish_card(name, headline, about)`
is narrow on purpose (forces `visibility="handshake_only"`, no
looking_for/can_offer/links/contact_pref/visibility control) — it exists only
for `PostRequest`/`ReplyToRequest`'s no_card fallback; this module is the
full editor's own read/write pair. OWNER: Person B.

`PublishCard` + the public `get_card` are both live (cards.sv.jac, SOH-178),
and `ExportGraph` is live (export.sv.jac, SOH-210) — no walker to wait on
here. `?mock=1` dev toggle still routes through `components/mocks/card.cl.jac`,
same idiom every other wrapper in `components/api.cl.jac` uses.

Reading "my own card" can't reuse `get_card` (it only ever returns Card
fields, never `visibility`, and refuses anything but `visibility=="link"` —
useless for an owner editing a handshake_only card) and can't reuse
`PublishCard` either (it ALWAYS applies `visibility`, defaulting to "link" —
calling it with empty args to "just read" would silently flip a
handshake_only card public). `MyCard` (cards.sv.jac, SOH-179) is the owner-side
read built for exactly this: same field set `get_card` returns plus
`visibility`, returned regardless of visibility, no write (contracts/walkers.md).
"""

import from .mocks.card { mock_my_card, mock_publish_card_full, mock_get_card }
import from .api { mocks_on }
sv import from ..cards { PublishCard, get_card, MyCard }

glob MOCK_FAST_MS: int = 150;

async def fake_delay(ms: int) {
    await new(Promise, lambda(resolve: any, reject: any) { setTimeout(resolve, ms); });
}

"""The walker's first report, or raise when it reported nothing."""
def _first(result: any, name: str) -> any {
    if not result.reports {
        raise Exception(name + " returned no report");
    }
    return result.reports[0];
}

"""The caller's own Card as the editor should see it — `{handle, name,
headline, about, looking_for, can_offer, links, contact_pref, visibility,
updated_at}`, or `None` before the first `PublishCard` ever ran. Read-only:
goes through `MyCard` (cards.sv.jac, SOH-179), never `PublishCard` or
`get_card` (see module docstring)."""
async def:pub my_card() -> dict | None {
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        return mock_my_card();
    }
    result = root spawn MyCard();
    out: dict = _first(result, "MyCard") as dict;
    if not (out["found"] as bool) {
        return None;
    }
    card: dict = out["card"] as dict;
    return card;
}

"""PublishCard(...) -> the saved Card, same shape as `my_card()`. The editor
always sends its whole form state (not just changed fields) so an empty
textarea reliably clears a list — `PublishCard` itself only skips
overwriting a field when the ARGUMENT is empty, so this is the one caller
that must always pass every field."""
async def:pub publish_card_full(
    headline: str, about: str, looking_for: list[str], can_offer: list[str],
    links: list[str], interests: list[str], contact_pref: str, visibility: str, name: str
) -> dict {
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        return mock_publish_card_full(headline, about, looking_for, can_offer, links, interests, contact_pref, visibility, name);
    }
    result = root spawn PublishCard(
        headline=headline, about=about, looking_for=looking_for, can_offer=can_offer,
        links=links, interests=interests, contact_pref=contact_pref, visibility=visibility, name=name
    );
    card = _first(result, "PublishCard") as dict;
    return card;
}

"""fetch_public_card(handle) -> Card fields only (never `visibility`) — "what a
friend sees" when handed this handle right now. `found: false` with empty
fields for an unknown handle OR a `handshake_only` card, same as the live
`def:pub`.

Named `fetch_public_card`, not `get_card` (SOH-228): `sv import`'s generated
RPC stub dispatches to `/function/<local binding name>` — an alias
(`get_card as sv_get_card`) sends the request to `/function/sv_get_card`,
which doesn't exist server-side, and the failure is a silent 405 at runtime
with `jac check` green (the module-not-found guard doesn't catch a renamed
endpoint). This wrapper keeps the `sv import` binding UNALIASED (`get_card`,
matching the server's own name exactly) and is itself named something else,
so the two don't collide in this module."""
async def:pub fetch_public_card(handle: str) -> dict {
    if mocks_on() {
        await fake_delay(MOCK_FAST_MS);
        return mock_get_card(handle);
    }
    out: dict = await get_card(handle);
    return out;
}
