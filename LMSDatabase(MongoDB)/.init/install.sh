#!/usr/bin/env bash
set -euo pipefail
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi
DEV_MODE=${DEV_MODE:-true}
MONGOD_CONF=${MONGOD_CONF:-/etc/mongod-dev.conf}
# verify package and persist if present
if dpkg -l | grep -q '^ii\s\+mongodb-org\b'; then
  dpkg -l | grep '^ii\s\+mongodb-org' | head -n1 | awk '{print $2 " " $3}' > "${WORKSPACE}/.mongodb_pkg" || true
else
  echo "WARN: mongodb-org package not found via dpkg; mongod binary may still exist" >&2
fi
# binaries
command -v mongod >/dev/null 2>&1 || { echo "ERROR: mongod binary not found; ensure mongodb-org is installed" >&2; exit 2; }
if command -v mongosh >/dev/null 2>&1; then MONGO_SHELL="mongosh"; elif command -v mongo >/dev/null 2>&1; then MONGO_SHELL="mongo"; else echo "ERROR: neither mongosh nor mongo shell found" >&2; exit 3; fi
# helper utilities check (ss, nc, timeout, tail)
for util in ss nc timeout tail; do command -v "$util" >/dev/null 2>&1 || { echo "ERROR: required utility '$util' missing" >&2; exit 4; }; done
# create data/log dirs and set ownership
${SUDO} mkdir -p /data/db /var/log/mongodb
# detect service user
if id -u mongod >/dev/null 2>&1; then MONGO_USER=mongod; elif id -u mongodb >/dev/null 2>&1; then MONGO_USER=mongodb; else MONGO_USER="$(id -u):$(id -g)"; fi
${SUDO} chown -R "${MONGO_USER}" /data/db /var/log/mongodb || true
${SUDO} chmod 0755 /data/db /var/log/mongodb || true
# back up distro config if present
if [ -f /etc/mongod.conf ]; then
  TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
  ${SUDO} cp -n /etc/mongod.conf /etc/mongod.conf.orig.${TIMESTAMP} || true
fi
# create development override config if not present
if [ ! -f "${MONGOD_CONF}" ]; then
  ${SUDO} tee "${MONGOD_CONF}" > /dev/null <<EOF
# Development mongod override (DEV_MODE=${DEV_MODE})
storage:
  dbPath: /data/db
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
net:
  bindIp: $( [ "${DEV_MODE}" = "true" ] && echo "0.0.0.0" || echo "127.0.0.1" )
  port: 27017
processManagement:
  fork: false
# Note: auth is disabled in DEV_MODE=true. To enable secure mode set DEV_MODE=false and provide an appropriate /etc/mongod.conf
EOF
  ${SUDO} chmod 0644 "${MONGOD_CONF}" || true
  ${SUDO} chown root:root "${MONGOD_CONF}" || true
fi
# sanity check mongod binary
mongod --version >/dev/null 2>&1 || { echo "ERROR: mongod --version failed; library mismatch possible" >&2; exit 5; }
# persist detected shell and config path for downstream steps
mkdir -p "${WORKSPACE}"
printf '%s' "${MONGO_SHELL}" > "${WORKSPACE}/.mongo_shell" || true
printf '%s' "${MONGOD_CONF}" > "${WORKSPACE}/.mongod_conf_path" || true
exit 0
