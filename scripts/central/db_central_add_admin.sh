#!/bin/sh
# Add/update one ckey in the central admin roster (ss13_central_admins) --
# the shared list every server with CENTRAL_SQL_ENABLED on treats as its
# ENTIRE admin roster (see load_admins_from_central_database(), auth.dm). A
# ckey not in this table is not an admin on ANY centrally-enabled server, no
# matter what that server's own local admins.txt/ss13_admins says.
#
# Connects using config/central_dbconfig_admin.txt -- the ADMIN tier, same
# as db_central_add_server.sh/db_central_update.sh. Deliberately NOT the
# per-server runtime tier: that login only has read access to this specific
# table, even though it can read/write every other central table -- a
# compromised or buggy game server must never be able to grant itself admin
# by writing to ss13_central_admins directly.
#
# "rank" is a display label only -- it is NOT resolved against any server's
# own config/admin_ranks.json. "flags" is the actual enforced R_* rights
# bitmask, used as-is. Common values (code/__DEFINES/admin.dm):
#   R_ALL = 32767 (full admin), R_ADMIN = 1, R_BAN = 2, R_PERMISSIONS = 32
#
# Native translation of db_central_add_admin.ps1 -- no PowerShell dependency.
#
# Usage:
#   db_central_add_admin.sh --ckey someone --rank "Head Admin" --flags 32767
#   db_central_add_admin.sh --ckey someone --rank Moderator --flags 35 --whatif

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_PATH="$ROOT/config/central_dbconfig_admin.txt"

CKEY=""
RANK=""
FLAGS=""
WHATIF=0

while [ $# -gt 0 ]; do
	case "$1" in
		--ckey) CKEY="$2"; shift 2 ;;
		--rank) RANK="$2"; shift 2 ;;
		--flags) FLAGS="$2"; shift 2 ;;
		--whatif) WHATIF=1; shift ;;
		*) echo "Unknown argument: $1"; exit 1 ;;
	esac
done

if [ -z "$CKEY" ] || [ -z "$RANK" ] || [ -z "$FLAGS" ]; then
	echo "Usage: $0 --ckey <ckey> --rank <label> --flags <int> [--whatif]"
	exit 1
fi

case "$FLAGS" in
	''|*[!0-9]*)
		echo "Flags must be a plain integer -- got '$FLAGS'."
		exit 1
		;;
esac

# Lowercase, then strip anything outside the safe ckey charset -- same
# normalization db_central_add_admin.ps1 applies.
CKEY=$(echo "$CKEY" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9@._-]//g')
if [ -z "$CKEY" ]; then
	echo "Ckey is empty after normalization."
	exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
	echo "config/central_dbconfig_admin.txt not found -- run db_central_setup, or copy it from config/example/central_dbconfig_admin.txt and fill in the central database's admin credentials yourself."
	exit 1
fi

# Same tiny "KEY value" format GetDBConfig() (centraldb.dm) reads at runtime,
# re-parsed here since this is a standalone script with no access to the DM
# config loader -- same approach every other db_central_* script uses.
ADDRESS="localhost"
PORT="3306"
DATABASE="aurora_central"
LOGIN=""
PASSWORD=""
while IFS= read -r line || [ -n "$line" ]; do
	t=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
	[ -z "$t" ] && continue
	case "$t" in \#*) continue ;; esac
	key=$(printf '%s' "$t" | cut -d' ' -f1 | tr 'A-Z' 'a-z')
	value=$(printf '%s' "$t" | cut -s -d' ' -f2-)
	case "$key" in
		address) ADDRESS="$value" ;;
		port) PORT="$value" ;;
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

# Rank is free text (a display label) -- escape single quotes so it can't
# break out of the SQL string. Ckey was already normalized to a safe
# charset above; Flags was validated as a plain integer.
RANK_ESCAPED=$(printf '%s' "$RANK" | sed "s/'/''/g")

SQL="INSERT INTO \`ss13_central_admins\` (ckey, \`rank\`, flags, added_by)
VALUES ('$CKEY', '$RANK_ESCAPED', $FLAGS, '$LOGIN')
ON DUPLICATE KEY UPDATE \`rank\` = VALUES(\`rank\`), flags = VALUES(flags);"

echo "Target: $ADDRESS:$PORT/$DATABASE via $CLIENT"
echo ""
echo "SQL to run:"
echo "$SQL"
echo ""

if [ "$WHATIF" -eq 1 ]; then
	echo "--whatif: nothing changed."
	exit 0
fi

RESULT=$(printf '%s' "$SQL" | "$CLIENT" -h "$ADDRESS" -P "$PORT" -u "$LOGIN" "-p$PASSWORD" 2>&1)
STATUS=$?
if [ $STATUS -ne 0 ]; then
	echo "FAILED:"
	echo "  $RESULT"
	exit 1
fi

echo "'$CKEY' is now in the central admin roster as '$RANK' (flags $FLAGS)."
echo "Takes effect on every centrally-enabled server's next reboot (admin roster loads once at boot)."
