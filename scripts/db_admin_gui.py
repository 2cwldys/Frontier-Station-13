"""
Aurora-Persistence -- standalone DB admin GUI.

Browses/edits the live MariaDB database directly (the same database
DreamDaemon uses), completely independently of whether the game server is
running or not -- same reasoning as stock_market_daemon.py, which this
script's connection handling is copied from almost verbatim. Three tabs:

  - Browse & Edit: pick a table, page/filter its rows, double-click a cell
    to edit it in place, add/delete rows.
  - Raw SQL: free-text SQL execution for anything the grid doesn't cover.
  - Migrations: cross-references SQL/migrate-2023/V*.sql against the live
    schema (information_schema) to show which migrations are actually
    applied vs. still pending. There is no migrations-tracking table in
    this project -- db_update.ps1 just force-reapplies every file every
    time -- so existence-checking the real schema is the only way to tell
    without reading DB error logs (this is exactly what silently broke the
    faction cache once already).

Requires: pip install pymysql psutil
"""

import pathlib
import re
import tkinter as tk
from tkinter import messagebox, ttk

import psutil
import pymysql
import pymysql.cursors

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = REPO_ROOT / "SQL" / "migrate-2023"
ROW_PAGE_SIZE = 200
AUTO_REFRESH_MS = 5000


# ============================================================
# Connection (mirrors stock_market_daemon.py's load_db_config()/connect())
# ============================================================

def load_db_config() -> dict:
    """Parses config/dbconfig.txt the same way GetDBConfig() (dbcore.dm)
    does -- "KEY value" per line, blank/# lines ignored -- falling back to
    the docker-compose dev defaults if the file is missing."""
    config = {
        "address": "localhost",
        "port": "3306",
        "database": "aurora_persist",
        "login": "aurora",
        "password": "aurora",
    }
    config_path = REPO_ROOT / "config" / "dbconfig.txt"
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


def is_dreamdaemon_running() -> bool:
    for proc in psutil.process_iter(["name"]):
        try:
            name = proc.info.get("name") or ""
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
        if "dreamdaemon" in name.lower():
            return True
    return False


# ============================================================
# Schema introspection
# ============================================================

def list_tables(conn) -> list:
    with conn.cursor() as cur:
        cur.execute("SHOW TABLES")
        rows = cur.fetchall()
    # DictCursor keys this "Tables_in_<database>" -- grab the value regardless of the key name.
    return sorted(next(iter(row.values())) for row in rows)


def get_columns(conn, table: str) -> list:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT "
            "FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = %s "
            "ORDER BY ORDINAL_POSITION",
            (table,),
        )
        return cur.fetchall()


def get_primary_key_columns(conn, table: str) -> list:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT COLUMN_NAME FROM information_schema.key_column_usage "
            "WHERE table_schema = DATABASE() AND table_name = %s AND CONSTRAINT_NAME = 'PRIMARY' "
            "ORDER BY ORDINAL_POSITION",
            (table,),
        )
        return [row["COLUMN_NAME"] for row in cur.fetchall()]


# ============================================================
# Migration file parsing -- best-effort regex, not a real SQL parser.
# Good enough for this project's migrations, which are consistently plain
# ALTER TABLE ADD COLUMN / CREATE TABLE IF NOT EXISTS statements with no
# stored procedures or DELIMITER blocks (confirmed against V129-V133).
# ============================================================

