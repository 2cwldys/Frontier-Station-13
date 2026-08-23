/*
 * Piracy Beacon
 * A crude, field-assembled beacon that only functions in unregulated
 * (nullsec) space. Never sweeps machinery and never touches zone security --
 * once tethered (see the tethered var), it CAN be claimed by a faction via
 * the standard Faction Tagger interface and then behaves like faction-beacon
 * territory (raid-blocked respecting the raiding toggle, shielded from
 * gunnery bombardment, both same-faction exempt -- see
 * piracy_beacon_claimed_faction_on_z() below) -- but deliberately never
 * bumps zone security or shows the overmap "shield" a real faction beacon
 * claim does. Giving away a pirate base's location on the overmap defeats
 * the point of it. Also exists purely as a live "is there piracy
 * infrastructure on this Z" check for other systems (see
 * piracy_beacon_active_on_z() below, used by the cargo order console to gate
 * the syndicate uplink terminal purchase).
 */

/obj/structure/machinery/piracy_beacon
	name = "piracy beacon"
	desc = "A crude, unlicensed anchor beacon favored by pirates. Only functions in unregulated space."
	icon = 'icons/obj/machinery/telecomms.dmi'
	icon_state = "bspacerelay"
	anchored = TRUE // permanent once assembled -- matches the existing deployable_kit/surgery_table
	                // precedent ("cannot be put together again after being unfolded"), no wrench/move path
	density = FALSE
	layer = OBJ_LAYER
	maxhealth = OBJECT_HEALTH_HIGH
	color = "#996633" // rusty/pirate tint -- distinct from the faction beacon's default and the hub beacon's blue

	/// Manual on/off toggle -- spawns off like the faction beacon.
	var/powered = FALSE
	/// Manual, independent of powered/is_operational() -- whether this Z's
	/// turfs/objects are currently registered for persistence (and, while
	/// tethered, shielded from gunnery bombardment). A beacon can be fully
	/// wrenched down and powered while untethered, or tethered while
	/// unpowered/dormant -- the two states don't imply each other.
	var/tethered = FALSE
	/// The faction currently claiming this Z through this beacon, or "" if
	/// unclaimed. Only has any effect while ALSO tethered -- see
	/// piracy_beacon_claimed_faction_on_z() -- so untethering silently makes
	/// an existing claim inert without needing to clear this var; re-tethering
	/// later resumes it with no need to re-tag. Set via the standard Faction
	/// Tagger interface (faction_tagger_compatible()/_get_uid()/_set() below),
	/// exactly like a real faction beacon.
	var/faction_uid = ""
	/// Sparks while operational, for a visible "this is online" tell.
	var/datum/effect_system/sparks/spark_system
	/// Looping hum while operational -- reuses the faction beacon's sound, no new asset needed.
	var/looping_sound_type = /datum/looping_sound/faction_beacon
	VAR_PRIVATE/datum/looping_sound/beacon_looping_sound
	/// Physical credit reserve -- see faction_beacon.dm's fuel_credits for the
	/// full design rationale. Drains only while is_operational() (powered AND
	/// in nullsec) -- a beacon that's powered but dormant in regulated space
	/// isn't "running" and shouldn't burn fuel.
	var/fuel_credits = 0
	var/max_fuel_credits = 50000
	var/next_fuel_drain_time = 0

/// Every piracy beacon that currently exists -- unlike faction_beacon_by_z this
/// isn't an exclusive per-Z claim, so it's just a flat registry.
GLOBAL_LIST_EMPTY(piracy_beacons)

/obj/structure/machinery/piracy_beacon/Initialize(mapload)
	. = ..()
	spark_system = bind_spark(src, 5)
	if(zone_security_get(GET_Z(src)) == ZONE_HIGHSEC)
		log_game("Piracy beacon at ([x],[y],[z]) could not be assembled -- highsec space.")
		return INITIALIZE_HINT_QDEL
	// Any Z a live mission is currently using (auto-generated for the
	// mission, or a dynamic/admin-placed site it's reusing) is meant to stay
	// uncontrolled infrastructure-free ground -- no piracy beacon either.
	if(is_active_mission_sector(GET_Z(src)))
		log_game("Piracy beacon at ([x],[y],[z]) could not be assembled -- mission sector.")
		return INITIALIZE_HINT_QDEL
	if(is_asteroid_zone(GET_Z(src)))
		log_game("Piracy beacon at ([x],[y],[z]) could not be assembled -- asteroid.")
		return INITIALIZE_HINT_QDEL
	GLOB.piracy_beacons += src

