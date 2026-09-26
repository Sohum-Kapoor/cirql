"""Handler bodies for the client shell. OWNER: Person B."""

impl app.signup -> None {
    signup_result: dict | None = None;
    login_ok: bool = False;
    signup_result = await jacSignup(email, password);
    if not signup_result["success"] {
        status = "signup failed (email may be in use)";
        return;
    }
    login_ok = await jacLogin(email, password);
    if not login_ok {
        status = "login after signup failed";
        return;
    }
    logged_in = True;
    status = "signed up";
    refresh();
}

impl app.login(e: FormEvent) -> None {
    e.preventDefault();
    ok: bool = False;
    ok = await jacLogin(email, password);
    if not ok {
        status = "invalid credentials";
        return;
    }
    logged_in = True;
    status = "logged in";
    refresh();
}

impl app.logout -> None {
    jacLogout();
    logged_in = False;
    people = [];
    status = "logged out";
}

impl app.refresh -> None {
    ping = root spawn Ping();
    status = "server says: " + str(ping.reports[0]);
    result = root spawn ListPeople();
    people = result.reports;
}
