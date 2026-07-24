/*
 * Pod save persistence -- opts into the generic tracked-object system
 * (code/game/objects/objs.dm's persistent_objects_track_active/
 * persistent_objects_get_content()/persistent_objects_apply_content(),
 * registered via SSpersistence.objectsRegisterTrack() in pod.dm's
 * Initialize()), not the shuttle/ship-ledger system
 * (persistence_shuttles.dm) -- that one's built for multi-tile purchased
 * ships (Z-allocation, docking, crew lists), not a single free-floating
 * vehicle.
 *
 * Like every other type on this system, this is a curated field whitelist,
 * not automatic full-state serialization -- see /obj/item/tank's own real
 * override (tanks.dm:72-88), which engine.dm's fuel_tank persistence below
 * delegates to directly rather than reimplementing gas serialization.
 */
/obj/vehicle/bike/pod/persistent_objects_get_content()
	var/list/content = ..()
	content["name"] = name
	content["health"] = health
	content["on"] = on
	content["locked"] = locked
	content["owner_name"] = owner_name
	content["owner_faction"] = owner_faction

	var/list/parts = list()
	for(var/slot in installed_parts)
		var/obj/item/podcomponent/P = installed_parts[slot]
		if(!P)
			continue
		parts[slot] = list(
			"type" = "[P.type]",
			"active" = P.active,
			"disrupted" = P.disrupted,
			"content" = P.persistent_objects_get_content(),
		)
	content["parts"] = json_encode(parts)
	return content

/**
 * Parts are restored (via install_part()) before locked/owner_name/
 * owner_faction are applied -- install_part() refuses outright on a locked
 * pod (see pod.dm), so restoring lock state first would leave every saved
 * part unable to reinstall itself.
 */
/obj/vehicle/bike/pod/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(content["name"])
		name = content["name"]
	if(!isnull(content["health"]))
		health = text2num(content["health"])

	var/list/parts = json_decode(content["parts"])
	if(islist(parts))
		for(var/slot in parts)
			var/list/part_data = parts[slot]
			var/part_type = text2path(part_data["type"])
			if(!part_type)
				continue
			var/obj/item/podcomponent/P = new part_type(src)
			if(!install_part(null, P, eject_existing = FALSE))
				qdel(P)
				continue
			if(part_data["content"])
				P.persistent_objects_apply_content(part_data["content"], null, null, null)
			P.active = part_data["active"] ? TRUE : FALSE
			P.disrupted = part_data["disrupted"] ? TRUE : FALSE

	if(content["on"])
		turn_on()
	locked = content["locked"] ? TRUE : FALSE
	owner_name = content["owner_name"]
	owner_faction = content["owner_faction"]
