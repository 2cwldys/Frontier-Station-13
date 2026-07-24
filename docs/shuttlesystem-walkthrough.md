# Shuttle / Drydock / Corvette System — Walkthrough & Testing Reference

Companion to `docs/shuttlesystem.txt` (original notes) and
`docs/shuttlesystem-architecture.md` (the researched design doc, still the
source of truth for *why* things are built the way they are). This doc is
the practical "what exists, how to use it, how to test it" reference for
going hands-on in-game. Written after Phase 8 (Faction Corvettes) reached
`RESULT: CLEAN`.

---

## 1. The big picture

Two independent player-facing systems, sharing one piece of core
infrastructure (the docking beacon):

- **Drydock shuttles** -- personal or faction-owned small craft, built by
  hand from a hull + shuttle core (legacy) or bought/customized through the
  Drydock program, stored/retrieved on **pads** via turf-grid serialization.
- **Faction corvettes** -- faction-only, larger, pre-built ships with their
  own Z-level, stored/retrieved through the **Faction Ship Program** via
  full Z materialize/wipe (no pad, no turf-grid).

Both share one rule: **nothing about a stashed shuttle or corvette exists in
the live world.** A stashed shuttle is a DB row (`ss13_drydock_shuttles`,
`hull_json` blob). A stashed corvette is a DB row
(`ss13_faction_corvettes`), full stop -- no Z content, no overmap marker.

---

## 2. Drydock Shuttles

### 2.1 Docking beacon (`code/modules/shuttles/shuttle_core.dm`)

The shared "port" object. Wrench to anchor, screwdriver to activate (prompts
for a label). Once active it registers a shuttle landmark any ship can dock
at. ID-swipe with a faction ID:
- Unclaimed beacon -> restricts it to your faction (officer+ rank required).
- Your faction's claimed beacon -> release it back to public (officer+).
- Someone else's claimed beacon -> refused.

### 2.2 Drydock pad (blueprint-designated)

A **red-tinted drydock blueprint** (`/obj/item/blueprints/drydock`) lets an
officer+ select a rectangular area with the freelook eye tool and designate
it as a pad:
- Minimum size **30x18 tiles**, must be a solid rectangle (no gaps/notches).
- Exactly one **active** docking beacon must be inside the selection.
- One beacon = one pad, at most one landed shuttle at a time.

Pad turfs are canonical, non-decorated plating -- they are a landing grid,
not a room. Nothing is ever saved on a pad turf (`AREA_FLAG_DRYDOCK_PAD` +
`persistence_area_excluded()`), so a pad always boots pristine.

### 2.3 Stash / Retrieve engine (`persistence_shuttles.dm`)

- **Stash**: shuttle must currently be docked at the target pad's beacon, no
  player mobs aboard the hull or standing on the pad. Serializes every hull
  turf (type + structural props) and every object on it (reusing the same
  three serializers persistence already has: item, worldstate, tracked
  object) into `hull_json`, then tears the live hull down (`ChangeTurf`
  back to plating, `qdel`s objects, deletes the shuttle datum).
- **Retrieve**: pad must be unoccupied, hull must fit the pad's bounding
  box, no collision. Rebuilds every turf + object from `hull_json`, creates
  a fresh `player_built` shuttle datum, `short_jump()`s it onto the pad.
- A deployed drydock shuttle is **deliberately not** registered in the
  normal `ss13_persistent_shuttles`/`ss13_player_shuttles` tables -- its
  hull sits on a persistence-excluded pad, so the generic restore path can't
  safely reconstruct it. Instead, **`drydockAutoStashAll()`** force-stashes
  every deployed drydock shuttle at `SSpersistence.Shutdown()`/
  `forceSaveAll()`, before the generic sweep runs. A shuttle flying free
  (not on any pad) is *not* protected by this -- matches the design
  philosophy that "being done with" a shuttle means docking and drydocking
  it, not leaving it parked mid-flight.

### 2.4 Drydock program (`.../programs/command/drydock.dm`, TGUI `ShuttleDrydock`)

Three tabs:
- **Drydock**: Personal / Faction sub-lists. Retrieve (stashed, pad
  selected), Stash (deployed, currently on this pad), Rename (stashed only),
  Sell/Remove (owner or officer+, stashed only, DB row deleted).
- **Pad Status**: pick from nearby pads, see size/occupancy, "Highlight
  Pad" spawns 15s warning markers over every pad turf.
