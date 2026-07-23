/*
 * Pod engine -- the one working part for Phase 1. Runs on an inserted
 * phoron fuel tank (the same phoron-fuel model overmap_shuttle.dm's
 * exploration shuttles already use) rather than the pod's own inherited
 * /obj/vehicle cell -- ignition just requires the tank to have some fuel
 * left. warp.dm's jump-capable engine subtype reuses this same tank/attackby
 * for jump fuel too (drains a further fixed amount per jump on top of this).
 */
/obj/item/podcomponent/engine
	name = "pod engine"
	desc = "A compact drive engine for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "engine"
	power_used = 0

	/// The inserted phoron tank supplying power, if any.
	var/obj/item/tank/fuel_tank

/obj/item/podcomponent/engine/Destroy()
	QDEL_NULL(fuel_tank)
	return ..()

/obj/item/podcomponent/engine/get_slot()
	return POD_PART_ENGINE

/// Reachable both while the engine is a loose item in-hand AND once it's
/// installed in a pod -- pod.dm's own attackby() forwards unrecognized
/// items to the installed engine part specifically so this isn't a dead
/// end after installation.
/obj/item/podcomponent/engine/attackby(obj/item/attacking_item, mob/user)
	if(istype(attacking_item, /obj/item/tank))
		if(fuel_tank)
			to_chat(user, SPAN_WARNING("\The [src] already has a fuel tank installed."))
			return TRUE
		user.drop_from_inventory(attacking_item, src)
		fuel_tank = attacking_item
		to_chat(user, SPAN_NOTICE("You slot \the [attacking_item] into \the [src]."))
		return TRUE
	return ..()

/obj/item/podcomponent/engine/attack_hand(mob/user)
	if(fuel_tank && loc == user)
		eject_fuel_tank(user)
		return
	return ..()

/// Ejects the fuel tank (empty or not) into user's hands. Reachable both
/// while the engine is loose in-hand (attack_hand() above) and, via the
/// cockpit's "eject_fuel" action, once the engine is installed -- there was
/// previously no way to remove a tank at all once the engine was bolted in.
/obj/item/podcomponent/engine/proc/eject_fuel_tank(mob/user)
	if(!fuel_tank)
		return FALSE
	var/obj/item/tank/T = fuel_tank
	fuel_tank = null
	if(user)
		T.forceMove(get_turf(src))
		user.put_in_hands(T)
		to_chat(user, SPAN_NOTICE("You remove \the [T] from \the [src]."))
	else
		T.forceMove(get_turf(src))
	return TRUE

/obj/item/podcomponent/engine/activate(give_message = TRUE)
	if(!fuel_tank || fuel_tank.air_contents.get_by_flag(XGM_GAS_FUEL) <= 0)
		if(pod)
			pod.visible_message(SPAN_WARNING("\The [pod]'s engine sputters -- no fuel tank installed, or it's empty."))
		return FALSE
	return ..()

/// Delegates straight to fuel_tank's own real persistence override
/// (tanks.dm) for the gas mixture/temperature -- no need to reimplement gas
/// serialization here.
/obj/item/podcomponent/engine/persistent_objects_get_content()
	var/list/content = ..()
	if(fuel_tank)
		content["fuel_tank_type"] = "[fuel_tank.type]"
		content["fuel_tank_content"] = fuel_tank.persistent_objects_get_content()
	return content

/obj/item/podcomponent/engine/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content) || !content["fuel_tank_type"])
		return
	var/tank_type = text2path(content["fuel_tank_type"])
	if(!tank_type)
		return
	QDEL_NULL(fuel_tank)
	fuel_tank = new tank_type(src)
	if(content["fuel_tank_content"])
		fuel_tank.persistent_objects_apply_content(content["fuel_tank_content"], null, null, null)
