#!/bin/bash
# Stops the Discord status bot, using the PID the bot recorded itself.
# Invoked from SSpersistence.Shutdown() via world.shelleo() when the server is
# genuinely closing (not on a soft round reboot -- see the hard-reset guard
# there), so the bot does not outlive the server it reports on.
#
# Being asked to stop an already-stopped bot is a normal outcome, not an error:
# exits 0 whether it killed anything or found nothing to kill.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
PIDFILE="$ROOT/data/discord_status_bot.pid"

if [ ! -f "$PIDFILE" ]; then
    echo "discord_bot_stop: no PID file -- nothing to stop."
    exit 0
fi

BOTPID="$(cat "$PIDFILE" 2>/dev/null)"
rm -f "$PIDFILE"

if [ -z "$BOTPID" ]; then
    echo "discord_bot_stop: empty PID file -- nothing to stop."
    exit 0
fi

# A stale PID whose process is already gone is expected after a crash --
# report it plainly rather than treating it as a failure.
if kill -0 "$BOTPID" 2>/dev/null; then
    kill "$BOTPID" 2>/dev/null
    sleep 1
    kill -9 "$BOTPID" 2>/dev/null
    echo "discord_bot_stop: stopped PID $BOTPID."
else
    echo "discord_bot_stop: PID $BOTPID was not running."
fi
exit 0
