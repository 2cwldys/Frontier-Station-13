/*
 * Pod cockpit -- a real tgui interface, replacing plain verbs (see
 * weapons.dm's now-deleted fire_main_weapon()). Follows cargo_train.dm's
 * confirmed pattern of a plain /obj/vehicle implementing
 * ui_interact()/ui_data()/ui_act() directly (no modular-computer program
 * framework). No ui_state() override needed: the pilot is always buckled to
 * the pod, so GLOB.default_state's adjacency check is satisfied for free,
 * same as cargo_train.dm/helm.dm/engine_control.dm.
 */
/obj/vehicle/bike/pod/attack_hand(mob/user)
	if(user == buckled)
		ui_interact(user)
		return
	if(passenger_attack_hand(user))
		return
	return ..()

/obj/vehicle/bike/pod/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PodCockpit", "[name] - Cockpit", 500, 600)
		ui.open()

/obj/vehicle/bike/pod/ui_data(mob/user)
	var/list/data = list()
	data["on"] = on
	data["locked"] = locked
	data["cell_charge"] = cell ? cell.percent() : null

	var/obj/item/podcomponent/engine/E = get_part(POD_PART_ENGINE)
	data["engine_fuel"] = (istype(E) && E.fuel_tank) ? round(E.fuel_tank.air_contents.get_by_flag(XGM_GAS_FUEL)) : null

	var/list/parts = list()
	for(var/slot in installed_parts)
		var/obj/item/podcomponent/P = installed_parts[slot]
		var/list/part_data = list(
			"slot" = slot,
			"name" = P ? P.name : null,
			"active" = P ? P.active : FALSE,
			"disrupted" = P ? P.disrupted : FALSE,
		)
		// Shield timing -- so the cockpit can show why/when it'll drop or
		// come back, instead of it just switching off with no explanation.
		if(istype(P, /obj/item/podcomponent/secondary/shielding))
			var/obj/item/podcomponent/secondary/shielding/Sh = P
			part_data["shield_active_remaining"] = Sh.active ? max(0, Sh.shield_active_until - world.time) : null
			part_data["shield_recharge_remaining"] = (!Sh.ready) ? max(0, Sh.shield_ready_at - world.time) : null
		parts += list(part_data)
	data["parts"] = parts

	var/obj/item/podcomponent/comms/C = get_part(POD_PART_COMMS)
	data["nav_available"] = istype(C) && C.active
	if(data["nav_available"])
		var/obj/item/podcomponent/engine/warp/W = get_part(POD_PART_ENGINE)
		if(istype(W))
			var/obj/effect/overmap/visitable/current = get_current_sector()
			data["current_sector"] = current?.name
			data["viewing_sector"] = (viewing_user == user)
			var/obj/effect/overmap/visitable/primed = get_primed_destination()
			data["primed_sector"] = primed ? list("name" = primed.name, "distance" = get_dist(current, primed)) : null
			data["jump_cooldown"] = max(0, W.last_jump + POD_JUMP_COOLDOWN - world.time)
			data["fuel_percent"] = W.fuel_tank ? round(100 * W.fuel_tank.air_contents.get_by_flag(XGM_GAS_FUEL) / max(POD_JUMP_FUEL_MOLES, 1)) : null

	var/obj/item/podcomponent/sensors/Sn = get_part(POD_PART_SENSORS)
	data["sensors_active"] = istype(Sn) && Sn.active

	return data

/obj/vehicle/bike/pod/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(usr != buckled)
		to_chat(usr, SPAN_WARNING("You're not piloting \the [src]."))
		return
	switch(action)
		if("toggle_engine")
			toggle_engine(usr)
			. = TRUE
		if("toggle_part")
			var/slot = params["slot"]
			// Engine has its own dedicated toggle (keeps pod.on in sync with
			// the installed part) -- see toggle_engine() above.
			if(slot == POD_PART_ENGINE)
				return
			var/obj/item/podcomponent/P = get_part(slot)
			if(istype(P))
				if(P.active)
					P.deactivate()
				else
					P.activate()
				. = TRUE
		if("fire_weapon")
			var/obj/item/podcomponent/mainweapon/W = get_part(POD_PART_MAIN_WEAPON)
			if(istype(W))
				W.Fire(usr)
				. = TRUE
		if("toggle_lock")
			locked = !locked
			to_chat(usr, SPAN_NOTICE("You [locked ? "lock" : "unlock"] \the [src]'s hatch."))
			. = TRUE
		if("open_cargo")
			var/obj/item/podcomponent/secondary/cargo/C = get_part(POD_PART_SECONDARY)
			if(istype(C) && C.hold)
				C.hold.open(usr)
				. = TRUE
		if("eject_fuel")
			var/obj/item/podcomponent/engine/E = get_part(POD_PART_ENGINE)
			if(istype(E))
				E.eject_fuel_tank(usr)
				. = TRUE
		if("eject_part")
			var/slot = params["slot"]
			if(get_part(slot))
				eject_part(usr, slot)
				. = TRUE
		if("toggle_sector_view")
			toggle_sector_view(usr)
			. = TRUE
		if("jump")
			var/obj/item/podcomponent/engine/warp/W = get_part(POD_PART_ENGINE)
			if(istype(W))
				W.attempt_jump(usr)
				. = TRUE
