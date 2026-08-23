#!/bin/sh
# Creates a new local game-server "shard" -- a second, independent
# DreamDaemon instance on THIS machine, sharing the same central database
# as the main server, but starting with completely fresh local data
# (turfs/objects/machinery/local DB). See docs/cross_server_persistence.md.
#
# Two new Docker containers, never touching aurora-db/aurora-central-db:
#   aurora-shard-<ShardId>-db      local MariaDB, fresh schema, NOT
#                                   published to the host.
#   aurora-shard-<ShardId>-server  the game server, built from
#                                   docker/shard.Dockerfile. Repo bind-
#                                   mounted read-only; only shards/<ShardId>/
#                                   and backups/shards/<ShardId>/ are
#                                   writable. Published on --port.
#
# Native translation of db_central_add_shard.ps1 -- no PowerShell
# dependency. See that script for full documentation of the design.
#
# Usage:
#   db_central_add_shard.sh --shard-id frontier-shard-1 --port <port>
#   db_central_add_shard.sh --shard-id frontier-shard-1 --port <port> --whatif

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

SHARD_ID=""
PORT=""
WHATIF=0

while [ $# -gt 0 ]; do
	case "$1" in
		--shard-id) SHARD_ID="$2"; shift 2 ;;
		--port) PORT="$2"; shift 2 ;;
		--whatif) WHATIF=1; shift ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$SHARD_ID" ] || [ -z "$PORT" ]; then
	echo "Usage: $0 --shard-id <name> --port <port> [--whatif]"
	exit 1
fi

case "$SHARD_ID" in
	*[!A-Za-z0-9_-]*|"")
		echo "shard-id must be letters, digits, hyphens, or underscores only -- got '$SHARD_ID'."
		exit 1
		;;
esac
case "$PORT" in
	''|*[!0-9]*)
		echo "Port must be a plain integer -- got '$PORT'."
		exit 1
		;;
esac

if [ ! -f "$CONFIG_PATH" ]; then
	echo "config/central_dbconfig_admin.txt not found -- run db_central_setup first."
	exit 1
fi

ADDRESS="localhost"; PORT_DB="3306"; DATABASE="aurora_central"; LOGIN=""; PASSWORD=""
while IFS= read -r line || [ -n "$line" ]; do
	t=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	[ -z "$t" ] && continue
	case "$t" in \#*) continue ;; esac
	key=$(printf '%s' "$t" | cut -d' ' -f1 | tr 'A-Z' 'a-z')
	value=$(printf '%s' "$t" | cut -s -d' ' -f2-)
	case "$key" in
		address) ADDRESS="$value" ;;
		port) PORT_DB="$value" ;;
		database) DATABASE="$value" ;;
		login) LOGIN="$value" ;;
		password) PASSWORD="$value" ;;
	esac
done < "$CONFIG_PATH"

if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
	echo "config/central_dbconfig_admin.txt is missing LOGIN/PASSWORD -- fill those in first."
	exit 1
fi

CLIENT=$(command -v mariadb || command -v mysql || true)
if [ -z "$CLIENT" ]; then
	echo "No 'mariadb' or 'mysql' client found on PATH."
	exit 1
fi

# ── Uniqueness checks ────────────────────────────────────────────────────────

