/obj/structure/machinery/computer/ship/targeting
	name = "targeting systems console"
	desc = "A targeting systems console using Zavodskoi software."
	icon_screen = "teleport"
	icon_keyboard = "teal_key"
	icon_keyboard_emis = "teal_key_mask"
	light_color = LIGHT_COLOR_CYAN
	circuit = /obj/item/circuitboard/ship/targeting
	var/obj/structure/machinery/ship_weapon/cannon
	var/selected_entrypoint
	var/platform_direction
	var/selected_z = 0
	var/list/names_to_guns = list()
	var/list/names_to_entries = list()
	/// The locked target process() last checked -- lets a genuinely new lock
	/// (or losing the lock) reset last_watched_target_strength cleanly
	/// instead of carrying over stale state from whatever was locked before.
	var/obj/effect/overmap/last_watched_target
	/// Target's shield_strength as of the last poll -- compared against the
	/// current value the same way _check_tier_transition()
	/// (ship_shield_generator.dm) compares the OWN ship's, so a threshold
	/// crossed between two 3-second polls still gets announced even if it
	/// happened between checks. null right after a new lock (no prior
	/// reading to compare against yet).
	var/last_watched_target_strength
	/// Self-throttle for process(), same shape as ship.dm's own
	/// next_engine_hum_check -- this doesn't need to check every tick.
	var/next_shield_check = 0

/obj/structure/machinery/computer/ship/targeting/terminal
	name = "targeting systems terminal"
	desc = "A targeting systems terminal using Zavodskoi software."
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "hostile"
	icon_keyboard = "red_key"
	icon_keyboard_emis = "red_key_mask"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1

/obj/structure/machinery/computer/ship/targeting/Initialize()
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/structure/machinery/computer/ship/targeting/LateInitialize()
	. = ..()
	if(SSatlas.current_map.use_overmap && !linked)
		var/my_sector = GLOB.map_sectors["[z]"]
		if(istype(my_sector, /obj/effect/overmap/visitable))
			attempt_hook_up(my_sector)

/obj/structure/machinery/computer/ship/targeting/Destroy()
	cannon = null
	names_to_guns.Cut()
	names_to_entries.Cut()
	return ..()

/// Called from target()/detarget() (overmap_object.dm) the instant a lock
/// is acquired or cleared -- starts/stops the continuous enemy-shield
/// readout below instead of leaving this console ticking with nothing
/// locked, or waiting a stray interval to notice a fresh lock.
/obj/structure/machinery/computer/ship/targeting/proc/check_processing()
	if(linked?.targeting)
		START_PROCESSING(SSprocessing, src)
	else
		STOP_PROCESSING(SSprocessing, src)

/**
 * Continuously watches whatever this console currently has locked and
 * announces every 25%/50%/max/down threshold the target's shields actually
 * cross between polls, Z-wide on the OBSERVING ship (this console's own
 * ship, not the target's) -- per your explicit call that the enemy readout
 * should keep updating live, not just once at lock-on. Same crossing-based
 * comparison as _check_tier_transition() (ship_shield_generator.dm): a big
 * change between two 3-second polls can skip straight past a checkpoint
 * without the target's CURRENT value ever landing near it, and that
 * crossing still gets announced. Self-throttled the same way ship.dm's own
 * engine hum check is; check_processing() above already keeps this from
 * running at all with no lock held.
 */
/obj/structure/machinery/computer/ship/targeting/process()
	if(world.time < next_shield_check)
		return
	next_shield_check = world.time + 3 SECONDS

	if(!linked?.targeting)
		check_processing()
		return

	if(linked.targeting != last_watched_target)
		last_watched_target = linked.targeting
		last_watched_target_strength = null

	var/obj/structure/machinery/ship_shield_generator/target_gen
	if(istype(linked.targeting, /obj/effect/overmap/visitable/ship))
		var/obj/effect/overmap/visitable/ship/target_ship = linked.targeting
		target_gen = target_ship.shield_generator

	if(!target_gen || !target_gen.shields_up())
		// No active shields to track -- announce once on the transition
		// into this state (sentinel -1), not every 3s while it holds.
		if(last_watched_target_strength != -1)
			last_watched_target_strength = -1
			announce_to_ship_z(linked.map_z, 'sound/AI/announcements/enemy_ship_no_shields.ogg', 50, TRUE)
		return

	var/old_strength = last_watched_target_strength
	var/new_strength = target_gen.shield_strength
	last_watched_target_strength = new_strength

	// No prior reading to compare against (fresh lock, or shields just came
	// back from a "no shields" state) -- set the baseline silently, same as
	// the own-ship generator not re-disclosing a retained charge on
	// reactivation. The next real change will announce normally.
	if(isnull(old_strength) || old_strength == -1 || old_strength == new_strength)
		return

	var/declining = (new_strength < old_strength)
	var/max_strength = target_gen.max_shield_strength

	var/list/checkpoints = list(
		list(max_strength, 'sound/AI/announcements/enemy_shields_at_max.ogg'),
		list(max_strength * 0.5, 'sound/AI/announcements/enemy_shields_at_fifty_percent.ogg'),
		list(max_strength * 0.25, 'sound/AI/announcements/enemy_shields_at_twenty_five_percent.ogg'),
		list(0, 'sound/AI/announcements/enemy_shields_are_down.ogg'),
	)
	if(!declining)
		checkpoints = reverselist(checkpoints)

	for(var/list/checkpoint in checkpoints)
		var/point = checkpoint[1]
		// Crossed-INTO test, same as the own-ship generator's own tier check
		// (_check_tier_transition(), ship_shield_generator.dm) -- see its
		// comment for why both ends can't be inclusive.
		if(declining ? (point >= new_strength && point < old_strength) : (point > old_strength && point <= new_strength))
			announce_to_ship_z(linked.map_z, checkpoint[2], 50, TRUE)

