# Shuttle Drydock System + Faction Chat -- Implementation Architecture

Source requirements: `docs/shuttlesystem.txt` (user notes). This document is the
researched, codebase-grounded implementation plan for those notes. Every claim
about existing code below was verified by reading the actual files in this
checkout -- file:line references are current as of writing.

**Hard requirement from the user:** the minimum drydock pad grid is **30x18
tiles** for a docking port to function.

---

## Part 0: What already exists (do not rebuild these)

The notes say "tied into, refactoring, the already existing
persistent_shuttles.dm" -- but the existing layer is bigger than that file.
Inventory:

### 0.1 Player-built shuttle datum layer -- `code/modules/shuttles/shuttle_core.dm`

- `/datum/shuttle/player_built` (line 21): hull stored as a **list of turf
  refs by position** (`hull_turfs`), NOT by area. `owner_ckey`, `faction_uid`
  vars. `attempt_move()` (line 51) builds a turf translation from `hull_turfs`,
  does `check_collision()` on the destination footprint, and refuses
  faction-restricted beacons (`/obj/effect/shuttle_landmark/player_dock`,
  line 90, `faction_restricted` var).
- `/proc/create_player_shuttle(name, hull_turfs, home_turf, ckey, faction_uid)`
  (line 99): creates a home landmark `"[name]_home"` + the datum. Used both by
  live registration and boot-time restore.
- `/obj/structure/machinery/shuttle_core` (line 120): flood-fill hull scanner
  (max 200 tiles, `max_hull_size`), `preview_hull()` ASCII-grid verb,
  `finalize_shuttle()` verb writes `ss13_player_shuttles` (hull as JSON list of
  `"x,y,z"` strings).
- `/obj/structure/machinery/docking_beacon` (line 313): wrench-anchor +
  screwdriver-activate flow, registers `/obj/effect/shuttle_landmark/player_dock`
  with tag `"dock_[x]_[y]_[z]"`, writes `ss13_player_docking_beacons`. Faction
  claim/release by ID swipe, officer+ rank via `get_faction_member()` (lines
  360-403).

### 0.2 Persistence restore -- `code/controllers/subsystems/persistence/persistence_shuttles.dm`

`shuttleStateRestore()` (line 54), called at the end of `SSshuttle.Initialize()`:
1. Recreates beacon landmarks from `ss13_player_docking_beacons`.
2. Reconstructs `/datum/shuttle/player_built` datums from `ss13_player_shuttles`
   (`hull_json` coords -> live turf refs).
3. Moves ALL shuttles (map + player) to their saved landmark from
   `ss13_persistent_shuttles` via `short_jump()`.

Save side: `shuttleStateFinalize()` (line 20) from `SSpersistence.Shutdown()`.
**Ordering guarantee (critical, keep it):** SSshuttle (init_order -2.2) restores
positions BEFORE SSpersistence (-10) loads objects, so objects load at the
shuttle's real position (file header, lines 6-11).

### 0.3 SQL already migrated

- `V053__shuttle_state.sql`: `ss13_persistent_shuttles (shuttle_name UNIQUE, location_tag)`.
- `V055__player_shuttles.sql`: `ss13_player_shuttles (shuttle_name PK,
  owner_ckey, faction_uid, home_x/y/z, hull_json)` and
  `ss13_player_docking_beacons (landmark_tag PK, x, y, z, label)`.

### 0.4 Two verified pre-existing BUGS to fix during the refactor

**(a) Dead beacon persistence.** `shuttle_core.dm` defines
`persistent_objects_get_content()`/`apply_content()` for the docking beacon
TWICE (lines 340-358 rich version incl. `beacon_active`, `faction_restricted`,
`beacon_shackled`; lines 439-449 label-only version). Empirically verified with
DM 516.1682 (scratch project, duplicate proc definitions): **the compiler
accepts duplicates silently, 0 errors 0 warnings, and the LAST definition
wins.** So the rich block is dead code -- beacon active-state and faction
restriction currently do NOT persist. Fix: delete the label-only duplicate at
439-449, keep 340-358.

**(b) Beacon restore never re-activates.** `docking_beacon/Initialize()` (line
330) only calls `_register_landmark()` when `anchored && beacon_active` -- but
`beacon_active` is restored later by `persistent_objects_apply_content()`, and
because of bug (a) it's never restored at all. After fixing (a), also re-run
`_register_landmark()` from `apply_content()` when `beacon_active` becomes TRUE
(idempotent -- it already early-outs via `landmark_registered` and claims
landmarks pre-made by `shuttleStateRestore()`).

### 0.5 Turf-move mechanics ("eating turfs") -- `code/__HELPERS/turfs.dm`

- `get_turf_translation(src_origin, dst_origin, turfs_src)` (line 138): pure
  offset mapping.
- `translate_turfs(translation, base_area, base_turf, ignore_background)`
  (line 152): destination turf becomes `ChangeTurf(source.type)` +
  `transport_properties_from()`, contents `forceMove`d; then every source turf
  is reset to `base_turf` (for shuttles: `current_location.base_turf`, plating
  for player docks -- `shuttle.dm:247`).

Consequence the notes are worried about: a decorated pad tile gets overwritten
by the hull on landing and reverts to **plating** on departure. The
architecture answer (Part 2): pad tiles are a standardized, non-persisted,
canonical grid -- they are cheap and regenerate; nothing of value is ever on a
pad tile except the shuttle itself.

### 0.6 Blueprint eye system -- reusable as-is

