/*
 * Faction Beacon
 * A single placeable object that anchors a faction's territory to an entire
 * Z-level. Every compatible object/area on that Z-level automatically
 * inherits the faction's persistent_network, so admins configure one object
 * instead of each cryopod, telepad, console, telecomms machine, and
 * blueprint-created area individually. Every site this codebase deals with
 * is single-faction territory, so whole-Z-level scope (not a configurable
 * radius) is the intended design -- see GLOB.faction_beacon_by_z below for
 * how a second beacon on the same Z-level is handled.
 *
 * Claiming a Z-level (successful _apply_network()) also ensures that Z is in
 * the persistence save list and bumps its security to at least medsec.
 * Destroying the beacon by damage reverses both -- the Z stops saving and
 * drops to nullsec -- the "station becomes defeated" mechanic. Admin
 * deletion and any future tool-deconstruction path deliberately do NOT
 * trigger this (see on_death()/destroyed_by_damage below).
 */

/obj/structure/machinery/faction_beacon
	name = "faction beacon"
	desc = "An anchor beacon that ties nearby infrastructure to a faction network."
	icon = 'icons/obj/machinery/telecomms.dmi'
	icon_state = "bspacerelay"
	anchored = TRUE // default -- can be wrenched loose (see attackby()) once powered off
	density = FALSE
	layer = OBJ_LAYER
	maxhealth = OBJECT_HEALTH_HIGH // hard to destroy by accident, not immune to a real assault

	/// Faction UID this beacon represents (e.g. "nanotrasen", "zavodskoi")
	var/faction_uid = ""
	/// Whether this beacon is actively networked
	var/active = FALSE
	/// Manual on/off -- an unpowered beacon can never hold a Z claim, letting
	/// command deliberately hand a Z off to a different beacon without
	/// having to destroy the old one first. Spawns off -- must be deliberately
	/// powered up via the TGUI, never active out of the box.
	var/powered = FALSE
	/// Alt-click to toggle (mirrors APC/air alarm's lock pattern) -- while
	/// locked, only admins can use the TGUI's power toggle. Secure by default.
	var/locked = TRUE
	/// How many overmap sectors out (in addition to this beacon's own Z) get
	/// their security bumped to at least medsec when the network applies.
	/// Admin-adjustable via the TGUI. 0 = only this beacon's own Z, matching
	/// the original design before this was added.
	var/security_radius = 1
	/// Minimum security tier this beacon's claim guarantees, for both its own
	/// Z and the overmap security radius -- never downgrades a Z already at
	/// or above this tier. ZONE_MEDSEC for the standard beacon; the hub
	/// beacon variant (below) raises this to ZONE_HIGHSEC.
	var/guaranteed_security_tier = ZONE_MEDSEC
	/// Set just before qdel() when health hit zero (see on_death()) --
	/// distinguishes genuine combat destruction from admin qdel/VV-delete
	/// and any future tool-deconstruction path, neither of which call
	/// on_death() at all.
	var/destroyed_by_damage = FALSE
	/// Sparks while active, for a visible "this is online" tell.
	var/datum/effect_system/sparks/spark_system
	/// Looping hum while active, same visible-online purpose as the sparks.
	var/looping_sound_type = /datum/looping_sound/faction_beacon
	VAR_PRIVATE/datum/looping_sound/beacon_looping_sound

/// Z-number (as text) -> the faction beacon currently claiming that whole
/// Z-level. Only one beacon may be active per Z at a time -- first-placed/
/// configured takes precedence; a second beacon on the same Z is refused
/// until the first is powered off or destroyed.
GLOBAL_LIST_EMPTY(faction_beacon_by_z)

/obj/structure/machinery/faction_beacon/Initialize(mapload)
	. = ..()
	spark_system = bind_spark(src, 5)
	if(faction_uid)
		_apply_network()

/obj/structure/machinery/faction_beacon/on_death()
	destroyed_by_damage = TRUE
	. = ..()