/obj/structure/machinery/computer/ship/targeting/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Gunnery", "Ajax Targeting Console", 400, 525)
		ui.open()

/obj/structure/machinery/computer/ship/targeting/ui_data(mob/user)
	var/list/data = list()
	data["guns"] = list()
	data["selected_entrypoint"] = selected_entrypoint
	data["mobile_platform"] = cannon ? cannon.mobile_platform : null
	if(data["mobile_platform"])
		data["platform_direction"] = platform_direction
		data["platform_directions"] = list("NORTH", "NORTHEAST", "EAST", "SOUTHEAST", "SOUTH", "SOUTHWEST", "WEST", "NORTHWEST")
	// Own ship's shields -- independent of whatever's currently locked (or
	// nothing at all), so this is resolved outside the targeting block below.
	// linked is typed as the base /visitable (_machinery.dm) -- shield_generator
	// only exists on the /ship subtype (ship.dm), hence the istype cast.
	if(istype(linked, /obj/effect/overmap/visitable/ship))
		var/obj/effect/overmap/visitable/ship/own_ship = linked
		data["own_shields"] = get_shield_data(own_ship.shield_generator)
		data["own_shield_control"] = get_shield_control_data(own_ship.shield_generator)
		data["own_cloak_control"] = get_cloak_control_data(_find_own_cloak(own_ship))
	if(linked?.targeting)
		for(var/obj/structure/machinery/ship_weapon/SW in linked.ship_weapons)
			if(!SW.special_firing_mechanism)
				data["guns"] += list(get_gun_data(SW))
		data["targeting"] = list(
			"name" = linked.targeting.name,
			"shiptype" = linked.targeting.shiptype,
			"distance" = get_dist(linked, linked.targeting)
		)
		// Target's shields, if it's a ship with a linked generator -- lets a
		// gunner see whether their shots are actually getting through
		// without needing a separate sensors console readout.
		if(istype(linked.targeting, /obj/effect/overmap/visitable/ship))
			var/obj/effect/overmap/visitable/ship/target_ship = linked.targeting
			data["target_shields"] = get_shield_data(target_ship.shield_generator)
		data["show_z_list"] = FALSE
		data["selected_z"] = selected_z
		if(istype(linked.targeting, /obj/effect/overmap/visitable))
			var/obj/effect/overmap/visitable/V = linked.targeting
			if(length(V.map_z) > 1)
				data["show_z_list"] = TRUE
				if(length(V.map_z) > 1)
					var/list/string_z_levels = list()
					for(var/z in V.map_z)
						string_z_levels += "[z]"
					data["z_levels"] = string_z_levels
				else
					selected_z = 0
					data["selected_z"] = 0
			var/obj/effect/entry_point = selected_entrypoint
			if(istype(entry_point) && entry_point.z)
				data["entry_point_map_image"] = SSholomap.minimaps_scan_base64[entry_point.z]
				data["entry_point_x"] = entry_point.x
				data["entry_point_y"] = entry_point.y
		data["entry_points"] = copy_entrypoints(selected_z)
		if(cannon)
			data["cannon"] = get_gun_data(cannon);
	else
		data["targeting"] = null
	return data

