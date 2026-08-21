/**
 * Buildable, multitool-linkable remote door button -- controls any mix of
 * blast doors/shutters AND plain airlocks from one button ("functional
 * checkpoints").
 *
 * All of the actual linking logic (_link_door(), _link_airlock(),
 * _get_linked_doors(), _reset_links(), _can_link_faction_door(), the
 * multitool attackby() branch, and trigger() -- a combined toggle across
 * every linked door/airlock, no picker) lives on the parent
 * /obj/structure/machinery/button/remote/blast_door type (door_control.dm)
 * so every already-mapped button gets it too, not just a button built from
 * this frame. This subtype only adds the construction lifecycle (mirroring
 * /obj/structure/machinery/access_button, airlock_control.dm) and gates use
 * behind buildstage == 2 (fully wired).
 *
 * Blast door linking uses /obj/structure/machinery/door/blast's own `id`
 * field. Airlock linking uses a dedicated `door_button_tag` field
 * (airlock_control.dm) -- deliberately NOT `id_tag`, which is already
 * shared by the legacy remote button and the airlock cycler system; reusing
 * it here would desync a cycler-managed door's link the moment this button
 * linked it too. Both fields are just set to this button's own single `id`
 * string -- one button, one tag, matched against two different door-side
 * fields depending on door type.
 */
/obj/structure/machinery/button/remote/blast_door/buildable
	name = "door button"
	desc = "A remote control switch for airlocks, blast doors, and shutters."

	/// 2 = complete/wired, 1 = circuit inserted but unwired, 0 = frame only.
	/// Mirrors access_button's own buildstage shape (airlock_control.dm).
	var/buildstage = 2

/obj/structure/machinery/button/remote/blast_door/buildable/Initialize(mapload, var/dir, var/building = 0)
	. = ..()
	if(building)
		if(dir)
			set_dir(dir)
		apply_wall_mount_offset()
		buildstage = 0
		update_icon()

/obj/structure/machinery/button/remote/blast_door/buildable/persistence_reapply_wall_offset()
	apply_wall_mount_offset()

/obj/structure/machinery/button/remote/blast_door/buildable/persistent_objects_get_content()
	. = ..()
	.["buildstage"] = buildstage

/obj/structure/machinery/button/remote/blast_door/buildable/persistent_objects_apply_content(list/content, x, y, z)
	..()
	if(!islist(content))
		return
	if("buildstage" in content)
		buildstage = text2num(content["buildstage"])
	update_icon()

/obj/structure/machinery/button/remote/blast_door/buildable/update_icon()
	if(buildstage < 2)
		icon_state = "doorctrl-p"
	else
		..()

/obj/structure/machinery/button/remote/blast_door/buildable/attackby(obj/item/attacking_item, mob/user)
	if(_handle_construction(attacking_item, user))
		return TRUE
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return TRUE
	return ..()

/obj/structure/machinery/button/remote/blast_door/buildable/proc/_handle_construction(obj/item/attacking_item, mob/user)
	switch(buildstage)
		if(0)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				set_dir(turn(dir, -90))
				to_chat(user, SPAN_NOTICE("You rotate \the [src]."))
				return TRUE
			if(istype(attacking_item, /obj/item/blast_door_button_electronics))
				to_chat(user, SPAN_NOTICE("You insert the circuit board."))
				qdel(attacking_item)
				buildstage = 1
				update_icon()
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You remove \the [src] from the wall."))
				new /obj/item/frame/blast_door_button(get_turf(user))
				attacking_item.play_tool_sound(get_turf(src), 50)
				qdel(src)
				return TRUE
		if(1)
			if(attacking_item.tool_behaviour == TOOL_CABLECOIL)
				var/obj/item/stack/cable_coil/C = attacking_item
				if(C.use(5))
					to_chat(user, SPAN_NOTICE("You wire \the [src]."))
					buildstage = 2
					update_icon()
					if(GLOB.config.sql_enabled && GLOB.persistence_ready)
						SSpersistence.objectsRegisterTrack(src)
				else
					to_chat(user, SPAN_WARNING("You need 5 pieces of cable to wire \the [src]."))
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You pry out the circuit board."))
				new /obj/item/blast_door_button_electronics(get_turf(user))
				attacking_item.play_tool_sound(get_turf(src), 50)
				buildstage = 0
				update_icon()
				return TRUE
		if(2)
			if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
				to_chat(user, SPAN_NOTICE("You pry out the circuit board."))
				new /obj/item/blast_door_button_electronics(get_turf(user))
				buildstage = 1
				update_icon()
				return TRUE
	return FALSE

/// Only extra behavior needed on top of the parent's (door_control.dm)
/// combined toggle: refuse use entirely while still under construction.
/obj/structure/machinery/button/remote/blast_door/buildable/attack_hand(mob/user as mob)
	if(buildstage < 2)
		return
	return ..()

/**
 * Circuit board for the buildable blast door button, mirroring
 * airlock_cycler_electronics' own shape (airlock_control.dm).
 */
/obj/item/blast_door_button_electronics
	name = "blast door button electronics"
	desc = "A circuit board for a blast door button."
	icon = 'icons/obj/module.dmi'
	icon_state = "door_electronics"
	w_class = WEIGHT_CLASS_SMALL
	matter = list(DEFAULT_WALL_MATERIAL = 50, MATERIAL_GLASS = 50)
