"""
Frontier-Station-13 -- Discord server-status bot.

Mirrors the live server status onto a Discord bot's presence, the same way the
Rich Presence helper mirrors it onto a player's profile. The activity line is
the player count; the status dot carries server health:

    Watching  14 players

    green  (online)  server up and answering
    yellow (idle)    persistence save in progress
    red    (dnd)     unreachable -- down, restarting, or wrong host/port

Data comes from the game server's own `get_serverstatus` Topic command
(code/modules/world_api/commands/server_query.dm), which is `no_auth` and
`no_fail2topic` precisely so external tools can poll it without a key and
without tripping abuse detection. It reads the same globals as
/world/proc/update_status() (world.dm), so this bot and the BYOND hub listing
can never disagree.

Run it alongside the server, by hand or as a service. Nothing in the round
depends on it; if the bot dies the game does not care, and if the game dies the
bot goes red and keeps polling until it comes back.

Config: config/discord_status_bot.json -- see config/example/ for a documented
template. config/ is gitignored in full, so the token stays out of the repo.

Requires: pip install discord.py

Usage:

  python scripts/discord_status_bot.py            # run the bot
  python scripts/discord_status_bot.py --once     # one poll, print, exit (no Discord)
"""

import argparse
import asyncio
import json
import os
import pathlib
import socket
import struct
import sys
import time

REPO = pathlib.Path(__file__).resolve().parent.parent
CONFIG_PATH = REPO / "config" / "discord_status_bot.json"
EXAMPLE_PATH = REPO / "config" / "example" / "discord_status_bot.json"

# Two files, two different questions -- one cannot answer both, because a
# hand-started bot has to be invisible to reaping but still visible to
# duplicate detection.
#
#   .lock  written by EVERY instance   -> "a bot is already running, here's its PID"
#   .pid   written ONLY when --managed -> "the game started this one, it may be reaped"
#
# So the game may only ever kill something it started itself, while still
# refusing to start a second bot alongside one you launched by hand.
#
# Both are written from in here rather than from the launcher: the launcher's
# own PID is the shell, not Python, and on Windows `start /B` makes it useless
# for this anyway. data/ is gitignored and is already where world.shelleo()
# puts its own scratch files.
PID_PATH = REPO / "data" / "discord_status_bot.pid"
LOCK_PATH = REPO / "data" / "discord_status_bot.lock"

PLACEHOLDER_TOKEN = "REPLACE_WITH_BOT_TOKEN"

# BYOND's topic wire format. A request is:
#
#   \x00\x83  <len:2, big-endian>  \x00\x00\x00\x00\x00  <payload>  \x00
#
# where len counts the payload, the five pad bytes and the trailing NUL.
# The payload is "?" + the query string; BYOND strips the "?" and hands the
# rest to /world/Topic() as T, which json_decode()s it (world.dm).
TOPIC_MAGIC = b"\x00\x83"
TOPIC_TYPE_FLOAT = 0x2A
TOPIC_TYPE_STRING = 0x06


class TopicError(Exception):
    """Server unreachable or spoke something we could not parse."""


def topic_query(host, port, query, timeout=5.0):
    """
    Sends one BYOND topic query and returns the decoded response.

    Returns a dict (the server answers JSON), a float, or a string, depending
    on what the far end sent. Raises TopicError for anything that means "no
    usable answer" -- which for this bot is a normal, expected state, not a
    crash.
    """
    payload = f"?{query}".encode("utf-8")
    packet = (
        TOPIC_MAGIC
        + struct.pack(">H", len(payload) + 6)
        + b"\x00\x00\x00\x00\x00"
        + payload
        + b"\x00"
    )

    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            sock.sendall(packet)

            header = _recv_exactly(sock, 5)
            if header[:2] != TOPIC_MAGIC:
                raise TopicError(f"not a BYOND response (got {header[:2]!r})")

            # Bytes 2-3 are the length of what follows the length field; one of
            # those bytes is the type tag we already consumed as header[4].
            body_len = struct.unpack(">H", header[2:4])[0]
            kind = header[4]
            body = _recv_exactly(sock, max(0, body_len - 1))
    except TopicError:
        raise
    except (OSError, socket.timeout) as e:
        raise TopicError(f"{host}:{port} unreachable ({e})") from e

    if kind == TOPIC_TYPE_FLOAT:
        return struct.unpack("<f", body[:4])[0]
    if kind == TOPIC_TYPE_STRING:
        text = body.rstrip(b"\x00").decode("utf-8", errors="replace")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            # Older/other commands can answer plain text -- hand it back as-is
            # rather than pretending it was an error.
            return text
    raise TopicError(f"unknown response type tag 0x{kind:02x}")


