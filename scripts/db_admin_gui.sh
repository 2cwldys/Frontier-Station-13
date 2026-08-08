#!/bin/sh
# Launches the standalone DB admin GUI (db_admin_gui.py). Mirrors db_admin_gui.bat.
# Requires: pip install pymysql psutil
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
if command -v python3 >/dev/null 2>&1; then
	python3 db_admin_gui.py
else
	python db_admin_gui.py
fi