- `/obj/item/blueprints` (`code/game/objects/items/blueprints.dm:1`) attaches
  `/datum/component/eye/blueprints` (line 108-109); `attack_self()` menu ->
  `look()` enters the freelook eye.
- `/mob/abstract/eye/blueprints`
  (`code/modules/mob/abstract/freelook/blueprints/blueprints.dm:3`):
  rectangular box-select via BYOND `block()` (line 346), shift-remove,
  ctrl-clear, validity via `check_turf_validity()` (line 373: z-check, no
  stealing non-background areas via `AREA_FLAG_IS_BACKGROUND`, no space,
  `check_contiguity()` flood-fill at 391). Selection highlight: per-turf
  `image('icons/effects/blueprints.dmi', T, "valid"/"invalid")` on
  `client.images`, HUD_PLANE (lines 436-448).
- `finalize_area()` (line 90): `new /area`, `is_blueprint_area = TRUE`,
  `T.change_area()` per turf.
- Blueprint areas persist via `ss13_persistent_areas`
  (`persistence_areas.dm:113`, `V070__persistent_areas.sql`): per-area row of
  `name, area_type, turfs(JSON), persistent_network`; rebuilt at boot BEFORE
  worldstate by `areasInitialize()` (line 24) using `text2path` +
  `change_area()`, never stealing mapped areas' turfs.
- Faction gating precedent for blueprint use on claimed Z-levels:
  `blueprints.dm:35-47` (beacon-claimed Z requires matching ID
  `employer_faction`).

### 0.7 Area-scoped persistence exclusion -- precedent exists, general mechanism does not

All turf/object persistence sweeps are **z-level scoped only**
(`persistence_z_excluded()` / `persistence_z_manual_blocked()`,
`persistence.dm:40-53`). The ONE area-scoped exclusion today is
`AREA_FLAG_PREVENT_PERSISTENT_TRASH` (`code/__DEFINES/misc.dm:141`, checked in
`items.dm:519-539`). Part 2 generalizes this pattern for pad areas.

### 0.8 Runtime .dmm template loader -- exists

`/datum/map_template` (`code/modules/mapping/map_template.dm`): `var/mappath`,
`width`, `height`; **`load(turf/T, centered)` (line 176) loads the .dmm
in-place at an arbitrary turf** with bounds checks and atom init. This is the
premade-shuttle loader -- no new .dmm machinery needed. (Away sites use the
same datum via `SSmapping.away_sites_templates`.)

### 0.9 Modular computer program plumbing -- all patterns exist

- Program definition: subtype `/datum/computer_file/program`
  (`file_system/program.dm:1-88`); model example
  `generic/invoice_program.dm:9-22` (`filename`, `size`, `usage_flags`,
  `requires_ntnet`, `available_on_ntnet`, `tgui_id`, `ui_auto_update`).
  Registration is automatic via `build_software_lists()`
  (`NTNet/NTNet.dm:92-107`) -- any program with a unique filename +
  `available_on_ntnet` is downloadable; presets in `app_presets_.dm`.
- `ui_data()` must start from `initial_data()` (`_program.dm:4-5`).
- Background/event API: `process_tick()` (`program.dm:207`),
  `program_events.dm` service hooks; `ntnrc_client.dm:45-56` registers into a
  global list to receive messages while minimized -- the model for Faction
  Chat delivery.
- **PDA ping pattern (First Responder)** -- lives in
  `persistence_zone_security.dm:338-357`, NOT in first_responder.dm: loop
  `for(var/obj/item/modular_computer/MC in world)`, filter
  `MC.persistent_network`, powered/screen-on, program-on-drive
  (`MC.hard_drive.find_file_by_name("firstresponder")`), then
  `MC.get_notification(text, 1, title)` (`computers/modular_computer/core.dm:540-545`
  -- plays twobeep, shows to holder). Cooldown lives at the caller.
- SQL from programs: `faction_manage.dm:78-92` (`SSdbcore.NewQuery` with named
  params, blocking `Execute()` -- fine in `ui_act`, never in `process_tick`).
- Faction identity: ID-based lenient check
  (`normalize_faction_uid(ID.employer_faction) == net`, `invoice_program.dm:46`)
  vs strict roster check (`get_faction_member(ckey, uid)`,
  `persistence_factions.dm:1629`). A civilian ID has `employer_faction == null`
  (`cards_ids.dm:222-225`).

---

## Part 1: New DB schema -- migration `V073__drydock.sql`

