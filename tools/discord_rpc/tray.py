"""
System tray icon -- the player's only handle on a tool that otherwise has no
window.

The distributable is built with --noconsole so it stays out of the way, which
also means there's no console to pass --uninstall to and nothing to close. A
tray icon gives them somewhere to go: see that it's running, stop it, and take
it back out of Windows startup without touching a registry editor or hunting
for a command line.

pystray/Pillow are optional at runtime. If either is missing (or the platform
has no tray), the caller falls back to running headless exactly as before --
losing the menu, not the presence.
"""

import logging
import os
import sys

logger = logging.getLogger(__name__)


def _asset_path(filename: str) -> str:
    """Resolve an asset next to the script, or inside the PyInstaller bundle."""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "assets", filename)


def _load_image():
    from PIL import Image

    for candidate in ("tray_icon.png", "eye.png", "discord_icon.png", "discord_icon_small.png"):
        path = _asset_path(candidate)
        if os.path.exists(path):
            return Image.open(path)
    # No bundled art -- draw a plain square rather than refusing to show a menu.
    return Image.new("RGB", (64, 64), (88, 101, 242))


def create_icon(stop_event):
    """
    Build the tray icon, or return None if tray support isn't available.

    stop_event is set when the player chooses to quit, which is what unblocks
    the presence loop so it can clear the presence and exit cleanly.
    """
    try:
        import pystray
    except ImportError:
        logger.info("pystray not installed -- running without a tray icon.")
        return None

    import autostart

    def _toggle_autostart(icon, item):
        if autostart.is_registered():
            autostart.unregister()
            icon.notify("Frontier RPC will no longer start with Windows.")
        else:
            if autostart.register():
                icon.notify("Frontier RPC will start with Windows.")
            else:
                # Only meaningful for the frozen build -- see autostart.register().
                icon.notify("Couldn't enable startup (only works for the .exe build).")

    def _disable_and_quit(icon, item):
        autostart.unregister()
        stop_event.set()
        icon.stop()

    def _quit(icon, item):
        stop_event.set()
        icon.stop()

    menu = pystray.Menu(
        pystray.MenuItem(
            "Start with Windows",
            _toggle_autostart,
            checked=lambda item: autostart.is_registered(),
        ),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Turn off and remove from startup", _disable_and_quit),
        pystray.MenuItem("Quit (keep startup enabled)", _quit),
    )

    try:
        return pystray.Icon(
            "frontier_rpc",
            _load_image(),
            "Frontier Station 13 Rich Presence",
            menu,
        )
    except Exception as e:
        logger.warning("Could not create tray icon: %s", e)
        return None
