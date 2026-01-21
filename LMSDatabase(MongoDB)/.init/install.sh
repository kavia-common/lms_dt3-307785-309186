#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
mkdir -p "$WORKSPACE"/logs "$WORKSPACE"/scripts
MONGOD_BIN=$(command -v mongod || true)
MONGO_BIN=$(command -v mongo || true)
MONGOSH_BIN=$(command -v mongosh || true)
MONGOIMPORT_BIN=$(command -v mongoimport || true)
if [ -z "$MONGOD_BIN" ]; then echo "ERROR: mongod not found" > "$WORKSPACE"/logs/deps-check.log && exit 12; fi
CLIENT=""
if [ -n "$MONGO_BIN" ]; then CLIENT=mongo
elif [ -n "$MONGOSH_BIN" ]; then CLIENT=mongosh
else echo "ERROR: no mongo client found" > "$WORKSPACE"/logs/deps-check.log && exit 11
fi
# record absolute paths and versions
{ echo "mongod: $MONGOD_BIN"; "$MONGOD_BIN" --version 2>&1 | head -n1; echo "client: $CLIENT"; if [ -n "$MONGOIMPORT_BIN" ]; then echo "mongoimport: $MONGOIMPORT_BIN"; "$MONGOIMPORT_BIN" --version 2>&1 | head -n1; fi; } > "$WORKSPACE"/logs/deps-check.log
# write bin stubs for scaffold to consume
cat > "$WORKSPACE"/scripts/_bins.env <<EOF
MONGOD_BIN=$MONGOD_BIN
MONGO_BIN=$MONGO_BIN
MONGOSH_BIN=$MONGOSH_BIN
MONGOIMPORT_BIN=$MONGOIMPORT_BIN
EOF
chmod 600 "$WORKSPACE"/scripts/_bins.env || true
# check executability by mongodev (best-effort)
if sudo -u mongodev test -x "$MONGOD_BIN" >/dev/null 2>&1; then echo "mongod executable by mongodev" >> "$WORKSPACE"/logs/deps-check.log; else echo "WARN: mongod not executable by mongodev user" >> "$WORKSPACE"/logs/deps-check.log; fi
exit 0
