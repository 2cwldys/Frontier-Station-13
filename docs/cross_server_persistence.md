# Cross-server shared persistence

A second, independent database connection (`SScentraldb`,
`code/controllers/subsystems/centraldb.dm`) alongside the normal local one
(`SSdbcore`, `dbcore.dm`), so a set of *authorized* servers -- not any server
running this codebase, only ones you explicitly approve -- can share
characters, money, factions, and ship schematics, while worldstate, turfs,
atmos, and machinery stay local to each server as they always have.

**Status: foundation only, as of this writing.** The connection, its
config, the presence-lock table, and the server-authorization tooling all
exist and are verified. Nothing in the game actually *queries* the central
database yet -- no character, faction, or ship currently lives there. See
[What's built vs. not](#whats-built-vs-not) before assuming more works than
does.

## Why a second connection, not one shared local DB

`SSdbcore` is a single connection, called directly from hundreds of places
across every `persistence_*.dm` file -- there's no routing layer that could
send "this table" to one database and "that table" to another. Rather than
rebuild that, `SScentraldb` is a genuine DM subtype of
`/datum/controller/subsystem/dbcore`, so it inherits the entire proven query
lifecycle (async job polling, timeouts, connection backoff) for free, with
its own completely independent connection, config, and query bookkeeping.
The one shared-code change was to `/datum/db_query` itself: several of its
procs used to hardcode the literal global `SSdbcore`; they now read an
`owner` var instead (defaulting to `SSdbcore` for every existing caller, so
nothing that exists today changed behavior). A future persistence call site
moving to central storage is then just a matter of calling `SScentraldb.`
instead of `SSdbcore.` -- same `NewQuery()`/`.Execute()`/`q.item[n]` shape
either way.

## The presence lock

The mechanism that makes sharing safe without rewriting how saving works.
One table on the *central* database, `ss13_presence_lock`
(`SQL/migrate-central/V001__presence_lock.sql`): a row's existence **is**
the lock. A character or ship gets a row the moment it's actively in play
(spawned in, or retrieved from drydock) naming which server holds it; the
row is removed when it stops being active there (cryo, disconnect without
cryo, or stashed). A second server checks for a row before allowing the
same spawn/retrieve locally, and refuses -- naming which server currently
has it -- if one already exists.

This is what avoids the classic double-spend/split-brain problem: only the
server holding the lock ever has that character or ship loaded in memory,
so only one server is ever writing it back at a time. It deliberately does
**not** cover faction treasury, since a faction's legitimate actors are
multiple different characters possibly on different servers at once -- that
needs its own fix (atomic SQL-side balance updates) when factions actually
move to the central DB, not a lock.

**Characters: built and live** (ships/drydock retrieve-stash still not --
see the table below). `presenceLockAcquire()`/`Release()`
(`code/controllers/subsystems/persistence/persistence_cryo.dm`) are the two
procs everything funnels through:

- **Acquire** -- `PersistentAutoSpawn()` (`code/modules/mob/abstract/
  new_player/new_player.dm`), right after the player's character selection
  is resolved, before any reattach/spawn actually happens. Refuses cleanly
  (kicks back to the character menu with a message naming the other server)
  if the lock is held elsewhere; fails closed (refuses, doesn't guess) if
  the central DB can't be reached at all.
- **Release** -- only when a character finishes being stored/logged-out
  **while alive**. `persistStoreCharacter()` and `persistence_cryo_despawn()`
  (both same file) release; `_persistence_dead_despawn()` deliberately never
  does. This one rule covers "out of cryo" (never released while active),
  "dead" (`char_state` would be `"dead_body"` at store time -- release
  skipped), and "neural lace vaulted" (a subset of dead -- vaulting only
  ever happens to an already-dead character's extracted lace, so it's
  covered by the same skip) in one place, without needing separate handling
  per case.
- **Outage UX** -- the character-select TGUI (`persistent_menu.dm` /
  `PersistentMenu.tsx`) disables Play outright while the central DB is
  unreachable (`centralDatabaseReachable()`), rather than letting a player
  click through to a runtime refusal. Both always come back "everything's
  fine, proceed" the instant `central_sql_enabled` is off, so this is a
  complete no-op on an ordinary standalone server.

## Setting up the central database

**Yes -- a separate Docker container (or any separate MariaDB/MySQL
instance), not the same one as `aurora-db`.** Two reasons it can't be the
same container:

- `aurora-db` (`docker-compose.yml`) is *this server's own local database*.
  The central database needs to be reachable by **every** authorized
  server, not just this one -- so it has to live somewhere all of them can
  actually connect to, not on any single server's own machine (unless that
  machine is also acting as the central host for the others, which works,
  but is then a deliberate choice, not an accident of reusing `aurora-db`).
- Mixing the two schemas into one container defeats the entire point of the
  two-tier credential split below -- the local DB's own users/permissions
  have nothing to do with which *game servers* are authorized against the
  shared one.

A minimal `docker-compose.yml` for the central host, mirroring the existing
local one but on its own port/volume:

```yaml
services:
  central-db:
    image: mariadb:10.11
    container_name: aurora-central-db
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: <choose a real one>
      MARIADB_DATABASE: aurora_central
    ports:
      - "3306:3306"   # or a different host port if this box runs other things
    volumes:
      - aurora_central_db_data:/var/lib/mysql

volumes:
  aurora_central_db_data:
```

Runs on whatever box you designate as the central host -- a small VPS, a
home server with the port reachable by the other servers (ideally over a
VPN rather than the open internet -- see
[Transport security](#transport-security-not-yet-solved) below), wherever.
Nothing about the container itself is special; `MARIADB_ROOT_PASSWORD` here
becomes the admin-tier login referenced everywhere below.

### Applying the schema

```
scripts\central\db_central_update.ps1
```

Applies everything in `SQL/migrate-central/*.sql` (currently just the
presence-lock table) against the central database, using
`config/central_dbconfig_admin.txt` (admin credentials -- see below).
Mirrors the existing `db_update.ps1` exactly, except it connects with a
plain `mysql`/`mariadb` CLI client over the network instead of `docker exec`,
since the central host generally isn't one this server itself controls the
same way it controls `aurora-db`.

All central-database tooling lives under `scripts\central\` -- see the full
list at the end of the [Revoking a server](#revoking-a-server) section
below.

## Two credential tiers

Two different jobs, two different privilege levels, **never the same
login**:

| | Admin tier | Runtime tier |
|---|---|---|
| Config file | `config/central_dbconfig_admin.txt` | `config/central_dbconfig.txt` |
| Used by | You, by hand, running the scripts below | Each game server's own `SScentraldb` |
| Privileges | Full DDL (`CREATE`/`ALTER`/...) | `SELECT, INSERT, UPDATE, DELETE` only |
| One login for | The whole setup | **Each authorized server, its own** |

Both files are gitignored (`config/.gitignore`'s blanket rule, same as the
existing local `dbconfig.txt`); committed templates live under
`config/example/`.

The runtime tier's restriction is deliberate and verified: a game server's
own connection can never `CREATE`/`DROP`/`ALTER` anything on the central
database, only read and write rows. A compromised or buggy game server can
corrupt *data* at worst, never the schema everyone else's data lives in.

### Authorizing a server

```
scripts\central\db_central_add_server.ps1 -ServerId frontier-alpha
```

Creates that server its own login (`CREATE USER` + a `GRANT` scoped to
exactly the runtime-tier privileges above), generates a random password if
you don't supply one, and prints the `config/central_dbconfig.txt` block to
hand to whoever runs that server -- along with `CENTRAL_SERVER_ID
frontier-alpha` / `CENTRAL_SQL_ENABLED` for their `config.txt`. `-WhatIf`
previews without creating anything.

By default the login is accepted from any IP (`'frontier-alpha'@'%'`) --
the password is the only gate. Pass `-SourceIP <their IP>` to also restrict
the login to that address (MariaDB's `'user'@'host'` scoping), so a leaked
password alone isn't enough to connect. Needs that server to have a stable
IP; skip it for dynamic/residential connections.

MariaDB treats `'user'@'host'` as one identity, not a list -- there's no
"add another allowed IP" for an existing login. To change a server's IP
(or add a second one), revoke the old account and create a new one:

```
scripts\central\db_central_remove_server.ps1 -ServerId frontier-alpha -SourceIP <old IP>
scripts\central\db_central_add_server.ps1 -ServerId frontier-alpha -SourceIP <new IP>
```

### Revoking a server

```
scripts\central\db_central_remove_server.ps1 -ServerId frontier-alpha
```

`DROP USER IF EXISTS` -- revoking an already-gone server is a normal no-op,
not an error. Because every server has its own login, this affects **only**
the named one; every other authorized server keeps working, untouched.

If the server was created with `-SourceIP`, pass the same `-SourceIP` here
-- `'frontier-alpha'@'203.0.113.7'` and `'frontier-alpha'@'%'` are different
accounts to MariaDB, so the wrong one silently no-ops and leaves the real
login live. Not sure which was used? Check with the admin login:
`SELECT host FROM mysql.user WHERE user = 'frontier-alpha';`

All central-database tooling lives under `scripts\central\`:

| Script | Purpose |
|---|---|
| `db_central_setup.ps1` | First-time setup: starts the container, applies the schema, enables `CENTRAL_SQL_ENABLED` |
| `db_central_start.ps1` / `db_central_stop.ps1` | Start/stop only the `central-db` container |
| `db_central_update.ps1` | Applies `SQL/migrate-central/*.sql` (also called by `db_central_setup.ps1`) |
| `db_central_add_server.ps1` | Authorizes a server (this section) |
| `db_central_remove_server.ps1` | Revokes a server (this section) |

Both scripts, and the exact SQL they generate, have been run end-to-end
against a real MariaDB instance: provisioned a login, confirmed it could
read/write but was refused on `CREATE TABLE`/`DROP TABLE`, revoked it,
confirmed the login was then refused while a separate login kept working.

## Centralized admin authorization

Unlike everything else in this doc, this one is **not opt-in per subject**
-- it's on the moment `CENTRAL_SQL_ENABLED` is. Every server's admin roster
normally comes from its own local storage (`config/admins.txt` or a local
`ss13_admins` table) -- with `CENTRAL_SQL_ENABLED` on, that local storage is
no longer consulted at all. Instead `SSauth.load_admins()`
(`code/controllers/subsystems/initialization/auth.dm`) loads the roster from
`ss13_central_admins` on the central database, and does so **fail-closed**:
if the central DB isn't reachable at boot, no admins are loaded anywhere on
that server, full stop -- no fallback to local storage. This was a deliberate
choice, not a default: the point is that a server operator can't just decide
locally who their admins are once they're part of a central-admin group.

Two local bypasses that would otherwise defeat this outright are closed at
the same time: `AUTO_LOCAL_ADMIN` (instant admin for any localhost
connection) is disabled whenever `CENTRAL_SQL_ENABLED` is on, and the
in-game Permissions Panel refuses to edit ranks (it would otherwise write to
the now-unused local table and silently do nothing). What this can't close:
someone who controls a server's own source and can recompile it can always
delete these checks -- true of any self-hosted software. This closes every
*practical* local vector (file edits, DB edits, the localhost shortcut,
in-game self-promotion), not that one.

`ss13_central_admins` mirrors the local `ss13_admins` table's shape
(`ckey`, `rank` as a display label only, `flags` as the actual enforced
`R_*` bitmask -- not resolved through any server's own
`config/admin_ranks.json`, so one row means the same thing everywhere).
Manage it with:

```
scripts\central\db_central_add_admin.ps1 -Ckey someone -Rank "Head Admin" -Flags 32767
scripts\central\db_central_remove_admin.ps1 -Ckey someone
scripts\central\db_central_list_admins.ps1
```

Each has a `.sh` (native POSIX shell, no PowerShell dependency) and `.bat`
(thin `powershell.exe` wrapper, forwards all arguments) sibling too, same
convention the rest of `scripts/` already uses (`db_update.sh`/`.bat`,
etc.) -- e.g. `db_central_add_admin.sh --ckey someone --rank "Head Admin"
--flags 32767`. `db_central_list_admins.*` is read-only -- prints the
current roster (`ckey`, `rank`, `flags`, `added_by`, `added_at`), nothing
else. All three use the admin credential tier, same as every other
`db_central_*` script. Every server's own *runtime* login can `SELECT` from
`ss13_central_admins` (it has to, to load the roster) but never
`INSERT`/`UPDATE`/`DELETE` on it -- granted per-table by
`db_central_add_server.ps1` rather than as part of its usual database-wide
write grant, specifically so a server can never grant itself admin by
writing to that table directly. Re-run `db_central_add_server.ps1` for
already-authorized servers after adding any new central table (including
this one, for servers authorized before it existed) to pick up write access
to it -- MySQL/MariaDB grants are additive across scopes, so this can't be
expressed as a single wildcard grant with an exception.

## Network-wide player count

Also automatic once `CENTRAL_SQL_ENABLED` is on -- no separate toggle, same
as the admin authorization above. `SSstatistics.fire()`
(`code/controllers/subsystems/statistics.dm`) upserts this server's live
player/admin count into `ss13_central_population` once a minute (one row
per `CENTRAL_SERVER_ID`, not a growing log), then caches the summed total
across every server with a row updated in the last 5 minutes (a freshness
cutoff -- a crashed server's last-known count doesn't count forever).
`get_serverstatus` (`code/modules/world_api/commands/server_query.dm`, the
same Topic() endpoint the Discord tools and any external status poller
already use) reports that cached total as `central_players`/
`central_server_count` -- **only present when central is on**; a
non-central server's response is unchanged. `players` itself always means
only this server, never the group.

`tools/discord_rpc` ("FrontierRPC," a player-side Discord Rich Presence
tool -- see its own README) shows the network-wide total on the player's
Discord card when the one server it's configured to poll reports it,
falling back to a plain single-server count otherwise. No changes to how
that tool connects -- it still only ever talks to the one server baked into
its `.env` at `build.bat` packaging time; that server does the aggregating.

## Config reference

In `config.txt`:

```
#CENTRAL_SQL_ENABLED
#CENTRAL_SERVER_ID my_server_name

#CENTRAL_SYNC_CHARACTERS
#CENTRAL_SYNC_SHIPS
#CENTRAL_SYNC_FACTIONS
#CENTRAL_SYNC_MONEY
```

All off/unset by default -- an ordinary standalone server needs none of
these and never attempts a central connection. `CENTRAL_SERVER_ID` must be
unique across every server sharing one central database (it's what a
*second* server displays when refusing to load something this server's
lock already holds); nothing enforces that uniqueness automatically, since
the servers allowed to connect at all are exactly the ones trusted to be
configured correctly.

The four `CENTRAL_SYNC_*` toggles (`code/controllers/configuration.dm`,
`GLOB.config.central_sync_characters` / `_ships` / `_factions` / `_money`)
are the modular per-subject switches -- independent of each other, so a
group can share characters and ships without also sharing money or faction
treasuries. Each is a plain comment/uncomment in `config.txt`, same as
`CENTRAL_SQL_ENABLED`. **They are currently inert** -- see the table below;
no persistence call site reads them yet, so enabling one today changes
nothing in-game. They exist now so the routing decision for each subject
type is already in place, in one obvious spot, before the code that would
consult it is built.

## Local game-server shards

Full guide: `docs/shards for dummies.txt`. Summary here for anyone reading
this doc top to bottom: a shard is a second (third, ...) DreamDaemon
instance on the *same machine*, sharing this server's central database but
with completely fresh local data. Structurally it's just another
authorized server -- `db_central_add_shard.ps1`/`.sh` provisions it the
same DML-only central login `db_central_add_server.ps1` gives any real,
separately-hosted server, then additionally handles the Docker container,
local DB, and port that a genuinely separate machine wouldn't need.

Gated at two independent levels: a compile-time switch
(`ALLOW_CENTRAL_SHARD_SPAWNING`, `code/_compile_options.dm` -- off by
default, since unlike everything else here this lets the game shell out to
Docker on its own) and, underneath that, the same `CENTRAL_SQL_ENABLED`
runtime check every other central feature already uses. The presence lock
above applies to shards automatically, with no shard-specific code needed
-- a shard is just another server as far as that mechanism is concerned.

A shard's `config.txt` is a one-time snapshot of the host's own, taken at
creation (`SQL_ENABLED`/`CENTRAL_SQL_ENABLED` forced on, a unique
`CENTRAL_SERVER_ID` set) -- not a live link. Its local saves
(`forceSaveAll()`) only ever touch its own local database, same as any
other server.

Creation, and every start/stop after that, relays to Discord's milestone
channel via `scripts/discord_status_bot.py` (see `docs/shards for
dummies.txt` for what that looks like) -- same delivery path as
`get_serverstatus`/`post_advert()`, just its own dedup'd event stream.

The existing "Trigger Database Backup" verb and auto-backup-on-autosave
toggle (`persistence_backups.dm`) are hardcoded to `docker exec aurora-db
...`, which is unreachable and unrunnable from inside a shard's container
(different local DB container name, no Docker CLI installed there at all).
A shard's own config.txt carries a `SHARD_ID` value (written once at
creation by `db_central_add_shard.ps1`/`.sh`) that both transparently
switch on: inside a shard they instead run
`scripts/central/shard_backup_self.sh`, a network-only mysqldump straight
to the shard's own sibling DB container (no Docker CLI needed), writing
into the same `backups/shards/<ShardId>/` directory
`db_central_backup_shard.ps1`/`.sh` uses from the host. Either command
works from either place -- an admin connected directly to a shard can just
use its in-game verb/toggle like normal, or back it up from the host
without connecting at all.

### Topic API / tokens

Shard automation (the backup redirect above, and any future external tool)
authenticates through this codebase's existing Topic API
(`code/modules/world_api/api_command.dm`), not anything new. A request is
a JSON payload sent over `world/Topic()`: `{"query":"<command>","auth":"<token>"}`
-- `query` picks the `/datum/topic_command` to run, `auth` is checked
against `ss13_api_tokens`/`ss13_api_commands`/`ss13_api_token_command` (the
LOCAL game DB) unless the command sets `no_auth = TRUE` (e.g.
`get_serverstatus`, which is meant to be publicly pollable). Commands that
change state instead of just reporting it -- so far, just
`force_persistence_save` (`code/modules/world_api/commands/force_save.dm`,
triggers `SSpersistence.forceSaveAll()` with no admin mob needed) -- are
NOT `no_auth`, and require a real token scoped to that exact command name.

`db_central_add_shard.ps1`/`.sh` provisions one such token per shard at
creation time, scoped only to `force_persistence_save` (never `_ANY`), and
both prints it once and saves it to the shard's own
`shards\<ShardId>\config\api_token.txt` -- nowhere else keeps a copy, so
back it up like any other credential if you're relying on it. This exists
for a future external tool (an idle-shard watchdog, or anything else that
needs to trigger a save without a human admin present) -- nothing in this
repo consumes it yet.

## What's built vs. not

| Built | Not built |
|---|---|
| `SScentraldb` connection, its config, its own query bookkeeping | Anything actually querying it for characters/money/factions/ships |
| `ss13_presence_lock` schema, character acquire/release hooks (spawn, cryo, disconnect), fail-closed | Ship acquire/release (drydock retrieve/stash) |
| Per-server credential provisioning + revocation, verified live | Money/factions/ships actually living on the central DB (characters' *presence* is locked; character *data* itself still isn't centrally stored) |
| `databaseCheckCentralConnection()` (persistence.dm) for future callers to gate on | Faction treasury's atomic-write fix (needed once factions move central -- see the presence-lock section above) |
| `CENTRAL_SYNC_CHARACTERS`/`_SHIPS`/`_FACTIONS`/`_MONEY` config toggles | Any code that reads those toggles to actually decide where a subject's data goes |
| Centralized admin authorization (`ss13_central_admins`), fail-closed, live | -- fully built, not a placeholder |
| Network-wide player count (`ss13_central_population`, `get_serverstatus`, `tools/discord_rpc`) | -- fully built, not a placeholder |
| Local game-server shards, containerized, admin/auto-spawned, backed up (backup verb/auto-toggle are shard-aware too, see above) | -- fully built, not a placeholder |

A second server could point valid credentials at a real central database
today and it would connect successfully -- and nothing would happen, because
no game system asks it anything yet.

## Transport security -- not yet solved

Neither this connection nor the existing local one passes any TLS/SSL
option to the underlying `rustg_sql_connect_pool` call, and it wasn't
possible to confirm from the vendored `rust_g.dll` alone whether the
connector supports one. If the central host is reachable over the open
internet rather than a private network, the login password *and every row
of shared data* cross the wire in plaintext.

**Recommended regardless of what rust_g turns out to support:** put the
central database behind a private network -- a VPN (WireGuard, etc.)
between every authorized server and the central host, or a cloud provider's
private networking -- so the connection never touches the open internet at
all, and the port isn't reachable by internet-wide scanning either. Treat
this as required before pointing a real deployment at a real central host
over the public internet, not optional hardening.