- **Market**: browse templates, Buy (personal or, if officer+, as a faction
  purchase charged to the faction account). A purchase inserts a `stashed=1`
  row -- retrieve it from the Drydock tab like any other stashed shuttle.

### 2.5 Templates

**Admin-only** "Publish as Template" action on any stashed shuttle: prompts
name/description/price, copies that row's `hull_json` into
`ss13_drydock_templates` as an independent, permanent catalog entry (the
source shuttle is untouched). Buying a template just copies its `hull_json`
into a new owned, stashed shuttle row -- customize by retrieving,
redecorating with normal construction, and stashing again (stash re-scans
the hull, so shape changes are captured too).

### 2.6 Testing checklist

1. Place + activate a docking beacon. Designate a 30x18+ pad around it
   (confirm a 29x17 selection is rejected).
2. Build or buy a shuttle, dock it on the pad, Stash it. Confirm the pad
   turfs are bare plating and the DB row shows `stashed=1`.
3. Retrieve it. Confirm the hull (including any redecorated tile) comes
   back exactly.
4. Restart the server with a shuttle deployed on a pad and NOT manually
   stashed. Confirm it was auto-stashed (check the log for
   `drydockAutoStashAll`) and the pad is empty on boot.
5. Publish a stashed shuttle as a template (admin), buy it as a different
   character, confirm it arrives stashed and retrievable.
6. Try stashing with a player still aboard -- confirm refusal, not silent
   failure.

---

## 3. Faction Chat (`.../programs/generic/faction_chat.dm`, TGUI `FactionChat`)

IRC-style channel scoped to a **real faction roster membership** (a printed
civilian ID is refused -- `employer_faction` must be set AND
`get_faction_member()` must return a roster row). Identity is character
`real_name`. PDA pings: any powered, screen-on device with the program
installed and held by a verified member gets a **private** notification
(`message_range = 0` -- wearer only, not audible to bystanders) whether or
not the program window is open.

**Testing checklist**: two faction members chat cross-map, confirm PDA
pings on both ends; a civilian-carded player is refused entry; a non-member
holding a member's PDA gets no ping; a PDA lying on a table (no holder)
gets no ping.

---

## 4. Faction Corvettes (Phase 8)

### 4.1 The lifecycle -- three separate actions, not two

This is the part most likely to cause confusion if mis-remembered, so it's
worth restating precisely:

