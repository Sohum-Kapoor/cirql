# Cirql — agent and human working agreement

This file is read by every coding agent on the project (Claude Code via `CLAUDE.md`,
Codex/ChatGPT via this file, Gemini CLI via `GEMINI.md`) and by both humans. It is
the single source of truth for **how** we work. **What** we're building is
`docs/PRD.md`.

## The project in three lines

Cirql is a personal CRM where AI agents walk your relationship graph. Meet someone,
capture the conversation, and let the two agents work out — each on its own graph —
who in either network could help the other. Loop: Capture → Aim → Find the gap →
Ask the network (both ways). Built in Jac for JacHacks UMich
(Sept 26–27, 2026); hard deadline Sunday 11:30 AM, ≥40% of the code must be Jac.

## Ownership — by file, not by feature

Two people, two Claude Code instances, one repo. Nobody edits the other person's
files. If you need a change there, write it in `contracts/walkers.md` or a Linear
comment and the owner makes it.

| Owner | Owns | Never touches |
|---|---|---|
| **A = SK** (graph & walkers) | `schema.sv.jac`, every other `*.sv.jac`, `*.sv.impl.jac`, `*.test.jac` for server code, `seed/load.jac` | anything client-side |
| **B = Jesse** (client, shell, hosting, voice, demo) | `frontend.cl.jac`, `*.impl.jac` for client, `components/`, `pages/`, `assets/`, `seed/*.json`, `[plugins.client.*]` in `jac.toml`, hosting, video, Devpost | any `*.sv.jac` |
| **Shared, append-only** | `contracts/walkers.md` | — |
| **Announce before editing** | `main.jac` (A), `jac.toml` outside `[plugins.client.*]` (A), `docs/PRD.md` (both, only at a sync) | — |

Server modules live at the **repo root** as `*.sv.jac` — not in a `server/`
directory. Reason (found the hard way): jac-scale resolves `sv import` targets by
flattening the dotted module name into a filename at the cwd, so a subdirectory
module is treated as a separate microservice and never becomes healthy. We also set
`[plugins.scale.microservices] enabled = false` in `jac.toml`. Don't remove either.

## Contract first

`contracts/walkers.md` lists every walker, its inputs, and the exact shape it
`report`s. B builds screens against `components/mocks/` that match those shapes;
A builds walkers that emit them. When A's walker lands, B swaps the mock for
`root spawn Walker(...)`. Contract changes are appended, never rewritten, and
announced as a comment on Linear SOH-160.

## Linear

- Project: **Cirql (JacHacks)** — https://linear.app/sohum/project/cirql-jachacks-fbf1ab222ae1
- **One issue In Progress per person. Claim it before you start.** The board is how
  you know what the other person is doing.
