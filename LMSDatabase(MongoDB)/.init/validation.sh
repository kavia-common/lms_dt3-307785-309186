#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
LOG="$WORKSPACE/logs/validation-result.log"
mkdir -p "$WORKSPACE"/logs
echo "VALIDATION: start $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOG"
# ensure helper scripts exist
if [ ! -x "$WORKSPACE/scripts/stop-mongod.sh" ] || [ ! -x "$WORKSPACE/scripts/start-mongod.sh" ] || [ ! -x "$WORKSPACE/scripts/healthcheck.sh" ]; then
  echo "ERROR: required lifecycle scripts missing or not executable" >> "$LOG"
  exit 11
fi
# stop any workspace mongod (best-effort)
"$WORKSPACE"/scripts/stop-mongod.sh >> "$LOG" 2>&1 || true
TS=$(date -u +%Y%m%dT%H%M%SZ)
CFG="$WORKSPACE/config/mongod.conf"
if [ ! -f "$CFG" ]; then
  echo "ERROR: workspace config not found: $CFG" >> "$LOG"
  exit 12
fi
cp "$CFG" "$WORKSPACE/config/mongod.conf.bak.$TS" >> "$LOG" 2>&1 || { echo "ERROR: failed to backup config" >> "$LOG"; exit 13; }
TMPCFG="$WORKSPACE/config/mongod.conf.tmp.$TS"
# create merged config safely via python+PyYAML (python3's yaml likely available)
python3 - <<PY > /dev/null 2>&1 || true
import sys
try:
    import yaml
except Exception:
    sys.exit(2)
old='''"$CFG"'''
# We will read the actual file path from environment by opening it outside this heredoc
PY
# Use a small python wrapper to read/merge reliably (avoid inline quoting issues)
python3 - <<'PY' >> "$LOG" 2>&1 || true
import sys, yaml
cfg_path = sys.argv[1]
out = sys.argv[2]
try:
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f) or {}
except Exception as e:
    print('WARN: could not parse existing config, creating minimal config:', e)
    cfg = {}
# ensure security.authorization is boolean or string 'enabled'
sec = cfg.get('security') if isinstance(cfg.get('security'), dict) else {}
sec['authorization'] = 'enabled'
cfg['security'] = sec
# preserve other keys
with open(out, 'w') as f:
    yaml.safe_dump(cfg, f, sort_keys=False)
print('INFO: wrote merged temp config to', out)
PY "$CFG" "$TMPCFG"
# locate mongod binary from workspace _bins.env or fallback to path
MONGOD_BIN=$(grep '^MONGOD_BIN=' "$WORKSPACE"/scripts/_bins.env 2>/dev/null | cut -d= -f2- || true)
if [ -z "$MONGOD_BIN" ]; then
  MONGOD_BIN=$(command -v mongod || true)
fi
if [ -n "$MONGOD_BIN" ] && [ -x "$MONGOD_BIN" ]; then
  # validate if binary supports --configCheck
  if "$MONGOD_BIN" --help 2>&1 | grep -q "--configCheck"; then
    if "$MONGOD_BIN" --configCheck --config "$TMPCFG" >> "$LOG" 2>&1; then
      mv "$TMPCFG" "$CFG" >> "$LOG" 2>&1 || { echo "ERROR: failed to move validated config" >> "$LOG"; exit 21; }
      echo "INFO: config validated and installed" >> "$LOG"
    else
      echo "ERROR: mongod --configCheck failed; leaving original config" >> "$LOG"
      rm -f "$TMPCFG"
      echo "VALIDATION: fail" >> "$LOG"
      exit 22
    fi
  else
    # fallback: only set authorization if no authorization present (append-safe alternative)
    if ! grep -q "authorization:" "$CFG" 2>/dev/null; then
      cat >> "$CFG" <<EOF
security:
  authorization: enabled
EOF
      echo "WARN: --configCheck unsupported; appended security.authorization if absent" >> "$LOG"
    else
      echo "INFO: authorization appears present in config; leaving as-is" >> "$LOG"
    fi
  fi
else
  echo "WARN: mongod binary not found; cannot run --configCheck" >> "$LOG"
  # as last resort, ensure file contains authorization line
  if ! grep -q "authorization:" "$CFG" 2>/dev/null; then
    cat >> "$CFG" <<EOF
security:
  authorization: enabled
EOF
    echo "WARN: appended security.authorization to config (no binary to validate)" >> "$LOG"
  fi
fi
# start mongod with new config
"$WORKSPACE"/scripts/start-mongod.sh >> "$LOG" 2>&1 || { echo "ERROR: start-mongod failed" >> "$LOG"; exit 31; }
# wait for auth-enabled server to become ready via healthcheck
HEALTH_USER=${ADMIN_USER:-admin}
HEALTH_PASS=${ADMIN_PASS:-adminpass}
for i in $(seq 1 30); do
  if HEALTH_USER="$HEALTH_USER" HEALTH_PASS="$HEALTH_PASS" "$WORKSPACE"/scripts/healthcheck.sh >> "$LOG" 2>&1; then
    echo "INFO: mongod ready after start" >> "$LOG"
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    echo "ERROR: mongod with auth failed to become ready" >> "$LOG"
    "$WORKSPACE"/scripts/stop-mongod.sh >> "$LOG" 2>&1 || true
    echo "VALIDATION: fail" >> "$LOG"
    exit 32
  fi
done
# run an authenticated sample query as dev user
DEV_USER=${DEV_USER:-devuser}
DEV_PASS=${DEV_PASS:-devpass}
if command -v mongo >/dev/null 2>&1; then
  mongo --username "$DEV_USER" --password "$DEV_PASS" --authenticationDatabase dev --eval "db.getSiblingDB('dev').items.find().limit(1).forEach(printjson)" --quiet >> "$LOG" 2>&1 || true
else
  if command -v mongosh >/dev/null 2>&1; then
    mongosh "mongodb://${DEV_USER}:${DEV_PASS}@localhost:27017/dev?authSource=dev" --eval "db.items.find().limit(1).forEach(printjson)" --quiet >> "$LOG" 2>&1 || true
  else
    echo "WARN: neither mongo nor mongosh client found; skipping sample query" >> "$LOG"
  fi
fi
# final healthcheck to confirm auth works
if HEALTH_USER="$HEALTH_USER" HEALTH_PASS="$HEALTH_PASS" "$WORKSPACE"/scripts/healthcheck.sh >> "$LOG" 2>&1; then
  echo "VALIDATION: ok" >> "$LOG"
else
  echo "VALIDATION: fail" >> "$LOG"
fi
# stop mongod
"$WORKSPACE"/scripts/stop-mongod.sh >> "$LOG" 2>&1 || true
echo "VALIDATION: finished $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
exit 0
