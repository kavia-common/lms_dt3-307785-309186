#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/mongodb/mongod.log
# determine mongo shell, default to "mongo" if not set
MONGO_SH="${MONGO_SH:-mongo}"
if command -v "$MONGO_SH" >/dev/null 2>&1; then
  "$MONGO_SH" --quiet --eval 'db.runCommand({ ping: 1 })' >/dev/null 2>&1 || { echo "HEALTH: ${MONGO_SH} failed to ping" >&2; tail -n 20 "$LOG" >&2 || true; exit 2; }
else
  echo "ERROR: no mongo client found (tried: ${MONGO_SH})" >&2
  exit 4
fi
exit 0
