#define AIRLOCK_CONTROL_RANGE 22

// This code allows for airlocks to be controlled externally by setting an id_tag and comm frequency (disables ID access)
/obj/structure/machinery/door/airlock
	var/id_tag
	var/frequency
	var/tmp/shockedby
	var/tmp/datum/radio_frequency/radio_connection
	var/tmp/cur_command = null	//the command the door is currently attempting to complete
	var/tmp/waiting_for_roundstart
	/// Dedicated tag for the buildable, multitool-linked door button
	/// (blast_door_button.dm) -- deliberately NOT id_tag, which is already
	/// shared by the legacy remote button (door_control.dm) and the airlock
	/// cycler system (_link_to_controller() below, which snapshots id_tag
	/// into the controller's own tag_exterior_door/tag_interior_door
	/// fields) -- reusing id_tag here would desync a cycler-managed door's
	/// link the moment this button linked it too.
	var/door_button_tag

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
		// Buffered door button (blast_door_button.dm) -- checked first, same
		// non-invasive "extra consumer type" shape as the controller check
		// right below, so buffering this door either applies just the same
		// (whichever the multitool is used on second decides which link
		// happens; neither check touches the other).
		var/obj/structure/machinery/button/remote/blast_door/buildable/door_button = MT.get_buffer(/obj/structure/machinery/button/remote/blast_door/buildable)
		if(door_button)
			door_button._link_airlock(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller = MT.get_buffer(/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller)
		if(!controller)
			MT.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
			return TRUE
		_link_to_controller(controller, user)
		MT.set_buffer(null)
		return TRUE
	return ..()

/// Unlinks src from controller if it's currently linked anywhere -- primary
/// or extra slot, either side. Returns TRUE if it was linked (and has now
/// been unlinked), FALSE if it wasn't linked at all.
/obj/structure/machinery/door/airlock/proc/_unlink_from_controller(obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller, mob/user)
	if(controller.tag_exterior_door == id_tag)
		controller.tag_exterior_door = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller] (was its primary exterior door)."))
		return TRUE
	if(controller.tag_interior_door == id_tag)
		controller.tag_interior_door = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller] (was its primary interior door)."))
		return TRUE
	if(id_tag in controller.tag_exterior_doors)
		controller.tag_exterior_doors -= id_tag
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller] (was an exterior door)."))
		return TRUE
	if(id_tag in controller.tag_interior_doors)
		controller.tag_interior_doors -= id_tag
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller] (was an interior door)."))
		return TRUE
	return FALSE

/// Drops every remote link this door currently has, because it just changed
/// hands. Without it, links made while the door was untagged outlive the tag:
/// someone wires a door to their own button, a faction then claims the door,
/// and that button still opens it from outside the faction. The link guards
/// only stop links being CHANGED -- they cannot retroactively invalidate one
/// that already exists, so the retag has to do it.
///
/// Covers both link systems a door can be part of: the remote door button
/// (door_button_tag) and an airlock cycler (master_tag plus whichever of the
/// controller's own door slots names this door's id_tag).
/obj/structure/machinery/door/airlock/proc/_clear_links_on_faction_change(mob/user, old_uid)
	var/cleared = 0
	if(door_button_tag)
		door_button_tag = null
		cleared++
	// An airlock has no master_tag of its own (unlike sensors and access
	// buttons) -- its cycler membership lives entirely in the controller's own
	// door slots, so that is the only place to clear it from.
	if(id_tag)
		for(var/obj/structure/machinery/embedded_controller/radio/airlock/C in SSmachinery.machinery)
			if(C.tag_exterior_door == id_tag)
				C.tag_exterior_door = null
				cleared++
			if(C.tag_interior_door == id_tag)
				C.tag_interior_door = null
				cleared++
			if(id_tag in C.tag_exterior_doors)
				C.tag_exterior_doors -= id_tag
				cleared++
			if(id_tag in C.tag_interior_doors)
				C.tag_interior_doors -= id_tag
				cleared++
	if(cleared && user)
		to_chat(user, SPAN_WARNING("\The [src] changed hands -- its remote button and cycler links have been cleared."))
	if(cleared)
		log_game("Airlock at [COORD(src)] changed faction ('[old_uid || "unassigned"]' -> '[persistent_network || "unassigned"]'), clearing [cleared] link(s).")

