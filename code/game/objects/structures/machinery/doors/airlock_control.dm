#define AIRLOCK_CONTROL_RANGE 22

// This code allows for airlocks to be controlled externally by setting an id_tag and comm frequency (disables ID access)
/obj/structure/machinery/door/airlock
	var/id_tag
	var/frequency
	var/tmp/shockedby
	var/tmp/datum/radio_frequency/radio_connection
	var/tmp/cur_command = null	//the command the door is currently attempting to complete
	var/tmp/waiting_for_roundstart

/obj/structure/machinery/door/airlock/receive_signal(datum/signal/signal)
	if (!arePowerSystemsOn()) return //no power

	if(!signal || signal.encryption) return

	if(id_tag != signal.data["tag"] || !signal.data["command"]) return

	cur_command = signal.data["command"]
	execute_current_command()

/obj/structure/machinery/door/airlock/proc/execute_current_command()
	set waitfor = FALSE
	if(operating)
		if (emagged == 1)
			// Come back and try again later.
			queue_command()
		return //emagged or busy doing something else

	if (!cur_command)
		return

	do_command(cur_command)
	if (command_completed(cur_command))
		cur_command = null
	else
		queue_command()

/obj/structure/machinery/door/airlock/proc/queue_command()
	if (waiting_for_roundstart)
		return

	if (ROUND_IS_STARTED)
		addtimer(CALLBACK(src, PROC_REF(execute_current_command)), 2 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
	else
		SSticker.OnRoundstart(CALLBACK(src, PROC_REF(handle_queue_command)))
		waiting_for_roundstart = TRUE

/obj/structure/machinery/door/airlock/proc/handle_queue_command()
	waiting_for_roundstart = null
	execute_current_command()

/obj/structure/machinery/door/airlock/proc/do_command(var/command)
	switch(command)
		if("open")
			open()

		if("close")
			close()

		if("unlock")
			unlock()

		if("lock")
			lock()

		if("secure_open")
			unlock()

			sleep(2)
			open()

			lock()

		if("secure_close")
			unlock()
			close()

			sleep(2)
			lock()

	send_status()

/obj/structure/machinery/door/airlock/proc/command_completed(var/command)
	switch(command)
		if("open")
			return (!density)

		if("close")
			return density

		if("unlock")
			return !locked

		if("lock")
			return locked

		if("secure_open")
			return (locked && !density)

		if("secure_close")
			return (locked && density)

	return 1	//Unknown command. Just assume it's completed.

/obj/structure/machinery/door/airlock/proc/send_status(var/bumped = 0)
	if(radio_connection)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = world.time

		signal.data["door_status"] = density?("closed"):("open")
		signal.data["lock_status"] = locked?("locked"):("unlocked")

		if (bumped)
			signal.data["bumped_with_access"] = 1

		radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, filter = RADIO_AIRLOCK)


/obj/structure/machinery/door/airlock/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	if(new_frequency)
		frequency = new_frequency
		radio_connection = SSradio.add_object(src, frequency, RADIO_AIRLOCK)

/// Auto-assigns a unique id_tag the first time this door is linked to a
/// cycler controller -- there's no in-game tool to type in a custom tag, and
/// a blank/null id_tag would make every untagged door match every other
/// untagged door's blank slot.
/obj/structure/machinery/door/airlock/proc/_ensure_id_tag()
	if(!id_tag)
		id_tag = "cycler_[REF(src)]"
	return id_tag

/// Multitool linking to an airlock cycler controller -- buffer the
/// controller, then click the door (or vice versa) to toggle-link/unlink,
/// mirroring the buffer-toggle pattern in contact_sensors.dm. Does not
/// interfere with any of the door's other tool interactions (repair, hit,
/// open/close), which are all handled by the parent attackby.
/obj/structure/machinery/door/airlock/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller = MT.get_buffer(/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller)
		if(!controller)
			MT.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
			return TRUE
		_link_to_controller(controller, user)
		MT.set_buffer(null)
		return TRUE
	return ..()

