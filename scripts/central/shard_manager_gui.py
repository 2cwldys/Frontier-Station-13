"""
Frontier Station 13 -- standalone shard manager GUI.

A thin GUI over the db_central_*_shard.ps1/.sh scripts in this same
folder -- deliberately does NOT reimplement any Docker/central-DB logic
itself. Every action (Create/Start/Stop/Remove) shells out to the matching
script, exactly the same as running it from a terminal, or the in-game
admin TGUI panel triggering it via world.shelleo() -- one implementation,
three ways to trigger it. Only the shard LIST is read directly (a plain
SELECT against ss13_shards, same connection pattern db_admin_gui.py already
uses for the local DB, just pointed at central_dbconfig_admin.txt instead).

Requires: pip install pymysql
"""

import pathlib
import platform
import subprocess
import threading
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

import pymysql
import pymysql.cursors

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
AUTO_REFRESH_MS = 10000


# ============================================================
# Connection -- same "KEY value" parsing db_admin_gui.py already uses,
# pointed at the ADMIN tier central config (read-only use here: listing
# shards is a plain SELECT, never a write -- all writes go through the
# scripts, which use this same file themselves).
# ============================================================

def load_central_admin_config() -> dict:
    config = {
        "address": "localhost",
        "port": "3306",
        "database": "aurora_central",
        "login": "",
        "password": "",
    }
    config_path = REPO_ROOT / "config" / "central_dbconfig_admin.txt"
    if not config_path.exists():
        return config
    for raw_line in config_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or " " not in line:
            continue
        key, _, value = line.partition(" ")
        key = key.strip().lower()
        if key in config:
            config[key] = value.strip()
    return config


def connect(config: dict) -> pymysql.connections.Connection:
    return pymysql.connect(
        host=config["address"],
        port=int(config["port"]),
        user=config["login"],
        password=config["password"],
        database=config["database"],
        autocommit=True,
        cursorclass=pymysql.cursors.DictCursor,
    )


def fetch_shards(config: dict) -> list:
    conn = connect(config)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT shard_id, port, status, created_at, started_at "
                "FROM `ss13_shards` ORDER BY shard_id"
            )
            return cur.fetchall()
    finally:
        conn.close()


# ============================================================
# Script invocation -- picks .ps1 (Windows) or .sh (everything else),
# matching every other db_central_* tool's own dual-platform convention.
# ============================================================