/obj/structure/machinery/piracy_beacon/Destroy()
	if(tethered)
		tethered = FALSE
		_apply_tether_state()
	GLOB.piracy_beacons -= src
	QDEL_NULL(beacon_looping_sound)
	qdel(spark_system)
	spark_system = null
	return ..()

/obj/structure/machinery/piracy_beacon/process()
	if(!is_operational())
		return
	if(prob(15))
		spark_system.queue()
	if(world.time >= next_fuel_drain_time)
		next_fuel_drain_time = world.time + BEACON_FUEL_DRAIN_INTERVAL
		fuel_credits = max(0, fuel_credits - BEACON_FUEL_DRAIN_AMOUNT)
		if(fuel_credits <= 0)
			_fuel_depleted()

/obj/structure/machinery/piracy_beacon/proc/_fuel_depleted()
	powered = FALSE
	QDEL_NULL(beacon_looping_sound)
	update_icon()
	visible_message(SPAN_WARNING("\The [src] sputters and powers down -- out of credits."))
	log_game("Piracy beacon at ([x],[y],[z]) auto-powered off -- ran out of fuel credits.")

/// TRUE only while powered AND this Z-level is genuinely nullsec AND not a
/// Z a live mission is currently using (is_active_mission_sector()) --
/// medsec/highsec, or an active mission sector, leave the beacon dormant
/// even if it's powered on. Computed live (not cached) so it always
/// reflects the current state, including changes made by an unrelated
/// faction/hub beacon claiming this Z later, or a mission claiming/
/// releasing it.
/obj/structure/machinery/piracy_beacon/proc/is_operational()
	return powered && zone_security_get(GET_Z(src)) == ZONE_NULLSEC && !is_active_mission_sector(GET_Z(src))

/obj/structure/machinery/piracy_beacon/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	ui_interact(user)

/obj/structure/machinery/piracy_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PiracyBeacon", "Piracy Beacon")
		ui.open()

/obj/structure/machinery/piracy_beacon/ui_data(mob/user)
	var/list/data = list()
	data["powered"] = powered
	data["operational"] = is_operational()
	data["tethered"] = tethered
	data["fuel_credits"] = fuel_credits
	data["max_fuel_credits"] = max_fuel_credits
	data["founding_cost"] = PIRATE_FACTION_FOUNDING_COST
	data["claimed_faction_name"] = faction_uid ? get_faction_name(faction_uid) : null
	return data

/obj/structure/machinery/piracy_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(action == "toggle_power")
		_toggle_power(usr)
		. = TRUE
	else if(action == "toggle_tether")
		_toggle_tether(usr)
		. = TRUE
	else if(action == "found_faction")
		_found_faction_flow(usr)
		. = TRUE

