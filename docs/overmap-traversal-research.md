# Overmap Traversal Research: On-Foot Edge-Crossing vs. Linked Telepads

Research-only investigation. No code was changed as part of this document. All paths are
relative to the repo root (`D:\GIT Storage\Aurora-Persistence`). Line numbers are current as
of commit `a88dce2e913fc194f4880f28ab290b68660a8277` (2026-07-10) and will drift as the
codebase evolves -- re-grep the cited procs if this doc is picked up later.

## Question this answers

Can players cross the overmap (the ~35x35 star-chart Z-grid) on foot, either by walking off
the edge of their current Z-level's map, or by building linked teleporter pairs? Does either
approach force every overmap tile to become a permanently-simulated Z-level, and does any
"freeze/suppress an idle Z" mechanic already exist to avoid that?

**Bottom line (see [Recommendation](#5-recommendation) for the full reasoning): extend the
existing telepad/faction-network system rather than building overmap edge-crossing.** The
telepad route reuses proven, already-in-production cross-Z lookup code and its cost scales
with "how many pads players build," not "how many overmap tiles exist." Edge-crossing
traversal has almost none of its needed pieces built, and its most natural implementation
runs straight into the exact "every tile becomes a live Z" cost problem the user was
worried about, because no Z-freeze mechanic exists anywhere in this codebase today.

---

## 1. BYOND Z-level resource cost model

### 1.1 The core engine fact: `world.maxz` is a dense grid, and it only grows

`world.incrementMaxZ()` is the entire mechanism for creating Z-level space:

```
code/game/world.dm:425-426
/world/proc/incrementMaxZ()
    maxz++
```

BYOND allocates one turf instance for **every** `(x, y, z)` coordinate that exists -- there
is no sparse/lazy turf model in DreamMaker. The instant `maxz` increments, the engine
allocates `world.maxx * world.maxy` new turf objects for the new level, whether or not any
content is ever placed on it. This is engine behavior, not something this codebase's DM code
controls or could change without a from-scratch renderer/engine swap.

**Map dimensions in this codebase:** counting the coordinate blocks in
`maps/sccv_horizon/sccv_horizon.dmm` (the currently-used SCCV Horizon map) confirms
`world.maxx = world.maxy = 255`: the file contains exactly 255 `(N,1,1) = {"` column blocks
for z=1 (`grep -c "^([0-9]*,1,1) = {" maps/sccv_horizon/sccv_horizon.dmm` → `255`), each
containing 255 one-tile-key rows. This is independently corroborated by
`maps/sccv_horizon/code/sccv_horizon.dm:53`, which sets `planet_size = list(255,255)` for
that map's exoplanets. So **one Z-level = roughly 65,025 permanent turf instances**, the
moment it's created.

**No Z-level is ever freed.** A codebase-wide grep for `decrementMaxZ`, `maxz--`, and
`maxz -=` returns nothing. There is no proc anywhere that shrinks `world.maxz`. Every Z ever
created lives for the rest of the server process's life. The codebase's only pattern for "we
don't need this Z's content anymore" is to **reset or repurpose it in place**, never to free
the underlying turf memory:
- `reset_zlevel()` admin verb wipes a Z's persisted content and reverts turfs to baseturf,
  live, without a restart (`code/controllers/subsystems/persistence/persistence_zlevel_reset.dm:139-289`)
  -- but the Z-level itself, and its ~65k turf instances, remain allocated.
- `GLOB.cached_space` caches spent "Deep Space" filler sector objects for reuse rather than
  ever deleting their underlying Z (`code/modules/overmap/spacetravel.dm:1-22, 110-116`).

### 1.2 What overmap_size actually is, confirming the user's "35x35" figure

`overmap_size = 35` is set identically on all four currently-active maps
(`maps/sccv_horizon/code/sccv_horizon.dm:51`, `maps/frontier/code/frontier.dm:51`,
`maps/runtime/code/runtime.dm:37`, `maps/voidwork/code/voidwork.dm:36`), confirming the
user's premise: the overmap grid is ~35x35 = up to 1,225 addressable tiles.

### 1.3 What has a per-tick cost that scales with Z-count, and what doesn't

The hot-tick subsystems in this codebase are **not partitioned by Z at all** -- they iterate
flat, world-wide lists, and only do work proportional to *actual content*, not to the number
of Z-levels that exist:

- **SSmobs** (`code/controllers/subsystems/mob.dm:72-115`): `fire()` iterates
  `GLOB.mob_list`, a flat world-wide list, calling `M.Life()` on every living mob every 2
  seconds (`wait = 2 SECONDS`, line 6). Zero Z-awareness. An empty Z with no mobs on it costs
  nothing here, by absence rather than by any active skip.
- **SSmachinery** (`code/controllers/subsystems/machinery.dm:29-89`): ticks flat
  `machinery`/`pipenets`/`powernets` lists (lines 40-44). Zero Z-awareness.
- **SSair / ZAS** (`code/controllers/subsystems/air.dm:169-286`): per-tick `fire()` only
  touches `tiles_to_update`, `zones_to_update`, `active_edges`, etc. -- lists of things that
  were explicitly marked dirty by gas/pressure changes. An idle Z with no active gas
  movement costs ~nothing per tick here either.

**Conclusion: a genuinely empty Z-level (no map-placed machines/mobs, just space turfs)
costs almost nothing per tick in this codebase.** The real costs are one-shot/boot-time and
scale with total Z-area:

- **SSair's full-world sweep**: `Initialize()`/`reboot()` iterate `for(var/turf/T in world)`
  across every turf on every Z to rebuild ZAS zone/edge geometry
  (`code/controllers/subsystems/air.dm:130-167`, `95-124`). This is O(total turfs across all
  Z's) and runs at boot and on any future full ZAS rebuild (`reboot()`, same file). More
  Z's = a slower boot/rebuild, permanently.
- **SSspatial_grid**: `propogate_spatial_grid_to_new_z()` is registered to fire on
  `COMSIG_GLOB_NEW_Z` (`code/controllers/subsystems/spatial_gridmap.dm:131, 166`), and its
  init loop explicitly walks `for(var/z_level in 1 to world.maxz)`
  (`spatial_gridmap.dm:115-117`) -- one grid-population pass per Z, proportional to that Z's
  area.
- **SSzcopy**: `calculate_zstack_limits()` re-scans `1 to world.maxz` every time a Z is added
  (`code/controllers/subsystems/zcopy.dm:106-120`), called from `add_new_zlevel()` itself
  (see 1.4). Cheap per-Z (just integer bookkeeping) but still O(maxz) on every single Z-add.
- **Icon smoothing**: `load_new_z()` explicitly disables/re-enables `SSicon_smooth` around a
  Z-load (`code/modules/mapping/map_template.dm:66, 82, 102`), which is itself evidence that
  materializing a new Z is treated as a large enough chunk of work to need deliberate MC
  (Master Controller) tick-budget management, not something to do casually mid-tick.

**The important caveat for the recommendation section:** this "idle Z is nearly free" result
only holds for a Z that is *genuinely empty*. The moment a Z gets real map content -- even a
small outpost with a few APCs, lights, and machines -- those objects self-register with
SSmachinery/SSmobs/SSair's flat, non-Z-partitioned lists and cost tick time **forever,
regardless of whether any player is anywhere near that Z.** This is exactly the tension that
motivates wanting a freeze mechanic (section 2) and is central to the recommendation.

### 1.4 Existing "create a Z on demand" precedent

This precedent is real and already load-bearing in production:

```
code/modules/mapping/space_management/zlevel_manager.dm:1-17
/datum/controller/subsystem/mapping/proc/add_new_zlevel(name, traits = list(), z_type = /datum/space_level, contain_turfs = TRUE)
    UNTIL(!adding_new_zlevel)
    adding_new_zlevel = TRUE
    var/new_z = z_list.len + 1
    if (world.maxz < new_z)
        world.incrementMaxZ()
        CHECK_TICK
    var/datum/space_level/S = new z_type(new_z, name, traits)
    manage_z_level(S, filled_with_space = TRUE, contain_turfs = contain_turfs)
    generate_linkages_for_z_level(new_z)
    adding_new_zlevel = FALSE
    SEND_GLOBAL_SIGNAL(COMSIG_GLOB_NEW_Z, S)
    SSzcopy.calculate_zstack_limits()
    return S
```

`manage_z_level()` itself (`code/controllers/subsystems/mapping.dm:107-116`) is cheap --
just list bookkeeping (`z_list += new_z`, a couple of lookup-table entries) -- the expensive
work happens in whatever else is listening to `COMSIG_GLOB_NEW_Z` (section 1.3) plus the
implicit engine-level turf allocation from `incrementMaxZ()`.

**Away sites already use this exact mechanism, on a budget, precisely to avoid materializing
every possible site every round:**

```
maps/_common/mapsystem/map.dm:292-366  (/datum/map/proc/build_away_sites)
maps/_common/mapsystem/map.dm:379-472  (/datum/map/proc/build_pinned_away_sites)
code/modules/mapping/map_template.dm:54-105  (/datum/map_template/proc/load_new_z)
```

`build_away_sites()` runs an explicit budget/weighting pass (`points`, `shippoints`,
`away_site_budget`, `map.dm:334-358`) and only calls `template.load_new_z()` -- which itself
calls `SSmapping.add_new_zlevel()` once per template Z (`map_template.dm:70`) -- for the
subset of templates the budget allows. **This is direct precedent for "don't eagerly
materialize every possible location as a live Z; only create the ones actually selected/in
use."** `build_pinned_away_sites()` is the deterministic variant (admin-pinned sites always
load, at a stable Z number so their persistence rows survive reboots,
`map.dm:379-472`).

The base map itself ships with only 4 Z-levels baked in (station z1-3, CentCom z4,
`maps/sccv_horizon/code/sccv_horizon.dm:6-15`); everything else (away sites, exoplanets,
mining, pinned sites) is added at runtime, one Z at a time, only when something actually
needs it.

---

## 2. Does a "suppress/freeze/unload a Z-level" mechanic already exist?

**No.** There is exactly one per-Z exclusion mechanism in the codebase, and it is a
**database save/load gate**, not a simulation gate:

```
code/controllers/subsystems/persistence/persistence.dm:52-65
/proc/persistence_z_excluded(z)
    if(z in GLOB.persistence_pinned_site_z)
        return FALSE
    if(persistence_z_manual_blocked(z))
        return TRUE
    if(z in GLOB.persistence_zlevel_skip)
        return TRUE
    if(is_away_level(z))
        return TRUE
    if(is_mining_level(z))
        return TRUE
    if(z in GLOB.persistence_template_loaded_z)
        return TRUE
    return FALSE
```

This proc (and its companion `persistence_z_manual_blocked()`, same file lines 40-43) only
controls whether turf/object/worldstate DB rows are written/read for that Z. Confirmed by the
admin diagnostic verb's own wording:

```
code/controllers/subsystems/persistence/persistence_zlevel_reset.dm:116
msg += "Persistence: [persisted ? "enabled (saves/loads)" : "disabled (regenerates each restart)"]\n"
```

A Z excluded by `persistence_z_excluded()` still **fully exists, still fully ticks in every
subsystem, and still consumes its full turf-allocation memory** -- only its DB round-trip is
skipped. This is not the mechanic the user is looking for.

**No subsystem has a per-Z pause/resume hook.** Directly confirmed by reading the two
subsystems most relevant to "is this Z alive":
- `SSmobs.fire()` (`code/controllers/subsystems/mob.dm:72-115`) iterates the flat
  `GLOB.mob_list` with no Z filter of any kind.
- `SSmachinery` (`code/controllers/subsystems/machinery.dm:29-89`) iterates flat
  `machinery`/`pipenets`/`powernets` lists with no Z filter of any kind.

Neither has anywhere to hook a "skip this Z" check into, because neither is structured
around Z-membership at all.

**Closest existing analog (not a real freeze mechanic):** `SSatlas.current_map.sealed_levels`
(`maps/_common/mapsystem/map.dm:22`) is a per-Z opt-out, but it only gates one specific
behavior -- the map-edge-crossing proc discussed in section 3
(`code/game/atoms_movable.dm:456-464`) -- not general simulation. It's populated once, at
sector-registration time, based on a static `in_space` property of the overmap sector
(`code/modules/overmap/sectors.dm:202-203`), not dynamically toggled based on player
presence or any "is anyone here" check.

### 2.1 Scoping estimate for a real freeze/suspend mechanic (since none exists)

Because nothing exists to extend, here is an honest scoping-level estimate of what a "Z stays
dormant until a player needs it" feature would require touching:

| Subsystem | What would need to change | Difficulty / risk |
|---|---|---|
| **SSmobs** | Gate `M.Life()` calls by a per-Z "frozen" flag, or maintain a separate frozen-mob list excluded from `GLOB.mob_list` iteration in `fire()` (`mob.dm:72-115`) | Moderate. Mob logic elsewhere (hunger, bleeding, status effect decay) generally assumes `Life()` runs every `seconds_per_tick` -- a frozen mob that "wakes up" after being frozen for real-world hours needs its elapsed-time math audited so it doesn't instantly bleed out / starve / decay on wake. |
| **SSmachinery** | Same shape of change to `machinery`/`pipenets`/`powernets` iteration (`machinery.dm:29-89`) | Higher risk than SSmobs: powernets/pipenets can span Z-level boundaries via multiz-connected APCs/pipes (see `generate_linkages_for_z_level()`/`multiz_levels`, `code/controllers/subsystems/mapping.dm:90-103`). A frozen Z sitting next to an active one is a real correctness hazard -- e.g. a frozen Z's APC drawing from an active Z's SMES. |
| **SSair (ZAS)** | Hardest of the three. Zones/edges are mostly self-contained per Z today, but `Initialize()`/`reboot()` are whole-world sweeps with no facility to re-run geometry processing for a single Z in isolation (`air.dm:130-167`). A "wake this Z back up" step has nothing to call -- it would need new, narrower geometry-rebuild code that doesn't exist. | High. |
| **Persistence** | Already has the necessary plumbing to reuse: Z-scoped purge/remap (`purgeZRows()`/`remapZRows()`, `persistence_zlevel_reset.dm:27-79`) and the save/load exclusion gate (`persistence_z_excluded()`) could back a "flush to DB before freezing, reload on wake" flow. | Low -- this part is close to ready-made. |
| **Z creation/teardown** | No `decrementMaxZ()` exists (section 1.1); "freezing" a Z can only mean pausing subsystem work on it, not reclaiming its ~65k turf instances' memory. A true memory-reclaiming unload is not just unbuilt, it runs against BYOND's dense-grid model and may not be achievable at all without deleting/re-creating turfs in place (expensive in a different way, and would break any stable Z-numbering assumptions used elsewhere, e.g. `persistence_pinned_site_z`, `GLOB.map_sectors`). | Structural engine limitation, not just missing code. |

**Net assessment:** a robust freeze/resume mechanic is a genuine multi-subsystem feature (at
minimum touching SSmobs, SSmachinery, SSair, plus new Z-lifecycle plumbing), not a small
patch, and the actual memory-allocation cost of a Z-level can never be un-paid once
incurred (no decrement path exists in the engine's model as used here). Given section 1.3's
finding that a genuinely *empty* Z already costs almost nothing per tick, the case for
building this is really about **Z's that already have live content on them** (an outpost,
a station) sitting idle with no players nearby -- and that is a materially harder freeze
problem (state consistency, multiz power/pipe dependencies, ZAS geometry) than freezing
truly empty overmap filler tiles.

---

## 3. Edge-crossing auto-travel feasibility

### 3.1 The plumbing already exists -- for ships, not stations

There already is a "leave your Z-level's mapped bounds -> get moved to a different Z-level"
mechanic in production today, and it is not a small thing to have missed:

```
code/game/atoms_movable.dm:456-495  (/atom/movable/proc/touch_map_edge)
code/game/turfs/space/space.dm:116-130  (/turf/space/Entered)
code/__DEFINES/misc.dm:3  (#define TRANSITIONEDGE 7)
```

`/turf/space/Entered()` checks whether the entering movable's `x`/`y` is within
`TRANSITIONEDGE` (7 tiles) of `world.maxx`/`world.maxy`/`1`, and if so calls
`A.touch_map_edge()` (`space.dm:129-130`). For overmap-enabled maps (all four active maps,
confirmed in section 1.2 -- `use_overmap = TRUE`), `touch_map_edge()` routes to:

```
code/modules/overmap/spacetravel.dm:57-116
/proc/overmap_spacetravel(var/turf/space/T, var/atom/movable/A)
```

**Players are not exempt.** `/mob/living/touch_map_edge()`
(`code/modules/mob/living/living.dm:822-840`) only adds a nuke-disk-carrier check on top,
then falls through to the base proc (`..()`, line 840) -- meaning a lone unanchored crewman
who drifts near a ship's map edge in zero-g **already gets swept through
`overmap_spacetravel()` today**, exactly like a ship hull would. This proves the low-level
plumbing (boundary detection, `forceMove()` to a turf on a different Z, carrying a grabbed/
pulled companion along, `spacetravel.dm:104-108`) is real, tested, and already handles
individual player mobs, not just vehicles.

### 3.2 But the destination logic is same-tile, not directional-adjacent

This is the critical nuance: `overmap_spacetravel()`'s destination selection is **not**
"go to whatever's north/south/east/west of me on the overmap grid." It is "find another
overmap object stacked on the *same* `(x,y)` overmap tile as my own sector, and land near its
edge; if nothing else occupies that tile, fall back to a shared 'Deep Space' filler Z for
that same tile":

```
code/modules/overmap/spacetravel.dm:61-100 (excerpt)
    var/obj/effect/overmap/visitable/M = GLOB.map_sectors["[T.z]"]
    ...
    var/turf/map = locate(M.x,M.y,SSatlas.current_map.overmap_z)
    var/obj/effect/overmap/visitable/TM
    for(var/obj/effect/overmap/visitable/O in map)
        if(O != M && O.in_space && prob(50))
            TM = O
            break
    if(!TM)
        TM = get_deepspace(M.x,M.y)
    nz = pick(TM.map_z)
```

This exists to depict "drifting into the void between two ships/objects docked at the same
overmap grid cell" -- not travel between grid cells. **Directional overmap adjacency (walk
off the north edge -> whatever tile is at `(mx, my+1)`) has no existing implementation at
all.** Only the "leave bounds -> get force-moved to a turf on some other Z" plumbing is
reusable; the actual destination-resolution logic would need to be built from scratch.

### 3.3 Stations are deliberately excluded from this today

`touch_map_edge()` early-returns for any Z in `SSatlas.current_map.sealed_levels`:

```
code/game/atoms_movable.dm:456-458
/atom/movable/proc/touch_map_edge()
    if(z in SSatlas.current_map.sealed_levels)
        return
```

`sealed_levels` is populated for every overmap sector whose `in_space` var is `FALSE`
(`code/modules/overmap/sectors.dm:202-203`), and `in_space` defaults `TRUE` only for ships
(`code/modules/overmap/sectors.dm:45`) -- stations, away sites, and planets are all
`in_space = FALSE` by design and therefore always sealed. **This exact feature already exists
for ships and is deliberately switched off for stations/away-sites** -- which is precisely
the traversal case the user is asking about (walking off a *station's* map edge). That
exclusion is very likely intentional and load-bearing: without it, any crew member drifting
near a hull breach on any station's outer edge would get randomly swept off to whatever
happens to share that station's overmap tile, which would be a serious, hard-to-predict
gameplay/griefing surface if simply flipped on.

### 3.4 Overmap grid adjacency vs. station map orientation: fully decoupled

Confirmed by how a Z-level is tied to the overmap at all: `GLOB.map_sectors`
(`code/modules/overmap/_defines.dm:4-7`) is a lookup from a stringified Z-number to **one**
`/obj/effect/overmap/visitable` object, which carries its own independent `(start_x,
start_y)` position on the 35x35 `overmap_size` grid
(`maps/_common/mapsystem/map.dm:114`, `maps/sccv_horizon/code/sccv_horizon.dm:51`). There is
no code anywhere relating a specific compass edge of a station's own internal
`(world.maxx x world.maxy = 255x255)` map to a compass direction on the 35x35 overmap grid --
the two coordinate systems are entirely separate namespaces, connected only by the Z-number
lookup, never by direction. Building "my station's north wall exit leads to the overmap tile
north of me" would be **wholly greenfield** design and implementation, not an extension of
anything that exists.

**The one directional-adjacency concept that does exist is vertical, not horizontal:**
`ZTRAIT_UP`/`ZTRAIT_DOWN` and `multiz_levels`
(`code/controllers/subsystems/mapping.dm:90-103`, `code/modules/mapping/space_management/traits.dm`)
represent deck-above/deck-below relationships within a single ship or station's own Z-stack
(used for e.g. ladders between decks) -- a different axis entirely from overmap-grid
adjacency.

### 3.5 Section 3 conclusion

The low-level mechanics (detect a boundary crossing, `forceMove()` a mob to a turf on a
different Z, bring along anyone/anything being pulled) are proven, in production, and already
handle individual player mobs -- reusable groundwork. Everything else is missing entirely:
- No concept of overmap-grid directional adjacency exists at all.
- No facility to resolve "what's at grid position `(mx, my+1)`" into a landable destination
  turf exists.
- The feature is deliberately disabled for exactly the Z-type (stations/away-sites) this
  traversal idea targets, and enabling it raises real safety/griefing questions that don't
  currently need answering.
- Any directional "walk to whatever's next" design collides directly with section 1's lazy
  materialization principle: "north" would need to already have a materialized Z to land on,
  or would need to trigger `add_new_zlevel()` synchronously mid-movement -- something
  `add_new_zlevel()`/`load_new_z()` have never been invoked for before (today they only ever
  run at round start for away sites, never on-demand from a player interaction).

---

## 4. Player-buildable linked telepad precedent

### 4.1 What `telepad_cargo`/`telepad_security` actually are

```
code/modules/telesci/telepad.dm:56-184
```

These are **faction-network cargo delivery/return points**, not player-travel devices.
Key vars: `persistent_network` (a string -- a faction UID or `"public"`, line 67-68) and
`persistent_spawn` (whether this pad accepts deliveries for that network, lines 69-70).
`telepad_security` (line 144) is a subtype used as the return point for first-responder
teleports, with `accepts_cargo = FALSE` (line 149) so cargo deliveries never land on it.

**The lookup model is "any matching pad on the network," not a specific linked pair:**

```
code/controllers/subsystems/persistence/persistence_cryo.dm:628-647
/proc/persistence_find_cargo_telepad(network = null)
    network = normalize_faction_uid(network)
    if(network)
        for(var/obj/structure/machinery/telepad_cargo/pad in world)
            if(!pad.accepts_cargo) continue
            if(!pad.z) continue
            if(!pad.persistent_spawn)  continue
            if(normalize_faction_uid(pad.persistent_network) == network)
                return get_turf(pad)
    for(var/obj/structure/machinery/telepad_cargo/pad in world)
        if(!pad.accepts_cargo) continue
        if(!pad.z) continue
        if(lowertext(pad.persistent_network) == "public" && pad.persistent_spawn)
            return get_turf(pad)
    return null
```

This is a flat, **world-wide** (every Z) search matching `persistent_network` by string
equality, faction match preferred, then `"public"` fallback. Delivery itself
(`persistence_telepad_deliver()`, `persistence_cryo.dm:652-659`) is a plain `forceMove()` to
that pad's turf with **no distance or Z-adjacency check of any kind**. This is important:
**cross-Z, instant delivery to a "linked" destination already works today, for cargo, for
free** -- it was implemented as "teleport to wherever a same-network pad happens to be,"
which is structurally very close to what the user's "linked pair, regardless of Z" idea
needs. The only real gaps versus what the user wants are (a) it moves items, not player mobs,
and (b) it's a many-to-one network-string match, not a strict one-to-one pair.

### 4.2 Who can build/configure one today

**Not player-buildable via the normal machine construction path.** A codebase-wide grep for
`circuitboard/telepad_cargo` and any frame-based construction recipe returns nothing --
there is no `/obj/item/circuitboard/telepad_cargo`. The only ways one comes into existence
are:
1. Map placement (mapper-authored, part of a station/ship template), or
2. A player using an `/obj/item/telepad_beacon` item's `attack_self()`, which drops one at
   the player's current location:
   ```
   code/modules/telesci/telepad.dm:187-202
   /obj/item/telepad_beacon/attack_self(mob/user)
       if(user)
           new /obj/structure/machinery/telepad_cargo(user.loc)
           ...
   ```
   This item is research/tech-gated (`origin_tech = list(TECH_BLUESPACE = 3)`, line 194), so
   it is player-*placeable* (any player who has obtained that item can drop a pad anywhere),
   but not player-*constructed* from raw materials the way an airlock or standard machine is.

**Configuring/"linking" a pad is not a pairing action -- it's setting one string field**, and
it's gated to admins or command-tier faction officers, not open to any player:
- The pad's own verbs (`configure_supply_network()`/`configure_security_network()`,
  `telepad.dm:83-109, 158-184`) are `check_rights(R_ADMIN)`-gated.
- The player-facing path is the faction tagger tool
  (`code/controllers/subsystems/persistence/persistence_faction_tagger.dm:36-48`):
  `faction_tagger_set()` on a `telepad_cargo` just does
  `persistent_network = new_uid; persistent_spawn = new_uid ? TRUE : FALSE; faction_shackled = new_uid ? TRUE : FALSE`
  -- one string assignment, no target-pad-selection step. Using the tagger requires
  command-tier faction authorization elsewhere in the codebase (the same
  `can_configure_faction_shackle()` gate used by `faction_beacon.dm`), not something any
  rank-and-file player can do freely. There is no "select pad A, select pad B, now they're
  linked" UI anywhere in the codebase -- linking is transitive membership in a named group,
  not pairing.

### 4.3 Persistence behavior -- and a real gap

`telepad_cargo` saves via the generic declarative worldstate system:

```
code/controllers/subsystems/persistence/persistence_worldstate.dm:314-315
/obj/structure/machinery/telepad_cargo
    worldstate_vars = list("persistent_network", "persistent_spawn", "faction_shackled")
```

which is keyed by `(map_path, type, x, y, z)` (`persistence_worldstate.dm:280-292`) -- i.e.
restore works by relocating the same structure type back to the **same fixed coordinates**
it was saved at. This is proven for map-placed pads. It is **not** proven for a pad a player
dropped at an arbitrary field location via the telepad beacon item: unlike the cryopod
equivalent, which explicitly self-registers for dynamic-object persistence tracking when
faction-tagged --

```
code/controllers/subsystems/persistence/persistence_faction_tagger.dm:58-66  (cryopod)
    if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
        SSpersistence.objectsRegisterTrack(src)
```

-- `telepad_cargo`'s `faction_tagger_set()` (same file, lines 44-48) has **no equivalent
call**. This strongly suggests a player-dropped `telepad_cargo` is not currently guaranteed
to survive a restart at all (only map-placed ones reliably round-trip through the
`(x,y,z)`-keyed worldstate table). Anyone extending this system for player-built travel pads
needs to close this gap first, or "survives a server restart" (one of the two hard
requirements in the ask) will silently fail for exactly the player-placed case that matters.

### 4.4 The actual player-operated point-to-point teleporter (a different system, and not a fit)

There is a separate, older system that already does aim-and-fire player/object teleportation:
`/obj/structure/machinery/telepad` + `/obj/structure/machinery/computer/telescience`
(`code/modules/telesci/telesci_computer.dm`). This is:
- Wired one-console-to-one-telepad via a multitool buffer copy (`telesci_computer.dm:173-179`),
- Aimed via rotation/angle/power projectile-trajectory math
  (`telesci_computer.dm:266-360`), gated by consumable bluespace crystals,
- Limited to Z-levels the console can already "see" -- its own ship's Z-stack
  (`our_zlevels`) or overmap contacts already scanned via ship sensors
  (`overmap_contacts_zlevels`, `telesci_computer.dm:75-87, 429-514`),
- Produces **temporary, decaying** `/obj/effect/portal` pairs with a lifespan of
  `25 * crystal_count` seconds (`telesci_computer.dm:346-358`), not a durable link.

This is closer to an artillery weapon than to fixed infrastructure -- not restart-durable,
not a simple "pick two pads and link them" UX, and range-limited to what a ship's sensors
have already scanned. **Not a usable base for the "player builds a permanent pair" ask as-is.**

---

## 5. Recommendation

**Extend the existing telepad/faction-network system. Do not build overmap edge-crossing
traversal.**

### Why edge-crossing loses

1. **Almost nothing needed for it exists.** Directional overmap-grid adjacency (section 3.4)
   is not implemented anywhere; `overmap_spacetravel()`'s destination logic is same-tile,
   not directionally-adjacent (section 3.2), so even the one relevant existing mechanic would
   need its core destination-resolution logic replaced, not extended.
2. **It's deliberately turned off for stations today** (section 3.3), almost certainly for
   good reason -- flipping that off-switch reopens a griefing/safety question (crew
   accidentally swept off a hull breach to a random neighboring Z) that the current design
   sidesteps entirely by scoping the mechanic to ships only.
3. **It directly recreates the cost problem the user was worried about.** Walking traversal
   implies every overmap tile a player *could* walk to needs to resolve to a landable Z. Since
   no freeze/suspend mechanic exists (section 2) and building one is a genuine multi-subsystem
   effort (SSmobs + SSmachinery + SSair, section 2.1) with no memory-reclamation path even in
   the best case (no `decrementMaxZ()`, section 1.1), the natural implementation path for
   "walk to any overmap tile" is exactly "every tile becomes a permanently-ticking Z the
   first time anyone visits it, forever" -- the expensive outcome both the user and their
   friend predicted, with nothing in the current codebase to prevent it.

### Why linked telepads win

1. **The hard part -- cross-Z lookup with zero distance/adjacency dependency -- is already
   built, proven, and running in production**, just for cargo instead of players
   (`persistence_find_cargo_telepad()` + `persistence_telepad_deliver()`,
   `persistence_cryo.dm:628-659`). A player-usable version is a comparatively small,
   additive change: a verb/interact that does the same flat world-search-by-shared-key, then
   `forceMove()`s a mob instead of items (with mob-specific checks a plain `forceMove` doesn't
   need for crates -- e.g. restrained/grabbed state, cooldown to prevent spam).
2. **Its cost scales with "how many pads players actually build," not "how many overmap
   tiles exist."** Nothing about this approach ever calls `add_new_zlevel()` beyond what a
   player's own base-building already causes -- it never touches SSair, SSmachinery, or
   SSmobs's per-tick cost model at all (section 1.3), because it's a point lookup among
   existing structures, not a traversal mechanic over the map grid.
3. **It sidesteps the entire "no directional overmap adjacency exists" gap from section 3**
   by design -- a telepad link is "beam me to my paired pad, wherever it is," not "beam me to
   whatever's geographically north," so section 3's missing greenfield work is simply not
   needed for this approach.

### What concretely needs to change to get there

1. **Add a real pairing/link-code concept.** Today's `persistent_network` is a many-to-one
   faction string; the user's ask needs a genuine 1:1 (or small-group) pairing identifier
   independent of faction membership -- e.g. a player-chosen link code, stored per-pad,
   matched during the travel lookup instead of/alongside `persistent_network`.
2. **Make it player-buildable, not just player-*placeable*.** Add a real
   frame + circuit-board construction recipe (there currently is none -- section 4.2) if the
   goal is "any player can build one," rather than relying on the tech-gated,
   drop-only `telepad_beacon` item.
3. **Close the persistence-registration gap** (section 4.3) -- give `telepad_cargo`'s
   `faction_tagger_set()` (or its new pairing-equivalent) the same
   `SSpersistence.objectsRegisterTrack()` call the cryopod path already has
   (`persistence_faction_tagger.dm:64-65`), or a player-built pad silently won't survive a
   restart, defeating one of the two hard requirements in the original ask.
4. **Build the actual player-facing travel action.** Mirror
   `persistence_telepad_deliver()`'s `forceMove()`-based approach for a living mob, adding
   whatever cooldown/interrupt/can't-teleport-while-restrained checks make sense
   (there is no existing player-teleport-via-verb precedent to copy directly here --
   the closest analog, telescience, uses temporary portals instead of a direct verb-triggered
   move, section 4.4).
5. **Decide the linking UX** -- since nothing in the codebase currently does "select A, select
   B, now they're linked" (section 4.2), this piece is genuinely new UI/interaction work,
   though small in scope compared to anything in section 3.

None of this requires touching `SSmapping`, `SSair`, `SSmachinery`, or `SSmobs`, and none of
it risks materializing overmap tiles that wouldn't otherwise need to exist -- which is the
central cost risk the user and their friend were right to be worried about for the
edge-crossing alternative.
