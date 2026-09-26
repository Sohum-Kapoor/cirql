"""Appearance: Light / Dark / System. OWNER: Person B (SOH-206).

System (the default) = no class on <html>; assets/main.css follows
prefers-color-scheme. Light / Dark put `.light` / `.dark` on <html> and are
persisted in localStorage (every access guarded: Safari private mode and some
WKWebView configs throw). `boot_theme()` runs when this module is first imported
— before React's first render — so a stored choice is on <html> before the app
paints.

<meta name="color-scheme"> and <meta name="theme-color"> are kept in sync so
Safari chrome and native form controls match. The theme-color value is read
back from the resolved `--background` token: no colour literal lives here.
"""

glob THEME_KEY: str = "cirql-theme",
     THEME_MODES: list[str] = ["light", "dark", "system"];

"""The stored choice: "light" | "dark" | "system" (default / unreadable)."""
def:pub stored_theme() -> str {
    mode: str = "system";
    try {
        v: any = localStorage.getItem(THEME_KEY);  # jac:ignore[W2001]
        if v == "light" or v == "dark" {
            mode = v as str;
        }
    } except Exception as e {
        mode = "system";
    }
    return mode;
}

def:pub save_theme(mode: str) -> None {
    try {
        if mode == "light" or mode == "dark" {
            localStorage.setItem(THEME_KEY, mode);  # jac:ignore[W2001]
        } else {
            localStorage.removeItem(THEME_KEY);  # jac:ignore[W2001]
        }
    } except Exception as e {
        return;
    }
}

def _meta(name: str) -> any {
    el: any = document.head.querySelector("meta[name='" + name + "']");  # jac:ignore[W2001]
    if not el {
        el = document.createElement("meta");  # jac:ignore[W2001]
        el.setAttribute("name", name);
        document.head.appendChild(el);  # jac:ignore[W2001,E1030]
    }
    return el;
}

"""Put the mode on <html> and sync the color-scheme / theme-color metas."""
def:pub apply_theme(mode: str) -> None {
    try {
        html_el: any = document.documentElement;  # jac:ignore[W2001]
        html_el.classList.remove("light");
        html_el.classList.remove("dark");
        if mode == "light" or mode == "dark" {
            html_el.classList.add(mode);
        }
        _meta("color-scheme").setAttribute("content", mode if mode == "light" or mode == "dark" else "light dark");
        bg: str = str(getComputedStyle(html_el).getPropertyValue("--background")).strip();  # jac:ignore[W2001]
        if bg {
            _meta("theme-color").setAttribute("content", bg);
        }
    } except Exception as e {
        return;
    }
}

"""Save + apply (the Appearance control)."""
def:pub set_theme(mode: str) -> None {
    save_theme(mode);
    apply_theme(mode);
}

"""Apply the stored mode now, and re-sync theme-color when the OS flips while
the user is on System."""
def boot_theme() -> str {
    mode: str = stored_theme();
    apply_theme(mode);
    try {
        mq: any = window.matchMedia("(prefers-color-scheme: dark)");  # jac:ignore[W2001]
        mq.addEventListener("change", lambda(e: any) {
            if stored_theme() == "system" {
                apply_theme("system");
            }
        });
    } except Exception as e {
        return mode;
    }
    return mode;
}

glob:pub BOOT_THEME: str = boot_theme();
