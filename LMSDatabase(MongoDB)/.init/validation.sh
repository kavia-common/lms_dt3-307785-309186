#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
mkdir -p "$WORKSPACE/validation" && cd "$WORKSPACE"
PIDFILE="/tmp/mongod_dev.pid"
started=0
# start wrapper if needed
if [ ! -f "$PIDFILE" ] || ! kill -0 "$(cat "$PIDFILE" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
  bash "$WORKSPACE/scripts/start_mongod.sh" &
  START_WRAPPER_PID=$!
  echo "$START_WRAPPER_PID" >"$PIDFILE"
  started=1
  # wait for healthcheck up to 30s
  for i in {1..30}; do
    if bash "$WORKSPACE/scripts/healthcheck.sh" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  if ! bash "$WORKSPACE/scripts/healthcheck.sh" >/dev/null 2>&1; then echo 'ERROR: healthcheck timeout' >&2; exit 8; fi
fi
# seed
bash "$WORKSPACE/scripts/init_seed.sh"
# collect healthcheck output
bash "$WORKSPACE/scripts/healthcheck.sh" > "$WORKSPACE/validation/healthcheck.out" 2>&1 || true
# collect versions
mongod --version > "$WORKSPACE/validation/mongod.version" 2>&1 || true
if command -v mongosh >/dev/null 2>&1; then mongosh --version > "$WORKSPACE/validation/mongosh.version" 2>&1 || true; fi
if command -v mongo >/dev/null 2>&1; then mongo --version > "$WORKSPACE/validation/mongo.version" 2>&1 || true; fi
# prepare mongodump args (auth-aware)
CREDFILE="$WORKSPACE/config/.mongo_dev_creds"
DUMP_DIR="$WORKSPACE/validation/dump"
mkdir -p "$DUMP_DIR"
DUMP_ARGS=()
if [ -f "$CREDFILE" ]; then
  # shellcheck disable=SC1090
  . "$CREDFILE" || true
  if [ -n "${MONGO_INITDB_ROOT_USERNAME:-}" ] && [ -n "${MONGO_INITDB_ROOT_PASSWORD:-}" ]; then
    DUMP_ARGS+=(--username "${MONGO_INITDB_ROOT_USERNAME}" --password "${MONGO_INITDB_ROOT_PASSWORD}" --authenticationDatabase admin)
  fi
fi
DUMP_ARGS+=(--db=lms_dev --out="$DUMP_DIR")
if command -v mongodump >/dev/null 2>&1; then
  mongodump "${DUMP_ARGS[@]}" --quiet || true
fi
# collect log tail if present
if [ -f /data/db/mongod.log ]; then tail -n 200 /data/db/mongod.log > "$WORKSPACE/validation/mongod.log.tail" || true; fi
# set restrictive perms
find "$WORKSPACE/validation" -type d -exec chmod 0700 {} + || true
find "$WORKSPACE/validation" -type f -exec chmod 0600 {} + || true
# stop if we started
if [ "$started" -eq 1 ]; then
  REC_PID=$(cat "$PIDFILE" 2>/dev/null || echo '')
  if [ -n "$REC_PID" ] && kill -0 "$REC_PID" >/dev/null 2>&1; then
    kill -TERM "$REC_PID" || true
    for i in {1..10}; do if ! kill -0 "$REC_PID" >/dev/null 2>&1; then break; fi; sleep 1; done
    if kill -0 "$REC_PID" >/dev/null 2>&1; then kill -KILL "$REC_PID" || true; fi
  fi
  rm -f "$PIDFILE" || true
fi
# list evidence files concisely
ls -la "$WORKSPACE/validation" || true
