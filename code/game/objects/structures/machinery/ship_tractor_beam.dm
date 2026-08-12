/*
 * Ship Tractor Beam
 * A cargo-purchasable machine that, once wrenched to a ship's hull and
 * powered, can grab an enemy ship on the overmap and hold it in place --
 * see toggle_tractor() for the full lock-on requirements (shields down,
 * locked via the targeting console, adjacent, not your own ship) and
 * ship.dm's can_burn()/_drag_tractored_target() for how a held ship's
 * engines get disabled and it gets towed alongside the tractoring ship
 * instead of drifting out of range.
 *
 * Modeled directly on ship_shield_generator.dm/ship_cloaking_device.dm --
 * same hook-up-to-ship pattern, same phoron-sheet hopper fuel model.
 * Locking on is driven from the SAME targeting console used for weapons and
 * the shield readout (_targeting_console.dm), not a separate console --
 * this machine only holds the mechanical state, same division of labor the
 * shield generator and cloak already use with that console.
 */

/// Compile-time color on the segment type itself, applied to every segment
/// Draw() creates -- unlike mutating .color after the fact, this survives
/// Draw()'s Reset()+rebuild cycle, which refires on every drag-along
/// movement tick while the lock holds. Same subtyping pattern
/// /obj/effect/ebeam/warp (heavy_vehicle/equipment/utility.dm) already
/// establishes for a beam_type override. Used with icon_state = "explore_beam"
/// (see _acquire_lock() below) -- a neutral-gray 7-frame wavy S-curve
/// animation meant to be recolored, rather than "b_beam"'s own already
/// near-saturated blue default, which leaves no headroom to tint deliberately.
/obj/effect/ebeam/tractor
	color = "#3fa9f5" // matches the projector's own accent color

/// How far (in overmap tiles) a target can be when the lock is first
/// established. Enforced continuously afterward too, but only ever as a
/// safety net -- _drag_tractored_target() (ship.dm) keeps the target at
/// exactly this distance by towing it along, so it shouldn't otherwise
/// drift out of range on its own.
#define TRACTOR_BEAM_MAX_RANGE 1

/// How often the held ship's own console can attempt to break free -- see
/// the "attempt_break_free" case in _targeting_console.dm.
#define TRACTOR_BREAK_FREE_COOLDOWN 150 SECONDS

/// Percent chance a break-free attempt actually severs the lock. First-pass
/// tuning, same spirit as SHIELD_METEOR_DAMAGE_PER_ROCK
/// (ship_shield_generator.dm) -- rebalance here without touching anything
/// else.
#define TRACTOR_BREAK_FREE_CHANCE 35

/obj/structure/machinery/ship_tractor_beam
	name = "tractor beam projector"
	desc = "A heavy graviton emitter that locks onto a nearby ship's mass and holds it in place, burning phoron to maintain the field."
	icon = 'icons/obj/power.dmi'
	icon_state = "rtg"
	color = "#3fa9f5"
	anchored = FALSE // spawns loose on purchase -- must be wrenched down before it can activate
	density = TRUE
	maxhealth = OBJECT_HEALTH_HIGH
	idle_power_usage = 0
	active_power_usage = 0

	var/active = FALSE
	/// Fuel efficiency -- how long 1 sheet lasts at power_output 1. Holding a
	/// ship in place is meant to be a real phoron cost, not free -- 1 sheet
	/// every 30 seconds while active, up to 50 sheets in the hopper (~25
	/// minutes of continuous lock on a full tank).
	var/time_per_sheet = 30
	var/max_sheets = 50
	var/sheets = 0
	var/sheet_left = 0
	var/power_output = 1
	var/sheet_path = /obj/item/stack/material/phoron
	var/sheet_name = "phoron crystals"

	/// Who this beam is currently holding, null if inactive.
	var/obj/effect/overmap/visitable/ship/locked_target
	/// The relative tile offset (target's position minus this ship's, at the
	/// moment the lock was established) -- held fixed for the duration of
	/// the lock. ship.dm's _drag_tractored_target() repositions the target
	/// to maintain exactly this offset every time the tractoring ship itself
	/// moves, instead of the target ever flying itself.
	var/lock_offset_x = 0
	var/lock_offset_y = 0
	/// The persistent beam visual connecting the two ships (Beam(),
	/// datums/beam.dm) -- null when inactive. time = -1 makes it persist
	/// until manually End()ed, same convention bluespace_drive.dm uses for
	/// its own persistent tow beam.
	var/datum/beam/lock_beam
	/// Self-throttle for _update_beam_loop(), same shape as
	/// ship_shield_generator.dm's own next_hum_check.
	var/next_loop_check = 0
	/// Mobs currently hearing the ambient loop -- reconciled every sweep,
	/// same shape as ship_shield_generator.dm's own hum_listeners.
	var/list/loop_listeners = list()