_CREATE_TABLE_RE = re.compile(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?(\w+)`?", re.IGNORECASE)
_ALTER_TABLE_RE = re.compile(r"ALTER\s+TABLE\s+`?(\w+)`?", re.IGNORECASE)
_ADD_COLUMN_RE = re.compile(r"ADD\s+COLUMN\s+`?(\w+)`?", re.IGNORECASE)


def parse_migration_targets(sql_text: str) -> list:
    """Returns a list of ("table", name) or ("column", table, name) tuples
    this migration file declares."""
    targets = []
    for statement in sql_text.split(";"):
        statement = statement.strip()
        if not statement:
            continue
        create_match = _CREATE_TABLE_RE.search(statement)
        if create_match:
            targets.append(("table", create_match.group(1)))
            continue
        alter_match = _ALTER_TABLE_RE.search(statement)
        if alter_match:
            table = alter_match.group(1)
            for col_match in _ADD_COLUMN_RE.finditer(statement):
                targets.append(("column", table, col_match.group(1)))
    return targets


def migration_status(conn, sql_text: str) -> str:
    """Returns "Applied", "Pending", or "Unparseable"."""
    targets = parse_migration_targets(sql_text)
    if not targets:
        return "Unparseable"
    with conn.cursor() as cur:
        for target in targets:
            if target[0] == "table":
                cur.execute(
                    "SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = %s",
                    (target[1],),
                )
            else:
                cur.execute(
                    "SELECT 1 FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = %s AND column_name = %s",
                    (target[1], target[2]),
                )
            if not cur.fetchone():
                return "Pending"
    return "Applied"


def run_migration(conn, sql_text: str) -> tuple:
    """Executes every statement in the file, tolerating "already exists"-style
    errors the same way db_update.ps1's --force flag does. Returns
    (statements_applied, list_of_error_strings)."""
    applied = 0
    errors = []
    with conn.cursor() as cur:
        for statement in sql_text.split(";"):
            statement = statement.strip()
            if not statement:
                continue
            try:
                cur.execute(statement)
                applied += 1
            except pymysql.MySQLError as exc:
                errors.append(str(exc))
    return applied, errors


# ============================================================
# Browse & Edit tab
# ============================================================

class BrowseTab(ttk.Frame):
    def __init__(self, parent, get_conn):
        super().__init__(parent)
        self.get_conn = get_conn
        self.current_table = None
        self.current_columns = []
        self.pk_columns = []
        self.offset = 0
        self.filter_var = tk.StringVar()
        self.auto_refresh_var = tk.BooleanVar(value=False)
        self._build_ui()
        self._auto_refresh_tick()

    def _build_ui(self):
        left = ttk.Frame(self)
        left.pack(side="left", fill="y")
        ttk.Label(left, text="Tables").pack()
        self.table_list = tk.Listbox(left, width=32, exportselection=False)
        self.table_list.pack(fill="y", expand=True)
        self.table_list.bind("<<ListboxSelect>>", self._on_table_selected)
        ttk.Button(left, text="Refresh Table List", command=self.reload_tables).pack(fill="x")

        right = ttk.Frame(self)
        right.pack(side="left", fill="both", expand=True)

        controls = ttk.Frame(right)
        controls.pack(fill="x")
        ttk.Label(controls, text="Filter (raw WHERE clause):").pack(side="left")
        filter_entry = ttk.Entry(controls, textvariable=self.filter_var, width=50)
        filter_entry.pack(side="left", fill="x", expand=True)
        filter_entry.bind("<Return>", lambda event: self.reload_rows())
        ttk.Button(controls, text="Apply Filter", command=self.reload_rows).pack(side="left")
        ttk.Button(controls, text="Refresh", command=self.reload_rows).pack(side="left")
        ttk.Checkbutton(controls, text="Auto-refresh (5s)", variable=self.auto_refresh_var).pack(side="left")

        pager = ttk.Frame(right)
        pager.pack(fill="x")
        ttk.Button(pager, text="<< Prev Page", command=self._prev_page).pack(side="left")
        ttk.Button(pager, text="Next Page >>", command=self._next_page).pack(side="left")
        self.page_label = ttk.Label(pager, text="")
        self.page_label.pack(side="left", padx=8)
        ttk.Button(pager, text="Add Row", command=self._add_row_dialog).pack(side="right")

        tree_frame = ttk.Frame(right)
        tree_frame.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(tree_frame, show="headings")
        vsb = ttk.Scrollbar(tree_frame, orient="vertical", command=self.tree.yview)
        hsb = ttk.Scrollbar(tree_frame, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        hsb.grid(row=1, column=0, sticky="ew")
        tree_frame.rowconfigure(0, weight=1)
        tree_frame.columnconfigure(0, weight=1)

        self.tree.bind("<Double-1>", self._on_cell_double_click)
        self.tree.bind("<Button-3>", self._on_right_click)

    def reload_tables(self):
        self.table_list.delete(0, "end")
        try:
            conn = self.get_conn()
            for name in list_tables(conn):
                self.table_list.insert("end", name)
        except Exception as exc:
            messagebox.showerror("Error", f"Failed to list tables: {exc}")

    def _on_table_selected(self, event):
        selection = self.table_list.curselection()
        if not selection:
            return
        self.current_table = self.table_list.get(selection[0])
        self.offset = 0
        self.reload_rows()

    def reload_rows(self):
        if not self.current_table:
            return
        try:
            conn = self.get_conn()
            self.current_columns = get_columns(conn, self.current_table)
            self.pk_columns = get_primary_key_columns(conn, self.current_table)
            col_names = [c["COLUMN_NAME"] for c in self.current_columns]

            self.tree.delete(*self.tree.get_children())
            self.tree["columns"] = col_names
            for name in col_names:
                self.tree.heading(name, text=name)
                self.tree.column(name, width=120, stretch=False)

            where_clause = ""
            filter_text = self.filter_var.get().strip()
            if filter_text:
                where_clause = f" WHERE {filter_text}"

            query = f"SELECT * FROM `{self.current_table}`{where_clause} LIMIT %s OFFSET %s"
            with conn.cursor() as cur:
                cur.execute(query, (ROW_PAGE_SIZE, self.offset))
                rows = cur.fetchall()

            for row in rows:
                self.tree.insert("", "end", values=[row.get(name) for name in col_names])

            self.page_label.config(text=f"Rows {self.offset}-{self.offset + len(rows)}")
        except Exception as exc:
            messagebox.showerror("Error", f"Failed to load rows: {exc}")

    def _prev_page(self):
        self.offset = max(0, self.offset - ROW_PAGE_SIZE)
        self.reload_rows()

    def _next_page(self):
        self.offset += ROW_PAGE_SIZE
        self.reload_rows()

    def _on_cell_double_click(self, event):
        region = self.tree.identify_region(event.x, event.y)
        if region != "cell":
            return
        row_id = self.tree.identify_row(event.y)
        col_id = self.tree.identify_column(event.x)
        if not row_id or not col_id:
            return
        col_index = int(col_id.replace("#", "")) - 1
        col_names = self.tree["columns"]
        col_name = col_names[col_index]
        current_value = self.tree.set(row_id, col_name)

        bbox = self.tree.bbox(row_id, col_id)
        if not bbox:
            return
        x, y, width, height = bbox
        edit_var = tk.StringVar(value=current_value)
        entry = ttk.Entry(self.tree, textvariable=edit_var)
        entry.place(x=x, y=y, width=width, height=height)
        entry.focus()
        entry.select_range(0, "end")

        def commit(event=None):
            new_value = edit_var.get()
            entry.destroy()
            if new_value != current_value:
                self._update_cell(row_id, col_name, current_value, new_value)

        def cancel(event=None):
            entry.destroy()

        entry.bind("<Return>", commit)
        entry.bind("<Escape>", cancel)
        entry.bind("<FocusOut>", commit)

    def _update_cell(self, row_id, col_name, old_value, new_value):
        col_names = self.tree["columns"]
        row_values = self.tree.item(row_id, "values")
        row_dict = dict(zip(col_names, row_values))

        if not self.pk_columns:
            if not messagebox.askyesno(
                "No primary key",
                f"Table '{self.current_table}' has no primary key -- this edit will "
                f"match on every current column's value, which could affect more than "
                f"one row if duplicates exist. Continue?",
            ):
                return
            where_cols = col_names
        else:
            where_cols = self.pk_columns

        set_clause = f"`{col_name}` = %s"
        where_clause = " AND ".join(f"`{c}` <=> %s" for c in where_cols)
        params = [new_value] + [row_dict[c] for c in where_cols]

        try:
            conn = self.get_conn()
            with conn.cursor() as cur:
                cur.execute(
                    f"UPDATE `{self.current_table}` SET {set_clause} WHERE {where_clause}",
                    params,
                )
            self.tree.set(row_id, col_name, new_value)
        except Exception as exc:
            messagebox.showerror("Error", f"Update failed: {exc}")

    def _on_right_click(self, event):
        row_id = self.tree.identify_row(event.y)
        if not row_id:
            return
        self.tree.selection_set(row_id)
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Delete Row", command=lambda: self._delete_row(row_id))
        menu.post(event.x_root, event.y_root)

    def _delete_row(self, row_id):
        if not messagebox.askyesno("Confirm delete", "Delete this row? This cannot be undone."):
            return
        col_names = self.tree["columns"]
        row_values = self.tree.item(row_id, "values")
        row_dict = dict(zip(col_names, row_values))
        where_cols = self.pk_columns or col_names
        where_clause = " AND ".join(f"`{c}` <=> %s" for c in where_cols)
        params = [row_dict[c] for c in where_cols]
        try:
            conn = self.get_conn()
            with conn.cursor() as cur:
                cur.execute(f"DELETE FROM `{self.current_table}` WHERE {where_clause}", params)
            self.tree.delete(row_id)
        except Exception as exc:
            messagebox.showerror("Error", f"Delete failed: {exc}")

    def _add_row_dialog(self):
        if not self.current_table:
            return
        dialog = tk.Toplevel(self)
        dialog.title(f"Add row to {self.current_table}")
        entries = {}
        for i, col in enumerate(self.current_columns):
            name = col["COLUMN_NAME"]
            default = col["COLUMN_DEFAULT"]
            ttk.Label(dialog, text=name).grid(row=i, column=0, sticky="w", padx=4, pady=2)
            var = tk.StringVar(value=default if default is not None else "")
            ttk.Entry(dialog, textvariable=var, width=40).grid(row=i, column=1, padx=4, pady=2)
            entries[name] = var

        def submit():
            col_names = list(entries.keys())
            values = [entries[c].get() for c in col_names]
            columns_sql = ", ".join(f"`{c}`" for c in col_names)
            placeholders = ", ".join(["%s"] * len(col_names))
            try:
                conn = self.get_conn()
                with conn.cursor() as cur:
                    cur.execute(
                        f"INSERT INTO `{self.current_table}` ({columns_sql}) VALUES ({placeholders})",
                        values,
                    )
                dialog.destroy()
                self.reload_rows()
            except Exception as exc:
                messagebox.showerror("Error", f"Insert failed: {exc}")

        ttk.Button(dialog, text="Insert", command=submit).grid(
            row=len(self.current_columns), column=0, columnspan=2, pady=6
        )

    def _auto_refresh_tick(self):
        if self.auto_refresh_var.get() and self.current_table:
            self.reload_rows()
        self.after(AUTO_REFRESH_MS, self._auto_refresh_tick)


# ============================================================
# Raw SQL tab
# ============================================================

class SqlTab(ttk.Frame):
    def __init__(self, parent, get_conn):
        super().__init__(parent)
        self.get_conn = get_conn
        self._build_ui()

    def _build_ui(self):
        top = ttk.Frame(self)
        top.pack(fill="x")
        self.sql_text = tk.Text(top, height=8)
        self.sql_text.pack(fill="x", expand=True, side="left")
        self.sql_text.bind("<Control-Return>", lambda event: self.execute())
        ttk.Button(top, text="Execute\n(Ctrl+Enter)", command=self.execute).pack(side="left", padx=6)

        self.result_label = ttk.Label(self, text="")
        self.result_label.pack(fill="x")

        tree_frame = ttk.Frame(self)
        tree_frame.pack(fill="both", expand=True)
        self.tree = ttk.Treeview(tree_frame, show="headings")
        vsb = ttk.Scrollbar(tree_frame, orient="vertical", command=self.tree.yview)
        hsb = ttk.Scrollbar(tree_frame, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        hsb.grid(row=1, column=0, sticky="ew")
        tree_frame.rowconfigure(0, weight=1)
        tree_frame.columnconfigure(0, weight=1)

    def execute(self):
        sql = self.sql_text.get("1.0", "end").strip()
        if not sql:
            return
        try:
            conn = self.get_conn()
            with conn.cursor() as cur:
                cur.execute(sql)
                if cur.description:
                    rows = cur.fetchall()
                    col_names = [d[0] for d in cur.description]
                    self.tree.delete(*self.tree.get_children())
                    self.tree["columns"] = col_names
                    for name in col_names:
                        self.tree.heading(name, text=name)
                        self.tree.column(name, width=120, stretch=False)
                    for row in rows:
                        self.tree.insert("", "end", values=[row.get(name) for name in col_names])
                    self.result_label.config(text=f"{len(rows)} row(s) returned.")
                else:
                    self.tree.delete(*self.tree.get_children())
                    self.tree["columns"] = ()
                    self.result_label.config(text=f"{cur.rowcount} row(s) affected.")
        except Exception as exc:
            messagebox.showerror("Error", str(exc))


# ============================================================
# Migrations tab
# ============================================================

class MigrationsTab(ttk.Frame):
    def __init__(self, parent, get_conn):
        super().__init__(parent)
        self.get_conn = get_conn
        self._build_ui()

    def _build_ui(self):
        top = ttk.Frame(self)
        top.pack(fill="x")
        ttk.Button(top, text="Refresh Status", command=self.reload).pack(side="left")
        ttk.Button(top, text="Run Selected", command=self.run_selected).pack(side="left")
        ttk.Button(top, text="Run All Pending", command=self.run_all_pending).pack(side="left")

        self.tree = ttk.Treeview(self, columns=("status",), show="tree headings")
        self.tree.heading("#0", text="Migration file")
        self.tree.heading("status", text="Status")
        self.tree.column("status", width=140, anchor="center")
        self.tree.pack(fill="both", expand=True)
        self.tree.tag_configure("applied", foreground="#1a7f1a")
        self.tree.tag_configure("pending", foreground="#b02020")
        self.tree.tag_configure("unparseable", foreground="#808080")

    def reload(self):
        self.tree.delete(*self.tree.get_children())
        if not MIGRATIONS_DIR.exists():
            return
        try:
            conn = self.get_conn()
        except Exception as exc:
            messagebox.showerror("Error", f"Failed to connect: {exc}")
            return
        for path in sorted(MIGRATIONS_DIR.glob("V*.sql")):
            sql_text = path.read_text(encoding="utf-8", errors="ignore")
            try:
                status = migration_status(conn, sql_text)
            except Exception as exc:
                status = f"Error: {exc}"
            tag = status.lower() if status in ("Applied", "Pending", "Unparseable") else ""
            self.tree.insert("", "end", iid=str(path), text=path.name, values=(status,), tags=(tag,))

    def _selected_paths(self):
        return [pathlib.Path(iid) for iid in self.tree.selection()]

    def run_selected(self):
        paths = self._selected_paths()
        if not paths:
            messagebox.showinfo("Nothing selected", "Select one or more migration files first.")
            return
        self._run_paths(paths)

    def run_all_pending(self):
        pending = [
            pathlib.Path(iid)
            for iid in self.tree.get_children()
            if self.tree.set(iid, "status") == "Pending"
        ]
        if not pending:
            messagebox.showinfo("Nothing pending", "No pending migrations found.")
            return
        if not messagebox.askyesno("Run all pending", f"Run {len(pending)} pending migration(s)?"):
            return
        self._run_paths(pending)

    def _run_paths(self, paths):
        try:
            conn = self.get_conn()
        except Exception as exc:
            messagebox.showerror("Error", f"Failed to connect: {exc}")
            return
        summary = []
        for path in paths:
            sql_text = path.read_text(encoding="utf-8", errors="ignore")
            applied, errors = run_migration(conn, sql_text)
            line = f"{path.name}: {applied} statement(s) applied"
            if errors:
                line += f", {len(errors)} error(s) (see console)"
                for err in errors:
                    print(f"[{path.name}] {err}")
            summary.append(line)
        messagebox.showinfo("Migration run complete", "\n".join(summary))
        self.reload()


# ============================================================
# App shell
# ============================================================

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Aurora-Persistence -- DB Admin")
        self.geometry("1150x720")

        self.config_data = load_db_config()
        self._conn = None

        notebook = ttk.Notebook(self)
        notebook.pack(fill="both", expand=True)

        self.browse_tab = BrowseTab(notebook, self.get_conn)
        self.sql_tab = SqlTab(notebook, self.get_conn)
        self.migrations_tab = MigrationsTab(notebook, self.get_conn)
        notebook.add(self.browse_tab, text="Browse & Edit")
        notebook.add(self.sql_tab, text="Raw SQL")
        notebook.add(self.migrations_tab, text="Migrations")

        self.status_var = tk.StringVar()
        status_bar = ttk.Label(self, textvariable=self.status_var, relief="sunken", anchor="w")
        status_bar.pack(fill="x", side="bottom")

        try:
            self.get_conn()
            self.browse_tab.reload_tables()
            self.migrations_tab.reload()
        except Exception as exc:
            messagebox.showerror("Connection failed", str(exc))

        self._update_status()

    def get_conn(self):
        if self._conn is None:
            self._conn = connect(self.config_data)
            return self._conn
        try:
            self._conn.ping(reconnect=True)
        except Exception:
            self._conn = connect(self.config_data)
        return self._conn

    def _update_status(self):
        server_state = "running" if is_dreamdaemon_running() else "stopped"
        target = f"{self.config_data['address']}:{self.config_data['port']}/{self.config_data['database']}"
        self.status_var.set(f"  DB: {target}    |    Game server: {server_state}")
        self.after(AUTO_REFRESH_MS, self._update_status)


def main():
    app = App()
    app.mainloop()


if __name__ == "__main__":
    main()
