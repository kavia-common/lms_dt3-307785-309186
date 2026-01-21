#!/usr/bin/env bash
set -euo pipefail
# scaffold: create workspace dirs, minimal mongod configs, and helper scripts
WS="/home/kavia/workspace-code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
ETC="$WS/etc"
DATADIR="$WS/var/lib/mongo"
LOGDIR="$WS/var/log"
BINDIR="$WS/bin"
sudo mkdir -p "$ETC" "$DATADIR" "$LOGDIR" "$BINDIR"
# detect DB runtime user
DB_USER=""
if getent passwd mongodb >/dev/null 2>&1; then DB_USER=mongodb; elif getent passwd mongod >/dev/null 2>&1; then DB_USER=mongod; fi
# verify if we can start mongod as DB_USER; fall back to root if not
START_AS_USER=0
if [ -n "${DB_USER}" ]; then
  if sudo -u "$DB_USER" bash -c 'command -v mongod >/dev/null 2>&1 && mongod --version >/dev/null 2>&1' >/dev/null 2>&1; then START_AS_USER=1; fi
fi
if [ "$START_AS_USER" -ne 1 ]; then DB_USER=root; fi
# ensure ownership for data and log dirs to the chosen user
sudo mkdir -p "$DATADIR" "$LOGDIR" && sudo chown -R "$DB_USER":"$DB_USER" "$DATADIR" "$LOGDIR"
# write main mongod.conf (authorization enabled for normal start)
cat > "$ETC/mongod.conf" <<EOF
storage:
  dbPath: "$DATADIR"
  wiredTiger:
    engineConfig:
      cacheSizeGB: 0.25
systemLog:
  destination: "console"
net:
  bindIp: 0.0.0.0
  port: 27017
processManagement:
  fork: false
security:
  authorization: "enabled"
replication:
  oplogSizeMB: 64
EOF
# write init mongod.conf for bootstrap (auth disabled, bind to localhost)
cat > "$ETC/mongod.init.conf" <<EOF
storage:
  dbPath: "$DATADIR"
systemLog:
  destination: "console"
net:
  bindIp: 127.0.0.1
  port: 27017
processManagement:
  fork: false
security:
  authorization: "disabled"
EOF
# ensure config ownership
sudo chown "$DB_USER":"$DB_USER" "$ETC/mongod.conf" "$ETC/mongod.init.conf" 2>/dev/null || true
# bootstrap script: start temporary mongod, create users idempotently, shutdown
cat > "$BINDIR/bootstrap-mongo.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace-code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
ETC="$WS/etc"
DATADIR="$WS/var/lib/mongo"
LOGDIR="$WS/var/log"
ROOT_USER="${MONGO_INITDB_ROOT_USERNAME:-admin}"
ROOT_PASS="${MONGO_INITDB_ROOT_PASSWORD:-adminpass}"
DEV_USER="${MONGO_DEV_USER:-lms_dev}"
DEV_PASS="${MONGO_DEV_PASS:-devpass}"
MARKER="$DATADIR/.users_created"
[ -f "$MARKER" ] && exit 0
# start init mongod as the owner of config (or root)
OWNER=$(stat -c '%U' "$ETC/mongod.init.conf" 2>/dev/null || echo root)
sudo -u "$OWNER" bash -c "mongod --config '$ETC/mongod.init.conf' >>'$LOGDIR/mongod.init.log' 2>&1 &"
MONGOD_PID=$!
# wait for readiness
for i in {1..60}; do
  if command -v mongosh >/dev/null 2>&1; then
    mongosh --quiet --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1 && break
  else
    mongo --quiet --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1 && break
  fi
  sleep 0.5
done
# create users idempotently
JS="var adminDb = db.getSiblingDB('admin'); if(!adminDb.getUser('$ROOT_USER')){ adminDb.createUser({user:'$ROOT_USER', pwd:'$ROOT_PASS', roles:[{role:'root', db:'admin'}]}); } var devDb = db.getSiblingDB('lms_dev'); if(!devDb.getUser('$DEV_USER')){ devDb.createUser({user:'$DEV_USER', pwd:'$DEV_PASS', roles:[{role:'readWrite', db:'lms_dev'}]}); }"
if command -v mongosh >/dev/null 2>&1; then
  mongosh --quiet --host 127.0.0.1 --port 27017 --eval "$JS"
else
  mongo --quiet --host 127.0.0.1 --port 27017 --eval "$JS"
fi
# attempt authenticated shutdown
if command -v mongosh >/dev/null 2>&1; then
  mongosh --quiet --host 127.0.0.1 --port 27017 -u "$ROOT_USER" -p "$ROOT_PASS" --authenticationDatabase admin --eval "db.getSiblingDB('admin').shutdownServer()" || true
else
  mongo --quiet --host 127.0.0.1 --port 27017 -u "$ROOT_USER" -p "$ROOT_PASS" --authenticationDatabase admin --eval "db.getSiblingDB('admin').shutdownServer()" || true
fi
# wait for process to exit
for i in {1..20}; do
  if ! kill -0 "$MONGOD_PID" 2>/dev/null; then break; fi
  sleep 0.5
done
sudo touch "$MARKER" || true
sudo chown $(stat -c '%U' "$ETC/mongod.conf" 2>/dev/null || echo root):$(stat -c '%G' "$ETC/mongod.conf" 2>/dev/null || echo root) "$MARKER" 2>/dev/null || true
BASH
sudo chmod +x "$BINDIR/bootstrap-mongo.sh"
# start script: exec mongod in foreground so container captures logs
cat > "$BINDIR/start-mongo.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace-code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
ETC="$WS/etc"
LOGDIR="$WS/var/log"
sudo mkdir -p "$LOGDIR"
exec mongod --config "$ETC/mongod.conf"
BASH
sudo chmod +x "$BINDIR/start-mongo.sh"
# healthcheck script
cat > "$BINDIR/healthcheck-mongo.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
HOST=${1:-127.0.0.1}
PORT=${2:-27017}
if [ -n "${MONGO_CLI:-}" ] && command -v ${MONGO_CLI##*/} >/dev/null 2>&1; then
  ${MONGO_CLI##*/} --quiet --host "$HOST" --port "$PORT" --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1 && exit 0 || exit 1
elif command -v mongosh >/dev/null 2>&1; then
  mongosh --quiet --host "$HOST" --port "$PORT" --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1 && exit 0 || exit 1
else
  mongo --quiet --host "$HOST" --port "$PORT" --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1 && exit 0 || exit 1
fi
BASH
sudo chmod +x "$BINDIR/healthcheck-mongo.sh"
# mongodump helper with optional output dir
cat > "$BINDIR/mongo-dump.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace-code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
OUT_DIR=${1:-"$WS/dumps/$(date +%Y%m%d%H%M%S)"}
mkdir -p "$OUT_DIR"
HOST=${2:-127.0.0.1}
PORT=${3:-27017}
USER=${MONGO_INITDB_ROOT_USERNAME:-admin}
PASS=${MONGO_INITDB_ROOT_PASSWORD:-adminpass}
if command -v mongodump >/dev/null 2>&1; then
  mongodump --host "$HOST" --port "$PORT" --username "$USER" --password "$PASS" --out "$OUT_DIR" --quiet
else
  echo "mongodump not available" >&2; exit 2
fi
BASH
sudo chmod +x "$BINDIR/mongo-dump.sh"
# ensure bin ownership for invoking user
sudo chown -R $(id -u):$(id -g) "$BINDIR"
# print path to main config for verification
printf "%s\n" "$ETC/mongod.conf"