- **Buy** (`corvetteBuy()`, Market tab): pure purchase. Debits the faction
  account, inserts one `ss13_faction_corvettes` row (`stashed=1`). **Nothing
  materializes** -- no Z, no overmap marker. Ownership is permanent from
  this point on (until the corvette is destroyed/removed some other way --
  there's no "sell" action for corvettes yet).
- **Retrieve** (`corvetteRetrieve()`, Status tab): the materialize step.
  Requires the operating computer to sit on a Z currently claimed by a
  faction beacon belonging to the *same* faction that owns the corvette.
  Always calls `load_new_z()` **fresh** -- a stashed corvette's old Z is
  never reused (Z-levels can't be freed by this engine at all, so reusing
  one would require a "reload template content onto an already-allocated
  Z" mechanism that doesn't exist; abandoning it is simpler and the
  abandoned Z costs ~nothing since it's genuinely empty). Places the new
  overmap marker within the claiming beacon's own `security_radius` of that
  beacon's overmap sector -- the same radius number officers already
  configure for territory security, reused as the "how far out can we
  deploy" knob.
- **Stash** (`corvetteStash()`, Status tab): wipes the Z's content
  (`resetZLevelContent()` -- the same engine the admin "Reset Z-Level" tool
  uses, extracted into a reusable proc), deletes the overmap marker
  (**and** clears every `GLOB.map_sectors` entry pointing to it -- this
  matters, see 4.3), and clears the ledger row's `z`/`overmap_x`/
  `overmap_y`. Blocked if any player is still aboard.
- **Dock/undock and general flight are completely untouched, stock Aurora
  overmap-ship logic.** Once retrieved, a corvette flies and docks exactly
  like Intrepid/Canary/Quark -- nothing in this phase adds or modifies
  movement code.
- **`corvetteAutoStashAll()`** mirrors `drydockAutoStashAll()` exactly:
  called at `SSpersistence.Shutdown()`/`forceSaveAll()`, force-stashes every
  deployed corvette so a faction never loses one to an ungraceful-shutdown
  edge case just because they forgot to stash it themselves.

### 4.2 Boarding

A `telepad_cargo/corvette_boarding` pad, faction-tagged via the normal
faction tagger tool, lets a member `attack_hand()` their way onto their
faction's currently-deployed corvette from any station-side pad on the same
network -- reuses the exact "any pad on my network" lookup the cargo
delivery system already uses, keyed off the corvette ledger instead of a
flat pad scan. Refuses if buckled, dead, or on a 30-second per-ckey
cooldown. The corvette's own boarding pad is map-placed inside its `.dmm`,
same as its console and landmark.

**Fixed a real gap while building this**: `telepad_cargo`'s faction tagger
action was missing the `SSpersistence.objectsRegisterTrack()` call the
cryopod path already had -- a player-dropped cargo telepad (via the
`telepad_beacon` item) silently never survived a server restart. Now fixed
at the base class, so every `telepad_cargo` subtype benefits, not just the
new boarding pad.

### 4.3 Why the overmap marker gets fully deleted, not just hidden

Worth understanding if you ever touch this code: `GLOB.map_sectors["[z]"]`
is looked up **unchecked** in ~90 places across this codebase. Nothing in
the base engine ever clears that mapping when a marker is destroyed
(because until this phase, nothing ever deleted a live overmap ship marker
at all). `corvetteStash()` explicitly nulls every `GLOB.map_sectors` entry
for the marker's own `map_z` before `qdel()`ing it -- skipping this would
leave a dangling reference that things like
`zone_security_update_overmap()`'s full-list sweep would trip over.

### 4.4 Faction Ship Program (`.../programs/command/faction_ships.dm`, TGUI `FactionShips`)

Three tabs: **Status** (your faction's corvettes, Retrieve/Stash buttons),
**Market** (templates, Buy), **Boarding** (read-only list of networked
boarding pads). Distinct from the Drydock program entirely -- corvettes
never appear there and vice versa.

### 4.5 The placeholder hull

`maps/factions/corvettes/faction_corvette_placeholder/` is a **deliberately
minimal** proof-of-framework hull (a single small room: console, ship
landmark, transit landmark, overmap marker, boarding pad). It exists to
prove Buy/Retrieve/Stash/beacon-radius-placement/boarding work end-to-end
without waiting on real map art. **A real multi-deck interior is a separate
content-authorship task, not yet done** -- swapping it in later means
replacing the `.dmm` and writing a new template/ship/shuttle-datum/console
subtype group modeled on `faction_corvette_placeholder.dm`; none of the
engine code in `persistence_corvettes.dm` changes.

### 4.6 Testing checklist

1. Stand a Faction Ship Program computer on a Z claimed by your faction's
   beacon. Buy a corvette (Market tab) -- confirm it shows up **stashed**,
   nothing appears on the overmap.
2. Retrieve it -- confirm the marker appears within the beacon's configured
   `security_radius` of that beacon's overmap sector, and the ship is
   flyable via its console (helm docking, sensor scans -- all stock).
3. Board it from a faction-tagged boarding pad at a station; confirm arrival
   at the ship's own boarding pad.
4. Stash it -- confirm the marker is gone from the overmap and `GLOB.map_sectors`
   for that Z no longer resolves to it (no stray sector in admin tools).
5. Retrieve again -- confirm a **new** Z gets allocated (check the log for
   two different z-values across the two retrieves) and everything still
   works.
6. Leave a corvette deployed and run a graceful shutdown -- confirm
   `corvetteAutoStashAll()` recovers it (check the log) and the DB row is
   `stashed=1` on the next boot.
7. Try retrieving from a Z with no beacon, or a beacon belonging to a
   different faction -- confirm a specific refusal message each time.
8. Try stashing with a player still aboard -- confirm refusal.

---

## 5. Reading the debug logs

Every action across both systems writes a verbose trace to the dedicated
persistence subsystem log file, gated behind the `log_subsystems_persistence`
config toggle (never shown to players, never spammed to the main server
log). Enable it, then grep the log by prefix:

- `Drydock: ...` -- every shuttle/pad/beacon action (`log_drydock`,
  `log_drydock_warning`, `log_drydock_error`).
- `Corvette: ...` -- every corvette action (`log_corvette`,
  `log_corvette_warning`, `log_corvette_error`).

`_warning` lines are expected refusals (bad input, permission, occupied
pad/beacon mismatch) -- read them as "here's exactly why this attempt was
rejected," not as bugs. `_error` lines are real failures (DB connection
down, corrupt data, a proc that should never fail failing anyway) and are
worth investigating. Every `ui_act()` case in both TGUI programs logs the
*request* (who asked for what) in addition to the engine logging the
*outcome*, so a player's bug report ("I clicked retrieve and nothing
happened") is traceable to the exact refusal reason the server actually saw.

---

## 6. Lifecycle tooling (tombstones, recall, `shuttle_core` removal)

Both items previously listed here as "known gaps" are now built.

**`shuttle_core` is gone.** The legacy hand-built-hull machine (and its two
verbs, `preview_hull()`/`finalize_shuttle()`) and its cargo entry are
removed -- the drydock system fully replaces it, and it never stopped
players from building their own hull anyway (retrieve, redecorate with
normal construction, stash again). The docking beacon and
`/datum/shuttle/player_built` stay, unaffected, in the same file
(`shuttle_core.dm`). The legacy `ss13_player_shuttles` table is dropped
(`V078`); `shuttleStateRestore()` no longer has a step reconstructing
shuttles from it.

**Tombstone rows**: a `ss13_drydock_shuttles` row now has `last_pad_tag`
(updated on every stash/retrieve) and `destroyed_at` (`V079`). If a
deployed shuttle's datum is destroyed *without* going through
`drydockStash()` first (combat, sabotage, admin `qdel`), `Destroy()` calls
`drydockMarkTombstoneIfDeployed()`, which sets `destroyed_at` if the row is
still `stashed=0` -- distinguishing a genuine unexpected loss from a normal
stash (which already set `stashed=1` before its own `qdel()`, and sets
`persistence_intentional_teardown = TRUE` on the datum first so `Destroy()`
skips the check entirely on the expected path). The row and its
`shuttle_name` stay reserved until an admin runs **Clear Tombstoned
Shuttles** (Persistence category) to review and delete them.

**Force Stash Ship** (Persistence category, admin): on-demand recall for
either system, not just the shutdown sweeps. Picking a corvette calls
`corvetteStash(..., force=TRUE)` directly (already position-agnostic).
Picking a drydock shuttle calls `drydockForceStashByName()`: looks up its
`last_pad_tag`, recalls it there via `short_jump()` if it's not already
docked there (refusing if the pad's occupied by a *different* shuttle or
the destination is obstructed), then stashes it normally. A shuttle that's
never been stashed/retrieved at least once has no `last_pad_tag` yet and
must be stashed manually the first time.

---

## 7. Quick file reference

| Piece | File |
|---|---|
| Docking beacon, player_built shuttle datum | `code/modules/shuttles/shuttle_core.dm` |
| Drydock pad blueprint/eye | `code/modules/mob/abstract/freelook/blueprints/blueprints.dm` |
| Drydock stash/retrieve engine, lifecycle tooling, `log_drydock*` | `code/controllers/subsystems/persistence/persistence_shuttles.dm` |
| Drydock program | `code/modules/modular_computers/file_system/programs/command/drydock.dm` + `tgui/packages/tgui/interfaces/ShuttleDrydock.tsx` |
| Faction Chat | `code/modules/modular_computers/file_system/programs/generic/faction_chat.dm` + `FactionChat.tsx` |
| Corvette ledger engine, `log_corvette*` | `code/controllers/subsystems/persistence/persistence_corvettes.dm` |
| Z-level reset engine (shared with admin tool) | `code/controllers/subsystems/persistence/persistence_zlevel_reset.dm` |
| Corvette ship/shuttle/console framework | `code/modules/overmap/ships/faction_corvette.dm` |
| Placeholder hull | `maps/factions/corvettes/faction_corvette_placeholder/` |
| Boarding pad | `code/modules/telesci/telepad_corvette_boarding.dm` |
| Faction Ship Program | `code/modules/modular_computers/file_system/programs/command/faction_ships.dm` + `FactionShips.tsx` |
| Migrations | `SQL/migrate-2023/V073` through `V079` |

## 8. Still not built

- **Real corvette interior art** -- see 4.5. The placeholder hull proves the
  framework; a real multi-deck ship is separate content-authorship work.
- **Corvette-side tombstoning** -- nothing can currently destroy a
  corvette's overmap marker except `corvetteStash()` itself (no
  ship-combat/vulnerability mechanic exists yet), so this wasn't built --
  revisit if/when corvettes become destructible.
