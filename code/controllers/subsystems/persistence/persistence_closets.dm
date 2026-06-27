/*
 * Persistence - Closet/Locker Contents
 * Saves and restores the item contents and state of map-placed closets/lockers
 * across server restarts via the worldstate system.
 *
 * Uses the same ss13_worldstate_objects table as machinery worldstate, keyed by
 * (type, x, y, z). Closet contents are serialized using serializePersistentItem()
 * from persistence_mobs.dm.
 *
 * Note: only items (/obj/item) inside closets are serialized; mobs, structures,
 * and other non-item contents are intentionally omitted.
 */

/obj/structure/closet/worldstate_get_content()
	var/list/items = list()
	for(var/obj/item/I in src)
		var/list/data = serializePersistentItem(I)
		if(data)
			items += list(data)
	// Always return content so closet state (locked/welded/open + items) is preserved.
	// worldstateSaveOneMachine skips only if length == 0, so return non-empty even for
	// empty-but-locked lockers.
	var/list/content = list(
		"opened" = opened,
		"locked" = locked,
		"welded" = welded
	)
	if(length(items))
		content["items"] = json_encode(items)
	// Skip saving entirely if closet is in its default resting state with no items
	if(!opened && !locked && !welded && !length(items))
		return list()
	return content

/obj/structure/closet/worldstate_apply_content(list/content)
	// Clear any default map-placed contents before restoring saved state
	for(var/atom/movable/AM in src)
		if(istype(AM, /obj/item))
			qdel(AM)

	// Restore items
	if(content["items"])
		var/list/items = json_decode(content["items"])
		for(var/list/item_data in items)
			try
				deserializePersistentItem(item_data, src)
			catch(var/exception/closet_e)
				log_subsystem_persistence_error("Closets: Failed to restore item in [src] at [get_turf(src)]: [closet_e]")

	// Restore closet state  set vars directly, NOT via open()/close() which call
	// dump_contents() and eject the items we just restored inside the closet.
	welded = content["welded"] ? TRUE : FALSE
	locked = content["locked"] ? TRUE : FALSE
	opened = content["opened"] ? TRUE : FALSE
	if(!opened)
		density = TRUE  // closed closets are dense
	else if(!dense_when_open)
		density = FALSE
	update_icon()
