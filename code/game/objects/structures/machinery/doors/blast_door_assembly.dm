/obj/structure/blast_door_assembly
	name = "blast door assembly"
	desc = "A blast door assembly."
	// Same generic under-construction door frame every airlock assembly
	// uses (door_assembly.dm) -- blast doors have no assembly-stage art of
	// their own (they were never buildable before), and this generic frame
	// is exactly what an assembly for any door type mid-build should look
	// like anyway.
	icon = 'icons/obj/doors/basic/single/generic/door.dmi'
	icon_state = "construction_new"
	anchored = 0
	opacity = 0
	density = 1
	build_amt = 4
	var/wired = 0
	/// Final door type this assembly finishes into -- see the /shutter
	/// subtype below.
	var/door_type = /obj/structure/machinery/door/blast/regular

/obj/structure/blast_door_assembly/shutter
	name = "shutter assembly"
	desc = "A shutter assembly."
	door_type = /obj/structure/machinery/door/blast/shutters

/obj/structure/blast_door_assembly/update_icon()
	if(wired)
		icon_state = "construction_wired"
	else if(anchored)
		icon_state = "construction_anchored"
	else
		icon_state = "construction_new"

/obj/structure/blast_door_assembly/attackby(obj/item/attacking_item, mob/user)
	if(attacking_item.tool_behaviour == TOOL_CABLECOIL && !wired && anchored)
		var/obj/item/stack/cable_coil/cable = attacking_item
		if (cable.get_amount() < 1)
			to_chat(user, SPAN_WARNING("You need one length of coil to wire \the [src]."))
			return TRUE
		user.visible_message("[user] wires \the [src].", "You start to wire \the [src].")
		if(do_after(user, 4 SECONDS, src, DO_REPAIR_CONSTRUCT) && !wired && anchored)
			if (cable.use(1))
				wired = 1
				to_chat(user, SPAN_NOTICE("You wire \the [src]."))
				update_icon()
		return TRUE
	else if(attacking_item.tool_behaviour == TOOL_WIRECUTTER && wired)
		user.visible_message("[user] cuts the wires from \the [src].", "You start to cut the wires from \the [src].")

		if(attacking_item.use_tool(src, user, 40, volume = 50))
			if(!src) return
			to_chat(user, SPAN_NOTICE("You cut the wires!"))
			new/obj/item/stack/cable_coil(src.loc, 1)
			wired = 0
			update_icon()
		return TRUE
	// No electronics/circuit step -- blast doors have no ID-scanning or
	// access-config concept at all (see blast_door.dm's own doc comment:
	// "they lack any ID scanning system, they just handle remote control
	// signals"), so wiring it and welding the plating shut is the whole
	// finishing step, unlike airlocks/firedoors which need a circuit insert.
	else if(attacking_item.tool_behaviour == TOOL_WELDER && wired && anchored)
		var/obj/item/weldingtool/WT = attacking_item
		if(WT.use(0, user))
			user.visible_message(SPAN_WARNING("[user] welds \the [src] shut."),
				"You start to weld \the [src] shut.")
			if(attacking_item.use_tool(src, user, 40, volume = 50))
				if(!src || !WT.isOn()) return
				playsound(src.loc, 'sound/items/Deconstruct.ogg', 50, 1)
				user.visible_message(SPAN_WARNING("[user] finishes \the [src]!"),
					"You finish \the [src]!")
				// dir = NORTH is the blast door base class's own default
				// (blast_door.dm) -- copy the assembly's own dir across, or a
				// correctly-oriented assembly's facing (set at build time by
				// Produce(), stack.dm) is silently discarded, same fix
				// already applied to firedoors (firedoor_assembly.dm).
				var/obj/structure/machinery/door/blast/new_door = new door_type(src.loc)
				new_door.dir = dir
				qdel(src)
		else
			to_chat(user, SPAN_NOTICE("You need more welding fuel."))
		return TRUE
	else if(attacking_item.tool_behaviour == TOOL_WRENCH)
		anchored = !anchored
		attacking_item.play_tool_sound(get_turf(src), 50)
		user.visible_message(SPAN_WARNING("[user] has [anchored ? "" : "un" ]secured \the [src]!"),
								"You have [anchored ? "" : "un" ]secured \the [src]!")
		update_icon()
		return TRUE
	else if(!anchored && !wired && attacking_item.tool_behaviour == TOOL_WELDER)
		var/obj/item/weldingtool/WT = attacking_item
		if(WT.use(0, user))
			user.visible_message(SPAN_WARNING("[user] dissassembles \the [src]."),
			"You start to dissassemble \the [src].")
			if(attacking_item.use_tool(src, user, 40, volume = 50))
				if(!src || !WT.isOn()) return
				user.visible_message(SPAN_WARNING("[user] has dissassembled \the [src]."),
									"You have dissassembled \the [src].")
				new /obj/item/stack/material/steel(src.loc, 2)
				qdel(src)
		else
			to_chat(user, SPAN_NOTICE("You need more welding fuel."))
		return TRUE
	else
		return ..()
