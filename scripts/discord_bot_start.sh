#!/bin/bash
# Launches the Discord status bot detached and returns immediately -- invoked
# from SSpersistence.Initialize() via world.shelleo(), which blocks the whole
# game world for however long the shelled-out command takes. The bot runs
# forever, so waiting on it would hang the server permanently at startup.
# Same backgrounding trick deploy_bg.sh uses for the same reason.
#
# Kills any previously-recorded bot first, so the process that ends up running
# always matches the current script -- including an orphan left behind by a
# DreamDaemon that died without running Shutdown().

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
PIDFILE="$ROOT/data/discord_status_bot.pid"
CONFIG="$ROOT/config/discord_status_bot.json"
LOG="$ROOT/data/discord_status_bot.log"

# Refuse rather than spawn a process that would only exit again a second later
# -- an unconfigured server should launch nothing at all.
if [ ! -f "$CONFIG" ]; then
    echo "discord_bot_start: no config at \"$CONFIG\" -- not starting."
    exit 1
fi

# Stop whatever was running before. A stale PID (process already gone) is
# normal and must not fail the start.
if [ -f "$PIDFILE" ]; then
    OLDPID="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$OLDPID" ]; then
        kill "$OLDPID" 2>/dev/null
        # Give it a moment to go quietly before insisting.
        sleep 1
        kill -9 "$OLDPID" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

mkdir -p "$ROOT/data"

# --managed is what makes the bot write the PID file and enable its self-exit
# watchdog -- i.e. what marks it as server-owned and therefore reapable. A bot
# started by hand (running the .py directly, without this flag) writes no PID
# file and is never touched by the server. The bot also refuses to start if
# another instance already holds the lock, so this cannot double up on one you
# started yourself.
nohup python3 "$ROOT/scripts/discord_status_bot.py" --managed >> "$LOG" 2>&1 &
exit 0
