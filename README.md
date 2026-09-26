# Cirql

**Other CRMs search your contacts. Cirql's agents walk your network.**

A personal CRM where AI agents walk your relationship graph: capture people by
talking, set a goal and watch your network re-rank around it, find the gap the goal
needs, and ask your friends' agents for an intro — with a human approving every step
and no agent ever reading another person's graph.

Built in [Jac](https://www.jaseci.org/) for JacHacks UMich, Sept 26–27, 2026.

- Spec: [`docs/PRD.md`](docs/PRD.md) (v0.3)
- How we work (humans and agents): [`AGENTS.md`](AGENTS.md)
- Walker contract (server ↔ client shapes): [`contracts/walkers.md`](contracts/walkers.md)
- Board: Linear → *Cirql (JacHacks)*
- Live: _hosted URL goes here (SOH-173)_

## Setup (one time, each Mac)

Jac needs **Python 3.12** (jac-client does not install on 3.11).

```bash
git clone <this repo> && cd cirql
uv venv --python 3.12 .venv && source .venv/bin/activate     # or python3.12 -m venv .venv
uv pip install "jaclang==0.16.7" "jac-client==0.3.25" "byllm==0.6.19" "jaseci==2.3.28"
jac install                                                   # npm deps into .jac/client
cp .env.example .env                                          # then fill in the keys
jac check main.jac                                            # must pass
```

## Run

```bash
jac start main.jac                 # app at http://localhost:8000/, API at /walker/<Name>
jac start --dev main.jac           # client HMR (server changes still need a restart)
pkill -f "jac star[t]"             # kill a stale server before restarting
```

Smoke test (what the scaffold already does):

```bash
B=http://localhost:8000
curl -s -X POST $B/user/register -H "Content-Type: application/json" \
  -d '{"identities":[{"type":"email","value":"alice@example.com"}],"credential":{"type":"password","password":"secret123"}}'
TOKEN=$(curl -s -X POST $B/user/login -H "Content-Type: application/json" \
  -d '{"identity":{"type":"email","value":"alice@example.com"},"credential":{"type":"password","password":"secret123"}}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["token"])')
curl -s -X POST $B/walker/Ping -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{}'
# → {"ok":true,"data":{"reports":["ok"]},...}
```

## Check, test, build

```bash
jac check main.jac schema.sv.jac walkers.sv.jac frontend.cl.jac   # after every edit
jac test                                                            # test blocks in *.test.jac
jac guide                                                           # the compiler's reference guides — read before writing Jac
scripts/jac_pct.sh                                                  # % of code that is Jac (must stay ≥ 40)
```

Mobile (Capacitor, same bundle) and PWA:

```bash
jac setup mobile --platform ios          # or android; one time
jac start main.jac --client mobile --dev # on-device loop
jac build --client mobile --platform ios # artifact
jac build --client pwa                   # fallback: add-to-home-screen
```

See `jac guide jac-mobile-app` for prerequisites (Xcode + CocoaPods for iOS; JDK 21 + Android SDK for Android).

## Layout

```
main.jac            entry: imports server walkers, mounts the client app
schema.sv.jac       nodes + edges (A owns) — the graph model in docs/PRD.md §8
walkers.sv.jac      walkers = the API (A owns); more *.sv.jac files as it grows
frontend.cl.jac     client shell (B owns); handler bodies in frontend.impl.jac
components/         client components; components/mocks/ = fake walker responses
pages/              client routes (jac guide jac-cl-routing)
contracts/          walker contract, append-only
seed/               seed.example.json (committed, pseudonymized) · seed.real.json (gitignored) · load.jac
docs/PRD.md         the spec
scripts/            jac_pct.sh
```

Server modules stay at the repo root as `*.sv.jac`; a `server/` directory makes
jac-scale treat each module as a microservice (see `AGENTS.md`).

## Data policy

The committed seed is pseudonymized. Real contacts live only in `seed/seed.real.json`,
which is gitignored. Never commit real people's facts, `.env`, or `.jac/`.
