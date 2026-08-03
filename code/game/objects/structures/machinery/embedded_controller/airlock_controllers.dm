//base type for controllers of two-door systems
/obj/structure/machinery/embedded_controller/radio/airlock
	obj_flags = OBJ_FLAG_MOVES_UNSUPPORTED
	// Setup parameters only
	radio_filter = RADIO_AIRLOCK
	var/tag_exterior_door
	var/tag_interior_door
	/// Primary chamber vent pump tag. Kept as a plain string for mapped-in
	/// cyclers, which set it directly in their .dmm.
	var/tag_airpump
	/// Additional chamber vent pump tags beyond tag_airpump. A chamber wide
	/// enough to need more than one vent gets one entry here per extra pump;
	/// every cycle command is issued to all of them together (see
	/// get_airpump_tags()).
	var/list/tag_airpumps
	var/tag_chamber_sensor
	var/tag_exterior_sensor
	var/tag_interior_sensor
	var/tag_airlock_mech_sensor
	var/tag_shuttle_mech_sensor
	var/tag_secure = FALSE
	var/tag_air_alarm
	var/cycle_to_external_air = FALSE
	var/has_interior_sensor
	var/has_exterior_sensor

/obj/structure/machinery/embedded_controller/radio/airlock/Initialize(mapload, given_id_tag, given_frequency, given_tag_exterior_door, given_tag_interior_door, given_tag_airpump, given_tag_chamber_sensor)
	. = ..()
	if(given_id_tag)
		id_tag = given_id_tag
	if(given_frequency)
		set_frequency(given_frequency)
	if(given_tag_exterior_door)
		tag_exterior_door = given_tag_exterior_door
	if(given_tag_interior_door)
		tag_interior_door = given_tag_interior_door
	if(given_tag_airpump)
		tag_airpump = given_tag_airpump
	if(given_tag_chamber_sensor)
		tag_chamber_sensor = given_tag_chamber_sensor
	program = new /datum/computer/file/embedded_program/airlock(src)

/obj/structure/machinery/embedded_controller/radio/airlock/attackby(obj/item/attacking_item, mob/user)
	//Swiping ID on the access button
	if (attacking_item.GetID())
		attack_hand(user)
		return TRUE
	return ..()

/obj/structure/machinery/embedded_controller/radio/airlock/attack_hand(mob/user)
	if(!allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return FALSE
	return ..()

//Advanced airlock controller for when you want a more versatile airlock controller - useful for turning simple access control rooms into airlocks
/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller
	name = "Advanced Airlock Controller"

/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockConsoleAdvanced", name, ui_x=470, ui_y=290)
		ui.open()

/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_data(mob/user)
	var/list/data = list()

	data["chamber_pressure"] = round(program.memory["chamber_sensor_pressure"])
	data["has_exterior_sensor"] = has_exterior_sensor
	data["external_pressure"] = round(program.memory["external_sensor_pressure"])
	data["has_interior_sensor"] = has_interior_sensor
	data["internal_pressure"] = round(program.memory["internal_sensor_pressure"])
	data["processing"] = program.memory["processing"]
	data["purge"] = program.memory["purge"]
	data["secure"] = program.memory["secure"]

	return data

/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "command")
		var/command_name = sanitize(params["command"])
		program.receive_user_command(command_name)

//Airlock controller for airlock control - most airlocks on the station use this
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller
	name = "Airlock Controller"
	tag_secure = TRUE

	/// 2 = complete/wired, 1 = circuit inserted but unwired, 0 = frame only.
	/// Player-built via /obj/item/frame/airlock_controller; mapped-in/preset
	/// controllers default to 2 (already finished).
	/// panel_open is inherited from base /obj/structure/machinery.
	var/buildstage = 2

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/Initialize(mapload, var/dir, var/building = 0)
	. = ..(mapload)
	if(building)
		if(dir)
			set_dir(dir)
		apply_wall_mount_offset()
		buildstage = 0
	update_icon()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/update_icon()
	if(buildstage < 2)
		ClearOverlays()
		return
	return ..()