/obj/structure/machinery/ship_tractor_beam/Initialize()
	. = ..()
	return INITIALIZE_HINT_LATELOAD

// Same reasoning as ship_cloaking_device.dm's own LateInitialize() --
// a freshly drydock-deployed ship's shuttle datum doesn't exist yet when
// LateInitialize() first runs here; SSshuttle's populate_sector_objects()
// links it moments later via a direct attempt_hook_up() call that bypasses
// LateInitialize() entirely, so hooking the link into attempt_hook_up()
// itself (via _hook_up_to_ship()) means it fires exactly once, whichever
// call site actually succeeds.
/obj/structure/machinery/ship_tractor_beam/LateInitialize()
	. = ..()
	_hook_up_to_ship()

/obj/structure/machinery/ship_tractor_beam/proc/_hook_up_to_ship()
	if(linked)
		return TRUE
	if(!SSatlas.current_map.use_overmap)
		return FALSE
	var/my_sector = GLOB.map_sectors["[GET_Z(src)]"]
	if(!istype(my_sector, /obj/effect/overmap/visitable))
		return FALSE
	if(!attempt_hook_up(my_sector))
		return FALSE
	if(istype(linked, /obj/effect/overmap/visitable/ship))
		var/obj/effect/overmap/visitable/ship/VS = linked
		VS.tractor_beam = src
	return TRUE

/obj/structure/machinery/ship_tractor_beam/Destroy()
	_release_lock()
	if(istype(linked, /obj/effect/overmap/visitable/ship))
		var/obj/effect/overmap/visitable/ship/VS = linked
		if(VS.tractor_beam == src)
			VS.tractor_beam = null
	DropFuel()
	return ..()

/obj/structure/machinery/ship_tractor_beam/proc/HasFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(sheets >= needed_sheets - sheet_left)
		return TRUE
	return FALSE

/obj/structure/machinery/ship_tractor_beam/proc/UseFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(needed_sheets > sheet_left)
		sheets--
		sheet_left = (1 + sheet_left) - needed_sheets
	else
		sheet_left -= needed_sheets

// Removes whatever's left in the hopper as a fresh stack -- mirrors
// ship_cloaking_device.dm's own DropFuel(), called on Destroy() so
// scrapping the projector doesn't silently delete stored phoron.
/obj/structure/machinery/ship_tractor_beam/proc/DropFuel()
	if(sheets)
		var/obj/item/stack/material/S = new sheet_path(loc)
		var/amount = min(sheets, S.max_amount)
		S.amount = amount
		sheets -= amount

