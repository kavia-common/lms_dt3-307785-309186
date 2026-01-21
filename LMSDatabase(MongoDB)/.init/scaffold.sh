#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
mkdir -p "$WORKSPACE"/scripts "$WORKSPACE"/data "$WORKSPACE"/logs "$WORKSPACE"/config
# discover absolute binaries
MONGOD_BIN=$(command -v mongod || true)
MONGO_BIN=$(command -v mongo || true)
MONGOSH_BIN=$(command -v mongosh || true)
MONGOIMPORT_BIN=$(command -v mongoimport || true)
: > "$WORKSPACE"/scripts/_bins.env
echo "MONGOD_BIN=${MONGOD_BIN:-}" >> "$WORKSPACE"/scripts/_bins.env
echo "MONGO_BIN=${MONGO_BIN:-}" >> "$WORKSPACE"/scripts/_bins.env
echo "MONGOSH_BIN=${MONGOSH_BIN:-}" >> "$WORKSPACE"/scripts/_bins.env
echo "MONGOIMPORT_BIN=${MONGOIMPORT_BIN:-}" >> "$WORKSPACE"/scripts/_bins.env
chmod 600 "$WORKSPACE"/scripts/_bins.env || true
# minimal mongod.conf for bootstrap (bind 0.0.0.0, dbPath inside workspace)
cat > "$WORKSPACE"/config/mongod.conf <<'YAML'
storage:
  dbPath: __WORKSPACE__/data
systemLog:
  destination: file
  path: __WORKSPACE__/logs/mongod.log
  logAppend: true
net:
  bindIp: 0.0.0.0
  port: 27017
security:
  authorization: ""
