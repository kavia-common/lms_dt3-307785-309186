#!/usr/bin/env bash
set -euo pipefail
WS="/home/kavia/workspace-code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
sudo mkdir -p "$WS" >/dev/null
# detect mongo client
MONGO_CLI=""
if command -v mongosh >/dev/null 2>&1; then MONGO_CLI=$(command -v mongosh)
elif command -v mongo >/dev/null 2>&1; then MONGO_CLI=$(command -v mongo)
fi
if [ -n "$MONGO_CLI" ]; then
  # print version if possible
  "$MONGO_CLI" --version 2>/dev/null || true
fi
# ensure mongodump available (install tools only if missing)
if ! command -v mongodump >/dev/null 2>&1; then
  # attempt to install mongodb-org-tools non-interactively; tolerates apt failure
  if sudo apt-get update -q >/dev/null 2>&1 && sudo apt-get install -y -q mongodb-org-tools >/dev/null 2>&1; then
    command -v mongodump >/dev/null 2>&1 || true
  else
    echo "WARNING: cannot install mongodb-org-tools (apt failed)" >&2
  fi
fi
# write profile only if absent to avoid overwriting user settings
PROFILE=/etc/profile.d/mongo-env.sh
if [ ! -f "$PROFILE" ]; then
  sudo tee "$PROFILE" >/dev/null <<'EOF'
# dev-only Mongo defaults (override in your env)
export MONGO_INITDB_ROOT_USERNAME="${MONGO_INITDB_ROOT_USERNAME:-admin}"
export MONGO_INITDB_ROOT_PASSWORD="${MONGO_INITDB_ROOT_PASSWORD:-adminpass}"
export MONGO_DEV_USER="${MONGO_DEV_USER:-lms_dev}"
export MONGO_DEV_PASS="${MONGO_DEV_PASS:-devpass}"
# path to mongo client; preserved if MONGO_CLI already set in environment
export MONGO_CLI="${MONGO_CLI:-$(command -v mongosh || command -v mongo || true)}"
EOF
  sudo chmod 644 "$PROFILE"
fi
# export detected MONGO_CLI for current shell session as well
if [ -n "${MONGO_CLI:-}" ]; then
  export MONGO_CLI
fi