/// Instant pirate-faction founding, paid in physical spacecash held in the
/// user's active hand (never an ewallet -- matches attackby()'s own
/// fuel-feed exclusion, keeps this off any bank record). Prompts for
/// uid/name/abbreviation the same sequential way faction_manage.dm's own
/// "start_founding" action does, then re-validates everything (held cash
/// included) before actually charging or creating anything, since the user
/// could have dropped the cash or someone else could have taken the uid
/// while they were typing.
/obj/structure/machinery/piracy_beacon/proc/_found_faction_flow(mob/user)
	var/obj/item/spacecash/cash = user.get_active_hand()
	if(!istype(cash) || istype(cash, /obj/item/spacecash/ewallet) || cash.worth < PIRATE_FACTION_FOUNDING_COST)
		to_chat(user, SPAN_WARNING("You need [PIRATE_FACTION_FOUNDING_COST] credits in hand, held as physical cash (not an ewallet), to found a pirate faction here."))
		return

	var/uid_raw = tgui_input_text(user, "Faction network UID (lowercase, underscores for spaces):", "Found Pirate Faction", max_length = 64)
	if(!uid_raw)
		return
	var/uid = normalize_faction_uid(uid_raw)
	if(!uid)
		return
	if(islist(GLOB.persistence_faction_cache) && (uid in GLOB.persistence_faction_cache))
		to_chat(user, SPAN_WARNING("This network is already registered to a faction."))
		return

	var/name = tgui_input_text(user, "Full faction name:", "Found Pirate Faction", max_length = 64)
	if(!name)
		return
	name = lowertext(name)
	if(islist(GLOB.persistence_faction_cache))
		for(var/existing_uid in GLOB.persistence_faction_cache)
			var/list/existing = GLOB.persistence_faction_cache[existing_uid]
			if(lowertext(existing["name"]) == name)
				to_chat(user, SPAN_WARNING("A faction named '[name]' already exists."))
				return

	var/abbr = tgui_input_text(user, "Abbreviation (2-4 letters):", "Found Pirate Faction", max_length = 8)
	if(!abbr)
		return

	// Re-validate after the async prompts -- mirrors faction_manage.dm's own
	// "start_founding" re-check.
	cash = user.get_active_hand()
	if(!istype(cash) || istype(cash, /obj/item/spacecash/ewallet) || cash.worth < PIRATE_FACTION_FOUNDING_COST)
		to_chat(user, SPAN_WARNING("You no longer have [PIRATE_FACTION_FOUNDING_COST] credits in hand."))
		return
	if(islist(GLOB.persistence_faction_cache) && (uid in GLOB.persistence_faction_cache))
		to_chat(user, SPAN_WARNING("This network was registered by someone else while you were typing."))
		return

	var/refusal = SSpersistence.piracyBeaconFoundFaction(user, name, abbr, uid)
	if(refusal)
		to_chat(user, SPAN_WARNING(refusal))
		return

	if(cash.worth <= PIRATE_FACTION_FOUNDING_COST)
		qdel(cash)
	else
		cash.worth -= PIRATE_FACTION_FOUNDING_COST
		cash.update_icon()