/obj/structure/machinery/ship_tractor_beam/process()
	if(!active)
		return

	if(!anchored || !istype(linked) || !HasFuel())
		// Ran out of phoron, got unanchored, or lost its ship link -- force
		// off, same as ship_shield_generator.dm/ship_cloaking_device.dm's
		// own process() auto-shutoff.
		var/out_of_fuel = !HasFuel()
		_release_lock()
		if(out_of_fuel)
			audible_message(SPAN_WARNING("\The [src] sputters and powers down -- out of phoron."))
		return

	UseFuel()
	_update_beam_loop()

	if(!locked_target)
		return

	if(QDELETED(locked_target) || get_dist(linked, locked_target) > TRACTOR_BEAM_MAX_RANGE)
		// Safety net only -- _drag_tractored_target() (ship.dm) keeps the
		// target at exactly lock_offset_x/y every time the tractoring ship
		// moves, so this should never fire in practice except at a map edge
		// the drag itself couldn't resolve.
		_release_lock()
		return

	if(linked.targeting != locked_target)
		// Operator detargeted or switched locks on the console -- this is
		// driven off the SAME lock the targeting console uses for weapons,
		// so losing that lock drops the tractor lock too.
		_release_lock()

/// Reconciles the ambient loop against who's currently on EITHER ship's
/// Z(s) -- same shape as ship_shield_generator.dm's own _update_hum(), the
/// one difference being a tractor beam connects two ships, so both crews
/// are covered instead of just one. Reuses ASFX_ENGINE_HUM (same "ship
/// mechanical ambient loop" preference _update_hum() itself reuses) rather
/// than a new toggle. Called every process() tick while active; self-
/// throttles. Only ever reached with a locked_target (process() already
/// returns early otherwise), so no separate active-with-no-target case to
/// handle here.
/obj/structure/machinery/ship_tractor_beam/proc/_update_beam_loop()
	if(world.time < next_loop_check)
		return
	next_loop_check = world.time + 3 SECONDS

	var/list/z_list = list()
	if(locked_target)
		if(istype(linked))
			z_list += linked.map_z
		if(istype(locked_target))
			z_list += locked_target.map_z

	var/list/current_listeners = list()
	if(length(z_list))
		for(var/mob/M in GLOB.player_list)
			if(!M.client || M.ear_deaf || !(GET_Z(M) in z_list))
				continue
			if(!(M.client.prefs.sfx_toggles & ASFX_ENGINE_HUM))
				continue
			current_listeners += M

	// The start/stop stingers are pushed in the SAME statement, right
	// alongside the loop sound itself, rather than from _acquire_lock()/
	// _release_lock() on their own timing -- those fire the instant the
	// lock is (de)established, up to one process() tick before this proc's
	// own 3-second-throttled reconciliation would actually start/stop the
	// loop for a given listener, which would land the stinger audibly
	// ahead of the loop instead of exactly with it. Separate, unchanneled
	// one-shots (not CHANNEL_TRACTOR_BEAM) -- sharing that channel would
	// have the loop's own repeat=1 sound immediately cut the stinger off,
	// since one channel can only play one sound at a time.
	for(var/mob/M in current_listeners)
		if(!(M in loop_listeners))
			M << sound('sound/effects/ship_weapons/tractor_start.ogg', volume = 35)
			M << sound('sound/effects/ship_weapons/tractor_beam_loop.ogg', repeat = 1, volume = 20, channel = CHANNEL_TRACTOR_BEAM)
	for(var/mob/M in loop_listeners)
		if(!(M in current_listeners))
			M << sound('sound/effects/ship_weapons/tractor_stop.ogg', volume = 35)
			M << sound(null, channel = CHANNEL_TRACTOR_BEAM)
	loop_listeners = current_listeners