def _recv_exactly(sock, count):
    """recv() until `count` bytes have arrived, or the peer hangs up."""
    chunks = []
    remaining = count
    while remaining > 0:
        chunk = sock.recv(remaining)
        if not chunk:
            raise TopicError("connection closed mid-response")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def fetch_status(host, port, timeout=10.0):
    """
    Asks for get_serverstatus and returns its `data` dict.

    /world/Topic() wraps every reply as
    {"statuscode": 200, "response": "...", "data": {...}}, so unwrap it here
    and treat a non-200 as unreachable -- from this bot's point of view a
    server that answers "429 Rate limited" is just as unusable as silence.
    """
    result = topic_query(host, port, '{"query":"get_serverstatus"}', timeout)
    if not isinstance(result, dict):
        raise TopicError(f"expected a JSON object, got {type(result).__name__}")
    code = result.get("statuscode")
    if code != 200:
        raise TopicError(f"server returned {code}: {result.get('response')}")
    data = result.get("data")
    if not isinstance(data, dict):
        raise TopicError("response carried no data object")
    return data


def _flag(value):
    """BYOND sends 1/0 for booleans; treat anything falsy or absent as off."""
    return bool(value) and value != "0"


def format_presence(data, save_window=0):
    """
    Builds the activity line: the player count, and nothing else.

    The whitelist/raiding/gate toggles are deliberately NOT in the line -- they
    are still fetched (get_serverstatus returns them) and still shown on the
    BYOND hub, but Discord gives a bot one short activity string and a count
    reads far better on its own than buried in a run of flags.

    Server health is carried by the status dot instead of the text, via the
    returned state: "up" / "saving" / "down".

    save_window is how many seconds after a save finishes it still counts as
    "saving". Polling alone misses saves almost every time -- a full save runs
    roughly 18 seconds against a 30 second poll interval, so the window it is
    live in usually falls entirely between two samples -- and a poll that DOES
    land inside one can time out, because the same thread that answers is the
    one doing the saving. So the server also reports `saved_ago`, and a save
    that finished within the window still shows yellow. The caller passes
    poll + timeout, so raising the poll interval cannot silently reopen the
    blind spot.
    """
    players = data.get("players", 0)
    try:
        players = int(float(players))
    except (TypeError, ValueError):
        players = 0

    text = f"{players} player{'' if players == 1 else 's'}"

    saving = _flag(data.get("saving"))
    if not saving and save_window > 0:
        try:
            # -1 means no save yet this round; anything >= 0 is seconds since.
            saved_ago = float(data.get("saved_ago", -1))
        except (TypeError, ValueError):
            saved_ago = -1
        saving = 0 <= saved_ago < save_window

    return text, ("saving" if saving else "up")


def _pid_alive(pid):
    """
    TRUE if a process with this PID currently exists.

    No new dependency for this -- os.kill(pid, 0) on POSIX, and a short
    OpenProcess call on Windows where os.kill cannot do a no-op signal.
    """
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = ctypes.windll.kernel32.OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION, False, pid
        )
        if not handle:
            return False
        # Still open == still running. A process that has exited but whose
        # handle lingers reports STILL_ACTIVE (259) as its exit code.
        exit_code = ctypes.c_ulong()
        ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
        ctypes.windll.kernel32.CloseHandle(handle)
        return bool(ok) and exit_code.value == 259
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Exists, just not ours to signal.
        return True
    return True