/obj/structure/machinery/door/airlock/proc/_link_to_controller(obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller, mob/user)
	_ensure_id_tag()
	controller._ensure_id_tag()
	if(controller.tag_exterior_door == id_tag || controller.tag_interior_door == id_tag)
		if(controller.tag_exterior_door == id_tag)
			controller.tag_exterior_door = null
		if(controller.tag_interior_door == id_tag)
			controller.tag_interior_door = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller]."))
		return
	if(!controller.tag_exterior_door)
		controller.tag_exterior_door = id_tag
	else if(!controller.tag_interior_door)
		controller.tag_interior_door = id_tag
	else
		to_chat(user, SPAN_WARNING("\The [controller] already has both an exterior and interior door assigned -- unlink one first."))
		return
	set_frequency(controller.frequency)
	to_chat(user, SPAN_NOTICE("You link \the [src] to \the [controller] and tune it to the controller's frequency."))

/obj/structure/machinery/airlock_sensor
	name = "airlock sensor"
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_sensor_off"

	anchored = 1
	power_channel = AREA_USAGE_ENVIRON
	obj_flags = OBJ_FLAG_MOVES_UNSUPPORTED

	var/id_tag
	var/master_tag
	var/frequency = 1379
	var/command = "cycle"

	var/datum/radio_frequency/radio_connection

	var/on = 1
	var/alert = 0
	var/previousPressure

	/// 2 = complete/wired, 1 = circuit inserted but unwired, 0 = frame only.
	/// Player-built via /obj/item/frame/airlock_sensor; mapped-in/preset
	/// sensors default to 2 (already finished).
	/// panel_open is inherited from base /obj/structure/machinery.
	var/buildstage = 2

/obj/structure/machinery/airlock_sensor/Initialize(mapload, var/dir, var/building = 0)
	. = ..()
	if(building)
		if(dir)
			set_dir(dir)
		buildstage = 0
	set_frequency(frequency)
	if(SSradio)
		set_frequency(frequency)
	update_icon()

/obj/structure/machinery/airlock_sensor/update_icon()
	if(buildstage < 2)
		icon_state = "airlock_sensor_off"
		return
	if(on)
		if(alert)
			icon_state = "airlock_sensor_alert"
		else
			icon_state = "airlock_sensor_standby"
	else
		icon_state = "airlock_sensor_off"

/// Auto-assigns a unique id_tag the first time this sensor is linked to a
/// cycler controller -- see door/airlock/_ensure_id_tag() for why.
/obj/structure/machinery/airlock_sensor/proc/_ensure_id_tag()
	if(!id_tag)
		id_tag = "cycler_[REF(src)]"
	return id_tag

/obj/structure/machinery/airlock_sensor/attackby(obj/item/attacking_item, mob/user)
	if(_handle_construction(attacking_item, user))
		return TRUE
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller = MT.get_buffer(/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller)
		if(!controller)
			MT.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
			return TRUE
		_link_to_controller(controller, user)
		MT.set_buffer(null)
		return TRUE
	//Swiping ID on the access button
	if (attacking_item.GetID())
		attack_hand(user)
		return TRUE
	return ..()

/obj/structure/machinery/airlock_sensor/proc/_handle_construction(obj/item/attacking_item, mob/user)
	switch(buildstage)
		if(0)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				set_dir(turn(dir, -90))
				to_chat(user, SPAN_NOTICE("You rotate \the [src]."))
				return TRUE
			if(istype(attacking_item, /obj/item/airlock_cycler_electronics/airlock_sensor))
				to_chat(user, SPAN_NOTICE("You insert the circuit board."))
				qdel(attacking_item)
				buildstage = 1
				update_icon()
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You remove \the [src] from the wall."))
				new /obj/item/frame/airlock_sensor(get_turf(user))
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
				new /obj/item/airlock_cycler_electronics/airlock_sensor(get_turf(user))
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

