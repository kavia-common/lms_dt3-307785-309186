#!/usr/bin/env bash
set -euo pipefail
# start-mongod-foreground: exec workspace start script so PID becomes mongod
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
START_SCRIPT="${WORKSPACE}/scripts/start-mongod.sh"
# ensure start script exists and is executable
[ -x "${START_SCRIPT}" ] || { echo "ERROR: start script missing or not executable: ${START_SCRIPT}" >&2; exit 2; }
# exec so PID 1 in container (or the foreground process) is the start script which should exec mongod
exec "${START_SCRIPT}"