/obj/structure/machinery/piracy_beacon/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, /obj/item/spacecash) && !istype(attacking_item, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/cash = attacking_item
		if(fuel_credits + cash.worth > max_fuel_credits)
			to_chat(user, SPAN_WARNING("\The [src] can't hold that much more -- [max_fuel_credits - fuel_credits] credits of space left."))
			return TRUE
		fuel_credits += cash.worth
		user.visible_message(SPAN_NOTICE("[user] feeds \the [cash] into \the [src]."), \
			SPAN_NOTICE("You feed [cash.worth] credits into \the [src]. Reserve: [fuel_credits]/[max_fuel_credits]."))
		qdel(cash)
		return TRUE
	return ..()

/obj/structure/machinery/piracy_beacon/AltClick(mob/user)
	if(!Adjacent(user))
		return
	if(!fuel_credits)
		to_chat(user, SPAN_WARNING("\The [src] has no stored credits."))
		return
	var/amount = tgui_input_number(user, "How many credits do you want to withdraw? (0 to [fuel_credits])", "Withdraw Fuel", 0, fuel_credits, 0)
	if(!amount)
		return
	amount = min(amount, fuel_credits)
	fuel_credits -= amount
	var/obj/item/spacecash/bundle/cash = new(get_turf(src))
	cash.worth += amount
	cash.update_icon()
	to_chat(user, SPAN_GOOD("Withdrew [amount] credits."))
	log_game("[key_name(user)] withdrew [amount] fuel credits from a piracy beacon at ([x],[y],[z]).")

/obj/structure/machinery/piracy_beacon/proc/_toggle_power(mob/user)
	powered = !powered
	if(is_operational())
		_go_operational()
		to_chat(user, SPAN_GOOD("\The [src] powers up and syncs with the local unregulated space."))
	else
		QDEL_NULL(beacon_looping_sound)
		if(powered)
			if(is_active_mission_sector(GET_Z(src)))
				to_chat(user, SPAN_WARNING("\The [src] powers up, but this sector is reserved for an active mission -- it stays dormant."))
			else
				to_chat(user, SPAN_WARNING("\The [src] powers up, but [zone_security_name(zone_security_get(GET_Z(src)))] space is too tightly regulated -- it stays dormant."))
		else
			to_chat(user, SPAN_WARNING("\The [src] powers down."))
	update_icon()

/// Shared "just became operational" side effects -- looping sound + Z
/// pin -- called from both the manual toggle and worldstate restore.
/obj/structure/machinery/piracy_beacon/proc/_go_operational()
	try
		if(!beacon_looping_sound)
			beacon_looping_sound = new looping_sound_type(src)
			beacon_looping_sound.start()
	catch(var/exception/tell_e)
		log_subsystem_persistence_error("Piracy beacon: online tell failed: [tell_e]")
	persistence_pin_site_at_z(GET_Z(src), "Piracy beacon at ([x],[y],[z])")

/obj/structure/machinery/piracy_beacon/proc/_toggle_tether(mob/user)
	tethered = !tethered
	_apply_tether_state()
	if(tethered)
		to_chat(user, SPAN_GOOD("\The [src] tethers to this Z -- its contents will now survive a restart."))
	else
		to_chat(user, SPAN_WARNING("\The [src] untethers from this Z."))

/// Shared tether side effects -- called from the manual toggle and both
/// restore paths, mirroring _go_operational()'s dual-use role. Registering
/// is always safe to repeat (setZLevelPersistence is a plain on/off switch).
/// Releasing is NOT always safe to repeat blindly -- another piracy beacon
/// on the same Z may still be tethered, or a faction beacon may separately
/// own this Z's own persistence registration -- so release only fires once
/// nothing else on this Z still needs it.
/obj/structure/machinery/piracy_beacon/proc/_apply_tether_state()
	var/z = GET_Z(src)
	if(tethered)
		SSpersistence.setZLevelPersistence(z, 1, "Piracy beacon (tethered) at ([x],[y],[z])")
	else if(!piracy_beacon_tethered_on_z(z) && !GLOB.faction_beacon_by_z["[z]"])
		SSpersistence.setZLevelPersistence(z, 0, "Piracy beacon (untethered) at ([x],[y],[z])")

// ------- Faction tagger compatibility (territory claim, see the top-of-file doc comment) -------

/obj/structure/machinery/piracy_beacon/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/piracy_beacon/faction_tagger_get_uid()
	return faction_uid

/obj/structure/machinery/piracy_beacon/faction_tagger_set(new_uid, mob/user)
	if(!new_uid)
		faction_uid = ""
		update_icon()
		return TRUE
	var/refusal = _claim_refusal_reason()
	if(refusal)
		if(user)
			to_chat(user, SPAN_WARNING("Cannot claim: [refusal]."))
		return FALSE
	faction_uid = new_uid
	update_icon()
	return TRUE

/// Deliberately much narrower than faction_beacon.dm's own
/// _claim_refusal_reason() -- no anchored check (piracy beacons are always
/// anchored once assembled), no zone-tier/security-radius/mission/asteroid
/// checks (this claim never touches zone security at all, so none of that
/// applies), no hub concept. Just: must be tethered (the piracy-beacon
/// equivalent of "anchored && powered" for a real beacon claim), and this Z
/// can't already be under a DIFFERENT claim -- either another faction's
/// pirate claim, or a real faction beacon (see the symmetric check
/// faction_beacon.dm's own _claim_refusal_reason() gained alongside this).
/obj/structure/machinery/piracy_beacon/proc/_claim_refusal_reason()
	if(!tethered)
		return "not tethered -- tether it first"
	var/z = GET_Z(src)
	var/existing = piracy_beacon_claimed_faction_on_z(z)
	if(existing && existing != faction_uid)
		return "this Z is already claimed by [get_faction_name(existing)]"
	if(GLOB.faction_beacon_by_z["[z]"])
		return "this Z is already claimed by a faction beacon"
	return null

/// worldstate hooks -- piracy_beacon previously had no persistence at
/// all, so powered silently reset to FALSE every restart. Skips saving a
/// row entirely when off with nothing stored (nothing worth restoring),
/// matching faction_beacon's own convention -- but an off beacon still
/// holding fuel credits must still be saved, or the reserve would be lost.
/obj/structure/machinery/piracy_beacon/worldstate_get_content()
	if(!powered && !fuel_credits && !tethered && !faction_uid)
		return list()
	return list("powered" = powered, "fuel_credits" = fuel_credits, "tethered" = tethered, "faction_uid" = faction_uid)

/obj/structure/machinery/piracy_beacon/worldstate_apply_content(list/content)
	powered = isnull(content["powered"]) ? FALSE : !!content["powered"]
	fuel_credits = isnull(content["fuel_credits"]) ? 0 : between(0, text2num(content["fuel_credits"]), max_fuel_credits)
	tethered = isnull(content["tethered"]) ? FALSE : !!content["tethered"]
	faction_uid = isnull(content["faction_uid"]) ? "" : content["faction_uid"]
	if(powered && !fuel_credits)
		powered = FALSE // no fuel -- don't silently restore as running
	if(is_operational())
		_go_operational()
	if(tethered)
		_apply_tether_state()
	update_icon()

/// Mirrors worldstate_get_content()/worldstate_apply_content() exactly --
/// see faction_beacon.dm's matching overrides for why non-mapload beacons
/// need this second path too (tracked-objects persistence, not worldstate).
/obj/structure/machinery/piracy_beacon/persistent_objects_get_content()
	var/list/content = ..()
	if(!powered && !fuel_credits && !tethered && !faction_uid)
		return content
	content["powered"] = powered
	content["fuel_credits"] = fuel_credits
	content["tethered"] = tethered
	content["faction_uid"] = faction_uid
	return content

/obj/structure/machinery/piracy_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["powered"]))      powered      = !!content["powered"]
	if(!isnull(content["fuel_credits"])) fuel_credits = between(0, text2num(content["fuel_credits"]), max_fuel_credits)
	if(!isnull(content["tethered"]))     tethered     = !!content["tethered"]
	if(!isnull(content["faction_uid"]))  faction_uid  = content["faction_uid"]
	if(powered && !fuel_credits)
		powered = FALSE
	if(is_operational())
		_go_operational()
	if(tethered)
		_apply_tether_state()
	update_icon()

