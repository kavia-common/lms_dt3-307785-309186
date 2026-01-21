#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
MISSING=()
command -v mongod >/dev/null 2>&1 || MISSING+=(mongod)
if ! command -v mongosh >/dev/null 2>&1 && ! command -v mongo >/dev/null 2>&1; then
  MISSING+=(mongosh_or_mongo)
fi
command -v mongodump >/dev/null 2>&1 || MISSING+=(mongodump)
if [ ${#MISSING[@]} -ne 0 ]; then
  echo "ERROR: missing required tools: ${MISSING[*]}" >&2
  exit 3
fi
# check mongod runnable
if ! mongod --version >/dev/null 2>&1; then
  echo 'ERROR: mongod exists but is not runnable' >&2; exit 4
fi
# report versions
mongod --version | head -n 1 || true
if command -v mongosh >/dev/null 2>&1; then
  mongosh --version 2>/dev/null || true
else
  mongo --version 2>/dev/null || true
fi
mongodump --version 2>/dev/null || true

echo "OK: dependencies verified"