/obj/structure/machinery/computer/ship/targeting/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	playsound(src, clicksound, clickvol)

	. = FALSE
	switch(action)
		if("fire")
			var/obj/effect/landmark/LM
			if(!selected_entrypoint)
				return
			if(!istype(linked.loc, /turf/unsimulated/map))
				to_chat(usr, SPAN_WARNING("The safeties are engaged! You need to be undocked in order to fire."))
				return
			var/is_hazard_shot = (selected_entrypoint == SHIP_HAZARD_TARGET)
			// Defense-in-depth safety net for ship-to-site bombardment --
			// the primary block is at lock-on time (overmap_object.dm's
			// target()); this catches a lock established before a beacon
			// powered on/a zone went highsec. Ship targets (drydock ships
			// included) and hazard shots are untouched -- see target()'s
			// own comment for why ship-to-ship stays log-only, never blocked.
			if(!is_hazard_shot && istype(linked.targeting, /obj/effect/overmap/visitable/sector) && site_bombardment_protected(linked.targeting, usr))
				to_chat(usr, SPAN_WARNING("Weapons systems refuse to fire -- the target is under active protection and cannot be bombarded."))
				return
			if(is_hazard_shot)
				LM = null
			else
				LM = selected_entrypoint
			var/result = cannon.firing_command(linked.targeting, LM, platform_direction ? text2dir(platform_direction) : 0)
			if(isliving(usr) && !isAI(usr) && usr.Adjacent(src))
				visible_message(SPAN_WARNING("[usr] presses the fire button!"))
				playsound(src, 'sound/machines/compbeep1.ogg', 60)
			switch(result)
				if(SHIP_GUN_ERROR_NO_AMMO)
					to_chat(usr, SPAN_WARNING("The console shows an error screen: the weapon isn't loaded!"))
				if(SHIP_GUN_FIRING_SUCCESSFUL)
					log_and_message_admins("[usr] has fired [cannon] with target [linked.targeting] and entry point [LM]!", location = get_turf(usr))
					// Combat is outlawed in highsec (see the zone shield's own
					// legend) -- opening ship-to-ship fire from OR into
					// beacon-covered highsec space records the gunner as a
					// highsec offense, feeding the same admin escalation +
					// First Responder log mob-on-mob violence already uses
					// (zone_security_record_offense's own per-ckey cooldown
					// keeps a sustained barrage from flooding it). Fire-time,
					// not hit-time: shooting at all is the offense, and only
					// this console knows who pulled the trigger. Zone comes
					// from live overmap beacon coverage, not the ships' Zs --
					// a moving ship's Z tier is stale by design.
					//
					// Hazard shots (asteroids/environmental threats within the
					// locked sector) are never an offense, whatever the
					// position -- only firing at a real target (another ship,
					// an away site, the CentCom marker) counts. Deliberately
					// does NOT call zone_security_exempt() here, unlike the
					// melee/admin_attack_log() version of this check --
					// directing warship weapons at a real target in highsec is
					// categorically more serious than personal self-defense, so
					// even Hub security get flagged for it.
					if(usr.ckey && !is_hazard_shot)
						var/turf/firer_tile = get_turf(linked)
						var/turf/victim_tile = linked.targeting ? get_turf(linked.targeting) : null
						if(zone_security_overmap_tier(firer_tile) == ZONE_HIGHSEC || (victim_tile && zone_security_overmap_tier(victim_tile) == ZONE_HIGHSEC))
							zone_security_record_offense(usr, null, "opened ship-to-ship fire in highsec space")
					. = TRUE
					if(issilicon(usr))
						to_chat(usr,SPAN_WARNING("The targeting systems register, showing a successful firing sequence."))
						visible_message(SPAN_WARNING("The console shows a neutral message: firing sequence successful, Silicon unit registered firing: [usr]"))
					else
						visible_message(SPAN_WARNING("The console shows a positive message: firing sequence successful!"))
					if(istype(linked))
						announce_to_ship_z(linked.map_z, 'sound/AI/announcements/firing_weapons.ogg', 50, TRUE)

		if("viewing")
			if(usr)
				viewing_overmap(usr) ? unlook(usr) : look(usr)
				. = TRUE

		if("select_entrypoint")
			if(!params["entrypoint"])
				return
			var/our_entrypoint = params["entrypoint"]
			if(our_entrypoint == SHIP_HAZARD_TARGET)
				selected_entrypoint = our_entrypoint
			else
				selected_entrypoint = names_to_entries[our_entrypoint]
			. = TRUE

		if("select_gun")
			if(!params["gun"])
				return
			var/gun_name = lowertext(params["gun"])
			for(var/obj/structure/machinery/ship_weapon/SW in linked.ship_weapons)
				if(lowertext(SW.name) == gun_name)
					cannon = SW
					. = TRUE

		if("select_z")
			if(!params["z"])
				return
			selected_z = text2num(params["z"])
			. = TRUE

		if("platform_direction")
			if(!params["dir"])
				return
			platform_direction = text2num(params["dir"])
			. = TRUE

		if("toggle_shields")
			if(istype(linked, /obj/effect/overmap/visitable/ship))
				var/obj/effect/overmap/visitable/ship/own_ship = linked
				if(istype(own_ship.shield_generator))
					own_ship.shield_generator.toggle_shield(usr)
			. = TRUE

		if("toggle_cloak")
			if(istype(linked, /obj/effect/overmap/visitable/ship))
				var/obj/effect/overmap/visitable/ship/own_ship = linked
				var/obj/structure/machinery/ship_cloaking_device/CD = _find_own_cloak(own_ship)
				if(CD)
					CD.toggle_cloak(usr)
			. = TRUE

