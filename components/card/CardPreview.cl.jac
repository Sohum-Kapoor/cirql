"""CardPreview (SOH-179): "What a friend sees" — renders EXACTLY the fields
`get_card` returns, nothing else. OWNER: Person B.

Deliberately does NOT take a raw Card: `visibility`, `_jac_id`/`id`, and
anything else off the Card node never reach this component, mirroring the
public `get_card` read (contracts/walkers.md, SOH-178) byte for byte — this
is the honest preview of what an outside viewer with the link gets, not a
mirror of the owner's own editor state.
"""

import from ..ui.card { Card, CardHeader, CardTitle, CardDescription, CardContent }
import from ..ui.badge { Badge }
import from ...lib.text { short_date }

def:pub CardPreview(
    name: str, handle: str, headline: str, about: str,
    looking_for: list[str], can_offer: list[str], links: list[str],
    contact_pref: str, updated_at: str
) -> JsxElement {
    updated: str = short_date(updated_at);

    return
        <Card className="border-dashed">
            <CardHeader>
                <CardTitle>What a friend sees</CardTitle>
                <CardDescription>Exactly what opens when someone with your handle or link looks you up.</CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-3">
                <div className="flex flex-col gap-0.5">
                    <span className="text-body font-medium">{name or "Unnamed"}</span>
                    {handle and <span className="text-caption text-muted-foreground">{"@" + handle}</span>}
                </div>

                {headline and <p className="text-body-sm font-medium">{headline}</p>}
                {not headline and <p className="text-body-sm text-muted-foreground">No headline yet.</p>}

                {about and <p className="text-body-sm text-muted-foreground">{about}</p>}

                {len(looking_for) > 0 and
                    <div className="flex flex-col gap-1.5">
                        <span className="text-caption font-medium text-ink-muted">Looking for</span>
                        <div className="flex flex-wrap gap-1.5">
                            {for (i, item) in enumerate(looking_for) {
                                <Badge key={str(i)} variant="secondary">{item}</Badge>
                            }}
                        </div>
                    </div>}

                {len(can_offer) > 0 and
                    <div className="flex flex-col gap-1.5">
                        <span className="text-caption font-medium text-ink-muted">Can offer</span>
                        <div className="flex flex-wrap gap-1.5">
                            {for (i, item) in enumerate(can_offer) {
                                <Badge key={str(i)} variant="outline">{item}</Badge>
                            }}
                        </div>
                    </div>}

                {len(links) > 0 and
                    <div className="flex flex-col gap-1">
                        <span className="text-caption font-medium text-ink-muted">Links</span>
                        {for (i, link) in enumerate(links) {
                            <span key={str(i)} className="truncate text-body-sm text-link">{link}</span>
                        }}
                    </div>}

                {contact_pref and
                    <div className="flex flex-col gap-1">
                        <span className="text-caption font-medium text-ink-muted">Contact</span>
                        <span className="text-body-sm">{contact_pref}</span>
                    </div>}

                {updated and <span className="text-caption text-muted-foreground">{"Updated " + updated}</span>}
            </CardContent>
        </Card>;
}
