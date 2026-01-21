#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
mkdir -p "$WORKSPACE/validation" && cd "$WORKSPACE"
# basic checks for required binaries
command -v mongod >/dev/null 2>&1 || { echo "ERROR: mongod not found" >&2; exit 2; }
if ! command -v mongosh >/dev/null 2>&1 && ! command -v mongo >/dev/null 2>&1; then
  echo "ERROR: neither mongosh nor mongo shell found" >&2; exit 3
fi
# run healthcheck
if bash "$WORKSPACE/scripts/healthcheck.sh" >/dev/null 2>&1; then
  echo "healthcheck: ok"
else
  echo "healthcheck: failed" >&2; exit 4
fi
# run init seed
bash "$WORKSPACE/scripts/init_seed.sh"
# simple verification query using best available shell
if command -v mongosh >/dev/null 2>&1; then
  mongosh --eval 'db.getMongo().getDBNames()' >/dev/null 2>&1 || true
else
  mongo --eval 'db.getMongo().getDBs()' >/dev/null 2>&1 || true
fi
