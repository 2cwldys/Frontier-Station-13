/*
 * Cleanup Subsystem
 * Automatically removes lag-causing objects that accumulate in a continuous persistent world:
 * gibs, bullet casings, old blood decals, and excess trash.
 *
 * Fires every 20 minutes. Thresholds are tunable via defines.
 * Admin verb "Force Cleanup Sweep" triggers an immediate sweep.
 */

/// Maximum gibs allowed on station before oldest are deleted
#define MAX_GIBS_ON_STATION    400
/// Maximum bullet/shell casings allowed on station
#define MAX_CASINGS_ON_STATION 600
/// Maximum trash items allowed on station
#define MAX_TRASH_ON_STATION   300
/// Hours before a blood/oil/filth decal is eligible for age-based cleanup
#define BLOOD_DECAL_LIFETIME_HOURS 72

SUBSYSTEM_DEF(cleanup)
	name = "Cleanup"
	wait = 20 MINUTES
	flags = SS_NO_INIT

/datum/controller/subsystem/cleanup/fire()
	var/gibs_removed    = cleanupGibs()
	var/casings_removed = cleanupCasings()
	var/blood_removed   = cleanupOldBlood()
	var/trash_removed   = cleanupTrash()

	if(gibs_removed || casings_removed || blood_removed || trash_removed)
		log_game("Cleanup: Removed [gibs_removed] gibs, [casings_removed] casings, [blood_removed] old blood decals, [trash_removed] trash items.")

/**
 * Delete excess gibs when the station-wide count exceeds MAX_GIBS_ON_STATION.
 * Gibs have no timestamp, so excess are deleted in arbitrary order.
 * RETURN: number deleted.
 */
/datum/controller/subsystem/cleanup/proc/cleanupGibs()
	var/list/gibs = list()
	for(var/obj/effect/decal/cleanable/blood/gibs/G in world)
		if(!is_station_level(G.z))
			continue
		gibs += G
		CHECK_TICK

	var/over = length(gibs) - MAX_GIBS_ON_STATION
	if(over <= 0)
		return 0

	var/deleted = 0
	for(var/i = 1 to over)
		if(i > length(gibs))
			break
		qdel(gibs[i])
		deleted++
		CHECK_TICK
	return deleted

/**
 * Delete excess bullet/shell casings when over MAX_CASINGS_ON_STATION.
 * RETURN: number deleted.
 */
/datum/controller/subsystem/cleanup/proc/cleanupCasings()
	var/list/casings = list()
	for(var/obj/item/ammo_casing/C in world)
		if(!is_station_level(C.z))
			continue
		casings += C
		CHECK_TICK

	var/over = length(casings) - MAX_CASINGS_ON_STATION
	if(over <= 0)
		return 0

	var/deleted = 0
	for(var/i = 1 to over)
		if(i > length(casings))
			break
		qdel(casings[i])
		deleted++
		CHECK_TICK
	return deleted

/**
 * Delete cleanable blood/oil/filth decals older than BLOOD_DECAL_LIFETIME_HOURS.
 * Age is tracked via `creation_time` on each decal (set in Initialize).
 * RETURN: number deleted.
 */
/datum/controller/subsystem/cleanup/proc/cleanupOldBlood()
	var/cutoff = world.time - (BLOOD_DECAL_LIFETIME_HOURS * 600 * 10)
	var/deleted = 0
	for(var/obj/effect/decal/cleanable/D in world)
		if(!is_station_level(D.z))
			continue
		if(D.creation_time && D.creation_time < cutoff)
			qdel(D)
			deleted++
		CHECK_TICK
	return deleted

/**
 * Delete excess trash items when over MAX_TRASH_ON_STATION.
 * RETURN: number deleted.
 */
/datum/controller/subsystem/cleanup/proc/cleanupTrash()
	var/list/trash = list()
	for(var/obj/item/trash/T in world)
		if(!is_station_level(T.z))
			continue
		trash += T
		CHECK_TICK

	var/over = length(trash) - MAX_TRASH_ON_STATION
	if(over <= 0)
		return 0

	var/deleted = 0
	for(var/i = 1 to over)
		if(i > length(trash))
			break
		qdel(trash[i])
		deleted++
		CHECK_TICK
	return deleted

// ---- Admin verb ----

/datum/admins/proc/force_cleanup_sweep()
	set name = "Force Cleanup Sweep"
	set category = "Special Verbs"

	if(!check_rights(R_ADMIN))
		return

	var/gibs_removed    = SScleanup.cleanupGibs()
	var/casings_removed = SScleanup.cleanupCasings()
	var/blood_removed   = SScleanup.cleanupOldBlood()
	var/trash_removed   = SScleanup.cleanupTrash()

	var/msg = "Cleanup sweep complete: [gibs_removed] gibs, [casings_removed] casings, [blood_removed] old blood decals, [trash_removed] trash items removed."
	to_chat(usr, SPAN_GOOD(msg))
	log_and_message_admins("ran a manual cleanup sweep. [msg]", usr)

	feedback_add_details("admin_verb","FCS")