/obj/structure/machinery/ship_tractor_beam/proc/toggle_tractor(mob/user)
	if(active)
		_release_lock()
		return
	if(!anchored)
		to_chat(user, SPAN_WARNING("\The [src] must be anchored before it can be activated."))
		return
	if(!_hook_up_to_ship())
		to_chat(user, SPAN_WARNING("\The [src] cannot locate this ship on the overmap."))
		return
	// Same istype() scoping ship_shield_generator.dm's own toggle_shield()
	// applies, for the same reason -- /ship/stationary is non-flyable
	// scenery, not a real drydock ship or shuttle.
	if(!istype(linked, /obj/effect/overmap/visitable/ship/landable))
		to_chat(user, SPAN_WARNING("\The [src] can only be activated aboard a drydock ship or shuttle, not a station."))
		return
	if(!HasFuel())
		to_chat(user, SPAN_WARNING("\The [src] has no phoron left to burn."))
		return
	if(_currently_at_away_site())
		to_chat(user, SPAN_WARNING("\The [src] refuses to engage -- it can't lock onto anything at an away site."))
		return
	var/obj/effect/overmap/visitable/target = linked.targeting
	if(!istype(target, /obj/effect/overmap/visitable/ship))
		to_chat(user, SPAN_WARNING("\The [src] needs a locked ship target first."))
		return
	if(target == linked)
		to_chat(user, SPAN_WARNING("\The [src] refuses to target your own ship."))
		return
	if(get_dist(linked, target) > TRACTOR_BEAM_MAX_RANGE)
		to_chat(user, SPAN_WARNING("\The [src] can't reach that far -- the target needs to be within [TRACTOR_BEAM_MAX_RANGE] tile of your ship."))
		return
	var/obj/effect/overmap/visitable/ship/target_ship = target
	if(istype(target_ship.shield_generator) && target_ship.shield_generator.shields_up())
		to_chat(user, SPAN_WARNING("\The [src] can't get a lock -- the target's shields are still up."))
		return
	if(target_ship.tractored_by)
		to_chat(user, SPAN_WARNING("\The [src] can't get a lock -- something else already has that ship."))
		return
	_acquire_lock(target_ship)

/obj/structure/machinery/ship_tractor_beam/proc/_acquire_lock(obj/effect/overmap/visitable/ship/target_ship)
	active = TRUE
	locked_target = target_ship
	lock_offset_x = target_ship.x - linked.x
	lock_offset_y = target_ship.y - linked.y
	target_ship.tractored_by = src
	lock_beam = Beam(target_ship, icon_state = "explore_beam", beam_type = /obj/effect/ebeam/tractor, time = -1, maxdistance = TRACTOR_BEAM_MAX_RANGE + 2)
	update_icon()
	visible_message(SPAN_DANGER("\The [src] locks onto \the [target_ship] with a low hum!"))
	announce_to_ship_z(linked.map_z, 'sound/AI/announcements/tractor_beam_engaged.ogg', 50, TRUE)
	announce_to_ship_z(target_ship.map_z, 'sound/AI/announcements/enemy_tractor_beam_engaged.ogg', 50, TRUE)
	broadcast_combat_sensor_contact(linked, target_ship, "[linked.name] has tractor-beamed [target_ship.name].")

/obj/structure/machinery/ship_tractor_beam/proc/_release_lock()
	if(!active && !locked_target)
		return
	var/obj/effect/overmap/visitable/ship/target_ship = locked_target
	active = FALSE
	locked_target = null
	if(lock_beam)
		lock_beam.End()
		lock_beam = null
	// process() won't run _update_beam_loop() again once active is FALSE,
	// so stop every current listener right here instead of waiting for a
	// reconciliation tick that will never come -- this is the "for any
	// condition" release path (manual toggle, fuel-out, range safety net,
	// detarget, the docking safety net in landable.dm's on_landing()), so
	// the stop stinger belongs here too, in the same statement as the loop
	// itself actually stopping, not on some separate announcement timing.
	for(var/mob/M in loop_listeners)
		M << sound('sound/effects/ship_weapons/tractor_stop.ogg', volume = 35)
		M << sound(null, channel = CHANNEL_TRACTOR_BEAM)
	loop_listeners = list()
	update_icon()
	if(istype(linked))
		announce_to_ship_z(linked.map_z, 'sound/AI/announcements/tractor_beam_released.ogg', 50, TRUE)
	if(istype(target_ship))
		if(target_ship.tractored_by == src)
			target_ship.tractored_by = null
		announce_to_ship_z(target_ship.map_z, 'sound/AI/announcements/enemy_tractor_beam_released.ogg', 50, TRUE)
		if(istype(linked))
			broadcast_combat_sensor_contact(linked, target_ship, "[linked.name] has released [target_ship.name] from a tractor beam.")
	visible_message(SPAN_NOTICE("\The [src] powers down its lock."))