/// Auto-assigns a unique id_tag the first time this controller is linked to
/// a door/sensor/button -- there's no in-game tool to type in a custom tag,
/// and a blank/null id_tag would make every untagged controller match every
/// other untagged device's blank slot.
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_ensure_id_tag()
	if(!id_tag)
		id_tag = "cycler_[REF(src)]"
	return id_tag

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/attackby(obj/item/attacking_item, mob/user)
	if(_handle_construction(attacking_item, user))
		return TRUE
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/door/airlock/door = MT.get_buffer(/obj/structure/machinery/door/airlock)
		if(door)
			door._link_to_controller(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/airlock_sensor/sensor = MT.get_buffer(/obj/structure/machinery/airlock_sensor)
		if(sensor)
			sensor._link_to_controller(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/access_button/button = MT.get_buffer(/obj/structure/machinery/access_button)
		if(button)
			button._link_to_controller(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/atmospherics/unary/vent_pump/pump = MT.get_buffer(/obj/structure/machinery/atmospherics/unary/vent_pump)
		if(pump)
			_link_to_airpump(pump, user)
			MT.set_buffer(null)
			return TRUE
		MT.set_buffer(src)
		to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
		return TRUE
	return ..()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_handle_construction(obj/item/attacking_item, mob/user)
	switch(buildstage)
		if(0)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				set_dir(turn(dir, -90))
				to_chat(user, SPAN_NOTICE("You rotate \the [src]."))
				return TRUE
			if(istype(attacking_item, /obj/item/airlock_cycler_electronics/airlock_controller))
				to_chat(user, SPAN_NOTICE("You insert the circuit board."))
				qdel(attacking_item)
				buildstage = 1
				update_icon()
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You remove \the [src] from the wall."))
				new /obj/item/frame/airlock_controller(get_turf(user))
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
				else
					to_chat(user, SPAN_WARNING("You need 5 pieces of cable to wire \the [src]."))
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You pry out the circuit board."))
				new /obj/item/airlock_cycler_electronics/airlock_controller(get_turf(user))
				attacking_item.play_tool_sound(get_turf(src), 50)
				buildstage = 0
				update_icon()
				return TRUE
		if(2)
			if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
				panel_open = !panel_open
				to_chat(user, SPAN_NOTICE("You [panel_open ? "open" : "close"] \the [src]'s panel."))
				return TRUE
			if(panel_open && attacking_item.tool_behaviour == TOOL_WIRECUTTER)
				to_chat(user, SPAN_NOTICE("You cut \the [src]'s wires."))
				new /obj/item/stack/cable_coil(get_turf(src), 5)
				buildstage = 1
				update_icon()
				return TRUE
	return FALSE

/// Toggle-links (or unlinks) an air vent to this controller's chamber pump
/// slot (tag_airpump) -- the "pressurize/depressurize" pump the controller
/// commands during a cycle. Vents already have a guaranteed non-null id_tag
/// (auto-assigned on their own Initialize()), so no _ensure_id_tag() step
/// is needed here, unlike doors/sensors/buttons.
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_link_to_airpump(obj/structure/machinery/atmospherics/unary/vent_pump/pump, mob/user)
	_ensure_id_tag()
	pump._ensure_id_tag()
	// Toggle off if this exact pump is already linked, in either slot.
	if(tag_airpump == pump.id_tag)
		// Promote an extra into the primary slot so removing the first pump
		// doesn't orphan the rest.
		tag_airpump = null
		if(LAZYLEN(tag_airpumps))
			tag_airpump = tag_airpumps[1]
			tag_airpumps -= tag_airpump
		to_chat(user, SPAN_NOTICE("You unlink \the [pump] from \the [src]. ([length(get_airpump_tags())] pump\s still linked.)"))
		return
	if(pump.id_tag in tag_airpumps)
		tag_airpumps -= pump.id_tag
		to_chat(user, SPAN_NOTICE("You unlink \the [pump] from \the [src]. ([length(get_airpump_tags())] pump\s still linked.)"))
		return

	if(!tag_airpump)
		tag_airpump = pump.id_tag
	else
		LAZYDISTINCTADD(tag_airpumps, pump.id_tag)
	pump.set_frequency(frequency)
	// Force the vent to re-scan for an adjacent pipe. atmos_init() bails
	// immediately on `if(node) return`, so a vent that initialized BEFORE its
	// pipes were laid keeps node == null permanently and reports "no pipe"
	// even when it's sitting against a fully pressurised run. Linking it to a
	// cycler is a deliberate player action and the natural point to retry.
	pump.node = null
	pump.atmos_init()
	pump.build_network()
	// Re-derive the pump's NOPOWER bit against its current area. Same reason
	// as the node re-scan: a machine whose turf was reassigned into another
	// area (blueprints) never recomputed it, so an otherwise-fine pump can sit
	// there insisting it has no power. Lets an already-broken cycler fix
	// itself on relink instead of needing the area rebuilt.
	pump.power_change()
	to_chat(user, SPAN_NOTICE("You link \the [pump] to \the [src] as a chamber vent pump and tune it to the controller's frequency. ([length(get_airpump_tags())] pump\s linked.)"))

/// Every chamber vent pump tag this controller drives -- the primary plus any
/// extras. Cycle commands go to all of them so a chamber with more than one
/// vent pressurises/depressurises as a unit.
/obj/structure/machinery/embedded_controller/radio/airlock/proc/get_airpump_tags()
	. = list()
	if(tag_airpump)
		. += tag_airpump
	for(var/extra_tag in tag_airpumps)
		if(extra_tag && !(extra_tag in .))
			. += extra_tag

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/ui_interact(mob/user, datum/tgui/ui)
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockConsoleStandard", name, ui_x=470, ui_y=290)
		ui.open()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/ui_data(mob/user)
	var/list/data = list()

	data["chamber_pressure"] = round(program.memory["chamber_sensor_pressure"])
	data["processing"] = program.memory["processing"]
#ifdef AIRLOCK_CYCLER_DIAGNOSTICS
	data["diagnostics"] = program.get_diagnostics()
#endif

	return data

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "command")
		var/command_name = sanitize(params["command"])
		program.receive_user_command(command_name)

//Access controller for door control - used in virology and the like
/obj/structure/machinery/embedded_controller/radio/airlock/access_controller
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_control_standby"

	name = "Access Controller"
	tag_secure = TRUE


/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/update_icon()
	if(on && program)
		if(program.memory["processing"])
			icon_state = "access_control_process"
		else
			icon_state = "access_control_standby"
	else
		icon_state = "access_control_off"

/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockConsoleAccess", name, ui_x=470, ui_y=290)
		ui.open()

/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/ui_data(mob/user)
	var/list/data = list()

	var/ext_door_status = (program.memory["exterior_status"]["state"] == "closed" && program.memory["exterior_status"]["lock"] == "locked")
	var/int_door_status = (program.memory["interior_status"]["state"] == "closed" && program.memory["interior_status"]["lock"] == "locked")

	data["exterior_secured"] = ext_door_status
	data["interior_secured"] = int_door_status
	data["processing"] = program.memory["processing"]

	return data

/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "command")
		var/command_name = sanitize(params["command"])
		program.receive_user_command(command_name)
