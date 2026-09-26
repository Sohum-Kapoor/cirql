"""Client shell — OWNER: Person B.

One stateful shell component; handler bodies live in frontend.impl.jac
(`jac guide jac-cl-organization`). Screens go in components/ as they appear.
Until a walker exists, build against components/mocks (contracts/walkers.md).
"""

import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }

sv import from walkers { Ping, ListPeople }
sv import from schema { Person }

def:pub app -> JsxElement {
    has logged_in: bool = False,
        email: str = "",
        password: str = "",
        status: str = "",
        people: list[Person] = [];

    can with entry {
        already: bool = jacIsLoggedIn();
        logged_in = already;
        if already {
            refresh();
        }
    }

    async def signup -> None;
    async def login(e: FormEvent) -> None;
    def logout -> None;
    async def refresh -> None;

    return
        <div
            style={{
                "maxWidth": "480px",
                "margin": "1.5rem auto",
                "padding": "0 1rem",
                "fontFamily": "system-ui, -apple-system, sans-serif"
            }}
        >
            <h1 style={{"fontSize": "1.4rem"}}>Cirql</h1>
            <p style={{"color": "#666"}}>Other CRMs search your contacts. Cirql's agents walk your network.</p>
            {
                (
                    <form onSubmit={login} style={{"display": "grid", "gap": "0.5rem"}}>
                        <input
                            type="email"
                            value={email}
                            onChange={lambda e: ChangeEvent { email = e.target.value; }}
                            placeholder="email"
                        />
                        <input
                            type="password"
                            value={password}
                            onChange={lambda e: ChangeEvent { password = e.target.value; }}
                            placeholder="password"
                        />
                        <div style={{"display": "flex", "gap": "0.5rem"}}>
                            <button type="submit">Log in</button>
                            <button type="button" onClick={lambda e: MouseEvent { signup(); }}>Sign up</button>
                        </div>
                    </form>
                ) if not logged_in else (
                    <div>
                        <button onClick={lambda e: MouseEvent { logout(); }}>Log out</button>
                        <button onClick={lambda e: MouseEvent { refresh(); }}>Ping</button>
                        <p>{"People you know: " + str(len(people))}</p>
                        <ul>
                            {[<li key={idx}>{p.name}</li> for (idx, p) in enumerate(people)]}
                        </ul>
                    </div>
                )
            }
            <p style={{"color": "#888", "fontSize": "0.9rem"}}>{status}</p>
        </div>;
}