/obj/structure/machinery/door/airlock/proc/_link_to_controller(obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller, mob/user)
	// Reached from BOTH directions -- multitooling the controller with this
	// door buffered, and multitooling this door with the controller buffered.
	// The controller's own attackby() guards the first; this guards the second.
	if(!controller.can_modify_links(user))
		to_chat(user, SPAN_WARNING("\The [controller] is tagged to [get_faction_name(controller.persistent_network)] -- you have no standing there to link to it."))
		return
	// The DOOR's own tag matters too, not just the controller's. Otherwise a
	// faction's exterior/interior airlock could be pulled into a cycler by
	// someone outside that faction, handing them control of it through the
	// cycler instead of directly.
	if(!can_rewire_faction_device(user, persistent_network))
		to_chat(user, SPAN_WARNING("\The [src] is tagged to [get_faction_name(persistent_network)] -- you have no standing there to wire it to a cycler."))
		return
	_ensure_id_tag()
	controller._ensure_id_tag()
	if(_unlink_from_controller(controller, user))
		return

	// A chamber can have more than one door on a side (see
	// get_exterior_door_tags()/get_interior_door_tags(), airlock_controllers.dm)
	// -- ask which side this one joins instead of auto-picking whichever
	// singular slot happens to be empty, and append instead of refusing once
	// the primary slot is already filled.
	var/choice = tgui_alert(user, "Link \the [src] to \the [controller] as which door?", "Airlock Cycler", list("Exterior", "Interior"))
	if(QDELETED(src) || QDELETED(user) || QDELETED(controller) || !user.Adjacent(src))
		return
	if(!choice)
		return
	var/slot
	if(choice == "Exterior")
		slot = "exterior"
		if(!controller.tag_exterior_door)
			controller.tag_exterior_door = id_tag
		else
			LAZYDISTINCTADD(controller.tag_exterior_doors, id_tag)
	else
		slot = "interior"
		if(!controller.tag_interior_door)
			controller.tag_interior_door = id_tag
		else
			LAZYDISTINCTADD(controller.tag_interior_doors, id_tag)
	set_frequency(controller.frequency)
	// Mapped cyclers lock() both doors as part of their marker-driven setup
	// (map_effects/marker/airlock_.dm) -- the multitool link flow never did,
	// so a freshly-linked door could be unlocked while the controller's
	// memory assumes "closed and locked" (the New() default in
	// airlock_program.dm). toggleDoor()'s secure-close branch only issues a
	// lock command when its cached state says "unlocked" -- if that cache is
	// wrong, check_doors_secured() reports secure based on a false
	// assumption instead of reality, and close_doors() silently never
	// corrects it. Lock for real here so cache and reality start in sync.
	lock()
	to_chat(user, SPAN_NOTICE("You link \the [src] to \the [controller] as an [slot] door and tune it to the controller's frequency."))

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
		apply_wall_mount_offset()
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
					// See the matching comment on airlock_controller's own
					// buildstage=2 branch (airlock_controllers.dm) -- player-
					// built sensors were never tracked for position/existence
					// persistence either, so a saved link had nothing to
					// reattach to after a reboot.
					if(GLOB.config.sql_enabled && GLOB.persistence_ready)
						SSpersistence.objectsRegisterTrack(src)
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

/// Which controller sensor slot this sensor type belongs in:
/// "chamber" (base type), "exterior", or "interior".
/obj/structure/machinery/airlock_sensor/proc/get_sensor_slot()
	return "chamber"

/obj/structure/machinery/airlock_sensor/airlock_exterior/get_sensor_slot()
	return "exterior"

/obj/structure/machinery/airlock_sensor/airlock_interior/get_sensor_slot()
	return "interior"

