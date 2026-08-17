"""
Frontier-Station-13 -- BYOND version/build bumper.

Changes the BYOND version numbers that are scattered across four files, in
one place, listing exactly what it will touch and asking for confirmation
before writing anything. Doing this by hand is how they drift apart -- before
this script existed the CI pin said 516.1673 while the machine actually
compiling said 516.1682, and the client gate in config.txt still documented
2015-era values.

There are THREE independent knobs here and conflating them is the usual
mistake, so they are separate flags:

  --version           The BYOND MAJOR (516). Rarely changes.
  --build             The build the SERVER is pinned to (1687). This is what
                      CI installs and what you should have installed locally.
  --min-client-build  The oldest build a PLAYER may connect with. Does NOT
                      have to equal the server pin, and usually shouldn't --
                      Baystation, for instance, runs 516.1667 while only
                      refusing clients below 516.1659, so players get a grace
                      window instead of being locked out the moment the
                      server updates. Set 0 to disable the gate.

Comment state is always preserved: a line that is commented out stays
commented out, and vice versa. This script only ever rewrites the number.

IMPORTANT -- what this script deliberately does NOT do:

  * It does not touch the database. The live minimum client build can be
    overridden at runtime by the "Set Minimum Client Build" admin verb, which
    writes ss13_min_client_build, and that override WINS over config.txt. If
    one is set, editing config.txt here changes nothing that players will
    feel. The script detects this and warns rather than silently misleading
    you -- clear the override with the verb (set it to 0) to hand control
    back to config.
  * It does not install BYOND. Bumping --build only changes what CI installs
    and what the pin claims; update your own BYOND install to match.
  * It does not restart the server. config.txt is read once at boot.

Usage:

  python scripts/set_byond_version.py                        # report only, no prompts
  python scripts/set_byond_version.py --report-only          # the same, said explicitly
  python scripts/set_byond_version.py --build 1687 --dry-run # preview a pin bump
  python scripts/set_byond_version.py --build 1687
  python scripts/set_byond_version.py --min-client-build 1659
  python scripts/set_byond_version.py --version 517 --build 1700 --min-client-build 1700

Two read-only modes, answering different questions -- neither writes anything:

  --report-only   Where do things stand? Prints the affected files, their git
    (--check)     state, the current numbers, and any live DB override, then
                  stops. Overrides the version flags, so it is always safe to
                  append to a command you are unsure about.
  --dry-run       What exactly would change? Runs the whole thing including
                  the warnings, prints the unified diff it would apply, and
                  stops before writing.

Confirmation is a GUI popup (tkinter, same as db_admin_gui.py). Pass --no-gui
to confirm in the terminal instead -- that also happens automatically if no
display is available. --yes skips confirmation entirely.

Requires: nothing outside the standard library. The database check shells out
to the same `docker exec aurora-db mariadb` that db_update.ps1 uses, and is
skipped silently if docker or the container is unavailable.
"""

import argparse
import difflib
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

DEPENDENCIES = REPO / "dependencies.sh"
WORLD_DM = REPO / "code" / "game" / "world.dm"
CONFIG_LIVE = REPO / "config" / "config.txt"
CONFIG_EXAMPLE = REPO / "config" / "example" / "config.txt"

# Shown up front, before anything is read or changed, so it is always obvious
# what is in scope. Order matches the order they are written in.
AFFECTED_FILES = [
    (DEPENDENCIES, "BYOND_MAJOR / BYOND_MINOR",
     "what CI installs, and the build you should have installed locally"),
    (WORLD_DM, "RECOMMENDED_VERSION",
     "server-side major-version check -- logs a warning, never blocks"),
    (CONFIG_LIVE, "CLIENT_ERROR_VERSION, CLIENT_WARN_VERSION, MIN_CLIENT_BUILD",
     "the LIVE client gate -- this is the file players are actually judged against"),
    (CONFIG_EXAMPLE, "CLIENT_ERROR_VERSION, CLIENT_WARN_VERSION, MIN_CLIENT_BUILD",
     "the shipped template -- kept in step so a fresh install starts correct"),
]

