"""
Run-at-login registration (Windows, per-user).

This is what turns the tool from "a script you remember to run" into
something a player installs once and then never thinks about again. The
presence itself already starts and stops on its own -- main.py watches for
the game window and clears the presence the moment it closes -- so the only
thing missing was having the watcher resident in the first place.

Writes to HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run, which is
per-user and needs no administrator rights. Nothing is written outside that
one value.

Note this is only meaningful for the frozen .exe build: running it from a
.py would register the interpreter path, which breaks the moment the folder
moves. is_frozen() gates on that.
"""

import logging
import os
import sys

logger = logging.getLogger(__name__)

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
VALUE_NAME = "FrontierStation13RPC"


def is_frozen() -> bool:
    """TRUE when running as a PyInstaller-built .exe rather than a .py."""
    return getattr(sys, "frozen", False)


def _executable_command() -> str:
    return f'"{os.path.abspath(sys.executable)}"'


def _open_run_key(access):
    import winreg

    return winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, access)


def is_registered() -> bool:
    if os.name != "nt":
        return False
    try:
        import winreg

        with _open_run_key(winreg.KEY_READ) as key:
            value, _ = winreg.QueryValueEx(key, VALUE_NAME)
            return value == _executable_command()
    except FileNotFoundError:
        return False
    except OSError as e:
        logger.warning("Could not read autostart registration: %s", e)
        return False


def register() -> bool:
    """Add this executable to the per-user run-at-login list."""
    if os.name != "nt":
        return False
    if not is_frozen():
        # Registering a bare script path would bake in the interpreter and the
        # current folder -- silently broken as soon as either changes.
        logger.info("Not a frozen build, skipping autostart registration.")
        return False
    if is_registered():
        return True
    try:
        import winreg

        with _open_run_key(winreg.KEY_SET_VALUE) as key:
            winreg.SetValueEx(key, VALUE_NAME, 0, winreg.REG_SZ, _executable_command())
        logger.info("Registered to start automatically at login.")
        return True
    except OSError as e:
        logger.warning("Could not register autostart: %s", e)
        return False


def unregister() -> bool:
    """Remove the run-at-login entry. Safe to call when not registered."""
    if os.name != "nt":
        return False
    try:
        import winreg

        with _open_run_key(winreg.KEY_SET_VALUE) as key:
            winreg.DeleteValue(key, VALUE_NAME)
        logger.info("Removed from automatic startup.")
        return True
    except FileNotFoundError:
        return True
    except OSError as e:
        logger.warning("Could not remove autostart: %s", e)
        return False
