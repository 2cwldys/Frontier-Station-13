//Engine control and monitoring console

/obj/structure/machinery/computer/ship/engines
	name = "engine control console"
	icon_screen = "enginecontrol"
	icon_keyboard = "cyan_key"
	icon_keyboard_emis = "cyan_key_mask"
	light_color = LIGHT_COLOR_CYAN
	circuit = /obj/item/circuitboard/ship/engines
	var/display_state = "status"

/obj/structure/machinery/computer/ship/engines/cockpit
	density = FALSE
	icon = 'icons/obj/cockpit_console.dmi'
	icon_state = "right"
	icon_screen = "engine"
	icon_keyboard = null
	circuit = null

/obj/structure/machinery/computer/ship/engines/terminal
	name = "engine control terminal"
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "engines"
	icon_keyboard = "tech_key"
	icon_keyboard_emis = "tech_key_mask"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1

/// Cargo-orderable variant a player can build into their own commissioned
/// hull (ship_commissioning_console.dm) -- unlike the mapped-in base type
/// above (always pre-anchored), this one starts loose like every other kit
/// part and needs a wrench first. Required at commission time
/// (_drydockCommissionRun(), persistence_shuttles.dm) -- without one,
/// engines_state has no way to ever become true, so a fuelled, helmed,
/// propulsion-equipped hull still can't move at all.
/obj/structure/machinery/computer/ship/engines/terminal/buildable
	anchored = FALSE

/obj/structure/machinery/computer/ship/engines/terminal/buildable/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Engine control terminal secured in place.") : SPAN_NOTICE("Engine control terminal unsecured."))
		return TRUE
	return ..(attacking_item, user, params)

/obj/structure/machinery/computer/ship/engines/ui_interact(mob/user, datum/tgui/ui)
	// `connected` is only ever set at Initialize() or a manual "sync" click and
	// goes stale across stash/unstash/retrieval/redelivery -- resync fresh
	// from GLOB.map_sectors before trusting it (see ship.dm's sync_linked()/
	// look() for the same reasoning).
	sync_linked()
	if(!connected)
		balloon_alert(user, "no connection!")
		return

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "EnginesControl", "[connected.get_real_name()] Engines Control")
		ui.open()

/obj/structure/machinery/computer/ship/engines/ui_data(mob/user)
	var/list/data = list()

	if(!connected)
		return

	data["state"] = display_state
	data["global_state"] = !!connected.engines_state
	data["global_limit"] = round(connected.thrust_limit * 100)
	data["tractored"] = !!connected.tractored_by
	// A landed/in-transit ship can't burn at all (can_burn()/burn(),
	// landable.dm, both refuse anything but SHIP_STATUS_OVERMAP), so the
	// power-on controls grey out instead of looking usable while docked.
	var/obj/effect/overmap/visitable/ship/landable/docked_check = connected
	data["docked"] = istype(docked_check) && docked_check.status != SHIP_STATUS_OVERMAP

	var/total_thrust = 0
	var/list/enginfo = list()

	for(var/datum/ship_engine/E in connected.engines)
		var/list/edata = list()
		edata["eng_type"] = E.name
		edata["eng_on"] = !!E.is_on()
		edata["eng_thrust"] = E.get_thrust() * 10
		edata["eng_thrust_limiter"] = round(E.get_thrust_limit() * 100)
		edata["eng_status"] = E.get_status()
		edata["eng_reference"] = "[REF(E)]"
		total_thrust += E.get_thrust()
		enginfo += list(edata)

	data["engines_info"] = enginfo
	data["total_thrust"] = total_thrust

	// Ship-level fuel reserve. The per-engine block above only ever reports
	// what each engine's own get_status() says, so a loaded fuel port was
	// invisible here: an ion engine has no fuel concept at all, and a gas
	// nozzle only mentions its own internal reservoir, never the tanks it can
	// draw from. Report the ship's fuel_ports directly instead
	// (refresh_fuel_ports_list(), overmap_shuttle.dm), so the crew can see what
	// is actually aboard regardless of which engine type is fitted.
	var/list/port_info = list()
	var/total_fuel = 0
	if(istype(connected, /obj/effect/overmap/visitable/ship/landable))
		var/obj/effect/overmap/visitable/ship/landable/landable_ship = connected
		var/datum/shuttle/autodock/overmap/fuel_shuttle = SSshuttle.shuttles[landable_ship.shuttle]
		if(istype(fuel_shuttle))
			for(var/obj/structure/FP in fuel_shuttle.fuel_ports)
				var/list/pdata = list()
				pdata["port_area"] = "[get_area(FP)]"
				var/obj/item/tank/FT = locate() in FP
				if(FT)
					var/moles = FT.air_contents.get_by_flag(XGM_GAS_FUEL)
					pdata["tank"] = "[FT.name]"
					pdata["fuel"] = round(moles, 0.01)
					total_fuel += moles
				else
					pdata["tank"] = null
					pdata["fuel"] = 0
				port_info += list(pdata)
	data["fuel_ports"] = port_info
	data["total_fuel"] = round(total_fuel, 0.01)

	return data

/obj/structure/machinery/computer/ship/engines/ui_act(action, params)
	. = ..()
	if(.)
		return

	if(!connected)
		return FALSE

	if(use_check_and_message(usr))
		return FALSE

	if(connected.tractored_by)
		to_chat(usr, SPAN_WARNING("The engine controls are locked out -- a tractor beam has this ship pinned in place."))
		return FALSE

	switch(action)
		if("set_state")
			var/new_state = params["state"]
			if(new_state in list("status", "engines"))
				display_state = new_state
				return TRUE
			return FALSE

		if("global_toggle")
			connected.engines_state = !connected.engines_state
			for(var/datum/ship_engine/E in connected.engines)
				if(connected.engines_state == !E.is_on())
					E.toggle()
			return TRUE

		if("set_global_limit")
			var/newlim = tgui_input_number(usr, "Input the new thrust limit.", "Thrust Limit", connected.thrust_limit * 100, 100, 0)
			if(isnull(newlim))
				return FALSE

			connected.thrust_limit = clamp(newlim / 100, 0, 1)
			for(var/datum/ship_engine/E in connected.engines)
				E.set_thrust_limit(connected.thrust_limit)
			return TRUE

		if("global_limit_delta")
			var/delta = text2num(params["delta"])
			connected.thrust_limit = round(clamp(connected.thrust_limit + delta, 0, 1),0.1)
			for(var/datum/ship_engine/E in connected.engines)
				E.set_thrust_limit(connected.thrust_limit)
			return TRUE

		if("engine_set_limit")
			var/datum/ship_engine/E = locate(params["engine"])
			if(!istype(E))
				return FALSE
			var/newlim = tgui_input_number(usr, "Input the new thrust limit.", "Thrust Limit", E.get_thrust_limit() * 100, 100, 0)
			if(isnull(newlim))
				return FALSE

			var/limit = clamp(newlim / 100, 0, 1)
			E.set_thrust_limit(limit)
			return TRUE

		if("engine_limit_delta")
			var/datum/ship_engine/E = locate(params["engine"])
			if(!istype(E))
				return FALSE

			var/delta = text2num(params["delta"])
			var/limit = clamp(E.get_thrust_limit() + delta, 0, 1)
			E.set_thrust_limit(limit)
			return TRUE

		if("engine_toggle")
			var/datum/ship_engine/E = locate(params["engine"])
			if(!istype(E))
				return FALSE

			E.toggle()
			return TRUE

	return FALSE
