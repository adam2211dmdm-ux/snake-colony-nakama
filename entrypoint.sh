#!/usr/bin/env bash
# Snake Colony — Nakama + CockroachDB in one container (Railway).
# Mirrors the verified VPS setup (same versions, same matchmaker flags),
# but tuned for Railway's small trial container: CockroachDB runs with
# tiny caches so the two processes fit in ~0.5 GB RAM.
#
# Ports (override with env vars only for local testing):
#   SOCKET_PORT  — game API, default 7350 (Railway TCP Proxy targets this)
#   CONSOLE_PORT — admin console, default 7351 (NOT exposed on Railway)
#   DB_PORT      — CockroachDB SQL, default 26257 (internal only)
# Data lives in $DATA_DIR (default /data) — attach a Railway volume there
# so accounts survive redeploys; without a volume the server still works
# but a redeploy wipes accounts (device auth re-creates them automatically).
set -euo pipefail

SOCKET_PORT="${SOCKET_PORT:-7350}"
CONSOLE_PORT="${CONSOLE_PORT:-7351}"
DB_PORT="${DB_PORT:-26257}"
HTTP_PORT="${HTTP_PORT:-8080}"
DATA_DIR="${DATA_DIR:-/data}"
COCKROACH_STORE="${DATA_DIR}/cockroach"
NAKAMA_DATA="${DATA_DIR}/nakama"

mkdir -p "${COCKROACH_STORE}" "${NAKAMA_DATA}"

echo "== CockroachDB (single node, low memory) =="
cockroach start-single-node --insecure \
  --store="${COCKROACH_STORE}" \
  --listen-addr="localhost:${DB_PORT}" --http-addr="localhost:${HTTP_PORT}" \
  --cache=128MiB --max-sql-memory=128MiB \
  --background=false &
CR_PID=$!

echo "Waiting for CockroachDB on :${DB_PORT}..."
for i in $(seq 1 30); do
  if cockroach sql --insecure --host=localhost --port="${DB_PORT}" -e "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
cockroach sql --insecure --host=localhost --port="${DB_PORT}" -e "CREATE DATABASE IF NOT EXISTS nakama;"

echo "== Nakama migrations =="
/opt/nakama/nakama migrate up --database.address "root@localhost:${DB_PORT}/nakama"

echo "== Nakama server (matchmaker flags are REQUIRED) =="
# Nakama defaults only match at min_count after ~30s (interval_sec 15 x
# max_intervals 2) — longer than the game's 15s search timeout, which
# caused false bot fallbacks. interval_sec 1 + max_intervals 1 matches
# in ~2s. Flag name is --data_dir (underscore): --data-dir does not exist
# in Nakama 3.26 and makes the server exit at startup.
exec /opt/nakama/nakama \
  --database.address "root@localhost:${DB_PORT}/nakama" \
  --logger.level INFO \
  --matchmaker.interval_sec 1 --matchmaker.max_intervals 1 \
  --socket.server_key defaultkey \
  --socket.port "${SOCKET_PORT}" --console.port "${CONSOLE_PORT}" \
  --data_dir "${NAKAMA_DATA}"
