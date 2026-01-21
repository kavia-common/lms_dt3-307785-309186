#!/usr/bin/env bash
set -euo pipefail
# Execute provided scaffold generation into workspace
WORKSPACE="/home/kavia/workspace/code-generation/lms_dt3-307785-309186/LMSDatabase(MongoDB)"
SCRIPTDIR="${WORKSPACE}/scripts"
mkdir -p "${SCRIPTDIR}" && chmod 0755 "${SCRIPTDIR}"
FORCE=${SCAFFOLD_FORCE:-0}
MONGO_SH="$(cat "${WORKSPACE}/.mongo_shell" 2>/dev/null || echo "mongo")"
MONGOD_CONF="$(cat "${WORKSPACE}/.mongod_conf_path" 2>/dev/null || echo "/etc/mongod-dev.conf")"
START="${SCRIPTDIR}/start-mongod.sh"
if [ ! -f "${START}" ] || [ "${FORCE}" -eq 1 ]; then
  cat > "${START}" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
# optional: run as specific user if MONGO_RUN_AS is set (username)
if [ -n "${MONGO_RUN_AS:-}" ] && command -v runuser >/dev/null 2>&1; then
  exec runuser -u "${MONGO_RUN_AS}" -- mongod --config "${MONGOD_CONF}"
else
  exec mongod --config "${MONGOD_CONF}"
fi
BASH
  chmod 0755 "${START}"
fi
HEALTH="${SCRIPTDIR}/healthcheck.sh"
if [ ! -f "${HEALTH}" ] || [ "${FORCE}" -eq 1 ]; then
  cat > "${HEALTH}" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/mongodb/mongod.log
# use embedded shell
MONGO_SH="${MONGO_SH}"
if [ "${MONGO_SH}" = "mongosh" ]; then
  ${MONGO_SH} --quiet --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1 || { echo "HEALTH: ${MONGO_SH} failed to ping" >&2; tail -n 20 "$LOG" >&2 || true; exit 2; }
else
  ${MONGO_SH} --quiet --eval 'db.runCommand({ ping: 1 })' >/dev/null 2>&1 || { echo "HEALTH: ${MONGO_SH} failed to ping" >&2; tail -n 20 "$LOG" >&2 || true; exit 2; }
fi
exit 0
BASH
  chmod 0755 "${HEALTH}"
fi
README="${WORKSPACE}/README.md"
if [ ! -f "${README}" ] || [ "${FORCE}" -eq 1 ]; then
  cat > "${README}" <<'MD'
Workspace for LMSDatabase(MongoDB)
- start: scripts/start-mongod.sh (runs mongod in foreground)
  * Optional env: MONGO_RUN_AS=username to drop privileges via runuser
  * Optional env: MONGOD_CONF to override config path
- healthcheck: scripts/healthcheck.sh (uses detected shell mongosh or mongo)
- DEV_MODE=true (default) binds 0.0.0.0 and disables auth for development convenience. Set DEV_MODE=false and provide a secure /etc/mongod.conf to enable production-like behavior.
- Use SCAFFOLD_FORCE=1 to regenerate scripts
MD
  chmod 0644 "${README}"
fi
exit 0