def _read_pid(path):
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return 0


def claim_lock():
    """
    Refuses to start a second bot alongside a live one.

    Returns True if we now hold the lock. Returns False if another instance is
    already running -- which is an ordinary outcome, not an error: the caller
    exits 0. Deliberately checks liveness rather than mere file existence, so a
    lock left behind by a crash names a dead PID and is simply reclaimed.

    Note this applies to hand-started bots too. That is the point: the game
    must not launch a duplicate next to one you started yourself. The NEWCOMER
    backs off -- nothing here ever kills the incumbent.
    """
    existing = _read_pid(LOCK_PATH)
    if existing and existing != os.getpid() and _pid_alive(existing):
        return False
    try:
        LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        LOCK_PATH.write_text(str(os.getpid()), encoding="utf-8")
    except OSError as e:
        # Not fatal -- run without the guard rather than refusing to start.
        print(f"[warn] could not write {LOCK_PATH}: {e}", flush=True)
    return True


def write_pid_file():
    """
    Marks this bot as game-owned so discord_bot_stop may reap it.

    Only called for --managed runs. A bot started by hand deliberately leaves
    no PID file, which is exactly what keeps the server's stop/orphan-sweep
    from ever touching it.
    """
    try:
        PID_PATH.parent.mkdir(parents=True, exist_ok=True)
        PID_PATH.write_text(str(os.getpid()), encoding="utf-8")
    except OSError as e:
        # Not fatal: the bot still works, it just cannot be stopped by script.
        print(f"[warn] could not write {PID_PATH}: {e}", flush=True)


def release_files():
    """
    Clears our lock and PID file on the way out.

    Only removes a file that names OUR pid -- if another instance has since
    claimed the lock, deleting it would let a third start alongside them.
    """
    for path in (PID_PATH, LOCK_PATH):
        try:
            if _read_pid(path) == os.getpid():
                path.unlink()
        except (OSError, FileNotFoundError):
            pass


def load_config():
    if not CONFIG_PATH.exists():
        sys.exit(
            f"ERROR: {CONFIG_PATH.relative_to(REPO).as_posix()} not found.\n"
            f"       Copy {EXAMPLE_PATH.relative_to(REPO).as_posix()} to it and fill it in."
        )
    try:
        cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR: {CONFIG_PATH.relative_to(REPO).as_posix()} is not valid JSON: {e}")

    token = cfg.get("token", "")
    # Refuse loudly rather than connecting and sitting there silent, which is
    # indistinguishable from the bot being broken.
    if not token or token == PLACEHOLDER_TOKEN:
        sys.exit(
            f"ERROR: no bot token set in {CONFIG_PATH.relative_to(REPO).as_posix()}.\n"
            "       Get one from the Discord Developer Portal (Applications ->\n"
            "       your app -> Bot -> Reset Token) and put it in 'token'."
        )
    return {
        "token": token,
        "host": cfg.get("game_host", "127.0.0.1"),
        "port": int(cfg.get("game_port", 6666)),
        # 10s, not 30s: a full persistence save runs ~18 seconds, so anything
        # slower than that can step straight over one and never observe it
        # live. Polling closer together than the save is long guarantees at
        # least one sample lands inside it, which is what makes the yellow dot
        # line up with the save actually happening rather than trailing it.
        # The endpoint is cheap and fail2topic-exempt, and presence is only
        # pushed on change, so the extra polls cost effectively nothing.
        "poll": max(5, int(cfg.get("poll_seconds", 10))),
        "timeout": max(1.0, float(cfg.get("timeout_seconds", 10))),
        # See the grace-window comment in the poll loop for why this is not 1.
        "offline_after": max(1, int(cfg.get("offline_after_failures", 3))),
        # Watchdog: seconds unreachable before a --managed bot exits on its
        # own. 300 is comfortably longer than a hard reboot takes to come back,
        # so a round restart never trips it. 0 disables it entirely.
        "exit_after_offline": max(0, int(cfg.get("exit_after_offline_seconds", 300))),
    }