# Every pattern below anchors to line start and captures the number as its own
# group, so the replacement only ever swaps digits. The optional leading "#?"
# is what preserves comment state -- it is captured in group 1 and written back
# verbatim, so this can never accidentally enable a disabled setting (or
# disable a live one, which on MIN_CLIENT_BUILD would quietly drop the gate).
#
# "#?KEY " with the trailing space also keeps MIN_CLIENT_BUILD from matching
# MIN_CLIENT_BUILD_MESSAGE, and keeps the "## prose mentioning
# CLIENT_ERROR_VERSION" comment lines from matching at all.

RE_BYOND_MAJOR = re.compile(r"^(export BYOND_MAJOR=)(\d+)$", re.MULTILINE)
RE_BYOND_MINOR = re.compile(r"^(export BYOND_MINOR=)(\d+)$", re.MULTILINE)
RE_RECOMMENDED = re.compile(r"^(#define RECOMMENDED_VERSION )(\d+)$", re.MULTILINE)
RE_CLIENT_ERROR = re.compile(r"^(#?CLIENT_ERROR_VERSION )(\d+)$", re.MULTILINE)
RE_CLIENT_WARN = re.compile(r"^(#?CLIENT_WARN_VERSION )(\d+)$", re.MULTILINE)
RE_MIN_BUILD = re.compile(r"^(#?MIN_CLIENT_BUILD )(\d+)$", re.MULTILINE)
# The player-facing message embeds a full "516.1687". Only the version pair is
# rewritten; the rest of the sentence is left exactly as written.
RE_MIN_BUILD_MSG = re.compile(r"^(#?MIN_CLIENT_BUILD_MESSAGE .*)$", re.MULTILINE)
RE_VERSION_PAIR = re.compile(r"\b(\d{3})\.(\d{4})\b")


def read(path):
    return path.read_text(encoding="utf-8")


def rel(path):
    return path.relative_to(REPO).as_posix()


# ---------------------------------------------------------------- popups ----

class Confirmer:
    """
    Confirmation front-end. Uses tkinter popups when a display is available,
    and degrades to terminal prompts when it is not (headless shell, --no-gui)
    rather than crashing -- this script is just as likely to be run over SSH
    as from the desktop.
    """

    def __init__(self, use_gui):
        self.root = None
        self.messagebox = None
        if not use_gui:
            return
        try:
            import tkinter as tk
            from tkinter import messagebox
            self.root = tk.Tk()
            self.root.withdraw()
            self.messagebox = messagebox
        except Exception:
            # No display, no tkinter, whatever -- terminal it is.
            self.root = None
            self.messagebox = None

    @property
    def gui(self):
        return self.messagebox is not None

    def warn(self, title, body):
        print(f"WARNING: {title}")
        for line in body.splitlines():
            print(f"         {line}")
        print()
        if self.gui:
            self.messagebox.showwarning(title, body)

    def ask(self, title, body):
        if self.gui:
            return bool(self.messagebox.askyesno(title, body, default="no"))
        print(body)
        return input("Write these changes? [y/N] ").strip().lower() in ("y", "yes")

    def done(self, title, body):
        print(body)
        if self.gui:
            self.messagebox.showinfo(title, body)

    def close(self):
        if self.root is not None:
            try:
                self.root.destroy()
            except Exception:
                pass


# ----------------------------------------------------------------- state ----

def current_values():
    """Scrapes the current numbers out of the files, for reporting."""
    deps = read(DEPENDENCIES)
    world = read(WORLD_DM)
    live = read(CONFIG_LIVE)

    def first(pattern, text):
        m = pattern.search(text)
        return m.group(2) if m else None

    return {
        "major": first(RE_BYOND_MAJOR, deps),
        "build": first(RE_BYOND_MINOR, deps),
        "recommended": first(RE_RECOMMENDED, world),
        "min_client_build": first(RE_MIN_BUILD, live),
        "min_client_build_enabled": bool(
            re.search(r"^MIN_CLIENT_BUILD \d+$", live, re.MULTILINE)
        ),
    }


