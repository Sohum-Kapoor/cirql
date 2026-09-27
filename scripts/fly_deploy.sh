#!/usr/bin/env bash
# Deploy Cirql to Fly.io: build the client bundle HERE (Fly's remote builder runs
# out of memory during the Vite build), ship it in the image, deploy.
# Usage: scripts/fly_deploy.sh [fly deploy args]
set -euo pipefail
cd "$(dirname "$0")/.."
command -v jac >/dev/null || export PATH="$PWD/.venv/bin:$PATH"
command -v fly >/dev/null || export PATH="/opt/homebrew/bin:$PATH"
rm -rf deploy/client-dist
jac build main.jac
test -n "$(ls .jac/client/dist/client.*.js 2>/dev/null)" || { echo "client bundle missing after jac build" >&2; exit 1; }
mkdir -p deploy && cp -R .jac/client/dist deploy/client-dist
fly deploy --app cirql "$@"