def run_once(host, port, save_window=40):
    """--once: prove the Topic path works without involving Discord at all."""
    try:
        data = fetch_status(host, port)
    except TopicError as e:
        print(f"UNREACHABLE: {e}")
        return 1
    text, state = format_presence(data, save_window)
    print(f"presence: Watching {text}")
    print(f"state:    {state}")
    print(f"raw:      {json.dumps(data, indent=2, sort_keys=True)}")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Discord bot mirroring FS13 server status.")
    ap.add_argument("--once", action="store_true",
                    help="Poll once, print the result, and exit. Does not touch Discord -- "
                         "use this to check host/port and the Topic wire format first.")
    ap.add_argument("--host", help="Override game_host from the config.")
    ap.add_argument("--port", type=int, help="Override game_port from the config.")
    ap.add_argument("--managed", action="store_true",
                    help="Marks this as a SERVER-started bot: writes the PID file so the "
                         "server may stop it, and enables the self-exit watchdog. Passed "
                         "by scripts/discord_bot_start. Run WITHOUT it and the server "
                         "will never stop, reap or otherwise touch this bot.")
    args = ap.parse_args()

    # --once needs no token, so don't demand one just to test connectivity.
    if args.once:
        host = args.host or "127.0.0.1"
        port = args.port or 6666
        if CONFIG_PATH.exists():
            try:
                cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
                host = args.host or cfg.get("game_host", host)
                port = args.port or int(cfg.get("game_port", port))
            except (json.JSONDecodeError, ValueError):
                pass
        return run_once(host, port)

    cfg = load_config()
    host = args.host or cfg["host"]
    port = args.port or cfg["port"]

    # Refuse to become a second bot. Two instances sharing one token both push
    # presence and fight over it. Checked here rather than in the wrappers so
    # it holds however the bot was launched -- including catching a bot YOU
    # started by hand, which the server otherwise knows nothing about.
    #
    # The newcomer is the one that backs off. Nothing here ever kills the bot
    # that is already running.
    if not claim_lock():
        print(f"Another Discord status bot is already running (PID "
              f"{_read_pid(LOCK_PATH)}). Not starting a second one.", flush=True)
        return 0

    try:
        import discord
        from discord.ext import tasks
    except ImportError:
        release_files()
        sys.exit("ERROR: discord.py is not installed.  pip install discord.py")

    # No privileged intents: this bot only ever sets its own presence. Asking
    # for members/message_content would make it fail to start until they were
    # enabled in the developer portal, for no benefit.
    client = discord.Client(intents=discord.Intents.none())

    status_for = {
        "up": discord.Status.online,
        "saving": discord.Status.idle,
        "down": discord.Status.dnd,
    }

    # Last applied presence. Discord rate-limits presence updates, and a quiet
    # server produces an identical line every interval, so only push on change.
    last = {"text": None, "state": None}
    # Consecutive failed polls, for the grace window below.
    misses = {"count": 0}
    # When the server first went unreachable, for the watchdog below. None
    # whenever the server is answering.
    offline_since = {"at": None}

    async def apply(text, state):
        if last["text"] == text and last["state"] == state:
            return
        await client.change_presence(
            status=status_for[state],
            activity=discord.Activity(type=discord.ActivityType.watching, name=text),
        )
        last["text"], last["state"] = text, state
        print(f"[presence] {state}: {text}", flush=True)

    @tasks.loop(seconds=cfg["poll"])
    async def poll():
        try:
            # Off the event loop: fetch_status() is a blocking socket call, and
            # during a save the server can take the full timeout to answer.
            # Calling it inline would stall discord.py's gateway heartbeat for
            # that whole time, which at a short poll interval is enough to get
            # the bot disconnected.
            data = await asyncio.to_thread(fetch_status, host, port, cfg["timeout"])
        except TopicError as e:
            # A failed poll is expected, not exceptional -- the server is down,
            # restarting, or busy. Crucially it does NOT immediately mean
            # "offline": BYOND is single-threaded and serves world.Topic() on
            # the same thread that runs the persistence save, so a save long
            # enough to block past the socket timeout looks exactly like a dead
            # server. Flipping straight to red would show "offline" precisely
            # during a save -- the opposite of the truth, at the one moment
            # someone is most likely to be looking.
            #
            # So hold the last known presence for a few consecutive misses
            # before declaring offline. A genuinely dead server still goes red,
            # just a poll or two later; a save-induced blip never shows at all.
            misses["count"] += 1
            if offline_since["at"] is None:
                offline_since["at"] = time.monotonic()

            # Watchdog. A server-started bot outlives its server whenever the
            # server goes away by a route that never runs SSpersistence's
            # Shutdown() -- DreamDaemon being closed directly, a taskkill, a
            # crash. There is no reliable in-game hook for those, so the bot
            # reaps itself instead.
            #
            # ONLY for --managed bots. One started by hand is meant to outlive
            # the server for as long as its owner wants, and must never be
            # reaped by this.
            if args.managed and cfg["exit_after_offline"]:
                gone_for = time.monotonic() - offline_since["at"]
                if gone_for >= cfg["exit_after_offline"]:
                    print(f"[watchdog] server unreachable for {int(gone_for)}s "
                          f"(limit {cfg['exit_after_offline']}s) -- shutting down.",
                          flush=True)
                    poll.cancel()
                    await client.close()
                    return

            # Nothing to hold on to if we have never had a good poll (bot
            # started while the server was down), and nothing worth holding if
            # we are already showing offline -- otherwise a long outage would
            # log "holding 'server offline'" at itself forever.
            have_good_state = last["text"] is not None and last["state"] != "down"
            within_grace = misses["count"] < cfg["offline_after"]
            if within_grace and have_good_state:
                # Nothing applied -- the previous line stays up. Logged once so
                # a real outage is still visible in the console as it develops.
                print(f"[poll] miss {misses['count']}/{cfg['offline_after']} "
                      f"(holding '{last['text']}'): {e}", flush=True)
                return
            if last["state"] != "down":
                print(f"[poll] unreachable: {e}", flush=True)
            await apply("server offline", "down")
            return

        misses["count"] = 0
        offline_since["at"] = None
        # Window = one full poll cycle plus the timeout, so a save is still
        # reported as current on the next poll even when the poll that would
        # have caught it live timed out against the busy world thread.
        text, state = format_presence(data, cfg["poll"] + cfg["timeout"])
        await apply(text, state)

    @poll.before_loop
    async def before_poll():
        await client.wait_until_ready()

    @client.event
    async def on_ready():
        print(f"Connected as {client.user}. Polling {host}:{port} "
              f"every {cfg['poll']}s.", flush=True)
        if not poll.is_running():
            poll.start()

    # Only a server-started bot gets a PID file, and the PID file is the sole
    # thing the server's stop/orphan-sweep will act on. A hand-started bot
    # writes none and is therefore untouchable by the game.
    if args.managed:
        write_pid_file()

    try:
        client.run(cfg["token"], log_handler=None)
    except discord.LoginFailure:
        sys.exit("ERROR: Discord rejected the token. Check 'token' in "
                 f"{CONFIG_PATH.relative_to(REPO).as_posix()}.")
    finally:
        # Covers Ctrl-C, SIGTERM and the watchdog as well as a normal return --
        # a stale lock would make the next start think a bot is still running.
        release_files()
    return 0


if __name__ == "__main__":
    sys.exit(main())
