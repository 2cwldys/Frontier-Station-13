/*
 * Piracy Beacon
 * A crude, field-assembled beacon that only functions in unregulated
 * (nullsec) space -- unlike the faction/hub beacon, it never claims
 * territory, never sweeps machinery, and never touches zone security. It
 * exists purely as a live "is there piracy infrastructure on this Z" check
 * for other systems (see piracy_beacon_active_on_z() below, used by the
 * cargo order console to gate the syndicate uplink terminal purchase).
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
	GLOB.piracy_beacons += src

/obj/structure/machinery/piracy_beacon/Destroy()
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

/// TRUE only while powered AND this Z-level is genuinely nullsec -- medsec/highsec
/// leave the beacon dormant even if it's powered on. Computed live (not cached) so
/// it always reflects the current security tier, including changes made by an
/// unrelated faction/hub beacon claiming this Z later.
/obj/structure/machinery/piracy_beacon/proc/is_operational()
	return powered && zone_security_get(GET_Z(src)) == ZONE_NULLSEC

/obj/structure/machinery/piracy_beacon/attack_hand(mob/user)
	. = ..()
	if(.)
		return
	_toggle_power(user)

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

/// worldstate hooks -- piracy_beacon previously had no persistence at
/// all, so powered silently reset to FALSE every restart. Skips saving a
/// row entirely when off with nothing stored (nothing worth restoring),
/// matching faction_beacon's own convention -- but an off beacon still
/// holding fuel credits must still be saved, or the reserve would be lost.
/obj/structure/machinery/piracy_beacon/worldstate_get_content()
	if(!powered && !fuel_credits)
		return list()
	return list("powered" = powered, "fuel_credits" = fuel_credits)

/obj/structure/machinery/piracy_beacon/worldstate_apply_content(list/content)
	powered = isnull(content["powered"]) ? FALSE : !!content["powered"]
	fuel_credits = isnull(content["fuel_credits"]) ? 0 : between(0, text2num(content["fuel_credits"]), max_fuel_credits)
	if(powered && !fuel_credits)
		powered = FALSE // no fuel -- don't silently restore as running
	if(is_operational())
		_go_operational()
	update_icon()

/// Mirrors worldstate_get_content()/worldstate_apply_content() exactly --
/// see faction_beacon.dm's matching overrides for why non-mapload beacons
/// need this second path too (tracked-objects persistence, not worldstate).
/obj/structure/machinery/piracy_beacon/persistent_objects_get_content()
	var/list/content = ..()
	if(!powered && !fuel_credits)
		return content
	content["powered"] = powered
	content["fuel_credits"] = fuel_credits
	return content

/obj/structure/machinery/piracy_beacon/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["powered"]))      powered      = !!content["powered"]
	if(!isnull(content["fuel_credits"])) fuel_credits = between(0, text2num(content["fuel_credits"]), max_fuel_credits)
	if(powered && !fuel_credits)
		powered = FALSE
	if(is_operational())
		_go_operational()
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