/obj/structure/machinery/faction_beacon/Destroy()
	// Losing the beacon "defeats" the station it anchored -- cut its Z out
	// of the persistence save list, drop its security to nullsec, and make
	// sure admins can't miss it. Only for genuine combat destruction (see
	// on_death()) -- admin deletion and tool disassembly skip this
	// entirely. Reversing this needs no new tooling: the existing Z-level
	// persistence/security admin verbs already write through the same
	// shared procs this uses.
	if(destroyed_by_damage && active && faction_uid)
		var/beacon_z = GET_Z(src)
		var/fname = get_faction_name(faction_uid)
		SSpersistence.setZLevelPersistence(beacon_z, 0, "Beacon destroyed -- [fname] station defeated")
		var/old_sec = zone_security_get(beacon_z)
		if(old_sec != ZONE_NULLSEC)
			persistence_set_zone_security(beacon_z, ZONE_NULLSEC)
		message_admins("<font size='4' color='red'><b>FACTION BEACON DESTROYED:</b></font> [fname]'s beacon at ([x],[y],[z]) was destroyed -- Z=[beacon_z] will no longer save/persist[old_sec != ZONE_NULLSEC ? " and has been reset to NULLSEC" : ""]. (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
		log_game("Faction beacon destroyed: [fname]'s beacon at ([x],[y],[z]), Z=[beacon_z] removed from persistence save list[old_sec != ZONE_NULLSEC ? ", security reset to nullsec" : ""].")
	QDEL_NULL(beacon_looping_sound)
	qdel(spark_system)
	spark_system = null
	_release_z_claim()
	return ..()

/obj/structure/machinery/faction_beacon/process()
	if(active && powered && prob(15))
		spark_system.queue()

/// Wrench to (un)anchor -- moving the beacon requires unwrenching it first.
/// Must be powered off before it can be unwrenched (that already guarantees
/// no active Z claim needs releasing here), and command-tier faction access
/// is required either way, matching toggle_beacon_power()'s own gate.
/obj/structure/machinery/faction_beacon/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(anchored && powered)
			to_chat(user, SPAN_WARNING("Power down \the [src] before unwrenching it."))
			return TRUE
		if(!can_configure_faction_shackle(user, faction_uid, 1))
			to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to (un)wrench it."))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		user.visible_message(SPAN_NOTICE("[user] [anchored ? "wrenches" : "unwrenches"] \the [src] [anchored ? "to" : "from"] the floor."), \
			SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		return TRUE
	return ..()

/obj/structure/machinery/faction_beacon/worldstate_get_content()
	if(!faction_uid)
		return list()
	return list("faction_uid" = faction_uid, "powered" = powered, "locked" = locked, "security_radius" = security_radius)

/obj/structure/machinery/faction_beacon/worldstate_apply_content(list/content)
	faction_uid = content["faction_uid"] || ""
	powered = isnull(content["powered"]) ? FALSE : !!content["powered"]
	locked = isnull(content["locked"]) ? TRUE : !!content["locked"]
	security_radius = isnull(content["security_radius"]) ? 1 : text2num(content["security_radius"])
	if(faction_uid && powered)
		_apply_network()

/// Null if this beacon could claim/hold its Z right now, otherwise a short
/// reason explaining why not -- lets callers show a specific message instead
/// of one generic blended "already claimed" line.
/obj/structure/machinery/faction_beacon/proc/_claim_refusal_reason()
	if(!anchored)
		return "not anchored -- wrench it to the floor first"
	if(!powered)
		return "not powered"
	var/obj/structure/machinery/faction_beacon/holder = GLOB.faction_beacon_by_z["[GET_Z(src)]"]
	if(holder && holder != src && !QDELETED(holder))
		return "Z-level [GET_Z(src)] is already claimed by [holder.faction_uid ? get_faction_name(holder.faction_uid) : "another beacon"]"
	return null

/// TRUE if this beacon currently holds (or can freely take) the Z claim --
/// FALSE if a different, still-existing beacon already holds it.
/obj/structure/machinery/faction_beacon/proc/_can_claim_z()
	return !_claim_refusal_reason()

/obj/structure/machinery/faction_beacon/proc/_release_z_claim()
	var/key = "[GET_Z(src)]"
	if(GLOB.faction_beacon_by_z[key] == src)
		GLOB.faction_beacon_by_z -= key

/// Scan every compatible object/area on this beacon's Z-level and set their
/// persistent_network to our faction_uid. Refuses to run (and logs why) if
/// unpowered, or if a different, still-active beacon already claims this Z
/// -- callers that need to tell a user why should check _can_claim_z()
/// themselves first for a proper chat message.
/obj/structure/machinery/faction_beacon/proc/_apply_network()
	faction_uid = normalize_faction_uid(faction_uid)
	if(!faction_uid)
		active = FALSE
		_release_z_claim()
		update_icon()
		return

	var/refusal = _claim_refusal_reason()
	if(refusal)
		active = FALSE
		log_game("Faction beacon at ([x],[y],[z]): refused to activate -- [refusal].")
		update_icon()
		return

	var/beacon_z = GET_Z(src)
	GLOB.faction_beacon_by_z["[beacon_z]"] = src
	active = TRUE

	// Visible/audible "online" tell and icon update happen immediately, not
	// after the sweep below -- if any sweep loop throws, active is already
	// TRUE and everything downstream of it must still reflect that
	// correctly instead of silently never running. Own try/catch too, since
	// this section can throw just as easily as the sweeps below it -- no
	// manual SSprocessing registration needed here, /obj/structure/machinery
	// already auto-registers every beacon with SSmachinery at spawn, and
	// process() self-gates on active/powered.
	try
		update_icon()
		if(!beacon_looping_sound)
			beacon_looping_sound = new looping_sound_type(src)
			beacon_looping_sound.start()
	catch(var/exception/tell_e)
		log_subsystem_persistence_error("Faction beacon: online tell failed: [tell_e]")

	var/configured = 0

	// Every branch below only claims genuinely UNASSIGNED targets (empty
	// network field) -- anything already set, whether to "public", a
	// different faction, or even this same faction, is left alone. This is
	// what makes a manual override (via the tagger, properly authorized)
	// stick permanently instead of getting silently re-claimed the next time
	// this sweep runs (e.g. every power-cycle of the beacon).
	try
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(GET_Z(pod) != beacon_z)
				continue
			if(pod.persistent_network)
				continue
			pod.persistent_network = faction_uid
			pod.persistent_spawn   = TRUE
			configured++
	catch(var/exception/cryo_e)
		log_subsystem_persistence_error("Faction beacon: cryopod sweep failed: [cryo_e]")

	try
		for(var/obj/structure/machinery/telepad_cargo/pad in world)
			if(GET_Z(pad) != beacon_z)
				continue
			if(pad.persistent_network)
				continue
			pad.persistent_network = faction_uid
			pad.persistent_spawn   = TRUE
			pad.faction_shackled   = TRUE
			configured++
	catch(var/exception/pad_e)
		log_subsystem_persistence_error("Faction beacon: telepad sweep failed: [pad_e]")

	// Configure modular computers directly (machine-level persistent_network).
	// Skips handheld PDAs/wristbound computers entirely -- those are personal
	// devices a crew member carries, not station/faction infrastructure.
	try
		for(var/obj/item/modular_computer/MC in world)
			if(GET_Z(MC) != beacon_z)
				continue
			if(istype(MC, /obj/item/modular_computer/handheld))
				continue
			if(MC.persistent_network)
				continue
			MC.persistent_network = faction_uid
			MC.faction_shackled   = TRUE
			configured++
	catch(var/exception/mc_e)
		log_subsystem_persistence_error("Faction beacon: modular computer sweep failed: [mc_e]")

	try
		for(var/obj/structure/machinery/telecomms/T in world)
			if(GET_Z(T) != beacon_z)
				continue
			if(T.persistent_network)
				continue
			T.persistent_network = faction_uid
			configured++
	catch(var/exception/tc_e)
		log_subsystem_persistence_error("Faction beacon: telecomms sweep failed: [tc_e]")

	try
		for(var/obj/structure/machinery/door/airlock/AL in world)
			if(GET_Z(AL) != beacon_z)
				continue
			if(AL.req_access_faction)
				continue
			AL.req_access_faction = faction_uid
			configured++
	catch(var/exception/al_e)
		log_subsystem_persistence_error("Faction beacon: airlock sweep failed: [al_e]")

	try
		for(var/area/A in GLOB.areas)
			if(!A.is_blueprint_area)
				continue
			if(A.persistent_network)
				continue
			var/on_z = FALSE
			for(var/turf/AT in A.contents)
				if(GET_Z(AT) == beacon_z)
					on_z = TRUE
					break
			if(!on_z)
				continue
			A.persistent_network = faction_uid
			configured++
	catch(var/exception/area_e)
		log_subsystem_persistence_error("Faction beacon: area sweep failed: [area_e]")

	log_game("Faction beacon at ([x],[y],[z]): networked [configured] objects/areas to faction '[faction_uid]' across z-level [beacon_z].")

	// A beacon claiming a Z should make sure that Z is actually in the
	// persistence save list -- otherwise the station it's meant to be
	// anchoring never persists in the first place. It should also grant at
	// least medsec (a faction establishing its own law), never downgrading
	// a Z an admin has already set to highsec (Hub law).
	if(!(beacon_z in GLOB.persistence_zlevel_allow))
		SSpersistence.setZLevelPersistence(beacon_z, 1, "Faction: [faction_uid]")
	if(zone_security_get(beacon_z) < guaranteed_security_tier)
		persistence_set_zone_security(beacon_z, guaranteed_security_tier)

	// Extends the security guarantee to nearby overmap sectors within
	// security_radius, same range() mechanic telecomms machines use for their
	// own broadcast reach. Never touches an already-highsec Z (same exception
	// as this beacon's own Z, just above), and never touches a Z already
	// claimed by a different active beacon (respects other factions' territory).
	if(SSatlas.current_map.use_overmap && security_radius > 0)
		var/obj/effect/overmap/visitable/my_sector = GLOB.map_sectors["[beacon_z]"]
		if(istype(my_sector))
			for(var/obj/effect/overmap/visitable/V in range(security_radius, my_sector))
				for(var/nearby_z in V.map_z)
					if(nearby_z == beacon_z)
						continue
					var/obj/structure/machinery/faction_beacon/other = GLOB.faction_beacon_by_z["[nearby_z]"]
					if(other && !QDELETED(other) && other != src)
						continue
					if(zone_security_get(nearby_z) < guaranteed_security_tier)
						persistence_set_zone_security(nearby_z, guaranteed_security_tier)

/obj/structure/machinery/faction_beacon/update_icon()
	icon_state = "bspacerelay"
	// No dedicated "on"/"off" sprite exists yet -- a light glow is a safe,
	// low-risk visual tell that doesn't depend on a sprite frame existing.
	if(active)
		set_light(2, 1, COLOR_CYAN)
	else
		set_light(0)

/// Alt-click toggles the physical lock (mirrors APC/air alarm) -- while
/// locked, the TGUI's power toggle is restricted to admins.
/obj/structure/machinery/faction_beacon/AltClick(mob/user)
	if(!Adjacent(user))
		return
	if(!can_configure_faction_shackle(user, faction_uid, 1))
		to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to (un)lock it."))
		return
	locked = !locked
	playsound(src, locked ? 'sound/machines/terminal/terminal_button03.ogg' : 'sound/machines/terminal/terminal_button01.ogg', 35, FALSE)
	balloon_alert(user, locked ? "locked" : "unlocked")

/obj/structure/machinery/faction_beacon/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	if(locked)
		to_chat(user, SPAN_WARNING("\The [src] is locked."))
		return
	ui_interact(user)

/obj/structure/machinery/faction_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionBeacon", "Faction Beacon", 420, 460)
		ui.open()

/obj/structure/machinery/faction_beacon/ui_data(mob/user)
	var/list/data = list()
	data["faction_uid"] = faction_uid
	data["faction_name"] = faction_uid ? get_faction_name(faction_uid) : null
	data["active"] = active
	data["powered"] = powered
	data["locked"] = locked
	data["anchored"] = anchored
	data["is_admin"] = check_rights(R_ADMIN, 0, user)
	data["can_configure"] = can_configure_faction_shackle(user, faction_uid, 1)
	data["refusal_reason"] = _claim_refusal_reason()
	data["security_radius"] = security_radius
	return data

/obj/structure/machinery/faction_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("toggle_power")
			if(!anchored)
				to_chat(user, SPAN_WARNING("\The [src] must be wrenched to the floor first."))
				return
			if(locked)
				to_chat(user, SPAN_WARNING("\The [src] is locked -- unlock it first (alt-click)."))
				return
			_toggle_power(user)
			. = TRUE
		if("set_faction")
			if(!check_rights(R_ADMIN, 0, user))
				return
			var/new_network = params["uid"]
			var/new_uid = new_network ? normalize_faction_uid(new_network) : null
			if(faction_tagger_set(new_uid, user))
				to_chat(user, SPAN_GOOD("Beacon network set to: [faction_uid ? get_faction_name(faction_uid) : "(none)"][active ? " (active)" : ""]"))
				log_admin("[key_name(user)] force-configured faction beacon at ([x],[y],[z]) to '[faction_uid]' via TGUI.")
			. = TRUE
		if("set_security_radius")
			if(!check_rights(R_ADMIN, 0, user))
				return
			var/radius_input = text2num(params["radius"])
			if(isnull(radius_input))
				return
			var/new_radius = between(0, radius_input, 10)
			security_radius = new_radius
			to_chat(user, SPAN_GOOD("Security radius set to [security_radius]."))
			log_admin("[key_name(user)] set faction beacon security radius to [security_radius] at ([x],[y],[z]).")
			. = TRUE

/// Shared power-toggle body -- used by the TGUI's "toggle_power" action.
/obj/structure/machinery/faction_beacon/proc/_toggle_power(mob/user)
	if(!can_configure_faction_shackle(user, faction_uid, 1))
		to_chat(user, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to toggle it."))
		return

	powered = !powered
	if(!powered)
		active = FALSE
		_release_z_claim()
		QDEL_NULL(beacon_looping_sound)
		update_icon()
		to_chat(user, SPAN_WARNING("Beacon powered down. Z-level [GET_Z(src)] is now unclaimed."))
	else
		_apply_network()
		if(active)
			to_chat(user, SPAN_GOOD("Beacon powered up. Network active."))
		else
			to_chat(user, SPAN_WARNING("Beacon powered up, but could not claim: [_claim_refusal_reason()]."))

	message_admins("[key_name(user)] [powered ? "powered up" : "powered down"] a faction beacon ([faction_uid ? get_faction_name(faction_uid) : "unconfigured"]) at ([x],[y],[z]). (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")

// Faction assignment is configured via the faction tagger tool, or the TGUI's
// admin-only "set_faction" action above (for a "raw" session where nobody has
// a faction ID yet, or admins who don't want to dig out a tagger item) --
// beacon placement itself is still an admin/mapping action.

/// "Break glass" admin access -- the normal TGUI (click to open, toggle_power
/// action) respects `locked` for everyone including admins, by design (a
/// physical lock should mean something). This verb is a separate entry point
/// that never goes through ui_act() at all, so it isn't subject to that gate,
/// for the rare case an admin genuinely needs to override a locked beacon.
/obj/structure/machinery/faction_beacon/verb/admin_override_beacon()
	set name = "Admin: Override Faction Beacon"
	set category = "Admin"
	set desc = "Bypass the lock to check status, toggle power, or force-set the faction network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	to_chat(usr, SPAN_NOTICE("Current: network=[faction_uid ? get_faction_name(faction_uid) : "(none)"] | active=[active] | powered=[powered] | locked=[locked] | anchored=[anchored]"))

	var/action = tgui_input_list(usr, "Select action:", "Admin Override", list("Toggle Power", "Toggle Lock", "Force-Set Faction", "Force-Clear Faction", "Close"))
	if(!action || action == "Close")
		return

	switch(action)
		if("Toggle Power")
			_toggle_power(usr)
		if("Toggle Lock")
			locked = !locked
			to_chat(usr, SPAN_GOOD("Beacon [locked ? "locked" : "unlocked"]."))
			log_admin("[key_name(usr)] [locked ? "locked" : "unlocked"] a faction beacon at ([x],[y],[z]) via admin override.")
		if("Force-Set Faction")
			var/new_network = tgui_input_text(usr, "Enter faction UID (leave blank to clear):", "Force-Set Faction", faction_uid, max_length = 32)
			if(new_network == null)
				return
			var/new_uid = new_network ? normalize_faction_uid(new_network) : null
			if(faction_tagger_set(new_uid, usr))
				to_chat(usr, SPAN_GOOD("Beacon network set to: [faction_uid ? get_faction_name(faction_uid) : "(none)"][active ? " (active)" : ""]"))
				log_admin("[key_name(usr)] force-configured faction beacon at ([x],[y],[z]) to '[faction_uid]' via admin override verb.")
		if("Force-Clear Faction")
			if(faction_tagger_set(null, usr))
				to_chat(usr, SPAN_GOOD("Beacon network cleared."))
				log_admin("[key_name(usr)] force-cleared faction beacon at ([x],[y],[z]) via admin override verb.")

/// Hub-issued variant -- guarantees highsec instead of medsec, visually
/// distinct (bluer tint), and deliberately not purchasable through any
/// player-facing channel (no cargo listing) -- admin-spawn only. Inherits
/// every proc unchanged (TGUI, sweep, lock, wrench) -- only the security
/// tier, default radius, color, and TGUI window title actually differ.
/obj/structure/machinery/faction_beacon/hub
	name = "hub beacon"
	desc = "A Hub-issued anchor beacon that guarantees the highest security tier for the infrastructure it claims."
	color = "#6699ff"
	guaranteed_security_tier = ZONE_HIGHSEC
	security_radius = 2 // reaches further than a standard faction beacon's default of 1

/obj/structure/machinery/faction_beacon/hub/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FactionBeacon", "Hub Beacon", 420, 460)
		ui.open()
