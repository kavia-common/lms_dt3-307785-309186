#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
DEV_USER="${MONGO_DEV_USER:-lms_dev}"
DEV_PASS="${MONGO_DEV_PASS:-devpass}"
HOST=127.0.0.1
PORT=27017
CLI=${MONGO_CLI:-$(command -v mongosh || command -v mongo || true)}
if [ -z "$CLI" ]; then echo "ERROR: no mongo client available" >&2; exit 2; fi
# print client used
$CLI --version 2>/dev/null || true
if $CLI --quiet "mongodb://${DEV_USER}:${DEV_PASS}@${HOST}:${PORT}/lms_dev" --eval 'db.runCommand({ping:1})' >/dev/null 2>&1; then
  echo "connectivity: ok"
else
  echo "ERROR: connectivity test failed (client=$CLI)" >&2
  # Minimal diagnostics
  echo "--- diagnostics: process list for mongod and listeners ---"
  ps aux | egrep "mongod|mongo" | sed -n '1,200p' || true
  ss -ltnp 2>/dev/null | egrep ":27017\b" || netstat -ltnp 2>/dev/null | egrep ":27017\b" || true
  # show client error detail by attempting a direct connection (prints error to stderr)
  $CLI "mongodb://${DEV_USER}:${DEV_PASS}@${HOST}:${PORT}/lms_dev" --eval 'db.runCommand({ping:1})' || true
  exit 6
fi
