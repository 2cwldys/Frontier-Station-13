#!/bin/sh
# Launches the standalone shard manager GUI (shard_manager_gui.py). Mirrors
# shard_manager_gui.bat.
# Requires: pip install pymysql
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
if command -v python3 >/dev/null 2>&1; then
	python3 shard_manager_gui.py
else
	python shard_manager_gui.py
fi
