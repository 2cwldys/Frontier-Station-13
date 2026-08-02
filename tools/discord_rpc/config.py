"""
Configuration for the Frontier Station 13 Discord Rich Presence client.

Real values live in a .env file in this same folder (never committed --
already covered by the repo's root .gitignore), not hardcoded here. Copy
.env.example to .env and fill it in -- see SETUP_GUIDE.txt.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent / ".env")


def _require(key: str) -> str:
    value = os.environ.get(key)
    if not value:
        raise RuntimeError(
            f"Missing {key} in .env -- copy .env.example to .env and fill it in "
            f"(see SETUP_GUIDE.txt)."
        )
    return value


# Required -- the app fails fast at startup if these are missing, instead of
# silently running with a placeholder string that fails deep in the network
# code with a confusing error.
DISCORD_CLIENT_ID = _require("DISCORD_CLIENT_ID")
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