def _script_path(base_name: str) -> tuple:
    if platform.system() == "Windows":
        return (["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                  str(SCRIPT_DIR / f"{base_name}.ps1")])
    return ["sh", str(SCRIPT_DIR / f"{base_name}.sh")]


def run_script(base_name: str, args: list) -> subprocess.CompletedProcess:
    cmd = _script_path(base_name) + args
    return subprocess.run(cmd, capture_output=True, text=True, cwd=str(SCRIPT_DIR))


def _flag(name: str) -> str:
    """--shard-id on POSIX (sh scripts), -ShardId on Windows (ps1 scripts)."""
    if platform.system() == "Windows":
        return "-" + "".join(p.capitalize() for p in name.split("-"))
    return "--" + name


# ============================================================
# GUI
# ============================================================

class ShardManagerApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        root.title("Aurora Shard Manager")
        root.geometry("760x460")

        self.config = load_central_admin_config()

        toolbar = ttk.Frame(root)
        toolbar.pack(fill="x", padx=8, pady=6)
        ttk.Button(toolbar, text="Create Shard...", command=self.create_shard).pack(side="left")
        ttk.Button(toolbar, text="Start", command=self.start_shard).pack(side="left", padx=4)
        ttk.Button(toolbar, text="Stop", command=self.stop_shard).pack(side="left")
        ttk.Button(toolbar, text="Remove...", command=self.remove_shard).pack(side="left", padx=4)
        ttk.Button(toolbar, text="Refresh", command=self.refresh).pack(side="left")
        self.status_label = ttk.Label(toolbar, text="")
        self.status_label.pack(side="right")

        columns = ("shard_id", "port", "status", "created_at", "started_at")
        self.tree = ttk.Treeview(root, columns=columns, show="headings", selectmode="browse")
        for col, width in zip(columns, (180, 80, 90, 160, 160)):
            self.tree.heading(col, text=col)
            self.tree.column(col, width=width, anchor="w")
        self.tree.pack(fill="both", expand=True, padx=8, pady=(0, 6))

        ttk.Label(root, text="Output:").pack(anchor="w", padx=8)
        self.output = tk.Text(root, height=10, wrap="word", state="disabled")
        self.output.pack(fill="both", expand=False, padx=8, pady=(0, 8))

        if not self.config["login"] or not self.config["password"]:
            self._log("config/central_dbconfig_admin.txt is missing LOGIN/PASSWORD -- "
                       "run db_central_setup first. The shard list below will stay empty until then.")

        self.refresh()
        self._schedule_auto_refresh()

    # -- helpers ------------------------------------------------------------

    def _log(self, text: str) -> None:
        self.output.configure(state="normal")
        self.output.insert("end", text.rstrip() + "\n\n")
        self.output.see("end")
        self.output.configure(state="disabled")

    def _selected_shard_id(self) -> str | None:
        selection = self.tree.selection()
        if not selection:
            messagebox.showinfo("No selection", "Select a shard first.")
            return None
        return self.tree.item(selection[0], "values")[0]

    def _schedule_auto_refresh(self) -> None:
        self.refresh(quiet=True)
        self.root.after(AUTO_REFRESH_MS, self._schedule_auto_refresh)

    def refresh(self, quiet: bool = False) -> None:
        try:
            rows = fetch_shards(self.config)
        except Exception as e:
            if not quiet:
                self._log(f"Failed to read ss13_shards: {e}")
            return
        self.tree.delete(*self.tree.get_children())
        for row in rows:
            self.tree.insert("", "end", values=(
                row["shard_id"], row["port"], row["status"],
                row["created_at"], row["started_at"] or "",
            ))
        self.status_label.configure(text=f"{len(rows)} shard(s)")

    def _run_async(self, base_name: str, args: list, busy_message: str) -> None:
        self.status_label.configure(text=busy_message)
        self.root.update_idletasks()

        def worker():
            result = run_script(base_name, args)
            self.root.after(0, lambda: self._on_script_done(result))

        threading.Thread(target=worker, daemon=True).start()

    def _on_script_done(self, result: subprocess.CompletedProcess) -> None:
        output = (result.stdout or "") + (result.stderr or "")
        self._log(output.strip() or f"(exit code {result.returncode}, no output)")
        self.refresh()

    # -- actions --------------------------------------------------------------

    def create_shard(self) -> None:
        shard_id = simpledialog.askstring("Create Shard", "Shard id (letters/digits/hyphen/underscore):")
        if not shard_id:
            return
        port = simpledialog.askstring("Create Shard", "Port (must be free):")
        if not port:
            return
        self._run_async(
            "db_central_add_shard",
            [_flag("shard-id"), shard_id, _flag("port"), port],
            f"Creating '{shard_id}'... this can take a while the first time (image build).",
        )

    def start_shard(self) -> None:
        shard_id = self._selected_shard_id()
        if not shard_id:
            return
        self._run_async(
            "db_central_start_shard",
            [_flag("shard-id"), shard_id],
            f"Starting '{shard_id}'...",
        )

    def stop_shard(self) -> None:
        shard_id = self._selected_shard_id()
        if not shard_id:
            return
        self._run_async(
            "db_central_stop_shard",
            [_flag("shard-id"), shard_id],
            f"Stopping '{shard_id}'...",
        )

    def remove_shard(self) -> None:
        shard_id = self._selected_shard_id()
        if not shard_id:
            return
        if not messagebox.askyesno(
            "Remove shard",
            f"Permanently remove '{shard_id}'? This deletes its containers, local data, "
            "and central DB login. This cannot be undone.",
        ):
            return
        self._run_async(
            "db_central_remove_shard",
            [_flag("shard-id"), shard_id, "--force" if platform.system() != "Windows" else "-Force"],
            f"Removing '{shard_id}'...",
        )


def main() -> None:
    root = tk.Tk()
    ShardManagerApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
