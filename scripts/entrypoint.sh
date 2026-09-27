#!/usr/bin/env bash
# Container entrypoint (Fly.io). Persistent state lives on the mounted volume at
# $DATA_DIR (default /data): the SQLite graph (.jac/data) and photo uploads.
set -euo pipefail
DATA_DIR="${DATA_DIR:-/data}"
PORT="${PORT:-8080}"
mkdir -p "$DATA_DIR/jac-data" "$DATA_DIR/uploads" .jac
if [ -d .jac/data ] && [ ! -L .jac/data ]; then
  # First boot on a fresh volume: keep anything the image happened to create.
  cp -rn .jac/data/. "$DATA_DIR/jac-data/" 2>/dev/null || true
  rm -rf .jac/data
fi
ln -sfn "$DATA_DIR/jac-data" .jac/data
rm -rf uploads && ln -sfn "$DATA_DIR/uploads" uploads
# Secrets (GOOGLE_API_KEY, ELEVENLABS_API_KEY, JWT_SECRET) arrive as env vars via
# `fly secrets set`; jac.toml and the server read them from the environment.
exec jac start main.jac --port "$PORT"
