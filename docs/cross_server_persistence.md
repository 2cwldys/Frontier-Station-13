# Cross-server shared persistence

A second, independent database connection (`SScentraldb`,
`code/controllers/subsystems/centraldb.dm`) alongside the normal local one
(`SSdbcore`, `dbcore.dm`), so a set of *authorized* servers -- not any server
running this codebase, only ones you explicitly approve -- can share
characters, money, factions, and ship schematics, while worldstate, turfs,
atmos, and machinery stay local to each server as they always have.

**Status, as of this writing:** the connection, its config, the
presence-lock table, and the server-authorization tooling all exist and
are verified. Characters are the first thing that actually *lives*
centrally now (identity/health/inventory/position, behind
`CENTRAL_SYNC_CHARACTERS`) -- see [Character sync](#character-sync)
below. Money, factions, and ships still don't query the central database
at all. See [What's built vs. not](#whats-built-vs-not) before assuming
more works than does.

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
row is removed ONLY on a genuine, deliberate store/stash -- never on a
bare disconnect, see below. A second server checks for a row before
allowing the same spawn/retrieve locally, and refuses -- naming which
server currently has it -- if one already exists.

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
- **Release** -- ONLY `persistStoreCharacter()` (a genuine, deliberate
  store: the Store Character verb, or a forced store -- prison
  freeze/arrest, AFK kick), and only while alive AND not currently
  imprisoned. `persistence_cryo_despawn()` (the same file) -- the grace-
  timer-driven consequence of a bare disconnect, `PERSISTENCE_CRYO_TIMEOUT`
  after `client/Destroy()` -- deliberately never releases it, dead or
  alive: that path is involuntary, not a decision to cryo out, and a
  character that merely disconnected without actually being stored is
  still "out of cryo" exactly as this system's original requirement
  describes -- embodied and un-stored, just hidden, and locked to this
  server until it's actually resolved here (reconnect and store properly,
  or an admin intervenes). `_persistence_dead_despawn()` also never
  releases. So the presence lock stays held for: simply being
  disconnected without an explicit store, "dead" (`char_state` would be
  `"dead_body"` at store time), "neural lace vaulted" (a subset of dead),
  and "imprisoned" (a cryogenic prison sentence, `persistence_character_actively_imprisoned()`,
  `persistence_mobs.dm` -- without this check, a sentence could be
  sidestepped entirely by reconnecting through a different central-linked
  server the moment the cell door closes). Only a clean, deliberate store
  of a character that's alive, not imprisoned, releases it.
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

## Character sync

`CENTRAL_SYNC_CHARACTERS` (`config.txt`) makes a character's identity,
health, inventory, and position follow them to any server/shard sharing
the central database -- not just presence-locked to stop double-play
(that part existed already), the actual data. Design: **write-through +
read-through-on-miss**, reusing the existing local schema shape verbatim
on the central DB rather than a combined blob format --
`SQL/migrate-central/V006__character_sync.sql` mirrors
`ss13_char_identity`/`ss13_char_health`/`ss13_char_inventory`/
`ss13_mob_position` (`SQL/migrate-2023`) column-for-column.

- **Write-through**: every existing local save (`charIdentitySaveOne()`,
  `mobsHealthSaveOne()`, `mobsInventorySaveOne()`, `mobPositionSave()`/
  `lacePositionSave()`, all `persistence_mobs.dm`) also upserts the same
  row centrally when the toggle is on and central is reachable.
  Non-fatal on failure -- the local save already succeeded.
- **Read-through-on-miss**: at character spawn, if this server's local
  cache has never seen this character (`applyPersistentIdentity()` and its
  three siblings), a central lookup runs before falling back to "no saved
  data." A hit populates the in-memory cache AND writes the row into this
  server's own local table (self-heal) -- no repeated central round-trips
  on future spawns.
- Shared helpers (`persistence_mobs.dm`), not four+ separate
  implementations: `_characterRowUpsert()` (the upsert SQL builder),
  `_centralCharacterWriteThrough()`/`_centralCharacterReadThrough()`/
  `_centralCharacterSelfHealLocal()`, and `_centralCharacterPartialUpdate()`
  (plain `UPDATE`, for the three position setter procs below that never
  INSERT). All gate through one `_centralCharacterSyncActive()` check
  (`central_sql_enabled` AND `central_sync_characters` both genuinely on,
  AND central reachable right now).
- Relies on the presence lock (above) for correctness: only the server
  currently holding a character's lock ever writes or read-through-hydrates
  its data, so there's no concurrent-write conflict to resolve.
- `ss13_mob_position`'s local table carries several columns written by
  procs OTHER than `mobPositionSave()` -- `last_pod_x`/`_y`/`_z`
  (`persistence_set_last_pod()`), `imprisoned`/`imprisoned_until`/
  `imprisoned_by_faction_uid` (`persistence_set_imprisoned()`),
  `faction_bound`/`faction_bound_uid` (`persistence_set_faction_bound()`).
  All three are wired to central too (`_centralCharacterPartialUpdate()`,
  a plain `UPDATE` rather than the upsert `_centralCharacterWriteThrough()`
  uses, since these procs only ever run against a row `mobPositionSave()`
  already created) -- a character's cryo-imprisonment, faction shackle,
  and last-used-pod memory all follow them across servers along with core
  position. `persistence_set_imprisoned()`'s timed-sentence branch keeps
  its `DATE_ADD(NOW(), ...)` SQL expression rather than going through the
  generic helper, matching its local counterpart exactly.
- Pre-existing, unrelated to this feature: `mobPositionInitialize()`'s own
  boot-time bulk load never selects `faction_bound`/`faction_bound_uid` at
  all, so a live faction-shackle set during a session doesn't survive that
  server's own restart locally (central's copy stays correct regardless,
  since `persistence_set_faction_bound()` writes it centrally every time
  it's called, independent of the local boot-load path). Noted, not fixed
  here -- out of scope for character sync specifically.
- Ships remain entirely local-only. Factions are now synced too, see
  below -- money (personal accounts, separate from faction treasury)
  remains local-only.

## Faction sync

`CENTRAL_SYNC_FACTIONS` makes a faction's existence, treasury, and
membership follow it across every server sharing the central database.
Existence (`ss13_factions`) and membership (`ss13_faction_members`) use
the exact same write-through + read-through-on-miss shape character sync
established -- factions have no presence-lock equivalent (members are
expected to be spread across servers simultaneously by design), so
there's no concurrent-write conflict to solve for those two.

Treasury (`ss13_faction_accounts`) needed a real fix first, not just a
mirror table: `faction_credit()`/`faction_debit()`
(`persistence_factions.dm`) used to read a cached balance, compute a new
one in DM, then write the ABSOLUTE result -- harmless on one server (DM
is single-threaded, nothing interleaves the read-compute-write), but a
textbook lost-update race the moment two separate server PROCESSES can
both write the same row, which -- since factions have no presence lock --
would be the routine case, not a rare edge case, once any two
central-linked servers both have active members trading stock or
spending faction money at once.

**The fix**: every balance mutation is now a SQL-side delta
(`balance = balance +/- :amount`) rather than an absolute overwrite --
correct regardless of which server's cache was stale when it computed the
delta, since addition/subtraction commute. Debits additionally use
`UPDATE ... WHERE balance >= :amount` as an atomic check-and-decrement
(`_faction_balance_debit_atomic()`, checking `query.affected`, exposed by
`dbcore.dm`'s `store_data()`) -- so two servers can never both approve a
debit that combined overdraws the account, with no faction-level lock
needed. When `CENTRAL_SYNC_FACTIONS` is active, the CENTRAL row is what's
actually checked/decremented (it's the one every server shares); the
local row is then kept in step with the same delta, unconditionally, no
separate check. When central sync is off, the local row is authoritative,
exactly as before this fix existed. The admin "Modify Balance" verb's Set
Balance/Remove Credits actions deliberately keep the old absolute-write
`_faction_balance_write()` -- a rare, deliberate override where "force it
to exactly this value" is the actual intent, not routine gameplay, so
there's no race to protect against.

**Known, disclosed limitation**: a faction's CACHED balance
(`GLOB.persistence_faction_cache`, what stock price display and "can I
afford this" UI hints read) only updates on a server when THAT server
does its own credit/debit, or hydrates the faction for the first time --
it does not periodically re-sync from the authoritative central value the
way the admin/ban lists do (`SSauth.fire()`). The underlying STORED value
stays correct regardless (that's what the atomic delta/check-decrement
guarantees), but a display on one server can lag behind a transaction
that just happened on another until this server's own next credit/debit
or restart. Not fixed here -- a periodic cache refresh, mirroring
`SSauth`'s pattern, is a natural follow-up if live-across-servers display
accuracy turns out to matter in practice.

## Central bans + live admin refresh

A ban applied on any `central_sql_enabled` server refuses the connection
on every other server sharing the central database
(`ss13_central_bans`, `code/modules/admin/DB ban/central_ban.dm`),
layered additively on top of each server's own existing local ban system
(`world/IsBanned()`, `IsBanned.dm`) -- never a replacement for it.
Deliberately fail-**open** on central being unreachable, the opposite of
central admin auth's fail-closed: refusing every connection during a
brief central DB blip would be worse than the narrow risk of a ban check
being skipped for that window, and the local ban list is still fully in
effect regardless. Applying a ban (`DB_ban_record()`, `DB ban/functions.dm`)
writes centrally too, only for full-connection ban types (never `JOB_*`,
which only restrict a role, not a connection).

Both this and `ss13_central_admins` (pre-existing) now refresh
automatically, not just at boot: `SSauth` fires every 5 minutes
(`central_sql_enabled` only, a no-op subsystem otherwise) re-running
`load_admins()`/`load_central_bans()`. Both are also manually
reloadable on demand ("Reload Admins" / "Reload Central Bans" verbs,
`diagnostics.dm` / `central_ban.dm`) for immediate effect.

Not built: proactively kicking an already-connected player the moment
they're banned on another server -- a ban only takes effect on that
player's *next* connection attempt, matching how local bans already
behave. Enforcing it retroactively would need actively re-checking every
connected client, not just gating new connections -- a real feature, but
a separate, harder problem than "a ban applies everywhere."

## What's built vs. not

| Built | Not built |
|---|---|
| `SScentraldb` connection, its config, its own query bookkeeping | Personal money (`ss13_money_accounts`) and ships actually living on the central DB |
| `ss13_presence_lock` schema, character acquire/release hooks (spawn, cryo, disconnect), fail-closed | Ship acquire/release (drydock retrieve/stash) -- `shuttle_id` has no cross-server identity yet either |
| Per-server credential provisioning + revocation, verified live | -- |
| `databaseCheckCentralConnection()` (persistence.dm) for future callers to gate on | -- |
| Character identity/health/inventory/position sync, including imprisonment/last-pod/faction-bound (`CENTRAL_SYNC_CHARACTERS`, write-through + read-through-on-miss, see above) | -- fully built, not a placeholder |
| Faction existence/treasury/membership sync, treasury atomic-write-safe (`CENTRAL_SYNC_FACTIONS`, see above) | Faction balance cache periodic refresh (display can lag, stored value stays correct -- see "Known, disclosed limitation" above) |
| `CENTRAL_SYNC_CHARACTERS`/`_FACTIONS` -- read and acted on | `_SHIPS`/`_MONEY` config toggles still unread -- no code branches on them yet |
| Centralized admin authorization (`ss13_central_admins`), fail-closed, live | -- fully built, not a placeholder |
| Network-wide player count (`ss13_central_population`, `get_serverstatus`, `tools/discord_rpc`) | -- fully built, not a placeholder |
| Local game-server shards, containerized, admin/auto-spawned, backed up (backup verb/auto-toggle are shard-aware too, see above) | -- fully built, not a placeholder |
| Central ban list + live-refreshing central admin list (`ss13_central_bans`, `SSauth.fire()`) | Proactive kick of an already-connected player banned on another server -- enforced on next connection attempt only, see above |

Characters and factions are the two subjects actually living on the
central database today -- everything else connecting still means what it
did before: `SScentraldb` reachable, nothing asking it anything for those
remaining subjects yet.

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
