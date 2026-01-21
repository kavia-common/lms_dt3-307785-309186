#!/usr/bin/env bash
set -euo pipefail
WORKSPACE=${WORKSPACE:-/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)}
# create data dir and set ownership to mongod/mongodb if present
sudo mkdir -p /data/db
MONGOD_USER=""
if id -u mongod >/dev/null 2>&1; then MONGOD_USER=mongod; elif id -u mongodb >/dev/null 2>&1; then MONGOD_USER=mongodb; fi
if [ -n "${MONGOD_USER}" ]; then sudo chown -R "${MONGOD_USER}:${MONGOD_USER}" /data/db; else sudo chown -R "$(id -u):$(id -g)" /data/db; fi
sudo chmod 700 /data/db
# check for lockfiles
if [ -e /data/db/WiredTiger.lock ] || [ -e /data/db/mongod.lock ]; then
  if [ "${DEV_FORCE_REUSE:-0}" != "1" ]; then echo "ERROR: /data/db contains mongod lock file; set DEV_FORCE_REUSE=1 to proceed with existing DB files" >&2; exit 4; fi
fi
# detect running mongod
if [ -f /var/run/mongodb/mongod.pid ]; then PID=$(cat /var/run/mongodb/mongod.pid 2>/dev/null || true); fi
if pgrep -f '[m]ongod' >/dev/null 2>&1 || ( [ -n "${PID:-}" ] && kill -0 "$PID" >/dev/null 2>&1 ); then
  echo "INFO: mongod process already present; set DEV_FORCE_REUSE=1 to reuse" >&2
fi
# verify mongod and shell
if ! command -v mongod >/dev/null 2>&1; then echo "ERROR: mongod not found in PATH" >&2; exit 2; fi
if command -v mongosh >/dev/null 2>&1; then MONGO_SHELL="mongosh"; elif command -v mongo >/dev/null 2>&1; then MONGO_SHELL="mongo"; else echo "ERROR: mongosh/mongo not found" >&2; exit 3; fi
# write workspace-local env (do not change workspace dir permissions to avoid failures)
mkdir -p "$WORKSPACE" || true
# write .mongo_env with restrictive perms; avoid trying to chmod workspace directory itself
TMP_ENV=$(mktemp)
cat > "$TMP_ENV" <<EOF
MONGO_INITDB_DATABASE=lmstest
MONGO_SHELL=${MONGO_SHELL}
# DEV_ALLOW_NETWORK=1 to bind 0.0.0.0; DEV_FORCE_REUSE=1 to reuse existing mongod or DB files
EOF
chmod 600 "$TMP_ENV"
mv -f "$TMP_ENV" "$WORKSPACE/.mongo_env"
# persist lightweight non-secret globals for interactive shells
PROFILE=/etc/profile.d/lms_mongo.sh
sudo bash -c "cat > ${PROFILE} <<'P'
# LMS mongo workspace helpers (non-secret)
export LMS_WORKSPACE=\"${WORKSPACE}\"
export MONGO_SHELL=\"${MONGO_SHELL}\"
P
" && sudo chmod 644 "$PROFILE"
# summary
echo "Wrote $WORKSPACE/.mongo_env and $PROFILE"
