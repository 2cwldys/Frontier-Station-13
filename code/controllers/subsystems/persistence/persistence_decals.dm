/*
 * Persistence - Cleanable Decals
 * Piggybacks on the existing ss13_persistent_objects system to save blood,
 * filth, graffiti, and other cleanable decals across rounds.
 *
 * No new SQL table required  uses existing persistent_objects infrastructure.
 * Decals auto-register via Initialize() when created during a live round on station levels.
 * The existing objectsInitialize() / objectsFinalize() handles DB load/save automatically.
 */

/// Days before a decal record is cleaned from the database
#define DECAL_PERSISTENCE_EXPIRY_DAYS 30

/obj/effect/decal/cleanable
	persistant_objects_expiration_time_days = DECAL_PERSISTENCE_EXPIRY_DAYS

/obj/effect/decal/cleanable/Initialize(mapload)
	. = ..()
	// Only register decals created during live play on station levels.
	// Restored decals (from objectsInitialize) are created before ROUND_IS_STARTED,
	// so they don't double-register here.
	if(!GLOB.config.sql_enabled || mapload || !ROUND_IS_STARTED)
		return
	// Blacklisted: blood, oil, gibs (transient combat mess), dirt (ambient grime), and
	// cum (Super Hug cap novelty decal, not meant to persist across rounds).
	if(istype(src, /obj/effect/decal/cleanable/blood))
		return
	if(istype(src, /obj/effect/decal/cleanable/dirt))
		return
	if(istype(src, /obj/effect/decal/cleanable/cum))
		return
	var/turf/T = get_turf(src)
	if(!T || !T.z)
		return
	if(persistence_area_excluded(T))
		return
	SSpersistence.objectsRegisterTrack(src)

/obj/effect/decal/cleanable/Destroy()
	if(persistent_objects_track_active)
		SSpersistence.objectsDeregisterTrack(src)
	return ..()

/obj/effect/decal/cleanable/persistent_objects_get_content()
	return list(
		"icon_state" = icon_state,
		"color"      = color,
		"name"       = name,
		"dir"        = dir,
		"layer"      = layer
	)

/obj/effect/decal/cleanable/persistent_objects_apply_content(list/content, x, y, z)
	icon_state = content["icon_state"]
	color      = content["color"]
	name       = content["name"]
	if(!isnull(content["dir"]))
		dir = text2num(content["dir"])
	if(!isnull(content["layer"]))
		layer = text2num(content["layer"])
	src.x = x
	src.y = y
	src.z = z

// Blood, oil, and gibs (/obj/effect/decal/cleanable/blood and all subtypes) are blacklisted.
// The Initialize guard above prevents them from being registered  no content hooks needed.
