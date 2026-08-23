"""
Frontier Station 13 Discord Rich Presence.

Watches for a running DreamSeeker client connected to Frontier Station 13,
queries the server's live status, and reflects it in the local Discord
client's Rich Presence. See README.md for one-time setup (Discord
Application/asset registration, config.py placeholders).
"""

from __future__ import annotations

import argparse
import logging
import threading

from pypresence import Presence

import autostart
import config
import tray
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

    # Present only when the server we're polling has CENTRAL_SQL_ENABLED on
    # (server_query.dm omits both keys entirely otherwise, rather than
    # sending 0 -- see get_serverstatus) -- a network-wide total across
    # every server sharing that one central database, not just this one.
    # Falls back to the plain single-server string below when absent, so
    # this works unchanged against a non-central server or an older DM
    # build that doesn't send these fields yet.
    central_players = status.get("central_players")
    central_servers = status.get("central_server_count")

    if central_players is not None:
        state = f"Players: {players} ({central_players} across {central_servers} servers)"
    else:
        state = f"Players: {players}"

    # "Frontier Station 13" already shows on its own as the bold header line
    # of the card -- that's the Discord Application's own registered name,
    # not something set here, so repeating it in "details" just duplicated
    # it. Round duration is dropped entirely: the server runs persistent,
    # continuous rounds rather than discrete timed ones, so an elapsed round
    # timer isn't meaningful here. "details" is a static "Persistence" label
    # instead of the live round-type/gamemode string.
    presence = {
        "details": "Persistence",
        "state": state,
        "large_image": config.LARGE_IMAGE_KEY,
        "large_text": config.LARGE_IMAGE_TEXT,
    }

    if config.SMALL_IMAGE_KEY:
        presence["small_image"] = config.SMALL_IMAGE_KEY
        presence["small_text"] = config.SMALL_IMAGE_TEXT

    # Discord caps Rich Presence at two buttons. "Join Server" goes first so
    # the primary action reads first on the card. Note that Discord never
    # renders your own buttons back to you on your own profile -- only other
    # people viewing it see them, so these looking absent while self-testing
    # is expected, not a failure.
    buttons = []
    if config.JOIN_URL:
        buttons.append({"label": config.JOIN_BUTTON_LABEL, "url": config.JOIN_URL})
    if config.DISCORD_INVITE_URL:
        buttons.append({"label": "Join Discord", "url": config.DISCORD_INVITE_URL})
    if buttons:
        presence["buttons"] = buttons[:2]

    return presence


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="FrontierRPC",
        description=(
            "Shows your live Frontier Station 13 status on Discord while you play. "
            "Runs quietly in the background; presence appears when the game is open "
            "and clears when you close it."
        ),
    )
    parser.add_argument(
        "--no-autostart",
        action="store_true",
        help="Run this session only -- don't register to start automatically at login.",
    )
    parser.add_argument(
        "--uninstall",
        action="store_true",
        help="Remove the run-at-login registration and exit. Deletes nothing else.",
    )
    return parser.parse_args()


def main() -> None:
    args = _parse_args()

    if args.uninstall:
        autostart.unregister()
        logger.info("No longer starting automatically. You can delete this file now.")
        return

    # Register on every normal launch, not just a tracked "first run" -- it's a
    # no-op when already correct, and it self-heals if the player moves the exe
    # (the stored path would otherwise point at nothing).
    if not args.no_autostart:
        autostart.register()

    stop_event = threading.Event()

    # The tray icon owns the main thread when it exists (a tray needs one on
    # Windows), so the presence loop moves to a worker. Without a tray we just
    # run the loop directly and behave exactly as before.
    icon = tray.create_icon(stop_event)
    if icon is None:
        _presence_loop(stop_event)
        return

    worker = threading.Thread(target=_presence_loop, args=(stop_event,), daemon=True)
    worker.start()
    icon.run()
    stop_event.set()
    worker.join(timeout=5)


def _presence_loop(stop_event: threading.Event) -> None:
    rpc: Presence | None = None
    presence_active = False

    while not stop_event.is_set():
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
            stop_event.wait(config.POLL_INTERVAL_SECONDS)
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
            stop_event.wait(backoff)
            continue
        except ByondQueryError as e:
            logger.warning("Could not fetch server status: %s", e)
            stop_event.wait(config.POLL_INTERVAL_SECONDS)
            continue

        if rpc is not None:
            try:
                rpc.update(**_build_presence(status))
                presence_active = True
            except Exception as e:
                logger.warning("Failed to update Discord presence: %s", e)
                rpc = None

        stop_event.wait(config.POLL_INTERVAL_SECONDS)

    # Quitting via the tray shouldn't leave a stale card sitting on the profile.
    if presence_active and rpc is not None:
        try:
            rpc.clear()
        except Exception as e:
            logger.warning("Failed to clear presence on shutdown: %s", e)


if __name__ == "__main__":
    main()