/obj/structure/machinery/piracy_beacon/update_icon()
	icon_state = "bspacerelay"
	if(is_operational())
		set_light(2, 1, COLOR_ORANGE)
	else
		set_light(0)

/// TRUE if any operational piracy beacon exists on Z -- what the cargo order
/// console checks to decide whether to expose the syndicate uplink terminal.
/proc/piracy_beacon_active_on_z(z)
	for(var/obj/structure/machinery/piracy_beacon/P in GLOB.piracy_beacons)
		if(GET_Z(P) == z && P.is_operational())
			return TRUE
	return FALSE

/// TRUE if ANY piracy beacon (regardless of current power state) sits on Z --
/// used to keep missions (persistence_missions.dm's find_mission_sector())
/// from ever targeting a live pirate base, even one that's temporarily
/// unpowered/out of fuel.
/proc/piracy_beacon_present_on_z(z)
	for(var/obj/structure/machinery/piracy_beacon/P in GLOB.piracy_beacons)
		if(GET_Z(P) == z)
			return TRUE
	return FALSE

/// TRUE if any piracy beacon on Z is currently tethered -- independent of
/// power/is_operational(), see the tethered var's own doc comment. Used both
/// to decide whether a beacon's own untether is actually safe to release
/// persistence for (_apply_tether_state()) and by site_bombardment_protected()
/// (persistence_zone_security.dm) to shield a tethered Z from gunnery.
/proc/piracy_beacon_tethered_on_z(z)
	for(var/obj/structure/machinery/piracy_beacon/P in GLOB.piracy_beacons)
		if(GET_Z(P) == z && P.tethered)
			return TRUE
	return FALSE

/// Returns the faction_uid claiming Z through a tethered, faction-tagged
/// piracy beacon, or null if none. Live scan, no registry to keep in sync --
/// a claim is simply the live fact "tethered AND faction-tagged right now",
/// so untethering (or clearing the tag) silently and immediately drops the
/// claim's effect with no explicit release step needed. Consulted by
/// site_bombardment_protected() (persistence_zone_security.dm) and
/// _faction_raid_blocked_for() (telepad_drydock_boarding.dm) as an
/// alternative to a real faction beacon's own GLOB.faction_beacon_by_z claim
/// -- deliberately never touches zone security or the overmap, see the
/// top-of-file doc comment.
/proc/piracy_beacon_claimed_faction_on_z(z)
	for(var/obj/structure/machinery/piracy_beacon/P in GLOB.piracy_beacons)
		if(GET_Z(P) == z && P.tethered && P.faction_uid)
			return P.faction_uid
	return null