YAML
sed -i "s|__WORKSPACE__|${WORKSPACE}|g" "$WORKSPACE"/config/mongod.conf
chmod 640 "$WORKSPACE"/config/mongod.conf || true
# start-mongod
cat > "$WORKSPACE"/scripts/start-mongod.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="'"${WORKSPACE}"'"
source "$WORKSPACE"/scripts/_bins.env || true
CONFIG="$WORKSPACE/config/mongod.conf"
PIDFILE="$WORKSPACE/mongod.pid"
MONGOD="${MONGOD_BIN:-mongod}"
# if pidfile exists verify process is our mongod
if [ -f "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
    CMD=$(tr -d '\0' < /proc/$PID/cmdline || true)
    if echo "$CMD" | grep -q "$(basename "$MONGOD")" && echo "$CMD" | grep -q "$WORKSPACE/data"; then
      echo already-running
      exit 0
    fi
  fi
  rm -f "$PIDFILE" || true
fi
# start mongod as mongodev writing pid to PIDFILE
if [ -z "$MONGOD_BIN" ]; then MONGOD="mongod"; fi
# ensure data dir exists
mkdir -p "$WORKSPACE/data" && chown -R $(id -u):$(id -g) "$WORKSPACE/data" || true
sudo -u mongodev "$MONGOD" --config "$CONFIG" --pidfilepath "$PIDFILE" &
# wait for pidfile
for i in {1..15}; do [ -f "$PIDFILE" ] && break || sleep 1; done
if [ ! -f "$PIDFILE" ]; then echo "ERROR: mongod failed to create pidfile" >&2; exit 21; fi
chown "$(id -un)":"$(id -gn)" "$PIDFILE" || true
BASH
chmod 750 "$WORKSPACE"/scripts/start-mongod.sh
# stop-mongod
cat > "$WORKSPACE"/scripts/stop-mongod.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="'"${WORKSPACE}"'"
source "$WORKSPACE"/scripts/_bins.env || true
PIDFILE="$WORKSPACE/mongod.pid"
MONGO_BIN="${MONGO_BIN:-}"
MONGOSH_BIN="${MONGOSH_BIN:-}"
AUSER="${STOP_USER:-}"
APASS="${STOP_PASS:-}"
if [ -f "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
    CMD=$(tr -d '\0' < /proc/$PID/cmdline || true)
    if echo "$CMD" | grep -q "mongod" && echo "$CMD" | grep -q "$WORKSPACE/data"; then
      # attempt client shutdown if client available
      if [ -n "$MONGO_BIN" ]; then
        if [ -n "$AUSER" ]; then
          echo 'db.getSiblingDB("admin").shutdownServer()' | "$MONGO_BIN" --username "$AUSER" --password "$APASS" --authenticationDatabase admin --quiet localhost:27017 || true
        else
          echo 'db.getSiblingDB("admin").shutdownServer()' | "$MONGO_BIN" --quiet localhost:27017 || true
        fi
      elif [ -n "$MONGOSH_BIN" ]; then
        if [ -n "$AUSER" ]; then
          "$MONGOSH_BIN" --quiet "mongodb://${AUSER}:${APASS}@localhost:27017/admin" --eval 'db.getSiblingDB("admin").shutdownServer()' || true
        else
          "$MONGOSH_BIN" --quiet "mongodb://localhost:27017" --eval 'db.getSiblingDB("admin").shutdownServer()' || true
        fi
      fi
      sleep 1 || true
      if [ -d "/proc/$PID" ]; then kill -TERM "$PID" || true; sleep 1 || true; fi
    fi
  fi
  rm -f "$PIDFILE" || true
fi
BASH
chmod 750 "$WORKSPACE"/scripts/stop-mongod.sh
# bootstrap-users
cat > "$WORKSPACE"/scripts/bootstrap-users.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="'"${WORKSPACE}"'"
source "$WORKSPACE"/scripts/_bins.env || true
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-adminpass}"
DEV_USER="${DEV_USER:-devuser}"
DEV_PASS="${DEV_PASS:-devpass}"
# only run if unauthenticated healthcheck succeeds (auth disabled)
if "$WORKSPACE"/scripts/healthcheck.sh >/dev/null 2>&1; then
  JS="db.getSiblingDB('admin').createUser({user: '${ADMIN_USER}', pwd: '${ADMIN_PASS}', roles:[{role:'root', db:'admin'}]}); db.getSiblingDB('dev').createUser({user:'${DEV_USER}', pwd:'${DEV_PASS}', roles:[{role:'readWrite', db:'dev'}]});"
  if [ -n "${MONGO_BIN}" ]; then
    echo "$JS" | "${MONGO_BIN}" --quiet localhost:27017 || true
  elif [ -n "${MONGOSH_BIN}" ]; then
    "${MONGOSH_BIN}" --quiet "mongodb://localhost:27017" --eval "$JS" || true
  else
    echo "no mongo client available to create users" >&2 || true
  fi
else
  echo "bootstrap-users: server requires auth or is unreachable; skipping" >&2
fi
BASH
chmod 750 "$WORKSPACE"/scripts/bootstrap-users.sh
# restore-sample
cat > "$WORKSPACE"/scripts/restore-sample.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="'"${WORKSPACE}"'"
source "$WORKSPACE"/scripts/_bins.env || true
TIMEOUT=${RESTORE_TIMEOUT:-30}
for i in $(seq 1 $TIMEOUT); do "$WORKSPACE"/scripts/healthcheck.sh >/dev/null 2>&1 && break || sleep 1; if [ "$i" -eq "$TIMEOUT" ]; then echo "restore-sample: mongod not ready"; exit 21; fi; done
if [ -f "$WORKSPACE/data/sample.json" ]; then
  if [ -z "${MONGOIMPORT_BIN}" ]; then echo "mongoimport not found" > "$WORKSPACE"/logs/restore-error.log; exit 23; fi
  "${MONGOIMPORT_BIN}" --db dev --collection items --jsonArray --file "$WORKSPACE/data/sample.json" --quiet || true
fi
BASH
chmod 750 "$WORKSPACE"/scripts/restore-sample.sh
# healthcheck
cat > "$WORKSPACE"/scripts/healthcheck.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="'"${WORKSPACE}"'"
source "$WORKSPACE"/scripts/_bins.env || true
TIMEOUT=${HEALTH_TIMEOUT:-10}
USER="${HEALTH_USER:-}"
PASS="${HEALTH_PASS:-}"
if [ -n "${MONGO_BIN}" ]; then
  CLIENT_CMD="$MONGO_BIN --quiet"
else
  CLIENT_CMD="${MONGOSH_BIN:-mongosh} --quiet"
fi
for i in $(seq 1 $TIMEOUT); do
  if [ -n "$USER" ] && [ -n "${MONGO_BIN}" ]; then $MONGO_BIN --username "$USER" --password "$PASS" --authenticationDatabase admin --eval "db.runCommand({ping:1})" >/dev/null 2>&1 && exit 0 || :; fi
  if [ -n "$USER" ] && [ -n "${MONGOSH_BIN}" ]; then $MONGOSH_BIN --quiet "mongodb://${USER}:${PASS}@localhost:27017/admin" --eval "db.runCommand({ping:1})" >/dev/null 2>&1 && exit 0 || :; fi
  if [ -z "$USER" ] && [ -n "${MONGO_BIN}" ]; then $MONGO_BIN --eval "db.runCommand({ping:1})" --quiet >/dev/null 2>&1 && exit 0 || :; fi
  if [ -z "$USER" ] && [ -n "${MONGOSH_BIN}" ]; then $MONGOSH_BIN --quiet "mongodb://localhost:27017" --eval "db.runCommand({ping:1})" >/dev/null 2>&1 && exit 0 || :; fi
  sleep 1
done
exit 2
BASH
chmod 750 "$WORKSPACE"/scripts/healthcheck.sh
chown -R "$(id -un)":"$(id -gn)" "$WORKSPACE"/scripts "$WORKSPACE"/data "$WORKSPACE"/logs || true
echo "scaffold: scripts written to $WORKSPACE/scripts"