/// Links (or unlinks, toggle-style) this sensor to a cycler controller in
/// both directions at once: master_tag so its manual "cycle" swipe reaches
/// the controller, and the controller sensor slot matching this sensor's own
/// subtype (see get_sensor_slot()) so the controller listens to this
/// sensor's passive pressure reports.
/obj/structure/machinery/airlock_sensor/proc/_link_to_controller(obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller, mob/user)
	if(!controller.can_modify_links(user))
		to_chat(user, SPAN_WARNING("\The [controller] is tagged to [get_faction_name(controller.persistent_network)] -- you have no standing there to link to it."))
		return
	_ensure_id_tag()
	controller._ensure_id_tag()
	var/linked = (master_tag == controller.id_tag) || (controller.tag_chamber_sensor == id_tag) || (controller.tag_exterior_sensor == id_tag) || (controller.tag_interior_sensor == id_tag)
	if(linked)
		var/slot = "chamber"
		if(controller.tag_exterior_sensor == id_tag)
			slot = "exterior"
		else if(controller.tag_interior_sensor == id_tag)
			slot = "interior"
		if(master_tag == controller.id_tag)
			master_tag = null
		if(controller.tag_chamber_sensor == id_tag)
			controller.tag_chamber_sensor = null
		if(controller.tag_exterior_sensor == id_tag)
			controller.tag_exterior_sensor = null
		if(controller.tag_interior_sensor == id_tag)
			controller.tag_interior_sensor = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller] (was its [slot] sensor)."))
		return
	// Slot comes from the sensor's own SUBTYPE, not from link order. Filling
	// chamber -> exterior -> interior by whichever got linked first meant the
	// role a sensor ended up playing depended entirely on click sequence, with
	// nothing on the sensor itself indicating which it was -- and a sensor
	// landing in the wrong slot silently breaks cycling.
	// Prefer the slot matching this sensor's own subtype, but fall back to any
	// still-empty slot rather than refusing outright -- a plain (chamber-type)
	// sensor is still perfectly usable in the interior/exterior slots, and
	// hard-refusing left players unable to link a third sensor at all once
	// chamber was taken.
	var/slot = get_sensor_slot()
	if(slot == "exterior" && controller.tag_exterior_sensor)
		slot = null
	else if(slot == "interior" && controller.tag_interior_sensor)
		slot = null
	else if(slot == "chamber" && controller.tag_chamber_sensor)
		slot = null
	if(!slot)
		if(!controller.tag_chamber_sensor)
			slot = "chamber"
		else if(!controller.tag_exterior_sensor)
			slot = "exterior"
		else if(!controller.tag_interior_sensor)
			slot = "interior"
		else
			to_chat(user, SPAN_WARNING("\The [controller] already has a chamber, exterior, and interior sensor assigned -- unlink one first."))
			return
	switch(slot)
		if("exterior")
			controller.tag_exterior_sensor = id_tag
		if("interior")
			controller.tag_interior_sensor = id_tag
		else
			controller.tag_chamber_sensor = id_tag
	master_tag = controller.id_tag
	set_frequency(controller.frequency)
	to_chat(user, SPAN_NOTICE("You link \the [src] to \the [controller] as its [slot] sensor and tune it to the controller's frequency."))

/// The turf this sensor actually measures: the first OPEN turf in the
/// direction it faces, i.e. the space on the far side of the wall it's
/// mounted on.
///
/// try_build() (wall_frames.dm) puts a wall device on the BUILDER's turf with
/// dir pointing at the wall, and refuses to build unless the builder is
/// standing on a /turf/simulated/floor -- so nobody can plant an exterior
/// sensor out in vacuum, and a sensor reading its own turf always reports
/// whichever room it was built from rather than the one it's named for.
/// Stepping past the mounting wall lets any sensor be built from whatever
/// side is reachable and still measure the space it faces.
///
/// Falls back to its own turf if there's no open turf within reach (e.g.
/// mounted facing solid rock), so it degrades to the old behavior instead of
/// reporting nothing.
/obj/structure/machinery/airlock_sensor/proc/get_sample_turf()
	var/turf/own_turf = get_turf(src)
	var/turf/probe = own_turf
	for(var/i = 1 to 3)
		probe = get_step(probe, dir)
		if(!probe)
			return own_turf
		if(probe.density)
			continue // the wall this sensor is mounted on -- keep going
		var/blocked = FALSE
		for(var/obj/O in probe)
			if(O.density)
				blocked = TRUE // a closed door counts as more wall, not a room
				break
		if(!blocked)
			return probe
	return own_turf

