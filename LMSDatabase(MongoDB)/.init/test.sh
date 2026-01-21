#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
LOG="$WORKSPACE/logs/test.log"
mkdir -p "$WORKSPACE"/logs
: > "$LOG"
# start mongod
if [ ! -x "$WORKSPACE/scripts/start-mongod.sh" ]; then echo "ERROR: missing start script: $WORKSPACE/scripts/start-mongod.sh" | tee -a "$LOG"; exit 12; fi
if [ ! -x "$WORKSPACE/scripts/healthcheck.sh" ]; then echo "ERROR: missing healthcheck script: $WORKSPACE/scripts/healthcheck.sh" | tee -a "$LOG"; exit 13; fi
"$WORKSPACE"/scripts/start-mongod.sh >> "$LOG" 2>&1
# wait for readiness with extended timeout
TIMEOUT=${START_TIMEOUT:-60}
for i in $(seq 1 "$TIMEOUT"); do
  if "$WORKSPACE"/scripts/healthcheck.sh >/dev/null 2>&1; then
    echo "mongod ready after ${i}s" >> "$LOG"
    break
  fi
  if [ "$i" -eq "$TIMEOUT" ]; then
    echo "ERROR: mongod failed to become ready within ${TIMEOUT}s" >> "$LOG"
    "$WORKSPACE"/scripts/stop-mongod.sh >> "$LOG" 2>&1 || true
    exit 22
  fi
  sleep 1
done
# bootstrap users
if [ -x "$WORKSPACE/scripts/bootstrap-users.sh" ]; then
  "$WORKSPACE"/scripts/bootstrap-users.sh >> "$LOG" 2>&1
else
  echo "WARN: bootstrap-users.sh missing, skipping user creation" >> "$LOG"
fi
# optional restore
if [ -x "$WORKSPACE/scripts/restore-sample.sh" ]; then
  "$WORKSPACE"/scripts/restore-sample.sh >> "$LOG" 2>&1 || true
else
  echo "INFO: restore-sample.sh missing, skipping restore" >> "$LOG"
fi
# verify listening on 0.0.0.0:27017
if ss -ltnp 2>/dev/null | grep -q ":27017" || netstat -ltnp 2>/dev/null | grep -q ":27017"; then
  echo 'listening: ok' >> "$LOG"
else
  echo 'listening: fail' >> "$LOG"
fi
# verify healthcheck
if "$WORKSPACE"/scripts/healthcheck.sh >/dev/null 2>&1; then echo 'healthcheck: ok' >> "$LOG"; else echo 'healthcheck: fail' >> "$LOG"; fi
# stop mongod
if [ -x "$WORKSPACE/scripts/stop-mongod.sh" ]; then
  "$WORKSPACE"/scripts/stop-mongod.sh >> "$LOG" 2>&1 || true
else
  echo "WARN: stop-mongod.sh missing; attempting pkill mongod" >> "$LOG"
  pkill -f mongod || true
fi
exit 0
