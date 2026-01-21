#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
HEALTH="${WORKSPACE}/scripts/healthcheck.sh"
[ -x "${HEALTH}" ] || { echo "ERROR: healthcheck script missing" >&2; exit 2; }
ATTEMPTS=10
SLEEP=1
i=0
while [ ${i} -lt ${ATTEMPTS} ]; do
  if bash "${HEALTH}"; then
    echo "HEALTH: OK"
    exit 0
  fi
  i=$((i+1))
  sleep ${SLEEP}
done
echo "ERROR: HEALTH FAILED after ${ATTEMPTS} attempts" >&2
exit 3
