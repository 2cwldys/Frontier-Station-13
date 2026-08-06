#!/bin/sh
# Launches the standalone Idris Stock Exchange daemon (stock_market_daemon.py).
# Mirrors stock_market_daemon.bat.
# Requires: pip install pymysql psutil rich
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
if command -v python3 >/dev/null 2>&1; then
	python3 stock_market_daemon.py
else
	python stock_market_daemon.py
fi
