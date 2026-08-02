"""
Detects whether Frontier Station 13 is currently open in a BYOND
(dreamseeker.exe) client window, by enumerating visible top-level windows
and checking both the owning process name and the window title.
"""

from __future__ import annotations

import logging

import psutil
import win32gui
import win32process

logger = logging.getLogger(__name__)

DREAMSEEKER_PROCESS_NAME = "dreamseeker.exe"


def _window_process_name(hwnd: int) -> str | None:
    try:
        _, pid = win32process.GetWindowThreadProcessId(hwnd)
        return psutil.Process(pid).name()
    except (psutil.NoSuchProcess, psutil.AccessDenied, OSError):
        return None


def is_frontier_running(title_match: str) -> bool:
    """
    TRUE if any visible, enabled dreamseeker.exe window's title contains
    title_match (case-insensitive).
    """
    found = False
    needle = title_match.lower()

    def _callback(hwnd: int, _extra) -> bool:
        nonlocal found
        if found:
            return True
        if not (win32gui.IsWindowVisible(hwnd) and win32gui.IsWindowEnabled(hwnd)):
            return True
        title = win32gui.GetWindowText(hwnd)
        if not title:
            return True
        if _window_process_name(hwnd) != DREAMSEEKER_PROCESS_NAME:
            return True
        if needle in title.lower():
            logger.debug("Matched Frontier window: %r", title)
            found = True
        return True

    win32gui.EnumWindows(_callback, None)
    return found