EXISTING=$(printf '%s' "SELECT shard_id FROM \`ss13_shards\` WHERE shard_id = '$SHARD_ID' OR port = $PORT;" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" -N 2>&1)
if [ $? -ne 0 ]; then
	echo "Failed to check ss13_shards for conflicts:"
	echo "  $EXISTING"
	exit 1
fi
if [ -n "$(printf '%s' "$EXISTING" | tr -d '[:space:]')" ]; then
	echo "ShardId '$SHARD_ID' or port $PORT is already registered in ss13_shards."
	exit 1
fi

DB_CONTAINER="aurora-shard-$SHARD_ID-db"
SERVER_CONTAINER="aurora-shard-$SHARD_ID-server"
for name in "$DB_CONTAINER" "$SERVER_CONTAINER"; do
	if [ -n "$(docker ps -a --filter "name=^/${name}\$" --format '{{.Names}}')" ]; then
		echo "A container named '$name' already exists. Remove it first (db_central_remove_shard.sh) or pick a different shard-id."
		exit 1
	fi
done

echo "Creating shard '$SHARD_ID' on port $PORT..."
if [ "$WHATIF" -eq 1 ]; then
	echo "--whatif: would create containers '$DB_CONTAINER' and '$SERVER_CONTAINER', provision a central DB login named '$SHARD_ID', and register it in ss13_shards."
	exit 0
fi

# ── Docker network ───────────────────────────────────────────────────────────

if ! docker network inspect aurora-shards-net >/dev/null 2>&1; then
	echo "Creating aurora-shards-net Docker network..."
	docker network create aurora-shards-net >/dev/null
fi

# ── Runtime image -- built once, reused by every shard ──────────────────────

if [ -z "$(docker images -q aurora-shard-runtime:latest)" ]; then
	echo "Building aurora-shard-runtime image (first shard only, this takes a while)..."
	docker build -t aurora-shard-runtime:latest -f "$ROOT/docker/shard.Dockerfile" "$ROOT"
	if [ $? -ne 0 ]; then
		echo "Image build failed."
		exit 1
	fi
fi

# ── Central DB login for this shard ─────────────────────────────────────────
# Inlined rather than calling db_central_add_server.sh as a subprocess -- same
# reasoning as db_central_add_shard.ps1, see that script's comment.

SHARD_CENTRAL_PASSWORD=$(LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 32)

TABLES=$(printf '%s' "SELECT table_name FROM information_schema.tables WHERE table_schema = '$DATABASE' AND table_name != 'ss13_central_admins';" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" -N 2>&1)

GRANT_SQL="CREATE USER IF NOT EXISTS '$SHARD_ID'@'%' IDENTIFIED BY '$SHARD_CENTRAL_PASSWORD';
GRANT SELECT ON \`$DATABASE\`.* TO '$SHARD_ID'@'%';"
for table in $TABLES; do
	GRANT_SQL="$GRANT_SQL
GRANT INSERT, UPDATE, DELETE ON \`$DATABASE\`.\`$table\` TO '$SHARD_ID'@'%';"
done
GRANT_SQL="$GRANT_SQL
FLUSH PRIVILEGES;"

GRANT_RESULT=$(printf '%s' "$GRANT_SQL" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" 2>&1)
if [ $? -ne 0 ]; then
	echo "Failed to provision this shard's central DB login:"
	echo "  $GRANT_RESULT"
	exit 1
fi

# ── Shard-local config/data directories ─────────────────────────────────────

SHARD_DIR="$ROOT/shards/$SHARD_ID"
SHARD_CONFIG_DIR="$SHARD_DIR/config"
SHARD_DATA_DIR="$SHARD_DIR/data"
mkdir -p "$SHARD_CONFIG_DIR" "$SHARD_DATA_DIR"

LOCAL_DB_PASSWORD="aurora"

cat > "$SHARD_CONFIG_DIR/dbconfig.txt" <<EOF
# MySQL Connection Configuration -- generated by db_central_add_shard.sh

ADDRESS $DB_CONTAINER
PORT 3306
DATABASE aurora_persist
LOGIN aurora
PASSWORD $LOCAL_DB_PASSWORD
EOF

# The admin config's ADDRESS is written for reaching central-db from THIS
# HOST (typically "localhost", since central-db is published to the host
# on its own port) -- but the shard's server container is not the host.
# "localhost" inside that container means the container itself, not
# central-db, which would silently break central connectivity entirely.
# host.docker.internal is Docker's own route back to the host (built into
# Docker Desktop; --add-host below adds it on native Linux Docker too), so
# the container reaches central-db the same way the host does: via its
# published port. Anything OTHER than localhost/127.0.0.1 (a real external
# hostname/IP for a genuinely remote central DB) is left unchanged.
CENTRAL_ADDRESS_FOR_SHARD="$ADDRESS"
if [ "$CENTRAL_ADDRESS_FOR_SHARD" = "localhost" ] || [ "$CENTRAL_ADDRESS_FOR_SHARD" = "127.0.0.1" ]; then
	CENTRAL_ADDRESS_FOR_SHARD="host.docker.internal"
fi

cat > "$SHARD_CONFIG_DIR/central_dbconfig.txt" <<EOF
# Central MySQL Connection Configuration -- generated by db_central_add_shard.sh

ADDRESS $CENTRAL_ADDRESS_FOR_SHARD
PORT $PORT_DB
DATABASE $DATABASE
LOGIN $SHARD_ID
PASSWORD $SHARD_CENTRAL_PASSWORD
EOF

sed \
	-e 's/^#\+\s*SQL_ENABLED/SQL_ENABLED/' \
	-e 's/^#\+\s*CENTRAL_SQL_ENABLED/CENTRAL_SQL_ENABLED/' \
	"$ROOT/config/config.txt" > "$SHARD_CONFIG_DIR/config.txt.tmp"
if grep -q '^#*\s*CENTRAL_SERVER_ID' "$SHARD_CONFIG_DIR/config.txt.tmp"; then
	sed "s/^#*\s*CENTRAL_SERVER_ID.*/CENTRAL_SERVER_ID $SHARD_ID/" "$SHARD_CONFIG_DIR/config.txt.tmp" > "$SHARD_CONFIG_DIR/config.txt"
	rm -f "$SHARD_CONFIG_DIR/config.txt.tmp"
else
	mv "$SHARD_CONFIG_DIR/config.txt.tmp" "$SHARD_CONFIG_DIR/config.txt"
	echo "CENTRAL_SERVER_ID $SHARD_ID" >> "$SHARD_CONFIG_DIR/config.txt"
fi

# SHARD_ID: what lets the in-game backup verb/auto-toggle detect they're
# running inside a shard and run shard_backup_self.sh instead of
# scripts/db_backup -- see persistence_backups.dm.
if grep -q '^#*\s*SHARD_ID' "$SHARD_CONFIG_DIR/config.txt"; then
	sed "s/^#*\s*SHARD_ID.*/SHARD_ID $SHARD_ID/" "$SHARD_CONFIG_DIR/config.txt" > "$SHARD_CONFIG_DIR/config.txt.tmp"
	mv "$SHARD_CONFIG_DIR/config.txt.tmp" "$SHARD_CONFIG_DIR/config.txt"
else
	echo "SHARD_ID $SHARD_ID" >> "$SHARD_CONFIG_DIR/config.txt"
fi

# The host's own SERVER_ROOT_PATH (config.txt) is an absolute path on the
# HOST's filesystem -- meaningless, and actively wrong, inside this shard's
# own Linux container, where the repo is always mounted at /aurora (matching
# the Dockerfile's WORKDIR and the docker run -v below). Without this
# override, every world.shelleo() call made from inside the shard (backups
# included) would try to `cd` into a path that doesn't exist in the
# container and fail.
if grep -q '^#*\s*SERVER_ROOT_PATH' "$SHARD_CONFIG_DIR/config.txt"; then
	sed "s#^#*\s*SERVER_ROOT_PATH.*#SERVER_ROOT_PATH /aurora#" "$SHARD_CONFIG_DIR/config.txt" > "$SHARD_CONFIG_DIR/config.txt.tmp"
	mv "$SHARD_CONFIG_DIR/config.txt.tmp" "$SHARD_CONFIG_DIR/config.txt"
else
	echo "SERVER_ROOT_PATH /aurora" >> "$SHARD_CONFIG_DIR/config.txt"
fi

# ── Local DB container ──────────────────────────────────────────────────────

echo "Starting $DB_CONTAINER..."
docker run -d --name "$DB_CONTAINER" --network aurora-shards-net --restart unless-stopped \
	-e MARIADB_ROOT_PASSWORD="$LOCAL_DB_PASSWORD" \
	-e MARIADB_DATABASE=aurora_persist \
	-e MARIADB_USER=aurora \
	-e MARIADB_PASSWORD="$LOCAL_DB_PASSWORD" \
	mariadb:10.11 >/dev/null
if [ $? -ne 0 ]; then
	echo "Failed to start $DB_CONTAINER."
	exit 1
fi

echo "Waiting for $DB_CONTAINER to be ready..."
READY=0
i=0
while [ $i -lt 30 ]; do
	sleep 2
	if docker exec "$DB_CONTAINER" mariadb-admin ping -u root "-p$LOCAL_DB_PASSWORD" >/dev/null 2>&1; then
		READY=1
		break
	fi
	i=$((i + 1))
done
if [ "$READY" -ne 1 ]; then
	echo "$DB_CONTAINER did not become ready within 60 seconds."
	exit 1
fi

echo "Applying local schema to $DB_CONTAINER..."
for f in "$ROOT"/SQL/migrate-2023/V*.sql; do
	[ -f "$f" ] || continue
	docker exec -i "$DB_CONTAINER" mariadb -u root "-p$LOCAL_DB_PASSWORD" --force aurora_persist < "$f" >/dev/null 2>&1
done

# ── API token, scoped ONLY to force_persistence_save -- for
# shard_watchdog.py, which has no in-game admin mob to trigger a save with.
# Written straight into ss13_api_commands/ss13_api_tokens/
# ss13_api_token_command (code/modules/world_api/api_command.dm's own auth
# tables) rather than waiting for the game to register the command itself
# (update_command_database is itself a Topic command -- chicken and egg),
# and scoped to exactly one command, not "_ANY", so a leaked token can
# never do more than trigger a save.
SHARD_API_TOKEN=$(LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' < /dev/urandom | head -c 40)

TOKEN_SQL="INSERT INTO \`ss13_api_commands\` (command, description) VALUES ('force_persistence_save', 'Shard watchdog auto-save') ON DUPLICATE KEY UPDATE description = VALUES(description);
INSERT INTO \`ss13_api_tokens\` (token, creator, description) VALUES ('$SHARD_API_TOKEN', 'db_central_add_shard', 'Shard watchdog auto-save token');
INSERT INTO \`ss13_api_token_command\` (token_id, command_id)
  SELECT t.id, c.id FROM \`ss13_api_tokens\` t, \`ss13_api_commands\` c
  WHERE t.token = '$SHARD_API_TOKEN' AND c.command = 'force_persistence_save';"
printf '%s' "$TOKEN_SQL" | docker exec -i "$DB_CONTAINER" mariadb -u root "-p$LOCAL_DB_PASSWORD" aurora_persist >/dev/null 2>&1

# Saved here too, not just the DB -- otherwise the only way to ever see
# this again is a raw SQL SELECT against the central DB with admin creds.
printf '%s' "$SHARD_API_TOKEN" > "$SHARD_CONFIG_DIR/api_token.txt"

# ── Game server container ───────────────────────────────────────────────────

SHARD_BACKUP_DIR="$ROOT/backups/shards/$SHARD_ID"
mkdir -p "$SHARD_BACKUP_DIR"

echo "Starting $SERVER_CONTAINER on port $PORT..."
# --add-host is a no-op on Docker Desktop (host.docker.internal already
# resolves there) but required for the same hostname to work on native
# Linux Docker Engine -- see the central_dbconfig.txt comment above.
# SHARD_ID env var + the backups/shards/<ShardId> mount are what let
# scripts/central/shard_backup_self.sh (run from inside this container by
# the in-game backup verb/auto-toggle, persistence_backups.dm) know its own
# identity and have somewhere writable to put the result -- everything else
# under /aurora is read-only.
docker run -d --name "$SERVER_CONTAINER" --network aurora-shards-net --restart unless-stopped \
	--add-host=host.docker.internal:host-gateway \
	-e "SHARD_ID=$SHARD_ID" \
	-p "${PORT}:${PORT}" \
	-v "${ROOT}:/aurora:ro" \
	-v "${SHARD_CONFIG_DIR}:/aurora/config:rw" \
	-v "${SHARD_DATA_DIR}:/aurora/data:rw" \
	-v "${SHARD_BACKUP_DIR}:/aurora/backups/shards/${SHARD_ID}:rw" \
	aurora-shard-runtime:latest aurorastation.dmb "$PORT" -trusted >/dev/null
if [ $? -ne 0 ]; then
	echo "Failed to start $SERVER_CONTAINER."
	exit 1
fi

# ── Register ─────────────────────────────────────────────────────────────────

REGISTER_RESULT=$(printf '%s' "INSERT INTO \`ss13_shards\` (shard_id, port, api_token, status, started_at) VALUES ('$SHARD_ID', $PORT, '$SHARD_API_TOKEN', 'running', NOW());" | "$CLIENT" -h "$ADDRESS" -P "$PORT_DB" -u "$LOGIN" "-p$PASSWORD" 2>&1)
if [ $? -ne 0 ]; then
	echo "Containers started, but failed to register in ss13_shards:"
	echo "  $REGISTER_RESULT"
	echo "Register it manually or re-run once the DB issue is fixed."
	exit 1
fi

echo ""
echo "Shard '$SHARD_ID' is up on port $PORT."
echo "Join: byond://<this host>:$PORT"
echo "Manage: db_central_start_shard.sh / db_central_stop_shard.sh / db_central_remove_shard.sh --shard-id $SHARD_ID"
echo "API token (force_persistence_save): $SHARD_API_TOKEN"
echo "  saved to shards/$SHARD_ID/config/api_token.txt"