/// Reports the pressure this sensor reads. It deliberately does NOT trigger a
/// cycle any more: sensors used to double as manual cycle buttons (sending
/// their `command` to the controller, "cycle" on the base type -> cycle_int),
/// which meant brushing the CHAMBER sensor -- mounted inside the airlock
/// itself -- would open the interior door. Cycling is the access buttons' job;
/// they're built per-side and labelled for it.
/obj/structure/machinery/airlock_sensor/attack_hand(mob/user)
	if(buildstage < 2)
		return
	add_fingerprint(usr)
	if(!allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return FALSE

	var/turf/sample = get_sample_turf()
	var/datum/gas_mixture/air_sample = sample ? sample.return_air() : null
	to_chat(user, SPAN_NOTICE("\The [src] reads <b>[air_sample ? round(XGM_PRESSURE(air_sample), 0.1) : 0] kPa</b>."))
	flick("airlock_sensor_cycle", src)

/obj/structure/machinery/airlock_sensor/process()
	if(buildstage < 2)
		return
	if(on)
		// Measures the space on the far side of the wall it faces, not its own
		// turf -- see get_sample_turf().
		var/turf/sample = get_sample_turf()
		var/datum/gas_mixture/air_sample = sample ? sample.return_air() : null
		var/pressure = air_sample ? round(XGM_PRESSURE(air_sample), 0.1) : 0

		// Broadcasts every tick unconditionally (no change-gate) -- this is a
		// single O(1) radio post per sensor per SSmachinery tick (2 SECONDS),
		// not a loop, so there's nothing here for CHECK_TICK to guard; the
		// subsystem already yields around its own loop over every processing
		// machine (controllers/subsystems/machinery.dm's process_machinery()).
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = world.time
		signal.data["pressure"] = num2text(pressure)

		radio_connection.post_signal(src, signal, range = AIRLOCK_CONTROL_RANGE, filter = RADIO_AIRLOCK)

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
	name = "interior airlock sensor"
	command = "cycle_interior"

/obj/structure/machinery/airlock_sensor/airlock_exterior
	name = "exterior airlock sensor"
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
					// See the matching comment on airlock_controller's own
					// buildstage=2 branch (airlock_controllers.dm) -- player-
					// built buttons were never tracked for position/existence
					// persistence either, so a saved link had nothing to
					// reattach to after a reboot.
					if(GLOB.config.sql_enabled && GLOB.persistence_ready)
						SSpersistence.objectsRegisterTrack(src)
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
	if(!controller.can_modify_links(user))
		to_chat(user, SPAN_WARNING("\The [controller] is tagged to [get_faction_name(controller.persistent_network)] -- you have no standing there to link to it."))
		return
	controller._ensure_id_tag()
	if(master_tag == controller.id_tag)
		master_tag = null
		to_chat(user, SPAN_NOTICE("You unlink \the [src] from \the [controller]."))
		return
	master_tag = controller.id_tag
	set_frequency(controller.frequency)
	to_chat(user, SPAN_NOTICE("You link \the [src] to \the [controller] and tune it to the controller's frequency -- it will send \"[command]\" when pressed."))

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

/obj/structure/machinery/access_button/Initialize(mapload, var/dir, var/building = 0)
	. = ..()
	if(building)
		if(dir)
			set_dir(dir)
		apply_wall_mount_offset()
		buildstage = 0

	if(SSradio)
		set_frequency(frequency)

/obj/structure/machinery/access_button/Destroy()
	if(SSradio)
		SSradio.remove_object(src, frequency)
	return ..()

/obj/structure/machinery/access_button/airlock_interior
	name = "interior access button"
	frequency = 1379
	command = "cycle_interior"

/obj/structure/machinery/access_button/airlock_exterior
	name = "exterior access button"
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
