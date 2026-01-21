Workspace for LMSDatabase(MongoDB)
- start: scripts/start-mongod.sh (runs mongod in foreground)
  * Optional env: MONGO_RUN_AS=username to drop privileges via runuser
  * Optional env: MONGOD_CONF to override config path
- healthcheck: scripts/healthcheck.sh (uses detected shell mongosh or mongo)
- DEV_MODE=true (default) binds 0.0.0.0 and disables auth for development convenience. Set DEV_MODE=false and provide a secure /etc/mongod.conf to enable production-like behavior.
- Use SCAFFOLD_FORCE=1 to regenerate scripts