- Labels: `tier:0` (demo doesn't exist without it) … `tier:3`; `owner:A` / `owner:B` / `owner:both`.
- Milestones are the checkpoints: C1 dinner 18:30 · **9 PM gate** (cross-user grants) · C2 midnight, freeze 02:00 · partial submission 9:00 · final 11:30.
- Branch: `<initials>/<issue-key>-<slug>`, e.g. `sk/SOH-169-goalrank`. Commit messages start with the key. Linear's GitHub integration moves the issue when the PR merges.

## Git

- Trunk-based. One branch per issue, alive for at most two or three hours, never
  overnight. Rebase on `main` before opening the PR. Merge your own PR — file
  ownership is the review. `main` must `jac check main.jac` clean at every checkpoint.
- **All commits inside hacking hours** (Sat 12:30 PM → Sun 12:00 PM). Judges check.
- Never commit `.env`, `seed/seed.real.json`, or `.jac/` (all gitignored).

## Working in Jac — read this before writing a line

Jac's syntax is easily confused with Python or JSX, and it has changed between
versions. The installed compiler ships the authoritative reference guides:

```
jac guide                       # list every guide
jac guide jac-core-cheatsheet   # start here, then:
jac guide jac-node-edge-patterns   jac guide jac-walker-patterns
jac guide jac-by-llm               jac guide jac-sv-auth
jac guide jac-sv-multi-user        jac guide jac-cl-components
jac guide jac-cl-auth              jac guide jac-mobile-app
jac guide --search <keyword>
```

Rules an agent must follow:

1. **Run `jac guide <name>` for the area you're about to touch before writing.**
   Do not write Jac from memory or from web tutorials — pinned versions below.
2. **Run `jac check <file>` after every edit.** Diagnostics link to the guide that
   explains the fix (`-> run 'jac guide ...'`). A file that fails `jac check` is not done.
3. Test walkers with `test` blocks (`jac guide jac-testing`) and `jac test`.
   The isolation negative test (account A never sees account B's nodes) is required.
4. Start the app with `jac start main.jac` (or `--dev` for client HMR). Kill stale
   servers first: `pkill -f "jac star[t]"`. The app serves at `/`; walkers at
   `/walker/<Name>`; auth at `/user/register`, `/user/login`.
5. Gotchas the guides document and agents keep hitting: `++>` returns a **list**
   (`(here ++> X())[0]`); typed edges declare endpoints (`edge E: A --> B {}`);
   `by llm` returns `obj`s, never nodes — copy fields into nodes; pre-declare
   variables that hold `await` results in `.cl.jac`; `jacSignup` returns a dict,
   `jacLogin` a bool; edge abilities are silent no-ops.
6. Keep JS to d3 configuration only. Everything else is `.jac` — the 40% rule.
7. Secrets come from `.env` (`GOOGLE_API_KEY`, `ELEVENLABS_API_KEY`). Server-side
   only; never in a `cl` block.

## Product rules the code must enforce (from the PRD)

- Relationships never decay. `Knows.last_contact` is display only; nothing reads it to lower anything. Facts and intents have freshness/expiry.
- Relevance is a property of (Person, Goal) — the `RelevantTo` edge — never of a Person. No worth scores, no give/take ledger.
- Every claim has provenance: a Fact/Intent/Promise is reachable from its Note via an `Asserts*` edge carrying `span`; a `Knows`/`Reported` tie carries `source_note` (+ span); web facts carry `source_url`. No receipts, no feature.
- The only graph object that crosses accounts is a `Card` its owner wrote, granted read-only to a specific user via `allow_root`. The Exchange on `root.shared` carries a need, one line about the requester, and a handle — never a name from anyone's graph. An agent answering an Exchange request runs on its owner's root only and returns a count and a strength — no identity — until every person involved has approved. (Wording per SOH-160 v1.1, 2026-09-26.)
- Nothing sends. Drafts only; approvals are recorded and labeled with their source.
- No automated fetching from LinkedIn or any platform whose terms forbid it.
- Privacy claims: say "isolated by construction" and "granted read-only"; never "private", "secure", "encrypted".

## Toolchain (pinned — do not upgrade this weekend)

Python **3.12** (jac-client does not install on 3.11 — `uv venv --python 3.12 .venv`).
jaclang 0.16.7 · jac-client 0.3.25 · byllm 0.6.19 · jac-scale 0.2.31 · jaseci 2.3.28.
Scaffolded with `jac create cirql --kind fullstack`.

## When you finish a task

Say what you verified (the `jac check` output, the test, the curl), not what you
intended. Update the Linear issue. If you learned something the next person will hit,
add it to this file under "Gotchas" — one line, with the fix.

## Gotchas (append here)

- `jac start` spawned "microservices" for every `sv import` target and they never got healthy → server modules at repo root as `*.sv.jac` + `[plugins.scale.microservices] enabled = false`.
- Registering a user with an `@…test` / reserved domain fails validation; use `@example.com` in tests.
- Reports come back as `data.reports` (also under `data.result.reports`).
- `pkill -f "jac start"` from a shell whose own command line contains that string kills the shell; use the `star[t]` bracket trick.
- `JacTestClient.from_file` can't target a `*.sv.jac` (or any dotted-basename) file directly: it derives the served module name by stripping only the trailing `.jac`, so `walkers.sv.jac` becomes target `"walkers.sv"` — Python's `import_module` then treats the dot as a package separator and 404s with `ModuleNotFoundError: No module named 'walkers.sv'; 'walkers' is not a package`. Point it at a dot-free harness file (e.g. a temp `app.jac` with `import from walkers { ... }`, copied next to the real `*.sv.jac`) instead.
- `jac clean --all --force` deletes `.jac/data|cache|client` in whatever directory you run it from — even while another `jac start` keeps running against that same directory (the process itself doesn't crash, but its on-disk state is gone and gets silently recreated empty). Never run `jac clean` in the shared repo root; only run it inside a scratch/test directory, or better, avoid it entirely by giving `JacTestClient`/tests their own `base_path`.
- `jac check foo.test.jac` (alone or beside its head) sees the head's symbols as `Unknown` (E1032/E1053) unless the test file imports them explicitly: `import from foo { Obj, helper }`. Then narrow optionals (`x = f(); assert x is not None and x.field == ...`) or E1099.
- `POST /user/register` needs BOTH a `username` and an `email` identity in `identities`; a bare email 400s with "identity.type 'username' is required". Login works with either.
- Gemini free tier returns transient 503 "high demand" on bursts; byLLM retries 3× then raises. Every walker wraps its one `by llm` call in `try/except` and still reports the stored Note.
- `jobj(id)` resolves ANY node regardless of grants; every cross-user read must call `Jac.check_read_access(getattr(n, "__jac__"))  # jac:ignore[E1053]` or it leaks (proven in gate.test.jac).
- `jid()` is dash-less hex; `getattr(n, "__jac__").root` is a dashed UUID. `.replace("-", "")` before comparing; pass `UUID(root_id)` to `Jac.allow_root`. Bare `allow_root(...)` passes `jac check` but NameErrors at runtime: `import from jaclang { JacRuntime as Jac }`.
- An `Exchange` under `root.shared` needs `grant(ex, level=ConnectPerm)` or other users can't attach requests; "Permission denied: field_write on Root[...]" warnings while attaching are harmless.
- Login must use the `username` identity (`{"identity":{"type":"username","value":...}}`); an email identity at login 400s with "identity.type must be 'username'" even though registration accepted both.
- `is None` narrowing does not propagate inside a walker ability body or into an `else` after a mutating loop: guard, then cast `x as Type` at the use site (E1099 otherwise). `dict.get(key, default)` on an inline dict fails E1054; use if/elif.
- Xcode's `/usr/bin/git` shim exits 69 until `sudo xcodebuild -license accept`; `/Library/Developer/CommandLineTools/usr/bin/git` works meanwhile (prepend it to PATH so `gh` finds it).
- `jac test` takes ONE file; run each `*.sv.jac` separately. The walkers restart test spawns `jac` from PATH, so put `.venv/bin` on PATH first.
- Reverse traversal across accounts works: `[req <-:RepliedTo:<-]` on the requester's root returns the friend's IntroReply once it was `allow_root`-granted; still filter with `check_read_access`. `grant(req, level=ConnectPerm)` is what lets a friend attach the edge.
- `def:pub` functions are served at `POST /function/<name>`. Inside one, `root` is `root.shared` only for an anonymous caller; a token-holder's `root` is their own graph, so a universal lookup (the `CardDirectory`) must address `root.shared` explicitly.
- `revoke(node)` undoes a public `grant` (ambient, no import). Still enforce visibility in the reader as defense in depth.
- Tests in one `*.test.jac` share a persisted root across runs: filter results by a per-run id (e.g. `source_note_id == jid(note)`), never by a text you reuse.
- No tuple unpacking (`a, b = f()`): return a dict. Module-level lists need `glob`. Importing plain defs across `*.sv.jac` (`import from goals { _parse_naive_utc }`) works; prefer it to copying helpers.
