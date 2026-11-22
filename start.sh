#!/bin/sh
# Snake Colony — Nakama on Railway: migrate the DB, then run the server.
# Railway provides DATABASE_URL (Postgres). The matchmaker flags are REQUIRED:
# Nakama defaults (interval 15s + 2 intervals) only match at min_count after
# ~30s — longer than the game's 15s search timeout. These flags match in ~2s.
set -e
echo "Running Nakama DB migrations..."
/nakama/nakama migrate up --database.address "$DATABASE_URL"
echo "Starting Nakama server..."
exec /nakama/nakama --database.address "$DATABASE_URL" --matchmaker.interval_sec 1 --matchmaker.max_intervals 1
