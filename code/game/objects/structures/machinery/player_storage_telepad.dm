/*
 * Player Storage Telepad
 *
 * Admin-placed machinery that serves as the destination for stored offline characters.
 * When a player uses "Store Character" or "Enter Cryopod" and their 60-second timer fires,
 * their mob is moved to the turf of the nearest registered telepad and placed in an
 * unconscious, non-blocking state until they reconnect.
 *
 * Persists across restarts via the worldstate blanket structure loop.
 * Admin-spawn one or more in a crew lounge, arrivals bay, or medical area.
 */
/obj/structure/machinery/player_storage_telepad
	name = "player storage telepad"
	desc = "A designated resting area for crew in cryogenic storage. Offline characters will appear here until their next login."
	icon = 'icons/obj/machinery/cryopod.dmi'
	icon_state = "body_vat_idle"
	anchored = TRUE
	density = FALSE  // Non-blocking so multiple stored mobs can share a pad

/obj/structure/machinery/player_storage_telepad/Initialize()
	. = ..()
	GLOB.player_storage_tepads += src

/obj/structure/machinery/player_storage_telepad/Destroy()
	GLOB.player_storage_tepads -= src
	return ..()

// Worldstate persistence — returning any non-null list marks this object for saving.
// The worldstate blanket /obj/structure loop handles save and restore automatically.
/obj/structure/machinery/player_storage_telepad/worldstate_get_content()
	return list("active" = TRUE)

/obj/structure/machinery/player_storage_telepad/worldstate_apply_content(list/content)
	return  // Nothing to configure — existence on the map is all that matters