/obj/structure/machinery/computer/ship/targeting/proc/get_gun_data(var/obj/structure/machinery/ship_weapon/SW)
	var/ammo_status = length(SW.ammunition) ? "Loaded, [length(SW.ammunition)] shots" : "Unloaded"
	var/obj/item/ship_ammunition/SA
	if(length(SW.ammunition))
		SA = SW.ammunition[1]
	. = list(
		"name" = SW.name,
		"caliber" = SW.caliber,
		"ammunition" = ammo_status,
		"ammunition_type" = capitalize_first_letters(SA ? SA.impact_type : "None Loaded")
	)

/// Shared shape for both the console's own ship and its currently-locked
/// target -- null if there's no generator at all, or it isn't active (an
/// unpowered/offline generator provides no meaningful "shield %" to show).
/obj/structure/machinery/computer/ship/targeting/proc/get_shield_data(obj/structure/machinery/ship_shield_generator/gen)
	if(!gen || !gen.active)
		return null
	return list("shield_strength" = gen.shield_strength, "max_shield_strength" = gen.max_shield_strength)

/// Own-ship shield toggle control data -- the same fields
/// ShipShieldGenerator.tsx already computes its own disabled/reason logic
/// from (ShipShieldGenerator.dm's ui_data()), so the console's own toggle
/// button can never disagree with the generator's own console about when
/// it's actually available.
/obj/structure/machinery/computer/ship/targeting/proc/get_shield_control_data(obj/structure/machinery/ship_shield_generator/gen)
	if(!istype(gen))
		return list("exists" = FALSE)
	return list(
		"exists" = TRUE,
		"active" = gen.active,
		"anchored" = gen.anchored,
		"has_fuel" = (gen.sheets > 0),
		"at_away_site" = gen._currently_at_away_site(),
		"recovery_seconds_left" = (world.time < gen.shield_recovery_at) ? round((gen.shield_recovery_at - world.time) / 10) : 0,
	)

/// No back-reference var exists from the ship to its own cloaking device
/// (unlike shield_generator on ship.dm) -- mirrors the exact same
/// SSmachinery.machinery scan _ship_gun.dm's own fire() already uses to
/// force-uncloak a firing ship.
/obj/structure/machinery/computer/ship/targeting/proc/_find_own_cloak(obj/effect/overmap/visitable/ship/own_ship)
	for(var/obj/structure/machinery/ship_cloaking_device/CD in SSmachinery.machinery)
		if(CD.linked == own_ship)
			return CD
	return null

/obj/structure/machinery/computer/ship/targeting/proc/get_cloak_control_data(obj/structure/machinery/ship_cloaking_device/CD)
	if(!istype(CD))
		return list("exists" = FALSE)
	return list(
		"exists" = TRUE,
		"active" = CD.active,
		"anchored" = CD.anchored,
		"has_fuel" = (CD.sheets > 0),
		"at_away_site" = CD._currently_at_away_site(),
		"lockout_seconds_left" = (world.time < CD.cloak_lockout_until) ? round((CD.cloak_lockout_until - world.time) / 10) : 0,
	)

/obj/structure/machinery/computer/ship/targeting/proc/copy_entrypoints(var/z_level_filter = 0)
	. = list()
	if(istype(linked.targeting, /obj/effect/overmap/visitable))
		var/obj/effect/overmap/visitable/V = linked.targeting
		if(V.targeting_flags & TARGETING_FLAG_ENTRYPOINTS)
			for(var/obj/effect/O in V.entry_points)
				if(!z_level_filter || (z_level_filter && O.z == z_level_filter))
					. += capitalize_first_letters(O.name)
					names_to_entries[capitalize_first_letters(O.name)] = O
		if(V.targeting_flags & TARGETING_FLAG_GENERIC_WAYPOINTS)
			for(var/obj/effect/O in V.generic_waypoints)
				. += capitalize_first_letters(O.name)
				names_to_entries[capitalize_first_letters(O.name)] = O
		. = sortList(.)
	if(!length(.))
		. += SHIP_HAZARD_TARGET //No entrypoints == hazard
