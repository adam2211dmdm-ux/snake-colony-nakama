#!/usr/bin/env bash
# Snake Colony — Nakama + CockroachDB in one container (Railway).
# Mirrors the verified VPS setup (same versions, same matchmaker flags),
# but tuned for Railway's small trial container: CockroachDB runs with
# tiny caches so the two processes fit in ~0.5 GB RAM.
#
# SUPERVISOR: this script stays alive and watches both processes.
# CockroachDB was dying on Railway (OOM on the small trial container);
# when it died, Nakama kept running but every DB call failed
# ("connection refused 127.0.0.1:26257", auth HTTP 500). The supervisor
# restarts a dead CockroachDB (wait for readiness + CREATE DATABASE +
# migrate up, all idempotent) and restarts a dead Nakama.
#
# Ports (override with env vars only for local testing):
#   SOCKET_PORT  — game API, default 7350 (Railway TCP Proxy targets this)
#   CONSOLE_PORT — admin console, default 7351 (NOT exposed on Railway)
#   DB_PORT      — CockroachDB SQL, default 26257 (internal only)
# Data lives in $DATA_DIR (default /data) — attach a Railway volume there
# so accounts survive redeploys; without a volume the server still works
# but a redeploy wipes accounts (device auth re-creates them automatically).
set -uo pipefail

SOCKET_PORT="${SOCKET_PORT:-7350}"
CONSOLE_PORT="${CONSOLE_PORT:-7351}"
DB_PORT="${DB_PORT:-26257}"
HTTP_PORT="${HTTP_PORT:-8080}"
DATA_DIR="${DATA_DIR:-/data}"
COCKROACH_STORE="${DATA_DIR}/cockroach"
NAKAMA_DATA="${DATA_DIR}/nakama"

CR_PID=""
NK_PID=""
SHUTTING_DOWN=0

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

mkdir -p "${COCKROACH_STORE}" "${NAKAMA_DATA}"

db_ready() {
  cockroach sql --insecure --host=localhost --port="${DB_PORT}" \
    -e "SELECT 1" >/dev/null 2>&1
}

wait_db_ready() {
  # $1 = label for the log. Returns 0 when ready, 1 after ~60s.
  local i
  for i in $(seq 1 30); do
    if db_ready; then
      return 0
    fi
    sleep 2
  done
  log "WARN: CockroachDB not ready on :${DB_PORT} after 60s ($1)"
  return 1
}

start_cockroach() {
  log "== CockroachDB (single node, low memory: cache 64MiB, GOMEMLIMIT 192MiB) =="
  GOMEMLIMIT=192MiB cockroach start-single-node --insecure \
    --store="${COCKROACH_STORE}" \
    --listen-addr="localhost:${DB_PORT}" --http-addr="localhost:${HTTP_PORT}" \
    --cache=64MiB --max-sql-memory=64MiB \
    --background=false &
  CR_PID=$!
  log "CockroachDB started (pid ${CR_PID})"
}

prepare_db() {
  # Idempotent: safe to run on every (re)start.
  cockroach sql --insecure --host=localhost --port="${DB_PORT}" \
    -e "CREATE DATABASE IF NOT EXISTS nakama;"
  log "== Nakama migrations =="
  /opt/nakama/nakama migrate up --database.address "root@localhost:${DB_PORT}/nakama"
}

start_nakama() {
  log "== Nakama server (matchmaker flags are REQUIRED) =="
  # Nakama defaults only match at min_count after ~30s (interval_sec 15 x
  # max_intervals 2) — longer than the game's 15s search timeout, which
  # caused false bot fallbacks. interval_sec 1 + max_intervals 1 matches
  # in ~2s. Flag name is --data_dir (underscore): --data-dir does not exist
  # in Nakama 3.26 and makes the server exit at startup.
  GOMEMLIMIT=128MiB /opt/nakama/nakama \
    --database.address "root@localhost:${DB_PORT}/nakama" \
    --logger.level INFO \
    --matchmaker.interval_sec 1 --matchmaker.max_intervals 1 \
    --socket.server_key defaultkey \
    --socket.port "${SOCKET_PORT}" --console.port "${CONSOLE_PORT}" \
    --data_dir "${NAKAMA_DATA}" &
  NK_PID=$!
  log "Nakama started (pid ${NK_PID})"
}

is_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

shutdown() {
  SHUTTING_DOWN=1
  log "Supervisor shutting down, stopping children..."
  if is_alive "${NK_PID:-}"; then kill "${NK_PID}" 2>/dev/null || true; fi
  if is_alive "${CR_PID:-}"; then kill "${CR_PID}" 2>/dev/null || true; fi
  sleep 3
  if is_alive "${NK_PID:-}"; then kill -9 "${NK_PID}" 2>/dev/null || true; fi
  if is_alive "${CR_PID:-}"; then kill -9 "${CR_PID}" 2>/dev/null || true; fi
  wait 2>/dev/null || true
  exit 0
}
trap shutdown SIGTERM SIGINT

# --- initial boot ---
start_cockroach
if wait_db_ready "initial boot"; then
  prepare_db
else
  log "ERROR: DB never became ready on first boot; supervisor will keep retrying"
fi
if db_ready; then
  start_nakama
else
  log "WARN: DB not ready, Nakama start deferred to the supervisor loop"
fi

# --- supervisor loop ---
log "Supervisor running (checking every 15s)"
while [ "${SHUTTING_DOWN}" -eq 0 ]; do
  sleep 15 || break
  if ! is_alive "${CR_PID:-}"; then
    log "ALERT: CockroachDB (pid ${CR_PID:-?}) is DEAD — restarting it"
    CR_PID=""
    start_cockroach
    if wait_db_ready "restart"; then
      prepare_db
      log "CockroachDB recovered"
    else
      log "ERROR: restarted CockroachDB did not become ready; will retry next cycle"
    fi
  fi
  if ! is_alive "${NK_PID:-}"; then
    if db_ready; then
      log "ALERT: Nakama (pid ${NK_PID:-?}) is DEAD — restarting it"
      NK_PID=""
      start_nakama
    else
      log "WARN: Nakama is dead but DB is not ready yet — will retry next cycle"
    fi
  fi
done

shutdown
