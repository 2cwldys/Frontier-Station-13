#!/bin/sh
# Start the Aurora MariaDB container.
# Run db_setup.sh first if this is a fresh install.
# Native translation of db_start.ps1 -- no PowerShell dependency.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Starting Aurora DB..."
docker compose up -d db

echo "Aurora DB is running on localhost:3306"
