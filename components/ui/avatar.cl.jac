"""Avatar (SOH-226): a deterministic initials avatar. A circle, 1–2 initials
from `name`, a muted background picked from a 6-hue palette keyed by the
name's first letter (assets/main.css `--avatar-1..6` — the only place a
colour literal may appear, per that file's own header comment). "?" for the
placeholder name "me" (nobody has typed a real name yet) or any name that
reduces to zero letters.

Used in the Settings header (`components/settings/AppearanceSheet.cl.jac`)
and the person sheet title row (`components/person/PersonSheet.cl.jac`).
Deliberately NOT used in the People list — HomeView is off limits (SOH-226).
Pure: no props beyond `name`/`size`, no state, no server calls.
"""

import from ...lib.text { join_with }
import from ...lib.utils { cn }

glob _AVATAR_PALETTE: list[str] = [
    "bg-avatar-1/15 text-avatar-1",
    "bg-avatar-2/15 text-avatar-2",
    "bg-avatar-3/15 text-avatar-3",
    "bg-avatar-4/15 text-avatar-4",
    "bg-avatar-5/15 text-avatar-5",
    "bg-avatar-6/15 text-avatar-6"
];

"""1–2 uppercase initials off the first two words of `name`. "?" for the
onboarding placeholder "me" or anything with no letters at all."""
def:pub avatar_initials(name: str) -> str {
    clean: str = (name or "").strip();
    if not clean or clean == "me" {
        return "?";
    }
    words: list[str] = [w for w in clean.split(" ") if w];
    letters: list[str] = [w[0] for w in words][:2];
    out: str = join_with(letters, "").upper();
    return out or "?";
}

"""A stable index into `_AVATAR_PALETTE` off `name`'s first character — the
same name always lands on the same hue; no identity is derived from it."""
def _avatar_palette_index(name: str) -> int {
    clean: str = (name or "").strip();
    if not clean {
        return 0;
    }
    code: int = ord(clean[0].lower());
    return code % len(_AVATAR_PALETTE);
}

def:pub Avatar(name: str, size: str = "md") -> JsxElement {
    initials: str = avatar_initials(name);
    palette: str = _AVATAR_PALETTE[_avatar_palette_index(name)];
    dim: str = "size-12 text-body-lg" if size == "lg" else ("size-6 text-caption" if size == "sm" else "size-8 text-caption");
    return
        <span
            aria-hidden="true"
            className={cn("flex shrink-0 items-center justify-center rounded-full font-medium", dim, palette)}
        >
            {initials}
        </span>;
}
