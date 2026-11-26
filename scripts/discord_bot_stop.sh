#!/bin/bash
# Stops the Discord status bot. Invoked from SSpersistence.Shutdown() via
# world.shelleo() when the server is genuinely closing (not on a soft round
# reboot -- see the hard-reset guard there), so the bot does not outlive the
# server it reports on.
#
# Being asked to stop an already-stopped bot is a normal outcome, not an error:
# exits 0 whether it killed anything or found nothing to kill.
#
# The PID file only exists for a bot launched with --managed
# (discord_bot_start.sh) -- a bot started by hand writes none, and used to be
# completely invisible to this script as a result. That is a real gap (the
# server's own shutdown should be able to actually stop every copy of this
# bot, not just ones it personally launched), so this always ALSO sweeps by
# command line via pkill -f, independent of the PID file entirely -- a
# self-reported PID is not something this should have to trust to guarantee
# the bot is gone.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
PIDFILE="$ROOT/data/discord_status_bot.pid"
STOPPED_ANY=0

if [ -f "$PIDFILE" ]; then
    BOTPID="$(cat "$PIDFILE" 2>/dev/null)"
    rm -f "$PIDFILE"
    if [ -n "$BOTPID" ] && kill -0 "$BOTPID" 2>/dev/null; then
        kill "$BOTPID" 2>/dev/null
        sleep 1
        kill -9 "$BOTPID" 2>/dev/null
        echo "discord_bot_stop: stopped PID $BOTPID (from PID file)."
        STOPPED_ANY=1
    fi
fi

# Catch-all sweep -- finds the bot by command line regardless of whether it
# was started with --managed, already handled above, or by hand.
if pgrep -f "discord_status_bot\.py" >/dev/null 2>&1; then
    pkill -f "discord_status_bot\.py" 2>/dev/null
    sleep 1
    pkill -9 -f "discord_status_bot\.py" 2>/dev/null
    echo "discord_bot_stop: stopped remaining instance(s) found running (no/stale PID file)."
    STOPPED_ANY=1
fi

if [ "$STOPPED_ANY" -eq 0 ]; then
    echo "discord_bot_stop: nothing was running."
fi
exit 0
