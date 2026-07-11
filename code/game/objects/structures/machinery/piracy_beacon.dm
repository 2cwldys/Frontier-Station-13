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
	if(is_operational() && prob(15))
		spark_system.queue()

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

/obj/structure/machinery/piracy_beacon/proc/_toggle_power(mob/user)
	powered = !powered
	if(is_operational())
		try
			if(!beacon_looping_sound)
				beacon_looping_sound = new looping_sound_type(src)
				beacon_looping_sound.start()
		catch(var/exception/tell_e)
			log_subsystem_persistence_error("Piracy beacon: online tell failed: [tell_e]")
		persistence_pin_site_at_z(GET_Z(src), "Piracy beacon at ([x],[y],[z])")
		to_chat(user, SPAN_GOOD("\The [src] powers up and syncs with the local unregulated space."))
	else
		QDEL_NULL(beacon_looping_sound)
		if(powered)
			to_chat(user, SPAN_WARNING("\The [src] powers up, but [zone_security_name(zone_security_get(GET_Z(src)))] space is too tightly regulated -- it stays dormant."))
		else
			to_chat(user, SPAN_WARNING("\The [src] powers down."))
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
