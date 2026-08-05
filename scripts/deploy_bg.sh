#!/bin/bash
# Launches deploy.sh detached in the background and returns immediately --
# invoked by the in-game "Sync Deployment Branch" admin verb via
# world.shelleo(), which blocks the whole game world for however long the
# shelled-out command takes. A full recompile can take minutes, so this
# only backgrounds the launch itself instead of waiting on it.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
nohup "$DIR/deploy.sh" > "$DIR/deploy.log" 2>&1 &
