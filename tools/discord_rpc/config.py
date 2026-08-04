"""
Configuration for the Frontier Station 13 Discord Rich Presence client.

Real values live in a .env file in this same folder (never committed --
already covered by the repo's root .gitignore), not hardcoded here. Copy
.env.example to .env and fill it in -- see SETUP_GUIDE.txt.
"""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

# Load .env from next to the script AND from inside the PyInstaller bundle.
#
# The server address deliberately isn't hardcoded here -- it stays in .env,
# which is gitignored, so it never lands in the repo. build.bat bundles the
# host's .env into the .exe, so the distributable a player downloads already
# knows where to connect while the address is still absent from source
# control. A .env sitting beside the exe overrides the bundled one, which is
# what a tester pointing at a private server wants.
_BUNDLE_DIR = getattr(sys, "_MEIPASS", None)
if _BUNDLE_DIR:
    load_dotenv(Path(_BUNDLE_DIR) / ".env")
load_dotenv(Path(sys.executable if getattr(sys, "frozen", False) else __file__).resolve().parent / ".env", override=True)


# The Application ID is safe to keep in source -- it's visible to anyone who
# can see the presence card, and it's already committed in .env.example.
DEFAULT_DISCORD_CLIENT_ID = "1533582038379266218"


def _setting(key: str, default: str = "") -> str:
    value = os.environ.get(key)
    return value if value else default


def _require(key: str) -> str:
    value = _setting(key)
    if not value:
        raise RuntimeError(
            f"Missing {key}. Copy .env.example to .env and fill it in (see "
            f"SETUP_GUIDE.txt). If you're building the player .exe, run "
            f"build.bat with a filled-in .env present so it gets bundled in."
        )
    return value


DISCORD_CLIENT_ID = _setting("DISCORD_CLIENT_ID", DEFAULT_DISCORD_CLIENT_ID)
SERVER_ADDR = _require("SERVER_ADDR")
SERVER_PORT = int(_require("SERVER_PORT"))

# Optional -- sensible defaults used if left blank/omitted from .env.
LARGE_IMAGE_KEY = os.environ.get("LARGE_IMAGE_KEY", "fs13")
LARGE_IMAGE_TEXT = os.environ.get("LARGE_IMAGE_TEXT", "Frontier Station 13")
WINDOW_TITLE_MATCH = os.environ.get("WINDOW_TITLE_MATCH", "Frontier Station 13")

# Optional -- a small badge icon overlaid on the bottom-right corner of the
# large image (e.g. Discord's own icon mark, to visually flag "this game has
# a Discord community"). Same upload flow as LARGE_IMAGE_KEY (Developer
# Portal -> Rich Presence -> Art Assets) -- SMALL_IMAGE_KEY must match
# whatever name you gave that upload. Left blank, no small image shows.
SMALL_IMAGE_KEY = os.environ.get("SMALL_IMAGE_KEY", "")
SMALL_IMAGE_TEXT = os.environ.get("SMALL_IMAGE_TEXT", "discord.gg/58tEbcCkUP")

# Optional -- adds a small "Join Discord" button below the presence text if
# set (Discord Rich Presence supports up to 2 of these; doesn't affect the
# details/state/image layout at all). Left blank, no button is shown. Note:
# Discord never shows your own buttons back to you on your own profile --
# only other people viewing it see and can click them, so don't expect to
# see it yourself while testing.
DISCORD_INVITE_URL = os.environ.get("DISCORD_INVITE_URL", "")

# Optional -- adds a "Join Server" button that opens the game directly.
# Defaults to the BYOND protocol link built from SERVER_ADDR/SERVER_PORT
# above, so it needs no configuration to work.
#
# The card's bold "Frontier Station 13" header can NOT be made a hyperlink --
# that's the Discord Application's own registered name, not a Rich Presence
# field, and Discord renders it as inert text. A button is the only clickable
# surface Rich Presence offers, and Discord allows at most two of them (this
# one plus DISCORD_INVITE_URL fills both).
#
# Caveat: Discord validates button URLs and may refuse a non-http(s) scheme,
# in which case the button silently won't render. If that happens, point
# JOIN_URL at an ordinary https page that immediately forwards to the same
# byond:// address, e.g. a one-line page doing
#   <script>location.replace("byond://ADDR:PORT")</script>
JOIN_URL = os.environ.get("JOIN_URL", f"byond://{SERVER_ADDR}:{SERVER_PORT}")
JOIN_BUTTON_LABEL = os.environ.get("JOIN_BUTTON_LABEL", "Join Server")

# 30s default -- comfortably above the server's fail2topic minimum request
# spacing (5s by default, code/controllers/subsystems/fail2topic.dm) with a
# lot of headroom, and Rich Presence doesn't need faster-than-30s precision
# anyway. Raise RATE_LIMIT_BACKOFF_SECONDS too if you ever lower this.
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "30"))
QUERY_TIMEOUT_SECONDS = float(os.environ.get("QUERY_TIMEOUT_SECONDS", "5.0"))

# Extra wait added on TOP of one POLL_INTERVAL_SECONDS after the server
# rejects a query with 429 (rate limited) -- guarantees the next attempt
# lands well clear of the server's minimum-spacing window instead of
# potentially repeating the same cadence that just tripped it, which would
# otherwise let consecutive-failure count climb toward a ban if the server
# ever has that escalation enabled.
RATE_LIMIT_BACKOFF_SECONDS = int(os.environ.get("RATE_LIMIT_BACKOFF_SECONDS", "30"))
