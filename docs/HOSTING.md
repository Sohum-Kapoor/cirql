# Hosting Cirql off the laptop (Fly.io)

Today the app is served from SK's Mac (`~/.cache/cirql-host`, port 8000) behind a
cloudflared quick tunnel. This moves the same process to one Fly.io machine with a
persistent volume, so the phone app and the judges' link stop depending on a laptop.

What ships: `Dockerfile` (python 3.14 + node 22, `requirements.lock` = the laptop's
`pip freeze`), `fly.toml` (one machine in `ord`, volume `data` at `/data`, HTTPS,
never auto-stopped), `scripts/entrypoint.sh` (links `.jac/data` and `uploads/` onto
the volume, then `jac start main.jac --port 8080`).

## One-time setup (about ten minutes, needs a card on the Fly account)

```
brew install flyctl
fly auth login                                  # opens the browser
cd ~/Downloads/cirql
fly launch --no-deploy --copy-config --name cirql --region ord
fly volumes create data --region ord --size 1
fly secrets set GOOGLE_API_KEY=... ELEVENLABS_API_KEY=... JWT_SECRET=...   # values from .env
fly deploy                                      # remote build, ~5 min the first time
```

Pick a different `--name` if `cirql` is taken (it becomes `https://<name>.fly.dev`);
`fly launch` rewrites the `app =` line in `fly.toml`, commit that.

`JWT_SECRET` must be the same value the laptop host uses or every existing login
token stops working. `IDENTITY_SALT` defaults to `JWT_SECRET`, so keep it too.

## Moving the existing data (accounts, people, notes) from the laptop

The graph is SQLite under `.jac/data`. Stop the Fly machine's server first so the
files are not written while they are copied:

```
fly ssh console -C "sh -c 'lsof -ti tcp:8080 | xargs kill'"   # or: fly machine stop
cd ~/.cache/cirql-host/.jac/data
fly ssh sftp shell
> put cirql.db /data/jac-data/cirql.db
> put main.db  /data/jac-data/main.db
> exit
fly machine restart
```

Copy the `-wal` and `-shm` files too if they exist, or run `sqlite3 cirql.db
"PRAGMA wal_checkpoint(TRUNCATE)"` on the laptop first so everything is in the
main file. Photo uploads live in `uploads/`; `put` them under `/data/uploads/`.

Starting fresh instead is fine for the demo: register, run onboarding, and the
seeds in `seed/` do the rest.

## Verify

```
curl -s -o /dev/null -w '%{http_code}\n' https://cirql.fly.dev/       # 200
DEMO_BASE=https://cirql.fly.dev DEMO_SLEEP=2 jac run scripts/demo_check.jac   # expect 22 PASS
fly logs                                                                 # "high demand" 503s from Gemini show here
```

## Point the clients at it

- Web: the URL itself.
- iPhone: rebuild with the new base URL, it is baked into the bundle:
  `scripts/ios_build.sh https://cirql.fly.dev`.
- Landing page (`assets/site/index.html`) and Devpost link: replace the tunnel URL.

## Day-to-day

```
fly deploy            # after every merge to main you want live
fly logs              # tail
fly ssh console       # a shell in the container; data is under /data
fly machine restart   # if the process wedges
```

Never `rm -rf /data/jac-data` on the machine; that is the only copy. `fly volumes
snapshots list data` shows Fly's daily snapshots.

## Why Fly and not the Jac Hammer hosted sandbox

The sandbox runs Python 3.14 with a newer jaclang; our `lambda e: T { ... }` does
not parse there and `main.jac` fails to import (AGENTS.md gotcha). The Docker image
pins jaclang 0.16.7 so the code that passes `jac check` here is what runs.

## Cost

One `shared-cpu-1x` machine with 1 GB and a 1 GB volume is roughly $7 to $10 a
month. Stop it with `fly machine stop` when it is not needed; the volume keeps the
data.