/// Links (or unlinks, toggle-style) this sensor to a cycler controller in
/// both directions at once: master_tag so its manual "cycle" swipe reaches
/// the controller, and the controller's first empty sensor tag slot
/// (chamber -> exterior -> interior) so the controller listens to this
/// sensor's passive pressure reports.
/obj/structure/machinery/airlock_sensor/proc/_link_to_controller(obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller, mob/user)
	_ensure_id_tag()
	controller._ensure_id_tag()
	var/linked = (master_tag == controller.id_tag) || (controller.tag_chamber_sensor == id_tag) || (controller.tag_exterior_sensor == id_tag) || (controller.tag_interior_sensor == id_tag)
	if(linked)
		if(master_tag == controller.id_tag)
			master_tag = null
		if(controller.tag_chamber_sensor == id_tag)
			controller.tag_chamber_sensor = null
		if(controller.tag_exterior_sensor == id_tag)
			controller.tag_exterior_sensor = null
		if(controller.tag_interior_sensor == id_tag)
			controller.tag_interior_sensor = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller]."))
		return
	if(!controller.tag_chamber_sensor)
		controller.tag_chamber_sensor = id_tag
	else if(!controller.tag_exterior_sensor)
		controller.tag_exterior_sensor = id_tag
	else if(!controller.tag_interior_sensor)
		controller.tag_interior_sensor = id_tag
	else
		to_chat(user, SPAN_WARNING("\The [controller] already has a chamber, exterior, and interior sensor assigned -- unlink one first."))
		return
	master_tag = controller.id_tag
	set_frequency(controller.frequency)
	to_chat(user, SPAN_NOTICE("You link \the [src] to \the [controller] and tune it to the controller's frequency."))

/obj/structure/machinery/airlock_sensor/attack_hand(mob/user)
	if(buildstage < 2)
		return
	add_fingerprint(usr)
	if(!allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return FALSE

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	signal.data["tag"] = master_tag
	signal.data["command"] = command

	radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, filter = RADIO_AIRLOCK)
	flick("airlock_sensor_cycle", src)

/obj/structure/machinery/airlock_sensor/process()
	if(buildstage < 2)
		return
	if(on)
		var/datum/gas_mixture/air_sample = return_air()
		var/pressure = round(XGM_PRESSURE(air_sample),0.1)

		if(abs(pressure - previousPressure) > 0.001 || previousPressure == null)
			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO
			signal.data["tag"] = id_tag
			signal.data["timestamp"] = world.time
			signal.data["pressure"] = num2text(pressure)

			radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, filter = RADIO_AIRLOCK)

			previousPressure = pressure

			alert = (pressure < ONE_ATMOSPHERE*0.8)

			update_icon()

/obj/structure/machinery/airlock_sensor/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_AIRLOCK)

/obj/structure/machinery/airlock_sensor/Destroy()
	if(SSradio)
		SSradio.remove_object(src,frequency)
	return ..()

/obj/structure/machinery/airlock_sensor/airlock_interior
	command = "cycle_interior"

/obj/structure/machinery/airlock_sensor/airlock_exterior
	command = "cycle_exterior"

/obj/structure/machinery/access_button
	name = "access button"
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_button_standby"
	obj_flags = OBJ_FLAG_MOVES_UNSUPPORTED

	anchored = 1
	power_channel = AREA_USAGE_ENVIRON

	var/master_tag
	var/frequency = 1449
	var/command = "cycle"

	var/datum/radio_frequency/radio_connection

	var/on = 1

	/// 2 = complete/wired, 1 = circuit inserted but unwired, 0 = frame only.
	/// Player-built via /obj/item/frame/access_button; mapped-in/preset
	/// buttons default to 2 (already finished).
	/// panel_open is inherited from base /obj/structure/machinery.
	var/buildstage = 2

/obj/structure/machinery/access_button/update_icon()
	if(buildstage < 2)
		icon_state = "access_button_off"
		return
	if(on)
		icon_state = "access_button_standby"
	else
		icon_state = "access_button_off"

/obj/structure/machinery/access_button/attackby(obj/item/attacking_item, mob/user)
	if(_handle_construction(attacking_item, user))
		return TRUE
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller = MT.get_buffer(/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller)
		if(!controller)
			MT.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
			return TRUE
		_link_to_controller(controller, user)
		MT.set_buffer(null)
		return TRUE
	//Swiping ID on the access button
	if (attacking_item.GetID())
		attack_hand(user)
		return TRUE
	return ..()