def git_states():
    """
    Cross-checks the hardcoded AFFECTED_FILES list against git's actual view
    of the repo. Returns {relative_path: state} or None if git is unavailable.

    The point is not bookkeeping -- it is catching the case where this script
    is pointed at files git does not track (a stray copy, a bad REPO guess, a
    detached working directory), which would edit something that never reaches
    a commit. It also flags an already-staged target, because writing to the
    worktree on top of a staged change splits that file across the index and
    the worktree and makes it very easy to commit half of it.

    git status --porcelain gives "XY path", X = index, Y = worktree. A file
    absent from the output is unmodified.
    """
    paths = [rel(p) for p, _k, _w in AFFECTED_FILES]
    try:
        tracked = subprocess.run(
            ["git", "-C", str(REPO), "ls-files", "--"] + paths,
            capture_output=True, text=True, timeout=15,
        )
        status = subprocess.run(
            ["git", "-C", str(REPO), "status", "--porcelain", "--"] + paths,
            capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if tracked.returncode != 0 or status.returncode != 0:
        return None

    known = {line.strip() for line in tracked.stdout.splitlines() if line.strip()}
    states = {p: ("clean" if p in known else "UNTRACKED") for p in paths}

    for line in status.stdout.splitlines():
        if len(line) < 4:
            continue
        index_state, worktree_state, name = line[0], line[1], line[3:].strip().strip('"')
        if name not in states:
            continue
        if index_state == "?" or worktree_state == "?":
            states[name] = "UNTRACKED"
        elif index_state != " " and worktree_state != " ":
            states[name] = "staged + further modified"
        elif index_state != " ":
            states[name] = "staged"
        else:
            states[name] = "modified, not staged"
    return states


def db_override():
    """
    Best-effort read of the runtime override in ss13_min_client_build.

    Returns the build number, 0 if no override, or None if the database could
    not be reached at all (docker missing, container down, whatever). None is
    not an error -- it just means we can't warn about it.
    """
    cmd = [
        "docker", "exec", "-i", "aurora-db",
        "mariadb", "-u", "aurora", "-paurora", "aurora_persist",
        "-N", "-B", "-e", "SELECT build FROM ss13_min_client_build WHERE id = 1",
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    text = out.stdout.strip()
    if not text:
        return 0
    try:
        return int(text.splitlines()[0].strip())
    except ValueError:
        return None


# ----------------------------------------------------------------- edits ----

def apply_edits(text, edits):
    """edits is a list of (compiled_regex, new_number). Returns new text."""
    for pattern, value in edits:
        text = pattern.sub(lambda m: f"{m.group(1)}{value}", text)
    return text


def rewrite_message_versions(text, major, build):
    """Rewrites the MAJOR.BUILD pair inside MIN_CLIENT_BUILD_MESSAGE only."""
    def fix_line(m):
        return RE_VERSION_PAIR.sub(f"{major}.{build}", m.group(1))
    return RE_MIN_BUILD_MSG.sub(fix_line, text)


def diff_for(path, old, new):
    return list(difflib.unified_diff(
        old.splitlines(keepends=True),
        new.splitlines(keepends=True),
        fromfile=f"a/{rel(path)}",
        tofile=f"b/{rel(path)}",
    ))


# ------------------------------------------------------------------ main ----

def main():
    ap = argparse.ArgumentParser(
        description="Change the BYOND version/build across every file that pins one.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Run with no arguments to just report the current values.",
    )
    ap.add_argument("--version", type=int, metavar="MAJOR",
                    help="BYOND major version, e.g. 516.")
    ap.add_argument("--build", type=int, metavar="BUILD",
                    help="Build the server/CI is pinned to, e.g. 1687.")
    ap.add_argument("--min-client-build", type=int, metavar="BUILD",
                    help="Oldest build a player may connect with. 0 disables the gate.")
    # Two different "don't write" modes, because they answer different
    # questions. --report-only stops before computing any change and just
    # tells you where things stand; --dry-run goes all the way through and
    # shows the exact diff it WOULD apply. Both are safe, neither writes.
    ap.add_argument("--report-only", "--check", action="store_true", dest="report_only",
                    help="Print the affected files and current values, then exit. "
                         "Overrides the version flags, so it is always safe to add.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Compute and show the full diff, but write nothing.")
    ap.add_argument("--yes", "-y", action="store_true",
                    help="Skip confirmation entirely.")
    ap.add_argument("--no-gui", action="store_true",
                    help="Confirm in the terminal instead of a popup.")
    args = ap.parse_args()

    # ---- affected files, always first -------------------------------------
    git = git_states()
    print("Files this script edits")
    print("=======================")
    for path, keys, why in AFFECTED_FILES:
        mark = " " if path.exists() else "!"
        print(f" {mark} {rel(path)}")
        print(f"     sets: {keys}")
        print(f"     why:  {why}")
        if git is not None:
            print(f"     git:  {git.get(rel(path), 'unknown')}")
    if git is None:
        print("\n     (git unavailable -- file states not cross-checked)")
    print()

    missing = [p for p, _k, _w in AFFECTED_FILES if not p.exists()]
    if missing:
        sys.exit("ERROR: missing (marked ! above): "
                 + ", ".join(rel(p) for p in missing))

    # An untracked target means this script is editing something outside the
    # repo's history -- almost certainly the wrong copy. Refuse rather than
    # write into a file that will never reach a commit.
    if git is not None:
        untracked = [p for p, s in git.items() if s == "UNTRACKED"]
        if untracked:
            sys.exit("ERROR: git does not track these targets: "
                     + ", ".join(untracked)
                     + "\n       This script is pointed at the wrong copy of the repo.")

    cur = current_values()

    print("Current values")
    print("==============")
    print(f"  Server pin (dependencies.sh)        {cur['major']}.{cur['build']}")
    print(f"  RECOMMENDED_VERSION (world.dm)      {cur['recommended']}  (major only, warning only)")
    state = "ACTIVE" if cur["min_client_build_enabled"] else "commented out"
    print(f"  MIN_CLIENT_BUILD (config.txt)       {cur['min_client_build']}  [{state}]")

    override = db_override()
    if override is None:
        print("  DB override                         (database unreachable -- not checked)")
    elif override:
        print(f"  DB override (ss13_min_client_build) {override}  <-- ACTUALLY ENFORCED")
    else:
        print("  DB override                         none (config.txt applies)")
    print()

    # --report-only wins over the version flags on purpose: it is meant to be
    # the thing you can always append to a command you are unsure about,
    # without having to first delete the arguments to make it safe.
    if args.report_only:
        print("--report-only: stopping here, nothing computed or written.")
        if args.version is not None or args.build is not None or args.min_client_build is not None:
            print("             (the version flags you passed were ignored -- "
                  "drop --report-only, or use --dry-run to see the diff.)")
        return 0

    if args.version is None and args.build is None and args.min_client_build is None:
        print("Report only -- nothing to change.")
        print("Pass --version / --build / --min-client-build to edit,")
        print("or --report-only to make that explicit.")
        return 0

    confirm = Confirmer(use_gui=not args.no_gui and not args.yes and not args.dry_run)
    try:
        return run(args, cur, override, confirm, git)
    finally:
        confirm.close()


def run(args, cur, override, confirm, git):
    # Default to whatever is already there, so a partial change doesn't blank
    # out the rest.
    major = args.version if args.version is not None else int(cur["major"])
    build = args.build if args.build is not None else int(cur["build"])
    min_build = (args.min_client_build if args.min_client_build is not None
                 else int(cur["min_client_build"] or 0))

    # A client floor above the server's own pin refuses essentially everyone,
    # since players cannot be running a build the server itself predates. This
    # is the exact trap a hand-edit walks into, so it is loud.
    if min_build and min_build > build:
        confirm.warn(
            "Client floor is newer than the server",
            f"--min-client-build {min_build} is NEWER than the server pin "
            f"{major}.{build}.\n\n"
            "That refuses essentially every player. Admins stay exempt, so you\n"
            "would not notice until someone else tried to connect."
        )

    if args.min_client_build is not None and override:
        confirm.warn(
            "A database override is already set",
            f"ss13_min_client_build is set to {override}, and it takes priority\n"
            "over config.txt.\n\n"
            "Editing MIN_CLIENT_BUILD here will have NO effect on players until\n"
            "you clear that override with the 'Set Minimum Client Build' admin\n"
            "verb (set it to 0)."
        )

    planned = {
        DEPENDENCIES: [(RE_BYOND_MAJOR, major), (RE_BYOND_MINOR, build)],
        WORLD_DM: [(RE_RECOMMENDED, major)],
        CONFIG_LIVE: [(RE_CLIENT_ERROR, major), (RE_CLIENT_WARN, major),
                      (RE_MIN_BUILD, min_build)],
        CONFIG_EXAMPLE: [(RE_CLIENT_ERROR, major), (RE_CLIENT_WARN, major),
                         (RE_MIN_BUILD, min_build)],
    }

    changes = {}
    for path, edits in planned.items():
        old = read(path)
        new = apply_edits(old, edits)
        if path in (CONFIG_LIVE, CONFIG_EXAMPLE):
            new = rewrite_message_versions(new, major, min_build or build)
        if new != old:
            changes[path] = (old, new)

    if not changes:
        print("Every file already holds these values. Nothing to do.")
        return 0

    print("Files that will change")
    print("======================")
    for path in changes:
        state = git.get(rel(path), "unknown") if git is not None else "unchecked"
        print(f"  {rel(path)}  [git: {state}]")
    print()

    # Writing into the worktree on top of an already-staged change leaves that
    # file split between the index and the worktree, which is how you end up
    # committing the old number and shipping the new one (or vice versa).
    if git is not None:
        staged = [rel(p) for p in changes if git.get(rel(p), "").startswith("staged")]
        if staged:
            confirm.warn(
                "Targets already have staged changes",
                "These files are staged, and this script writes to the WORKTREE:\n\n"
                + "\n".join(f"  - {p}" for p in staged)
                + "\n\nAfter writing, each will have a staged version and a different\n"
                  "worktree version. Re-stage them (git add) before committing, or\n"
                  "you will commit the old numbers."
            )

    print("Planned changes")
    print("===============")
    for path, (old, new) in changes.items():
        for line in diff_for(path, old, new):
            sys.stdout.write(line)
    print()

    if args.dry_run:
        print("--dry-run: nothing written.")
        return 0

    if not args.yes:
        summary = (
            f"Apply these BYOND version changes?\n\n"
            f"  Server pin        {cur['major']}.{cur['build']}  ->  {major}.{build}\n"
            f"  Min client build  {cur['min_client_build']}  ->  {min_build or 'disabled (0)'}\n\n"
            f"Writing to {len(changes)} file(s):\n"
            + "\n".join(f"  - {rel(p)}" for p in changes)
        )
        if not confirm.ask("Confirm BYOND version change", summary):
            print("Aborted. Nothing written.")
            return 1

    for path, (_old, new) in changes.items():
        path.write_text(new, encoding="utf-8", newline="")
        print(f"  wrote {rel(path)}")
    print()

    steps = []
    if args.build is not None:
        steps.append(f"Install BYOND {major}.{build} locally -- the pin now claims it, but\n"
                     "your machine compiles with whatever is in your BYOND folder.")
        steps.append("Recompile:  scripts\\debug-compile.ps1 -ReportOnly")
    if args.min_client_build is not None:
        steps.append("config.txt is read once at boot -- restart the server, OR set the\n"
                     "new minimum live with the 'Set Minimum Client Build' admin verb.")
    body = "Files written.\n\nRemaining steps this script cannot do for you:\n\n" + \
           "\n\n".join(f"  {i}. {s}" for i, s in enumerate(steps, 1))
    confirm.done("BYOND version updated", body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
