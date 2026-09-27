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
- **Cross-root edges vanish from typed traversals after a restart.** Typed traversals (`[n ->:E:->]`, `[n --> [?:T]]`, `[n <-:E:<-]`) are answered from an index stored with the node's OWNER; an edge another user attaches persists on the edge list but never updates that index, so after a restart (or on another worker) the typed form returns nothing while `[n -->]` still does. On any container other users attach to (`root.shared`, a request, the CardDirectory) use `[x for x in [n -->] if isinstance(x, T)]`. `grant(req, level=ConnectPerm)` is still what lets a friend attach.
- `jac test X.sv.jac` also runs the test files of modules X imports; a harness named `app.jac` clashes with another suite's cached `app` module (every walker 404s) — give each harness a unique name, and copy every module in the import chain (`llm`, `freshness`, `goals`, ...) into a `jac start` harness dir.
- `def:pub` functions are served at `POST /function/<name>`. Inside one, `root` is `root.shared` only for an anonymous caller; a token-holder's `root` is their own graph, so a universal lookup (the `CardDirectory`) must address `root.shared` explicitly.
- `revoke(node)` undoes a public `grant` (ambient, no import). Still enforce visibility in the reader as defense in depth.
- Tests in one `*.test.jac` share a persisted root across runs: filter results by a per-run id (e.g. `source_note_id == jid(note)`), never by a text you reuse.
- No tuple unpacking (`a, b = f()`): return a dict. Module-level lists need `glob`. Importing plain defs across `*.sv.jac` (`import from goals { _parse_naive_utc }`) works; prefer it to copying helpers.
- Never take `[root --> [?:Me]][0]` inside a helper that tests call on the shared root; walk `[root --> [?:Me] ->:HasGoal:->]` style paths instead. Comparing a `dict[str, any]` value needs a cast: `(d["n"] as int) >= 2` (E1110).
- (B, client) In `cl` code: `sep.join(xs)` crashes ("'str' has no attribute 'join'") → `join_with` in `lib/text.cl.jac`; `{**d, k: v}` makes a key literally named `"k"` → copy then `d2[k] = v`; `for k in some_dict` compiles to `for…of` on a plain object and crashes → `for k in list(d.keys())`; lambda handlers inside a JSX `for` miscompile → small row component with named handlers; string-form relative imports (`import from "..ui.button"`) can resolve Unknown → use the dotted form `import from ..ui.button { Button }`.
- (B) `jac add --npm` rewrites all of `jac.toml` (drops comments, pins "latest") → edit `[dependencies.npm]` by hand. `jac add --shadcn` needs a `[jac-shadcn]` section; we copied generated `components/ui/*` from a scratch project instead.
- (B) jac-client's error overlay itself crashes (reads `error.error.message`) and hides the real error → read what the page POSTs to `/cl/__error__` or use `jac start --dev`.
- (B) Jac Hammer sandbox runs Python 3.14 + a newer jaclang, not our pins: our `lambda e: T { … }` doesn't parse there and `main.jac` fails to import → we self-host (SOH-162/173).
- (B) `.env` written as `KEY= # comment` is an EMPTY key; hosted `Capture` then returns `ok:true` with empty lists in <1 s (the `by llm` 403 "unregistered callers" is swallowed) → grep the server log. Background `jac start` needs `< /dev/null` or it exits when stdin closes.
- (B, iOS) Set `[plugins.client.mobile] app_id` before the first `jac setup mobile` (it bakes `com.jac.app` into the Xcode project; a personal team can't sign it); `ios/` is gitignored and gets no `NSMicrophoneUsageDescription` → add it to `ios/App/App/Info.plist` after every `cap add ios`; `jac build --client mobile --platform ios` wants an "iPhone 16" simulator Xcode 26 doesn't create → `xcrun simctl create "iPhone 16" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-26-5`.
- A denied cross-root `edge_write` (target granted ReadPerm only) is a SILENT no-op: a warning is logged, nothing raises. After creating an edge to a node you do not own, verify it landed by traversing from the node you own, and fall back deliberately.
- (B, iOS) Build the Capacitor app only via `scripts/ios_build.sh <https-url>` (builds in `~/.cache/cirql-ios`): `jac build` always empties `.jac/client/dist`, i.e. the bundle a running repo-root `jac start` serves; jac-client 0.3.25 passes Capacitor 8's SPM `App.xcodeproj` to `xcodebuild -workspace` (fails) → script writes a stub `App.xcworkspace`; SPM hangs forever on a hidden keychain prompt for the `github.com` password → script pre-resolves with `-packageAuthorizationProvider netrc`; backend URL is `JAC_CLIENT_API_BASE_URL` (read by jaclang's bundler), not a jac.toml key; first WebView load in the simulator is white for ~20 s.
- (B, client) In a stateful shell's handler, a local variable with the same name as a `has` field compiles to that field's setter (`rows = …` → `setRows(…)`), silently overwriting shell state → never reuse a `has` name for a local. Also: `entry` and `to` are keywords (not usable as param names); `x as T` inside a list comprehension doesn't parse → use a loop.
- `round(x, 2)` fails E1054 on this compiler; use `int(x * 100 + 0.5) / 100.0`.
- `jac build --client mobile --platform ios` (jac-client 0.3.25) hardcodes simulator `name=iPhone 16`; Xcode 27 ships none → once per Mac: `xcrun simctl create "iPhone 16" com.apple.CoreSimulator.SimDeviceType.iPhone-16 com.apple.CoreSimulator.SimRuntime.iOS-27-0`. Build via `scripts/ios_build.sh <https-url>`, never in the repo root.
- (B, iOS) `jac_client`'s internal `_build_ios` xcodebuild call (jac_client/plugin/src/targets/mobile/bundle.jac) takes no passthrough args, so `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` can't ride on `jac build`; the Capacitor-generated Info.plist already references `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` (pbxproj defaults 1.0/1) → `scripts/ios_build.sh` runs its own extra `xcodebuild ... build MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION=$(date +%Y%m%d%H)` right after, same workspace/scheme/destination, which just relinks and reprocesses Info.plist. Also: a worktree has no `.venv`, so `command -v jac` needs `.venv/bin` on PATH first or the script silently sets `JAC=""` and fails with no output at all.
- (B, client) jac-client writes `[plugins.client.app_meta_data]` meta `content=` UNQUOTED, so any value containing a space is cut at the first word (`color-scheme` "light dark" → "light") → only set `title` there; put `color-scheme` in CSS. In `cl` code `x is None` compiles to `=== null` and misses an unpassed (undefined) prop → use `is not False`/truthiness; a `glob` must be `glob:pub` to be imported by another module or the Vite build fails; generated jac-shadcn dialog/sheet/dropdown import `@hugeicons/*` (not installed) → inline SVGs in `components/ui/icons.cl.jac`.
- A walker that resolves `me` via `[root --> [?:Me]][0]` cannot be tested end-to-end with `root spawn` once repeated `jac test` runs have left several `Me` nodes on the shared persisted test root (it silently picks the wrong one → every match is `not_found`). Put the lookup+mutate logic in a plain `def` that takes `me`, test that on a hand-built pair; only the pure not_found path is safe through `root spawn`.
- Every traversal (`[n -->]`, typed or not) silently drops targets the caller cannot READ (`edges_to_nodes` calls `check_read_access`). A revoked/`handshake_only` Card under the shared CardDirectory is invisible to everyone but its owner → publish a public pointer node (`CardListing { handle, card_id }`, `grant(..., ReadPerm)`) and resolve with `jobj(card_id)` + same-owner check (SOH-211).
- (both, client) `jac check` passes on a module that declares the same name twice after a merge (e.g. two `forget()` wrappers or two `sv import … { Forget }` in `components/api.cl.jac`), but the Vite build then fails with `Identifier "X" has already been declared` and `/` serves 503 → after every rebase touching a `.cl.jac`, restart `jac start` and `curl` `/` for 200 (or grep the log for "error during build") before merging.
- `jac start` in a directory that already has `.jac/client` prints "Client bundle already built" and never installs a dependency newly added to `[dependencies.npm]` (d3, SOH-185); the lazy Vite rebuild then fails (`Rollup failed to resolve import "d3"`) and every `GET /` is a 500 while walkers keep working. After pulling a jac.toml dependency change: stop the server, delete ONLY `.jac/client` (never `.jac/data`, never `jac clean`), start again.
- A `:priv` walker spawned in-process (`root spawn W(...)`) right after building fixtures with a bare `root ++>`/`+>:Edge:+>` in the SAME `jac test` method does not reliably re-see those edges through a chained typed traversal that starts at `root` (`[root --> [?:Me] ->:Knows:->]` reported 0 results even though `[me ->:Knows:->]` reported 4, moments earlier, in the same test) — extract the walker's filter/read logic into a plain def that takes the already-resolved node(s) directly (`filter_people(people, ...)`, SOH-217) and test THAT, same idiom `edits.sv.jac`'s `update_person_for` uses for the "which Me gets picked" problem.
- (B, client) `str.isalnum()` has no client-runtime polyfill (`_jac.poly` only wires it for `bytes`, not plain JS strings) → a char-scan tokenizer ported from server `.jac` throws `AttributeError: 'str' object has no attribute 'isalnum'` at runtime with no compile-time warning; use a fixed-charset membership check (`ch in "abc...0123456789"`) instead. Also: "Client bundle already built" skips a rebuild for a plain `.cl.jac` source edit too, not just a new npm dep — delete `.jac/client` (never `.jac/data`) and restart whenever a running server needs to pick up a `.cl.jac` change. `jac browse press <ref> <key>` did not reliably reach a React `onKeyDown` in this session; dispatching a real `KeyboardEvent('keydown', {key, bubbles:true})` via `jac browse eval` did.
- `jac browse` without `-s <name>` shares one default browser session across every agent on the machine; a parallel agent silently drives your page. Always `jac browse -s <worktree-name>`. Leftover headless Chromes (`~/.cache/jacbrowser/profile-*`) also stop the real Chrome from opening a window: `pkill -f "jacbrowser/profile-"`.
- Two branches that both APPEND to `components/api.cl.jac` (or any file) at the same anchor rebase without conflict markers but INTERLEAVED (one function spliced into another); only `jac check` catches it. On a rebase, take main's file and re-append only your block; put `.mocks.*` imports before the first `import from .mocks.` line, never inside a multi-line import.
- `pkill -f "port 8012"` does not match a server started with `-p 8012`; kill by the exact command text you used, or `lsof -ti tcp:<port> | xargs kill`.
- (B, web/iOS) Anything in `assets/` is served at `/static/<path>` (e.g. `assets/icon/icon-32.png` → `/static/icon/icon-32.png`; `.webmanifest` gets `application/manifest+json`); head links come from `[plugins.client.app_meta_data]` keys `icon`, `apple_touch_icon`, `manifest`, `theme_color` (no spaces). The running server rejects `curl -I` with 501 (HEAD unsupported), so probe with `curl -s -o /dev/null -w '%{http_code}'`. The iOS icon/splash live in the gitignored `ios/`, so `scripts/ios_build.sh` re-copies them every build; in a worktree (no `.venv`) it uses `jac` from PATH.
- `jac check main.jac *.sv.jac *.test.jac` run in the repo root while `jac start` serves it can report E1053 "Cannot assign list[EvidenceItem] to parameter of type list[EvidenceItem]" on test files that import `drafts.sv.jac` objects; the same batch in a clean worktree passes, and each file passes alone. It is a cache artifact, not code: run `scripts/check_all.sh` from a worktree (as its header says) before believing a whole-tree check.