```sql
-- Drydock pad definitions (one row per blueprint-designated pad)
CREATE TABLE IF NOT EXISTS `ss13_drydock_pads` (
    `pad_id`       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `map_path`     VARCHAR(64)  NOT NULL,
    `landmark_tag` VARCHAR(128) NOT NULL COMMENT 'docking beacon landmark this pad is bound to',
    `z`            INT NOT NULL,
    `turfs`        MEDIUMTEXT NOT NULL COMMENT 'JSON array of "x,y" strings (z implied)',
    `anchor_x`     INT NOT NULL COMMENT 'grid anchor (bottom-left of bounding box)',
    `anchor_y`     INT NOT NULL,
    `width`        INT NOT NULL,
    `height`       INT NOT NULL,
    `created_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`pad_id`),
    UNIQUE KEY `uq_pad_beacon` (`landmark_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Stashed (drydocked) shuttles. One row per stored shuttle.
CREATE TABLE IF NOT EXISTS `ss13_drydock_shuttles` (
    `shuttle_id`   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `shuttle_name` VARCHAR(64) NOT NULL,
    `owner_ckey`   VARCHAR(32) DEFAULT NULL COMMENT 'personal owner; NULL if faction-owned',
    `faction_uid`  VARCHAR(32) DEFAULT NULL COMMENT 'owning faction; NULL if personal',
    `home_z`       INT NOT NULL COMMENT 'z-level scope: retrievable at any pad on this z',
    `width`        INT NOT NULL,
    `height`       INT NOT NULL,
    `hull_json`    MEDIUMTEXT NOT NULL COMMENT 'JSON: relative turf grid, see Part 3 format',
    `stashed`      TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = in drydock (serialized), 0 = deployed live',
    `template_id`  VARCHAR(64) DEFAULT NULL COMMENT 'premade template it was bought from, if any',
    `purchased_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `stashed_at`   DATETIME DEFAULT NULL,
    PRIMARY KEY (`shuttle_id`),
    UNIQUE KEY `uq_drydock_name` (`shuttle_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Faction chat log
CREATE TABLE IF NOT EXISTS `ss13_faction_chat` (
    `msg_id`      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_uid` VARCHAR(32) NOT NULL,
    `sender_name` VARCHAR(64) NOT NULL COMMENT 'character real_name at send time',
    `sender_ckey` VARCHAR(32) NOT NULL,
    `message`     VARCHAR(512) NOT NULL,
    `sent_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`msg_id`),
    KEY `idx_faction_time` (`faction_uid`, `msg_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Notes: `ss13_player_shuttles` / `ss13_persistent_shuttles` /
`ss13_player_docking_beacons` stay as-is (deployed-state tracking).
`ss13_drydock_shuttles.stashed` distinguishes "in the DB vault" from "deployed
live" so a shuttle bought but currently flying still shows in the program with
its ownership row.

---

## Part 2: Drydock pad -- blueprint, area type, persistence exclusion

### 2.1 New area + flag

- `code/__DEFINES/misc.dm`: add `#define AREA_FLAG_DRYDOCK_PAD` (next free bit
  alongside `AREA_FLAG_PREVENT_PERSISTENT_TRASH`, misc.dm:141).
- New `/area/drydock_pad` (new file `code/game/area/drydock.dm` or inside the
  new drydock module file): `area_flags = AREA_FLAG_PREVENT_PERSISTENT_TRASH | AREA_FLAG_DRYDOCK_PAD`,
  `requires_power = FALSE`, `has_gravity = TRUE`. It is deliberately dumb --
  its only job is marking turfs.

### 2.2 Persistence exclusion (the "(NOT SAVED)" requirement, notes line 20)

New helper in `persistence.dm` next to `persistence_z_excluded()`:

```dm
/proc/persistence_area_excluded(turf/T)
    var/area/A = get_area(T)
    return A && (A.area_flags & AREA_FLAG_DRYDOCK_PAD)
```

Gate each content sweep with it (skip-and-continue, one line each):
- `persistence_turfs.dm` `turfsFinalize()` -- skip changed turfs inside pad areas.
- `persistence_worldstate.dm` `worldstateFinalize()` blanket loops (lines
  91-93 / 241-243 region) -- skip structures on pad turfs.
- `persistence_floor_items.dm` `floorItemsFinalize()` -- skip items on pad turfs.
- `persistence_objects.dm` -- in `objectsRegisterTrack()` refuse registration
  for objects on pad turfs (mirror the `try_make_persistent_trash()` /
  `AREA_FLAG_PREVENT_PERSISTENT_TRASH` de-registration pattern, items.dm:519-539).
- `persistence_decals.dm`, `persistence_closets.dm` -- same one-line skip.

Do NOT touch the Initialize/restore side: nothing was ever saved for these
turfs, so nothing loads onto them -- pads boot as their .dmm/blueprint default
state every round, exactly as the notes demand ("doesn't fight with autosaving
or manual saves").

The pad AREA ITSELF (name, turf membership) still persists via the existing
blueprint-area table (`ss13_persistent_areas`) -- that's designation metadata,
not contents, and `areasInitialize()` already rebuilds it before worldstate.

### 2.3 Drydock blueprint item

New `/obj/item/blueprints/drydock` in `blueprints.dm`:
- `color = "#cc3333"` tint + name "drydock blueprint" (notes: "uses blueprint
  sprite, colored red").
- Reuses the same eye component with a subtype
  `/mob/abstract/eye/blueprints/drydock` (mirror the existing
  `/mob/abstract/eye/blueprints/shuttle` subtype precedent, blueprints eye
  file line 475):
  - Selection rules identical (rectangular `block()` select, contiguity).
  - `finalize_area()` override: area type forced to `/area/drydock_pad`;
    **validate bounding box >= 30x18** (reject with a clear message otherwise);
    validate every turf in the 30x18+ bounding box is selected (the pad must
    be a full solid rectangle -- shuttles land as rectangles; partial/L-shaped
    pads are exactly the "eats turfs" hazard).
  - On success: find the (single) `/obj/structure/machinery/docking_beacon`
    inside the selection -- REQUIRED; refuse finalize without one ("place and
    activate a docking beacon on the pad first"). Write the
    `ss13_drydock_pads` row binding `landmark_tag` -> turf list + anchor +
    dimensions.
- Officer gating: same faction check the base blueprint `attack_self()` does
  (blueprints.dm:35-47) -- on a beacon-claimed Z only that faction's officers
  (or admins) can designate pads.

### 2.4 Runtime pad registry

`SSshuttle`-adjacent global: `GLOB.drydock_pads` -- assoc `landmark_tag ->
/datum/drydock_pad` (lightweight datum: turf list, anchor turf, w/h, pad_id,
occupancy cache). Loaded from `ss13_drydock_pads` in `shuttleStateRestore()`
step 1.5 (after beacon landmarks exist, before player shuttles reconstruct).
Live-created pads (blueprint finalize) insert both DB row and registry entry
immediately -- everything works mid-session with no restart (notes: "loads
live mid session").

**Occupancy rule** (notes line 10: "no shuttles may be undocked to be loaded
or wiped on another, no ships may dock when it is taken"): a pad is `occupied`
if any live shuttle's `current_location` is its bound landmark. Enforce in:
- `shuttle_landmark/player_dock/is_valid()` override -- refuse docking when the
  pad registry says occupied (belt-and-braces on top of `check_collision()`).
- Drydock program actions (Part 4): retrieve requires pad unoccupied; stash
  requires the target shuttle to be the one currently ON this pad.

---

## Part 3: Stash/retrieve engine (`persistence_shuttles.dm` refactor)

New procs on SSpersistence (or a `/datum/drydock_controller` singleton --
implementer's choice, keep it in `persistence_shuttles.dm`):

### 3.1 Serialization format (`hull_json`)

Per hull turf, relative to the shuttle's bounding-box bottom-left corner:

```json
{
  "w": 12, "h": 7,
  "turfs": [
    {"dx": 0, "dy": 0, "type": "/turf/simulated/floor/shuttle/dark_blue",
     "props": {...},
     "objs": [ {"type": "/obj/structure/machinery/door/airlock/...", "dir": 2,
                "name": "...", "content": {...}}, ... ]
    }, ...
  ]
}
```

- Turf `props`: reuse the exact same per-turf-type extraction
  `turfsFinalize()` already does (floor broken/burnt/color, wall
  material/reinf/health -- `persistence_turfs.dm:86-101` shows the apply side;
  mirror its save side).
- Object `content`: reuse the existing per-object serializers --
  `worldstate_get_content()` for worldstate-listed machines,
  `persistent_objects_get_content()` for tracked objects, and the floor-item
  field set (`type,pixel_x,pixel_y,dir,name,icon_state,extra` --
  `persistence_floor_items.dm:30`) for loose items. One dispatch helper:
  serialize an obj by trying those three vocabularies in that order.
- **Mobs are never serialized.** Stash is refused if any player mob is present
  (3.2); NPC/simple mobs on the hull at stash time are `qdel`'d after a
  confirm prompt listing them.

### 3.2 `drydock_stash(datum/shuttle/player_built/S, datum/drydock_pad/pad, mob/user)`

1. Validate: S is live, `S.current_location` == pad's landmark (must be
   physically landed on THIS pad), user is owner (`owner_ckey == user.ckey`) or
   faction officer (`can_configure_faction_shackle(user, S.faction_uid, 1)`,
   `persistence_factions.dm:345`) or admin.
2. **Player-mob check (notes line 24):** scan every hull turf AND every pad
   turf for `mob/living` with a client or ckey (covers SSD bodies). Any found
   -> refuse with names. Same check on retrieve.
3. Serialize per 3.1 -> UPDATE `ss13_drydock_shuttles` row (`stashed = 1`,
   `hull_json`, `stashed_at = NOW()`, `home_z = pad z`).
4. Tear down live presence: `qdel` every obj on hull turfs, `ChangeTurf` each
   hull turf to the pad's canonical base (plating -- same as departure
   behavior), delete the shuttle's home landmark, remove from
   `ss13_persistent_shuttles` + `ss13_player_shuttles` (it is no longer a live
   deployed shuttle), `qdel(S)` (its `Destroy()` already deregisters from
   SSshuttle, `shuttle_core.dm:46-49`).
5. This is fully "separate scope" from autosave (notes line 8): no
   worldstate/turf tables touched -- pad turfs were never persisted anyway.

### 3.3 `drydock_retrieve(shuttle_id, datum/drydock_pad/pad, mob/user)`

1. Validate: row `stashed = 1`; `home_z == pad z` OR admin override (notes
   line 20: z-scoped retrieval, admins can restore at any pad); ownership same
   as stash; pad unoccupied; shuttle `w x h` fits inside pad bounding box;
   player-mob check over the pad footprint; `check_collision()` over target
   turfs (dense obstructions).
2. Rebuild: for each serialized turf, `ChangeTurf(type)` + apply props; spawn
   objs + apply their content vocabularies. All placement at pad anchor +
   relative offsets.
3. Recreate the live shuttle: `create_player_shuttle(name, rebuilt_turfs,
   pad_anchor_turf, owner_ckey, faction_uid)`, re-insert
   `ss13_player_shuttles` + `ss13_persistent_shuttles` (location = this pad's
   landmark), flip `stashed = 0`.
4. Everything live, no restart (this is just the boot-time reconstruction path
   run on demand -- `shuttleStateRestore()` steps 2-3 already prove the
   mechanism works mid-process).

### 3.4 Boot interaction

`shuttleStateRestore()` gains step 1.5 (load pad registry). Stashed shuttles
(`stashed = 1`) are simply NOT reconstructed at boot -- they exist only as DB
rows until retrieved. Deployed ones restore exactly as today.

---

## Part 4: Drydock program (modular computer, TGUI)

New `/datum/computer_file/program/drydock` --
`code/modules/modular_computers/file_system/programs/command/drydock.dm`,
`tgui_id = "ShuttleDrydock"`, new `tgui/packages/tgui/interfaces/ShuttleDrydock.tsx`.
Follow `invoice_program.dm` shape exactly (Part 0.9). `available_on_ntnet = TRUE`.

The program operates on the NEAREST pad: `ui_data` locates the closest
registered pad on the computer's z (or lets the user pick from pads on this z
-- dropdown). All actions server-validated in `ui_act` (never trust client).

### Tabs / sections (notes lines 3-6, 22):

1. **Drydock** -- two sub-tabs, **Personal** (rows where
   `owner_ckey == user.ckey`) and **Faction** (rows where `faction_uid` matches
   the user's ID `employer_faction`, strict-checked via `get_faction_member()`
   for actions). Each row: name, size WxH, stashed/deployed status, home_z, and
   buttons: Retrieve (stashed, on matching z), Stash (deployed AND currently on
   this pad), Rename, Sell/Remove (owner only; removal of a STASHED shuttle
   deletes the DB row after confirm -- "removal of owned shuttles").
2. **Market** -- premade purchasable shuttle templates (Part 5): name, size,
   price, description, Buy button. Buying charges the user's account (reuse the
   charge idiom from the economy/invoice systems -- `ATM.dm` /
   `invoice_program.dm` account patterns) or the faction account
   (`ss13_faction_transactions`, `faction_manage.dm:165-180`) when "purchase as
   faction shuttle" is toggled (notes line 22). A purchase inserts a
   `ss13_drydock_shuttles` row with `stashed = 1` and `hull_json` pre-generated
   from the template (Part 5.2) -- buying puts it IN the drydock; the player
   then retrieves it onto the pad.
3. **Pad status** -- pad dimensions, occupied-by, and the **grid highlight
   button** (notes line 6): on click, spawn `/obj/effect/shuttle_warning`
   markers on every pad turf for ~15 seconds -- the exact mechanism
   `shuttle_core.preview_hull()` already uses (`shuttle_core.dm:179-186`), no
   new visuals needed. Additionally overlay the stashed-shuttle footprint
   (selected row's WxH from the anchor) in a second pass so the player can see
   whether a given shuttle fits before retrieving.

Access gating: opening the program is unrestricted; actions require ownership
/ officer rank / admin as per Part 3 validation.

---

## Part 5: Premade shuttle templates (notes lines 12-13)

**Revised after implementation discussion**: the original design below this
line called for hand-authored `.dmm` files loaded through a new
`/datum/map_template` pipeline, purely to get hull data into the same
`hull_json` shape Part 3.1's serializer already produces. That's unnecessary
-- Phase 4's stash engine already turns any docked shuttle into exactly that
JSON. Templates are built the same way a player builds a shuttle: construct
it in-game with normal tools (no map editor needed), dock it on a pad, Stash
it, then publish that stash as a catalog entry. No `.dmm` files, no new
template datum subtypes, no scratch z-level, no load-once-serialize-at-boot
step.

### 5.1 Publish a stashed shuttle as a template

New table, `ss13_drydock_templates` (own migration when this phase is built):
```sql
CREATE TABLE IF NOT EXISTS `ss13_drydock_templates` (
    `template_id`  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `display_name` VARCHAR(64) NOT NULL,
    `desc`         VARCHAR(255) DEFAULT NULL,
    `price`        INT UNSIGNED NOT NULL DEFAULT 0,
    `width`        INT NOT NULL,
    `height`       INT NOT NULL,
    `hull_json`    MEDIUMTEXT NOT NULL,
    `created_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`template_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

New admin-only drydock program action, "Publish as Template", available on
any row in the Personal/Faction tab with `stashed = 1`: prompts for
`display_name`/`desc`/`price`, then copies that row's `hull_json`/`width`/`height`
into a new `ss13_drydock_templates` row. The source stash is untouched --
publishing makes an independent copy, so the original owner keeps their build
and can keep customizing it without retroactively changing already-published
templates. Admins iterate by stashing a new version and publishing again.

### 5.2 Purchase-time generation ("customize, saves from there")

Buying a template (Market tab, Part 4): SELECT the template row, INSERT a new
`ss13_drydock_shuttles` row with `hull_json`/`width`/`height` copied verbatim,
`owner_ckey`/`faction_uid` set to the buyer (or their faction, if bought as a
faction shuttle), `stashed = 1`, `template_id` = the source template's id
(lineage, not required elsewhere). No live map interaction at purchase time --
works even if every pad on the map is occupied.

Customization loop is unchanged: retrieve (deploy) -> rebuild/redecorate the
hull in the world with normal construction -- the hull is a live
player_built shuttle -- then stash again; stash re-serializes whatever the
hull now is ("as well as ability to load/save their shuttle in the states it
were"). The flood-fill hull re-scan on stash picks up player modifications to
the hull SHAPE too: re-run the `shuttle_core` flood-fill from the shuttle core
machine at stash time rather than trusting the stale turf list, capped to the
pad bounding box.

This also answers notes line 14 ("use custom turf objects that work as a grid
to save and load? or perhaps some smarter way") -- the smarter way is: no
custom turf objects at all; the pad IS the grid (anchor + relative offsets),
and serialization reuses the three existing object vocabularies.

---

## Part 6: Faction Chat program (notes lines 26-28)

New `/datum/computer_file/program/faction_chat` --
`.../programs/generic/faction_chat.dm`, `tgui_id = "FactionChat"`, new
`FactionChat.tsx`. Model: `ntnrc_client.dm` (service registration for
background receive) + `invoice_program.dm` (faction gate) + the First
Responder ping loop (`persistence_zone_security.dm:338-357`).

### 6.1 Access gate (per notes: faction access, "not just civilian")

On every `ui_data`/`ui_act`: `var/net = normalize_faction_uid(ID.employer_faction)`
from `user.GetIdCard()`; require non-null AND
`get_faction_member(user.ckey, net)` returns a member row (strict roster
check -- this is what distinguishes a real faction member from someone handed
a blank printed card; a default civilian ID fails at the first step because
`employer_faction` is null, `cards_ids.dm:222-225`). Chat identity = character
`real_name` (notes: "by character name").

### 6.2 Message flow

- Send (`ui_act "send"`): sanitize + length-cap (512), INSERT into
  `ss13_faction_chat`, then fan out live (6.3). Per-ckey flood cooldown
  (~2s) via a static assoc list.
- History (`ui_data`): `SELECT ... WHERE faction_uid = :net ORDER BY msg_id
  DESC LIMIT 50 OFFSET :page*50` -- newest page first, "few pages" of history
  via Prev/Next page buttons (notes: "only shows up to a certain number of
  entries... decent and long enough history (few pages)"). Cache the current
  page in the program datum; refresh on send/receive rather than re-querying
  every ui_data tick (`ui_auto_update = FALSE`, push updates).
- Optional retention: prune rows older than N days in a nightly-ish hook
  (SSpersistence.Shutdown() is fine) -- keep it simple.

### 6.3 Live delivery + PDA pings (notes line 28)

On successful send, one world loop (exactly the First Responder shape):

```dm
for(var/obj/item/modular_computer/MC in world)
    if(!get_turf(MC)) continue
    if(!MC.enabled || !MC.computer_use_power()) continue
    if(!MC.hard_drive || !MC.hard_drive.find_file_by_name("factionchat")) continue
    // deliver only to devices whose CURRENT USER/holder is a member:
    //   resolve holder mob -> GetIdCard() -> employer_faction == sender's net
    MC.get_notification("[sender_name]: [message]", 1, "Faction Chat")
    // if the program instance is open, push a TGUI update too
    CHECK_TICK
```

The `get_notification()` call is the ping: twobeep sound + message visible to
the wearer only (`core.dm:540-545`) -- "they can basically see the chat
through pings in live time and then take it out and respond." Program
instances registered as running (mirror `GLOB.ntnet_global.chat_clients`
registration, `ntnrc_client.dm:45-56`) get their cached page invalidated so an
open window updates immediately.

Membership filter on delivery must be holder-based (whoever carries the PDA
right now), not device-owner-based -- a PDA lying on a table with no holder
gets no ping (holder resolution returns null).

---

## Part 7: Faction Corvettes (spawnable, pilotable, faction-owned away ships)

New idea, added after the drydock design above -- factions get access to
much larger, hand-authored multi-deck ships (corvette-class, like the
existing away-site ships, e.g. `maps/away/ships/biesel/tcaf_corvette/`) that
they can buy, deploy, fly around the overmap, and store again -- without any
admin verb, through a new modular computer program. This is a **structurally
different system from the drydock shuttles above, not an extension of it**:
no turf-grid serialization, no pad, no blueprint. Instead it reuses the
Z-level template-loading machinery this codebase already uses for away
sites, and the player-boarding mechanism recommended (but not yet built) in
`docs/overmap-traversal-research.md`.

### 7.1 Why this can't work like the drydock shuttles, and what to reuse instead

Three load-bearing facts, all confirmed by direct research already on file in
this repo (not re-derived here):

1. **Z-levels can never be freed.** `docs/overmap-traversal-research.md`
   section 1.1: `world.incrementMaxZ()` is the only way Z-space is created,
   there is no `decrementMaxZ()` anywhere in the codebase, and BYOND
   allocates a full `world.maxx * world.maxy` turf grid (~65,000 turfs on
   this codebase's 255x255 maps) the instant a Z is created, permanently, for
   the life of the server process. "Despawning" a corvette can never mean
   reclaiming its Z -- only *resetting it in place* and reusing it for the
   next deployment.
2. **A live template-Z-materialization precedent already exists and is
   exactly this shape.** Away sites already do "don't eagerly materialize
   every possible ship; only create the ones actually in use, one Z at a
   time, on a budget" via `/datum/map_template/proc/load_new_z()`
   (`map_template.dm:54-105`) -> `SSmapping.add_new_zlevel()`
   (`zlevel_manager.dm:1-17`) (`overmap-traversal-research.md` section 1.4).
   A purchased corvette is loaded the same way, on demand, at purchase time --
   not pre-materialized for every faction that might ever buy one.
3. **"Reset a Z live, without a restart" is also already built.** The `Reset
   Z-Level` admin tool (`persistence_zlevel_reset.dm:139-289`) respawns
   destroyed structures, resets existing ones to fresh compiled defaults,
   clears dynamic/player-placed content and floor items, reverts turfs to
   baseturf, and purges every persistence DB row for that Z -- live, with no
   server restart. This is precisely "store the corvette" -- the same
   operation, just triggered by the faction ship program instead of an admin,
   after confirming no player is on that Z (`zlevel_has_players(z)`,
   `persistence_zlevel_reset.dm:127-137`, already exists as a hard-block
   check for exactly this class of destructive action).

**Consequence for the design**: corvettes are managed as a **pool of
Z-levels per template type**, not one-Z-per-ship-forever. Buying a corvette
either claims an already-reset, currently-unclaimed Z previously loaded for
that template, or -- if the pool is empty -- calls `load_new_z()` to
materialize a new one (which, once created, is never returned to the OS;
it only ever gets reset-and-repooled from here on). Storing a corvette runs
the reset-in-place flow and returns that Z to the pool for the *next*
purchase (by any faction, of that same template) to reuse. This directly
matches the user's own framing: "loading as new Z levels that then despawn
as Z levels" -- despawn == reset-and-repool, not delete, because delete does
not exist as an operation in this engine.

### 7.2 Persistence: already free, by inheriting the away-site trait

`persistence_z_excluded()` (`persistence.dm:52-65`) already returns `TRUE`
for `is_away_level(z)`. Tagging every corvette Z with `ZTRAIT_AWAY` (same
`traits` list mechanism the existing corvette away-site `.dm` files already
use, e.g. `tcaf_corvette.dm:8-13`) means **turf/object/worldstate contents on
a corvette Z are already excluded from the normal save/restore sweeps with
zero new code** -- exactly the user's "they never persist" requirement,
already true today for any Z carrying that trait. No `AREA_FLAG`, no
`persistence_area_excluded()`-style helper needed here, unlike the drydock
pad system -- this is a coarser, Z-wide exclusion the away-site system
already provides for free.

What *does* need a small, dedicated persistence record -- because it's
genuinely new information, not turf contents -- is the **ownership/lifecycle
ledger**: which faction owns which corvette instance, which template it is,
and whether it's currently deployed (and at which Z/overmap position) or
stored (pooled, awaiting reuse). New table, own migration when this phase is
built:
```sql
CREATE TABLE IF NOT EXISTS `ss13_faction_corvettes` (
    `corvette_id`  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `template_id`  VARCHAR(64) NOT NULL COMMENT 'which corvette type, e.g. matches a /datum/map_template id',
    `faction_uid`  VARCHAR(32) DEFAULT NULL COMMENT 'NULL when pooled/unowned',
    `status`       ENUM('pooled','deployed') NOT NULL DEFAULT 'pooled',
    `z`            INT DEFAULT NULL COMMENT 'current Z if this template Z has ever been loaded; NULL until first load_new_z()',
    `overmap_x`    INT DEFAULT NULL,
    `overmap_y`    INT DEFAULT NULL,
    `purchased_at` DATETIME DEFAULT NULL,
    `stored_at`    DATETIME DEFAULT NULL,
    PRIMARY KEY (`corvette_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```
Restored at boot the same way the drydock pad registry is (a `GLOB.faction_corvettes`
lookup populated in `shuttleStateRestore()` or an adjacent proc) -- but
critically, a `status = 'deployed'` row does **not** by itself recreate the
Z (Z's aren't freed, so if the row says deployed and the Z was never actually
torn down, it's still sitting there exactly as left; the row is bookkeeping
for the program UI and faction-ownership checks, not a spawn trigger).

### 7.3 Piloting: reuse the existing overmap ship framework, no new movement code

`/obj/effect/overmap/visitable/ship/landable` + `/datum/shuttle/autodock/overmap/*`
+ `/obj/structure/machinery/computer/shuttle_control` is the exact, proven
framework every player-flyable ship in this codebase already uses (Intrepid,
Canary, Quark, the TCAF Gunship sub-shuttle inside `tcaf_corvette.dm:75-110`).
A new corvette needs its own subtype of these three (stats, sprite, shuttle
area, docking consoles) -- the movement/fuel/docking mechanics themselves are
completely unmodified, off-the-shelf. This directly delivers "maneuver the
overmap" with no new code beyond defining the ship's own stat block, the same
way every existing player ship type does it.

Away-site corvettes like `tcaf_corvette` are normally *static* content (a
location generated at a random overmap spot for players to encounter, not
something a player pilots) -- their own mothership object doesn't move.
Faction corvettes are different: the mothership itself needs to be the
player-flyable object (an `/obj/effect/overmap/visitable/ship/landable`
subtype, own `datum/shuttle/autodock/overmap`), not merely a location that
happens to contain a landable sub-shuttle. The *interior* (multi-deck .dmm
layout, room variety) can still be modeled on/copied from an existing
away-site corvette's `.dmm` as a starting point -- only the outer overmap
object and its docking console need to be purpose-built for player piloting
rather than away-site-encounter framing.

### 7.4 Boarding: the telepad extension `overmap-traversal-research.md` already recommended

That research doc's conclusion (section 5) is to extend the telepad/faction-network
system for player travel rather than build overmap edge-crossing, specifically
because the hard part -- cross-Z lookup by shared network key, zero
distance/adjacency dependency -- is already built and proven for cargo
(`persistence_find_cargo_telepad()` + `persistence_telepad_deliver()`,
`persistence_cryo.dm:628-659`). Boarding a corvette from a station reuses
exactly that lookup shape, `forceMove()`-ing a mob instead of an item, keyed
on the corvette's own `faction_uid` (from the ledger in 7.2) matching a
station-side pad's `persistent_network` -- the same "any pad on my faction's
network" model `telepad_cargo` already uses, no new pairing/link-code concept
needed (the traversal doc's gap #1, "add a real pairing concept," turns out
unnecessary here specifically *because* corvettes already have a natural
1:many key to match on -- their owning faction -- unlike the doc's more
general player-travel case).

The doc's other identified gaps still apply and need addressing when this
phase is built:
- **Persistence-registration gap** (section 4.3): a new boarding-telepad type
  must call `SSpersistence.objectsRegisterTrack()` when faction-tagged, the
  same way cryopods already do and `telepad_cargo` currently does not, or a
  player-placed boarding pad silently won't survive a restart.
- **Mob-specific move safety** (section 5, point 4): `forceMove()`-ing a
  living mob needs the restrained/buckled/cooldown checks a plain item
  `forceMove` doesn't need -- no existing precedent to copy directly, this is
  genuinely new (small) logic.
- The corvette-side boarding pad only needs to exist while the corvette is
  `deployed` -- map-place it in the corvette's own `.dmm` (matching how
  `tcaf_corvette.dm` already places its own landmarks/consoles), no
  dynamic creation needed.

### 7.5 Faction Ship Program (buy/deploy/store/board, no admin verbs)

New `/datum/computer_file/program/faction_ships` -- same shape as the
drydock program (Part 4): `tgui_id = "FactionShips"`, new `FactionShips.tsx`.
Actions, each `ui_act`-validated server-side against the ledger (7.2) and
`can_configure_faction_shackle()`-style officer-rank gating, matching every
other faction-configuration action already established in this codebase:
- **Buy**: officer+ action. Charges the faction account (reuse the
  `ss13_faction_transactions` idiom from `faction_manage.dm`). If a pooled,
  unowned Z exists for the chosen template, claim it (`status = 'deployed'`,
  set `faction_uid`); otherwise `load_new_z()` a fresh one. Places/activates
  the corvette's overmap ship object at a starting position.
- **Store**: officer+ action, hard-blocked by `zlevel_has_players(z)` (already
  exists, 7.1 point 3) exactly like the admin reset tool is. Runs the
  reset-in-place flow, clears `faction_uid`, sets `status = 'pooled'`.
- **List/Status**: shows the faction's currently deployed corvette(s) (name,
  template, overmap position) and available-to-buy templates with prices --
  same Personal/Faction-tab-less version of the drydock market UI, scoped
  purely to faction ownership since corvettes (unlike drydock shuttles)
  aren't personally ownable in this design.
- **Boarding info**: surfaces which station-side telepad(s) are networked to
  the faction (for the 7.4 boarding flow) -- read-only, no action.

---

## Part 8: Implementation order (phases -- each ends compile-CLEAN)

1. **Fixes first**: shuttle_core.dm duplicate-proc deletion + beacon
   reactivation on restore (0.4a/0.4b). Small, independently testable.
2. **Migration V073** + `AREA_FLAG_DRYDOCK_PAD` + `/area/drydock_pad` +
   `persistence_area_excluded()` gates in the five Finalize sweeps (Part 2.1-2.2).
3. **Drydock blueprint** + pad registry + `ss13_drydock_pads` load in
   `shuttleStateRestore()` (Part 2.3-2.4).
4. **Stash/retrieve engine** (Part 3) -- testable via temporary admin verbs
   before the program exists.
5. **Drydock program TGUI** (Part 4) wiring the engine + market skeleton.
6. **Templates** (Part 5): 2-3 .dmm files + load-once-serialize + market Buy.
7. **Faction Chat** (Part 6) -- fully independent of 1-6, can be done any time.
8. **Faction Corvettes** (Part 7) -- fully independent of 1-7 as well. Natural
   internal order: 8a Z-pool ledger + `ss13_faction_corvettes` migration
   (7.2), 8b one corvette overmap-ship subtype + its .dmm, provable with a
   temporary admin verb before the program exists (mirrors phase 4's own
   "engine before UI" approach), 8c boarding telepad extension (7.4), 8d
   Faction Ship Program TGUI (7.5) wiring 8a-8c together.

Verification per phase: `scripts\debug-compile.ps1 -ReportOnly` -> RESULT:
CLEAN, then in-game: designate a 30x18 pad (reject 29x17), buy skiff, retrieve
onto pad, fly it to another beacon, land back, redecorate one tile, stash,
confirm pad turfs revert + DB row updated, restart server, confirm pad is
pristine (nothing persisted), retrieve, confirm the redecorated tile came
back. Faction chat: two members chat cross-map with PDA pings; a
civilian-carded player is refused; non-member holding the PDA gets no ping.
Faction corvettes: buy one (fresh `load_new_z()`), fly it via its shuttle
console, board it from a station telepad networked to the same faction, store
it (blocked while a player is aboard), buy again and confirm the SAME Z gets
reused rather than a new one being created, restart the server and confirm
the ledger (not the Z's contents) is what survives.

## Known constraints & decisions

- `max_hull_size` 200 (shuttle_core.dm:131) stays for free-built hulls;
  drydock retrieval instead validates against the PAD bounding box (<= 30x18
  by default, so max 540 tiles -- raise `max_hull_size` to 540 for
  drydock-scanned hulls only, via an argument, not globally).
- Pad turfs are canonical plating -- decorating a pad is unsupported by
  design; it is a landing grid, not a room (this is what makes "won't eat
  turfs" true).
- One beacon = one pad = at most one landed shuttle. Multi-pad stations just
  place multiple beacon+pad pairs.
- All DB access blocking-in-ui_act/subsystem only, `qdel(q)` always, ASCII
  only in .dm files (compiler chokes on Unicode -- long-standing project
  rule), tabs for indentation.
- Faction corvette Z-levels are never freed, only reset-and-repooled (Part
  7.1) -- there is no `decrementMaxZ()` in this engine at all, confirmed in
  `docs/overmap-traversal-research.md` section 1.1. Every corvette Z ever
  materialized stays allocated (and, once populated with real machinery, keeps
  costing tick time in SSmachinery/SSmobs/SSair) for the life of the server
  process regardless of ownership status -- a server that sees many distinct
  factions buy-then-store corvettes over a long uptime will accumulate that
  many permanently-ticking Z's in the pool, not reclaim them. This is an
  accepted cost of the design, not a bug to fix later; there is no engine-level
  path to avoid it.
