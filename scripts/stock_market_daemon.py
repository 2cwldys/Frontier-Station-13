"""
Idris Stock Exchange -- standalone server-side daemon.

Keeps the stock market ticking against the same MySQL database DreamDaemon
uses (ss13_stock_companies/ss13_stock_holdings/ss13_stock_price_history/
ss13_faction_accounts/ss13_factions) even while the game server is stopped,
and shows a live console view of the market either way. The moment DreamDaemon
is detected running, this daemon stops writing -- SSstock_market (stock_market.dm)
owns the tick at that point -- but keeps reading/displaying, since that's
always safe to do concurrently.

Ports two DM procs from code/controllers/subsystems/stock_market.dm 1:1:
  - /datum/stock_company/proc/tick_price() -> gbm_tick() (AI-simulated
    companies: GBM random walk with mean-reversion + a rare jump).
  - /datum/stock_company/proc/sync_price_to_treasury() -> treasury_tick()
    (faction-listed companies: price IS the faction's own treasury balance
    per share -- no random walk at all).
And one from code/controllers/subsystems/persistence/persistence_stock_market.dm:
  - stockMarketRevokeFaction()'s automatic-insolvency branch +
    removeFactionCompletely() -> liquidate_faction_company() (a faction-listed
    company whose treasury hits zero or below is delisted and the faction
    itself is dissolved, exactly like the in-game auto-liquidation path --
    "even if offline" is the whole point of this script existing).

Requires: pip install pymysql psutil rich
"""

import math
import pathlib
import random
import time

import psutil
import pymysql
import pymysql.cursors
from rich.console import Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table

TICK_INTERVAL = 5.0  # seconds -- matches SUBSYSTEM_DEF(stock_market)'s wait
DISPLAY_INTERVAL = 1.0  # console refresh, independent of the tick cadence
HISTORY_KEEP = 200  # matches stockMarketSaveCompanies()'s own prune target
EVENT_LOG_LINES = 6


def load_db_config(repo_root: pathlib.Path) -> dict:
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
    config_path = repo_root / "config" / "dbconfig.txt"
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


def gbm_tick(company: dict) -> dict:
    """Python port of /datum/stock_company/proc/tick_price() -- same GBM-
    with-mean-reversion formula, same 2%-chance discrete news jump, same
    max(1, round(...)) floor. AI-simulated companies only (faction_uid IS
    NULL) -- a faction-listed company never takes this path."""
    sigma = float(company["volatility"]) / 100
    base_price = company["base_price"]
    current_price = company["current_price"]
    mean_reversion = (base_price - current_price) / max(base_price, 1) * 0.05
    mu = mean_reversion + 0.5 * sigma**2
    z = random.gauss(0, 1)
    log_return = (mu - 0.5 * sigma**2) + sigma * z
    if random.random() < 0.02:
        log_return += random.randint(-8, 8) / 100
    new_price = max(1, round(current_price * math.exp(log_return)))
    return {
        "previous_price": current_price,
        "current_price": new_price,
        "price_high": max(company["price_high"], new_price),
        "price_low": min(company["price_low"], new_price),
    }


def treasury_tick(company: dict, balance) -> dict:
    """Python port of /datum/stock_company/proc/sync_price_to_treasury() --
    price IS the faction's own treasury book value per share, recomputed
    every tick regardless of anyone watching. balance <= 0 rounds this to
    exactly 0 (see liquidate_faction_company())."""
    current_price = company["current_price"]
    new_price = max(0, round((balance or 0) / max(company["total_shares_outstanding"], 1)))
    return {
        "previous_price": current_price,
        "current_price": new_price,
        "price_high": max(company["price_high"], new_price),
        "price_low": min(company["price_low"], new_price),
    }


def liquidate_faction_company(cur, company: dict) -> str:
    """Python port of stockMarketRevokeFaction()'s automatic-insolvency
    branch + removeFactionCompletely() (persistence_stock_market.dm /
    persistence_factions.dm). By the time a treasury balance hits zero,
    treasury_tick() has already rounded current_price to exactly 0 (balance
    / shares), so there is never a real per-share payout to compute here --
    shareholders are wiped out along with the faction, same as the in-game
    path. Deleting the ss13_stock_companies row cascades (ON DELETE CASCADE)
    to ss13_stock_holdings and ss13_stock_price_history; deleting the
    ss13_factions row cascades to ss13_faction_accounts/ss13_faction_jobs --
    the faction ceases to exist entirely and would have to be founded again
    from scratch in-game."""
    cur.execute("DELETE FROM ss13_stock_companies WHERE company_id = %s", (company["company_id"],))
    cur.execute("DELETE FROM ss13_factions WHERE uid = %s", (company["faction_uid"],))
    return f"BANKRUPTCY: {company['ticker']} ({company['faction_uid']}) treasury depleted -- delisted and faction dissolved."