/// TRUE when this projector's ship is genuinely, physically parked at an
/// away site right now -- mirrors ship_shield_generator.dm's own
/// _currently_at_away_site() exactly (see its doc comment for the reasoning).
/obj/structure/machinery/ship_tractor_beam/proc/_currently_at_away_site()
	if(!istype(linked, /obj/effect/overmap/visitable/ship/landable))
		return FALSE
	var/obj/effect/overmap/visitable/ship/landable/VS = linked
	var/datum/shuttle/shuttle_datum = SSshuttle.shuttles[VS.shuttle]
	if(!istype(shuttle_datum) || !shuttle_datum.current_location)
		return FALSE
	return is_away_level(shuttle_datum.current_location.z)

/obj/structure/machinery/ship_tractor_beam/update_icon()
	set_light(active ? 2 : 0, 1, l_color = color)

/obj/structure/machinery/ship_tractor_beam/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, sheet_path))
		var/obj/item/stack/addstack = attacking_item
		var/amount = min((max_sheets - sheets), addstack.amount)
		if(amount < 1)
			to_chat(user, SPAN_NOTICE("\The [src] is full!"))
			return
		to_chat(user, SPAN_NOTICE("You feed [amount] [sheet_name] into \the [src]."))
		sheets += amount
		addstack.use(amount)
		return
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(anchored && active)
			to_chat(user, SPAN_WARNING("Power down \the [src] before unwrenching it."))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		user.visible_message(SPAN_NOTICE("[user] [anchored ? "wrenches" : "unwrenches"] \the [src] [anchored ? "to" : "from"] the floor."), \
			SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		return TRUE
	return ..()

/**
 * Persists the fuel hopper across a ship's stash/retrieve cycle, same as
 * ship_cloaking_device.dm's own get/apply pair. A live lock is deliberately
 * NOT persisted -- it's transient combat state tied to a specific enemy
 * ship instance that may not even exist after a restart, same reasoning
 * shield_recovery_at/cloak_lockout_until stay world.time-relative and
 * unsaved.
 */
/obj/structure/machinery/ship_tractor_beam/persistent_objects_get_content()
	var/list/content = ..()
	content["sheets"] = sheets
	content["sheet_left"] = sheet_left
	return content

/obj/structure/machinery/ship_tractor_beam/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	sheets = content["sheets"] || 0
	sheet_left = content["sheet_left"] || 0

/obj/structure/machinery/ship_tractor_beam/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/ship_tractor_beam/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShipTractorBeam", "Tractor Beam Projector", 380, 360)
		ui.open()

/// Read-only fuel/status visibility only -- same shape as
/// ship_cloaking_device.dm's own ui_data() (fuel/status fields are directly
/// comparable, same hopper model), but deliberately no ui_act() at all:
/// activating/releasing the lock is exclusively done from the gunnery
/// console's own tractor control panel (_targeting_console.dm's
/// "toggle_tractor" ui_act case, which already calls toggle_tractor()
/// directly), not from here.
/obj/structure/machinery/ship_tractor_beam/ui_data(mob/user)
	var/list/data = list()
	data["active"] = active
	data["anchored"] = anchored
	data["linked"] = istype(linked)
	data["sheets"] = sheets
	data["max_sheets"] = max_sheets
	data["sheet_name"] = sheet_name
	var/needed_sheets = power_output / time_per_sheet // fraction of a sheet burned per process() tick
	data["seconds_per_sheet"] = time_per_sheet
	data["seconds_remaining"] = (needed_sheets > 0) ? round((sheets + sheet_left) / needed_sheets) : null
	data["at_away_site"] = _currently_at_away_site()
	data["locked_target_name"] = istype(locked_target) ? locked_target.name : null
	var/obj/effect/overmap/visitable/console_target = istype(linked) ? linked.targeting : null
	data["has_console_target"] = istype(console_target, /obj/effect/overmap/visitable/ship) && console_target != linked
	return data
