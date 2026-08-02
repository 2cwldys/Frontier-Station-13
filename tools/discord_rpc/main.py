"""
Frontier Station 13 Discord Rich Presence.

Watches for a running DreamSeeker client connected to Frontier Station 13,
queries the server's live status, and reflects it in the local Discord
client's Rich Presence. See README.md for one-time setup (Discord
Application/asset registration, config.py placeholders).
"""

from __future__ import annotations

import logging
import time

from pypresence import Presence

import config
from byond_query import ByondQueryError, RateLimitedError, query
from window_detect import is_frontier_running

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("frontier_rpc")


def _connect() -> Presence | None:
    try:
        rpc = Presence(config.DISCORD_CLIENT_ID)
        rpc.connect()
        logger.info("Connected to Discord.")
        return rpc
    except Exception as e:  # pypresence's own exceptions aren't a stable set to enumerate
        logger.warning("Could not connect to Discord (is it running?): %s", e)
        return None


def _build_presence(status: dict) -> dict:
    players = status.get("players", "?")

    # "Frontier Station 13" already shows on its own as the bold header line
    # of the card -- that's the Discord Application's own registered name,
    # not something set here, so repeating it in "details" just duplicated
    # it. Round duration is dropped entirely: the server runs persistent,
    # continuous rounds rather than discrete timed ones, so an elapsed round
    # timer isn't meaningful here. "details" is a static "Persistence" label
    # instead of the live round-type/gamemode string.
    presence = {
        "details": "Persistence",
        "state": f"Players: {players}",
        "large_image": config.LARGE_IMAGE_KEY,
        "large_text": config.LARGE_IMAGE_TEXT,
    }

    if config.SMALL_IMAGE_KEY:
        presence["small_image"] = config.SMALL_IMAGE_KEY
        presence["small_text"] = config.SMALL_IMAGE_TEXT

    if config.DISCORD_INVITE_URL:
        presence["buttons"] = [{"label": "Join Discord", "url": config.DISCORD_INVITE_URL}]

    return presence


def main() -> None:
    rpc: Presence | None = None
    presence_active = False

    while True:
        if rpc is None:
            rpc = _connect()

        frontier_open = is_frontier_running(config.WINDOW_TITLE_MATCH)

        if not frontier_open:
            if presence_active and rpc is not None:
                try:
                    rpc.clear()
                except Exception as e:
                    logger.warning("Failed to clear presence: %s", e)
                    rpc = None
                presence_active = False
            time.sleep(config.POLL_INTERVAL_SECONDS)
            continue

        try:
            status = query(
                config.SERVER_ADDR,
                config.SERVER_PORT,
                "get_serverstatus",
                timeout=config.QUERY_TIMEOUT_SECONDS,
            )
        except RateLimitedError as e:
            # Back off well beyond the normal poll interval so the next
            # attempt lands clear of the server's minimum-spacing window,
            # instead of risking repeating the same cadence that just
            # tripped it (which would compound the strike count server-side).
            backoff = config.POLL_INTERVAL_SECONDS + config.RATE_LIMIT_BACKOFF_SECONDS
            logger.warning("Rate limited by server, backing off %ss: %s", backoff, e)
            time.sleep(backoff)
            continue
        except ByondQueryError as e:
            logger.warning("Could not fetch server status: %s", e)
            time.sleep(config.POLL_INTERVAL_SECONDS)
            continue

        if rpc is not None:
            try:
                rpc.update(**_build_presence(status))
                presence_active = True
            except Exception as e:
                logger.warning("Failed to update Discord presence: %s", e)
                rpc = None

        time.sleep(config.POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
