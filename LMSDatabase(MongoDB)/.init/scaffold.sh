#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
SCRIPTS_DIR="$WORKSPACE/scripts"
mkdir -p "$SCRIPTS_DIR" "$WORKSPACE/config"
# minimal mongod.conf
cat > "$SCRIPTS_DIR/mongod.conf" <<'EOF'
storage:
  dbPath: /data/db
systemLog:
  destination: file
  path: /data/db/mongod.log
  logAppend: true
net:
  bindIp: 127.0.0.1
  port: 27017
processManagement:
  pidFilePath: /tmp/mongod.pid
EOF
# start_mongod.sh
cat > "$SCRIPTS_DIR/start_mongod.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
PIDFILE="/tmp/mongod_dev.pid"
MONGOD_BIN="$(command -v mongod || true)"
if [ -z "$MONGOD_BIN" ]; then echo "mongod not found" >&2; exit 2; fi
mkdir -p /data/db
# run mongod in foreground, write pidfile
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null || echo 0)" >/dev/null 2>&1; then
  exit 0
fi
ARGS=(--config "$WORKSPACE/scripts/mongod.conf")
if [ "${MONGO_BIND_ALL:-0}" = "1" ]; then ARGS+=(--bind_ip_all); fi
# exec mongod
"$MONGOD_BIN" "${ARGS[@]}" &
echo "$!" >"$PIDFILE"
wait "$!"
EOF
chmod +x "$SCRIPTS_DIR/start_mongod.sh"
# healthcheck.sh
cat > "$SCRIPTS_DIR/healthcheck.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
# prefer mongosh
if command -v mongosh >/dev/null 2>&1; then
  mongosh --quiet --eval 'db.adminCommand({ping:1})' || exit 2
else
  mongo --quiet --eval 'db.adminCommand({ping:1})' || exit 2
fi
EOF
chmod +x "$SCRIPTS_DIR/healthcheck.sh"
# init_seed.sh
cat > "$SCRIPTS_DIR/init_seed.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
CREDFILE="$WORKSPACE/config/.mongo_dev_creds"
# if creds file exists, source it for username/password
if [ -f "$CREDFILE" ]; then
  # shellcheck disable=SC1090
  . "$CREDFILE" || true
fi
# build auth flags
AUTH_FLAGS=()
if [ -n "${MONGO_INITDB_ROOT_USERNAME:-}" ] && [ -n "${MONGO_INITDB_ROOT_PASSWORD:-}" ]; then
  AUTH_FLAGS+=(--username "$MONGO_INITDB_ROOT_USERNAME" --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin)
fi
# use mongosh if available
if command -v mongosh >/dev/null 2>&1; then
  mongosh "${AUTH_FLAGS[@]}" --eval 'db = db.getSiblingDB("lms_dev"); db.users.insertOne({seeded:true});' || true
else
  mongo "${AUTH_FLAGS[@]}" --eval 'db = db.getSiblingDB("lms_dev"); db.users.insertOne({seeded:true});' || true
fi
EOF
chmod +x "$SCRIPTS_DIR/init_seed.sh"
