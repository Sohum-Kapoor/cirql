#!/usr/bin/env bash
# Redeploy the hosted Cirql server on this Mac (SK's host, 2026-09-27 02:40).
# The host is a clean clone in ~/.cache/cirql-host serving port 8000 behind a
# cloudflared quick tunnel (`cloudflared tunnel --url http://127.0.0.1:8000`,
# started by hand in its own terminal; its URL is printed there and also at
# http://127.0.0.1:20241/quicktunnel). `.jac/data` (accounts, graphs) is kept;
# only the client bundle is rebuilt. Usage: scripts/host_redeploy.sh [ref]
set -euo pipefail
HOST_DIR="${CIRQL_HOST_DIR:-$HOME/.cache/cirql-host}"
REF="${1:-origin/main}"
LOG="${CIRQL_HOST_LOG:-$HOME/.cache/cirql-host.log}"
export PATH="/Users/sohum/Downloads/cirql/.venv/bin:$PATH"
cd "$HOST_DIR"
git fetch -q origin main
git checkout -q --detach "$REF"
echo "host at $(git log --oneline -1)"
pkill -f "main.jac --port 8000" || true
sleep 2
rm -rf .jac/client            # never .jac/data
nohup jac start main.jac --port 8000 < /dev/null >> "$LOG" 2>&1 &
disown
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:8000/ || true)
  [ "$code" = "200" ] && { echo "host up (200) after ${i}x3s"; exit 0; }
  sleep 3
done
echo "host did not answer 200 within 180s; see $LOG" >&2
exit 1
