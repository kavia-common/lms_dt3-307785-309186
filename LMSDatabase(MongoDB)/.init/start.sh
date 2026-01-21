#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
PIDFILE="/tmp/mongod_dev.pid"
mkdir -p "$WORKSPACE/scripts"
# Start the provided start_mongod.sh if not already running
if [ ! -f "$PIDFILE" ] || ! kill -0 "$(cat "$PIDFILE" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
  bash "$WORKSPACE/scripts/start_mongod.sh" &
  echo "$!" >"$PIDFILE"
fi