/obj/structure/machinery/access_button/proc/_handle_construction(obj/item/attacking_item, mob/user)
	switch(buildstage)
		if(0)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				set_dir(turn(dir, -90))
				to_chat(user, SPAN_NOTICE("You rotate \the [src]."))
				return TRUE
			if(istype(attacking_item, /obj/item/airlock_cycler_electronics/access_button))
				to_chat(user, SPAN_NOTICE("You insert the circuit board."))
				qdel(attacking_item)
				buildstage = 1
				update_icon()
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You remove \the [src] from the wall."))
				new /obj/item/frame/access_button(get_turf(user))
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
				new /obj/item/airlock_cycler_electronics/access_button(get_turf(user))
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

/// Toggle-links (or unlinks) this button to a cycler controller: master_tag
/// so its "cycle" command reaches the controller, tuned to the same
/// frequency. The button's own command string (plain "cycle" by default, or
/// "cycle_interior"/"cycle_exterior" on the door-side preset subtypes below)
/// is untouched by linking -- that's fixed by which subtype was built.
/obj/structure/machinery/access_button/proc/_link_to_controller(obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller, mob/user)
	controller._ensure_id_tag()
	if(master_tag == controller.id_tag)
		master_tag = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller]."))
		return
	master_tag = controller.id_tag
	set_frequency(controller.frequency)
	to_chat(user, SPAN_NOTICE("You link \the [src] to \the [controller] and tune it to the controller's frequency."))

/obj/structure/machinery/access_button/attack_hand(mob/user)
	if(buildstage < 2)
		return
	add_fingerprint(usr)
	if(!allowed(user))
		to_chat(user, SPAN_WARNING("Access denied"))

	else if(radio_connection)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO
		signal.data["tag"] = master_tag
		signal.data["command"] = command

		radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, filter = RADIO_AIRLOCK)
	flick("access_button_cycle", src)


/obj/structure/machinery/access_button/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_AIRLOCK)

/obj/structure/machinery/access_button/Initialize()
	. = ..()

	if(SSradio)
		set_frequency(frequency)

/obj/structure/machinery/access_button/Destroy()
	if(SSradio)
		SSradio.remove_object(src, frequency)
	return ..()

/obj/structure/machinery/access_button/airlock_interior
	frequency = 1379
	command = "cycle_interior"

/obj/structure/machinery/access_button/airlock_exterior
	frequency = 1379
	command = "cycle_exterior"

/obj/structure/machinery/door/airlock/proc/command(var/new_command)
	cur_command = new_command

	//if there's no power, receive the signal but just don't do anything. This allows airlocks to continue to work normally once power is restored
	if(arePowerSystemsOn())
		INVOKE_ASYNC(src, PROC_REF(execute_current_command))

/*
AIRLOCK CYCLER ELECTRONICS
Circuit boards used to build the airlock cycler parts from their wall
frames (see /obj/item/frame/access_button, /airlock_sensor, /airlock_controller
in wall_frames.dm). One subtype per part -- not interchangeable, matching
firealarm_electronics' pattern.
*/
/obj/item/airlock_cycler_electronics
	name = "airlock cycler electronics"
	icon = 'icons/obj/module.dmi'
	icon_state = "door_electronics"
	desc = "A circuit board for an airlock cycler component."
	w_class = WEIGHT_CLASS_SMALL
	matter = list(DEFAULT_WALL_MATERIAL = 50, MATERIAL_GLASS = 50)

/obj/item/airlock_cycler_electronics/access_button
	name = "access button electronics"
	desc = "A circuit board for an airlock access button."

/obj/item/airlock_cycler_electronics/airlock_sensor
	name = "airlock sensor electronics"
	desc = "A circuit board for an airlock pressure sensor."

/obj/item/airlock_cycler_electronics/airlock_controller
	name = "airlock controller electronics"
	desc = "A circuit board for an airlock cycler controller."

#undef AIRLOCK_CONTROL_RANGE
