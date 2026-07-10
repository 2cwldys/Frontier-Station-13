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
	/// having to destroy the old one first.
	var/powered = TRUE
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
	return list("faction_uid" = faction_uid, "powered" = powered)

/obj/structure/machinery/faction_beacon/worldstate_apply_content(list/content)
	faction_uid = content["faction_uid"] || ""
	powered = isnull(content["powered"]) ? TRUE : !!content["powered"]
	if(faction_uid && powered)
		_apply_network()

/// TRUE if this beacon currently holds (or can freely take) the Z claim --
/// FALSE if a different, still-existing beacon already holds it.
/obj/structure/machinery/faction_beacon/proc/_can_claim_z()
	if(!powered || !anchored)
		return FALSE
	var/obj/structure/machinery/faction_beacon/holder = GLOB.faction_beacon_by_z["[GET_Z(src)]"]
	if(!holder || holder == src || QDELETED(holder))
		return TRUE
	return FALSE

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

	if(!_can_claim_z())
		active = FALSE
		log_game("Faction beacon at ([x],[y],[z]): refused to activate -- z-level [GET_Z(src)] is already claimed by another active beacon, or this beacon is unpowered.")
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

	try
		for(var/obj/structure/machinery/cryopod/pod in world)
			if(GET_Z(pod) != beacon_z)
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
			if(pad.faction_shackled && pad.persistent_network != faction_uid)
				continue  // respect player shackle to a different faction
			pad.persistent_network = faction_uid
			pad.persistent_spawn   = TRUE
			configured++
	catch(var/exception/pad_e)
		log_subsystem_persistence_error("Faction beacon: telepad sweep failed: [pad_e]")

	// Configure modular computers directly (machine-level persistent_network).
	// Skips computers already shackled to a different faction, and skips
	// handheld PDAs/wristbound computers entirely -- those are personal
	// devices a crew member carries, not station/faction infrastructure.
	try
		for(var/obj/item/modular_computer/MC in world)
			if(GET_Z(MC) != beacon_z)
				continue
			if(istype(MC, /obj/item/modular_computer/handheld))
				continue
			if(MC.faction_shackled && MC.persistent_network != faction_uid)
				continue  // respect player shackle to a different faction
			MC.persistent_network = faction_uid
			configured++
	catch(var/exception/mc_e)
		log_subsystem_persistence_error("Faction beacon: modular computer sweep failed: [mc_e]")

	try
		for(var/obj/structure/machinery/telecomms/T in world)
			if(GET_Z(T) != beacon_z)
				continue
			T.persistent_network = faction_uid
			configured++
	catch(var/exception/tc_e)
		log_subsystem_persistence_error("Faction beacon: telecomms sweep failed: [tc_e]")

	try
		for(var/area/A in GLOB.areas)
			if(!A.is_blueprint_area)
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
	if(zone_security_get(beacon_z) != ZONE_HIGHSEC)
		persistence_set_zone_security(beacon_z, ZONE_MEDSEC)

/obj/structure/machinery/faction_beacon/update_icon()
	if(active && faction_uid)
		icon_state = "bspacerelay"
	else
		icon_state = "bspacerelay"

/obj/structure/machinery/faction_beacon/verb/toggle_beacon_power()
	set name = "Toggle Beacon Power"
	set category = "Object"
	set desc = "Power this beacon on or off. An unpowered beacon holds no Z-level claim."
	set src in oview(1)

	if(!can_configure_faction_shackle(usr, faction_uid, 1))
		to_chat(usr, SPAN_WARNING("You need command access in [faction_uid ? get_faction_name(faction_uid) : "this beacon's faction"] to toggle it."))
		return

	powered = !powered
	if(!powered)
		active = FALSE
		_release_z_claim()
		QDEL_NULL(beacon_looping_sound)
		update_icon()
		to_chat(usr, SPAN_WARNING("Beacon powered down. Z-level [GET_Z(src)] is now unclaimed."))
	else
		_apply_network()
		to_chat(usr, SPAN_GOOD("Beacon powered up.[active ? " Network active." : " Could not reclaim this Z-level -- already claimed by another active beacon."]"))

	message_admins("[key_name(usr)] [powered ? "powered up" : "powered down"] a faction beacon ([faction_uid ? get_faction_name(faction_uid) : "unconfigured"]) at ([x],[y],[z]). (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")

// Faction assignment is configured via the faction tagger tool now (see
// faction_tagger_set() in persistence_faction_tagger.dm) -- beacon
// placement itself is still an admin/mapping action, but the faction-uid
// step moved to the tagger so command-tier faction members can configure
// their own beacon. This admin-only quick-access verb stays for a "raw"
// session where nobody has a faction ID yet, or for admins who don't want
// to dig out a tagger item.
/obj/structure/machinery/faction_beacon/verb/configure_faction_beacon()
	set name = "Configure Faction Beacon"
	set category = "Admin"
	set desc = "Force-set or clear this beacon's faction network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	to_chat(usr, SPAN_NOTICE("Current network: [faction_uid ? get_faction_name(faction_uid) : "(none)"] | active=[active] | powered=[powered]"))

	var/new_network = tgui_input_text(usr, "Enter faction UID (leave blank to clear):", "Configure Faction Beacon", faction_uid, max_length = 32)
	if(new_network == null)
		return

	var/new_uid = new_network ? normalize_faction_uid(new_network) : null
	if(faction_tagger_set(new_uid, usr))
		to_chat(usr, SPAN_GOOD("Beacon network set to: [faction_uid ? get_faction_name(faction_uid) : "(none)"][active ? " (active)" : ""]"))
		log_admin("[key_name(usr)] force-configured faction beacon at ([x],[y],[z]) to '[faction_uid]' via admin verb.")
