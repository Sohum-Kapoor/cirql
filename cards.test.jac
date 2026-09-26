"""Tests for cards.sv.jac (SOH-178, PublishCard + get_card).

Annex to cards.sv.jac — run with `jac test cards.sv.jac`.

Same harness as gate.test.jac / exchange.test.jac: JacTestClient cannot
target a dotted `*.sv.jac` file, so each test copies the live server modules
into a fresh temp dir next to a dot-free `app.jac` and gives the client its
own base_path. No `jac clean` anywhere.

Two registered accounts (A, B) plus one anonymous client (`client.clear_auth()`
before hitting `get_card`, per `jac guide jac-sv-auth`: an anonymous caller's
`root` is the shared guest graph, a token-holder's is their own root — the
whole point of the test is that `get_card` behaves the same either way,
because it reaches the CardDirectory through `root.shared` explicitly).
"""

import from jaclang.runtimelib.testing { JacTestClient }
import os;
import shutil;
import tempfile;

glob CARDS_REPO_ROOT = os.path.dirname(os.path.abspath(__file__));

def _cards_harness(tmp_dir: str) -> str {
    for name in ["cards.sv.jac", "schema.sv.jac", "onboard.sv.jac"] {
        shutil.copyfile(os.path.join(CARDS_REPO_ROOT, name), os.path.join(tmp_dir, name));
    }
    harness_path = os.path.join(tmp_dir, "app.jac");
    f = open(harness_path, "w");
    f.write("import from cards { PublishCard, get_card }\n");
    f.close();
    t = open(os.path.join(tmp_dir, "jac.toml"), "w");
    t.write(
        "[project]\n"
        "name = \"cards-test-harness\"\n"
        "version = \"0.1.0\"\n"
        "entry-point = \"app.jac\"\n"
        "\n"
        "[plugins.scale.microservices]\n"
        "enabled = false\n"
    );
    t.close();
    return harness_path;
}

def _reg(client: JacTestClient, email: str) -> str {
    reg = client.register_user(email, "password123");
    assert reg.ok, f"register {email} failed: {reg.status_code} {reg.text}";
    return str((reg.data or {})["token"]);
}

def _publish(client: JacTestClient, token: str, body: dict[str, any]) -> dict[str, any] {
    client.set_auth_token(token);
    resp = client.post("/walker/PublishCard", json=body);
    assert resp.ok, f"PublishCard failed: {resp.status_code} {resp.text}";
    reports = list(resp.data["reports"]);
    assert len(reports) == 1, f"PublishCard reported {len(reports)} items: {reports}";
    return dict(reports[0]);
}

"""Anonymous get_card: clears auth first so the call truly runs with no
token, per jac-sv-auth (a token-holder would run get_card on their OWN root,
which happens to have no effect here since the lookup is root.shared-only —
but the point of the acceptance test is the anonymous path)."""
def _get_card_anon(client: JacTestClient, handle: str) -> dict[str, any] {
    client.clear_auth();
    resp = client.post("/function/get_card", json={"handle": handle});
    assert resp.ok, f"get_card failed: {resp.status_code} {resp.text}";
    return dict(resp.data["result"]);
}

test "cards 1: publish link, anonymous get_card finds it, no visibility/_jac_id leak" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_cards_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "cards_a1@example.com");

        card = _publish(cl, a, {
            "headline": "Robotics @ UMich",
            "about": "I build accessible robots.",
            "visibility": "link",
            "name": "Ada"
        });
        assert str(card["headline"]) == "Robotics @ UMich";
        assert str(card["visibility"]) == "link";
        handle = str(card["handle"]);
        assert handle, f"no handle assigned: {card}";

        found = _get_card_anon(cl, handle);
        print(f"[cards 1] anonymous get_card({handle}) -> {found}");
        assert found["found"], f"expected found: {found}";
        assert str(found["name"]) == "Ada";
        assert str(found["headline"]) == "Robotics @ UMich";
        assert "visibility" not in found, f"visibility leaked: {found}";
        assert "_jac_id" not in found, f"_jac_id leaked: {found}";
        assert set(found.keys()) == {
            "found", "name", "handle", "headline", "about",
            "looking_for", "can_offer", "links", "contact_pref", "updated_at"
        }, f"unexpected keys: {sorted(found.keys())}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "cards 2: republish handshake_only makes it unreadable to an anonymous caller" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_cards_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "cards_a2@example.com");

        card = _publish(cl, a, {"headline": "h", "visibility": "link", "name": "Ada"});
        handle = str(card["handle"]);
        first = _get_card_anon(cl, handle);
        assert first["found"], f"expected found before switch: {first}";

        card2 = _publish(cl, a, {"visibility": "handshake_only"});
        assert str(card2["handle"]) == handle, "same card, handle unchanged";
        assert str(card2["visibility"]) == "handshake_only";

        hidden = _get_card_anon(cl, handle);
        print(f"[cards 2] anonymous get_card({handle}) after handshake_only -> {hidden}");
        assert not hidden["found"], f"handshake_only card was still public: {hidden}";
        assert str(hidden["name"]) == "";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "cards 3: B's card is independently readable; a random handle is not found" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_cards_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "cards_a3@example.com");
        b = _reg(cl, "cards_b3@example.com");

        _publish(cl, a, {"headline": "A's card", "visibility": "link", "name": "Ada"});
        b_card = _publish(cl, b, {"headline": "B's card", "visibility": "link", "name": "Bo"});
        b_handle = str(b_card["handle"]);

        found_b = _get_card_anon(cl, b_handle);
        assert found_b["found"], f"B's card not found: {found_b}";
        assert str(found_b["headline"]) == "B's card";

        missing = _get_card_anon(cl, "no-such-handle-at-all");
        print(f"[cards 3] anonymous get_card(random) -> {missing}");
        assert not missing["found"], f"random handle unexpectedly found: {missing}";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}

test "cards 4: partial republish updates the same Card in place; empty args keep old values" {
    tmp_dir = tempfile.mkdtemp();
    client: (JacTestClient | None) = None;
    try {
        cl = JacTestClient.from_file(_cards_harness(tmp_dir), base_path=os.path.join(tmp_dir, "data"));
        client = cl;
        a = _reg(cl, "cards_a4@example.com");

        first = _publish(cl, a, {
            "headline": "First headline",
            "about": "First about",
            "visibility": "link",
            "name": "Ada"
        });
        first_id = str(first["_jac_id"]);

        second = _publish(cl, a, {"about": "Second about", "visibility": "link"});
        second_id = str(second["_jac_id"]);
        print(f"[cards 4] first={first} second={second}");

        assert second_id == first_id, f"republish created a new Card: {first_id} != {second_id}";
        assert str(second["headline"]) == "First headline", "empty headline should not overwrite";
        assert str(second["about"]) == "Second about", "non-empty about should overwrite";
        assert str(second["handle"]) == str(first["handle"]), "handle must stay stable";
    } finally {
        if client is not None { client.close(); }
        shutil.rmtree(tmp_dir, ignore_errors=True);
    }
}