def simulate_tick(conn) -> list:
    """One full tick across every company -- mirrors SSstock_market/fire()
    (stock_market.dm): AI companies get gbm_tick(), faction companies get
    treasury_tick() (and liquidate_faction_company() if that leaves their
    balance at or below zero). Returns any event log lines produced."""
    events = []
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM ss13_stock_companies")
        companies = cur.fetchall()

        for company in companies:
            if company["faction_uid"]:
                cur.execute(
                    "SELECT balance FROM ss13_faction_accounts WHERE faction_uid = %s",
                    (company["faction_uid"],),
                )
                row = cur.fetchone()
                if row is None:
                    continue  # faction gone from the DB entirely -- leave the listing for an admin to sort out
                balance = row["balance"]
                updated = treasury_tick(company, balance)
                if balance <= 0:
                    events.append(liquidate_faction_company(cur, company))
                    continue
            else:
                updated = gbm_tick(company)

            cur.execute(
                "UPDATE ss13_stock_companies SET current_price=%s, previous_price=%s, price_high=%s, price_low=%s WHERE company_id=%s",
                (updated["current_price"], updated["previous_price"], updated["price_high"], updated["price_low"], company["company_id"]),
            )
            cur.execute(
                "INSERT INTO ss13_stock_price_history (company_id, price) VALUES (%s, %s)",
                (company["company_id"], updated["current_price"]),
            )
            cur.execute(
                """DELETE FROM ss13_stock_price_history WHERE company_id = %s AND id NOT IN
                (SELECT id FROM (SELECT id FROM ss13_stock_price_history WHERE company_id = %s ORDER BY recorded_at DESC LIMIT %s) AS keep)""",
                (company["company_id"], company["company_id"], HISTORY_KEEP),
            )
    return events


def render_table(companies: list, dreamdaemon_running: bool) -> Table:
    status = (
        "[yellow]PAUSED -- DreamDaemon detected, the game server owns the tick[/]"
        if dreamdaemon_running
        else "[green]SIMULATING[/]"
    )
    table = Table(title=f"Idris Stock Exchange -- {status}", expand=True)
    table.add_column("Ticker", style="bold")
    table.add_column("Name")
    table.add_column("Price", justify="right")
    table.add_column("Change", justify="right")
    table.add_column("Low / High", justify="right")
    table.add_column("Market Cap", justify="right")

    for c in companies:
        change_pct = 0.0
        if c["previous_price"]:
            change_pct = (c["current_price"] - c["previous_price"]) / c["previous_price"] * 100
        color = "green" if change_pct > 0 else "red" if change_pct < 0 else "white"
        name = c["name"]
        if c["faction_uid"]:
            name += f" [dim](faction: {c['faction_uid']})[/]"
        table.add_row(
            c["ticker"],
            name,
            f"{c['current_price']} cr",
            f"[{color}]{change_pct:+.2f}%[/]",
            f"{c['price_low']} / {c['price_high']}",
            f"{c['current_price'] * c['total_shares_outstanding']:,} cr",
        )
    return table


def main():
    repo_root = pathlib.Path(__file__).resolve().parent.parent
    config = load_db_config(repo_root)
    conn = connect(config)

    next_tick = 0.0
    event_log: list = []

    try:
        with Live(refresh_per_second=1, screen=False) as live:
            while True:
                now = time.monotonic()
                dreamdaemon_running = is_dreamdaemon_running()

                if not dreamdaemon_running and now >= next_tick:
                    try:
                        event_log.extend(simulate_tick(conn))
                        del event_log[:-EVENT_LOG_LINES]
                    except pymysql.MySQLError as exc:
                        event_log.append(f"DB error: {exc} -- reconnecting")
                        del event_log[:-EVENT_LOG_LINES]
                        try:
                            conn.close()
                        except pymysql.MySQLError:
                            pass
                        conn = connect(config)
                    next_tick = now + TICK_INTERVAL

                try:
                    with conn.cursor() as cur:
                        cur.execute("SELECT * FROM ss13_stock_companies ORDER BY (faction_uid IS NULL) DESC, ticker")
                        companies = cur.fetchall()
                except pymysql.MySQLError:
                    conn = connect(config)
                    companies = []

                table = render_table(companies, dreamdaemon_running)
                if event_log:
                    live.update(Group(table, Panel("\n".join(event_log), title="Recent Events")))
                else:
                    live.update(table)

                time.sleep(DISPLAY_INTERVAL)
    except KeyboardInterrupt:
        pass
    finally:
        conn.close()


if __name__ == "__main__":
    main()
