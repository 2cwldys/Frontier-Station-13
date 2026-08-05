//Handles the control of airlocks

#define STATE_IDLE			0
#define STATE_PREPARE		1
#define STATE_DEPRESSURIZE	2
#define STATE_PRESSURIZE	3

#define TARGET_NONE			0
#define TARGET_INOPEN		-1
#define TARGET_OUTOPEN		-2

#define SENSOR_TOLERANCE	1

/// How long a cycle attempt may sit outside STATE_IDLE before process()
/// force-aborts it back to idle. Without this, a cycle that can never
/// complete (e.g. an unlinked/untagged pump that never reports "off") gets
/// stuck forever, and the state==target_state re-entry guard on every future
/// receive_user_command("cycle_ext"/"cycle_int") means NO further cycle
/// attempt can even start until something external resets state -- in
/// practice, rebuilding the controller from scratch. This is purely a safety
/// net: a working cycle finishes long before this fires.
#define AIRLOCK_CYCLE_STALL_TIMEOUT (30 SECONDS)
/// Chamber pressure must move by more than this between checks to count as
/// progress and reset the stall clock.
#define AIRLOCK_CYCLE_PROGRESS_EPSILON 0.5


/datum/computer/file/embedded_program/airlock
	var/tag_exterior_door
	var/tag_interior_door
	var/tag_airpump
	var/tag_chamber_sensor
	var/tag_exterior_sensor
	var/tag_interior_sensor
	var/tag_airlock_mech_sensor
	var/tag_shuttle_mech_sensor

	var/state = STATE_IDLE
	var/target_state = TARGET_NONE
	/// world.time of the last observed pressure PROGRESS, or 0 while idle.
	/// Backs the stall watchdog in process() -- see AIRLOCK_CYCLE_STALL_TIMEOUT.
	var/state_stall_start = 0
	/// Chamber pressure at the last stall check, for progress comparison.
	var/last_progress_pressure = null
	/// Rate-limit for the "linked pump tag resolves to nothing" warning.
	var/next_dead_pump_warning = 0
	/// Resolved vent pumps keyed by id_tag -- see _resolve_pump_by_tag().
	var/list/cached_pumps
	/// Every chamber vent pump tag, synced from the controller each tick.
	var/list/tag_airpumps = list()

	var/cycle_to_external_air = FALSE
	var/tag_pump_out_external
	var/tag_pump_out_internal

/datum/computer/file/embedded_program/airlock/New(var/obj/structure/machinery/embedded_controller/M)
	..(M)

	memory["chamber_sensor_pressure"] = ONE_ATMOSPHERE
	memory["external_sensor_pressure"] = 0					//assume vacuum for simple airlock controller
	memory["internal_sensor_pressure"] = ONE_ATMOSPHERE
	memory["exterior_status"] = list(state = "closed", lock = "locked")		//assume closed and locked in case the doors dont report in
	memory["interior_status"] = list(state = "closed", lock = "locked")
	memory["pump_status"] = "unknown"
	memory["target_pressure"] = ONE_ATMOSPHERE
	memory["purge"] = 0
	memory["secure"] = 0

	if (istype(M, /obj/structure/machinery/embedded_controller/radio/airlock))	//if our controller is an airlock controller than we can auto-init our tags
		var/obj/structure/machinery/embedded_controller/radio/airlock/controller = M
		cycle_to_external_air = controller.cycle_to_external_air
		if(cycle_to_external_air)
			tag_pump_out_external = "[id_tag]_pump_out_external"
			tag_pump_out_internal = "[id_tag]_pump_out_internal"
		tag_exterior_door = controller.tag_exterior_door? controller.tag_exterior_door : "[id_tag]_outer"
		tag_interior_door = controller.tag_interior_door? controller.tag_interior_door : "[id_tag]_inner"
		tag_airpump = controller.tag_airpump? controller.tag_airpump : "[id_tag]_pump"
		tag_chamber_sensor = controller.tag_chamber_sensor? controller.tag_chamber_sensor : "[id_tag]_sensor"
		tag_exterior_sensor = controller.tag_exterior_sensor
		tag_interior_sensor = controller.tag_interior_sensor
		tag_airlock_mech_sensor = controller.tag_airlock_mech_sensor? controller.tag_airlock_mech_sensor : "[id_tag]_airlock_mech"
		tag_shuttle_mech_sensor = controller.tag_shuttle_mech_sensor? controller.tag_shuttle_mech_sensor : "[id_tag]_shuttle_mech"
		memory["secure"] = controller.tag_secure
		addtimer(CALLBACK(src, PROC_REF(signalDoor), tag_exterior_door, "update"), 1 SECONDS)
		addtimer(CALLBACK(src, PROC_REF(signalDoor), tag_interior_door, "update"), 1 SECONDS)

//re-reads the per-slot tags live from the controller -- multitool linking
//(airlock_control.dm's _link_to_controller() procs) always happens after
//this program is first created, so the New()-time snapshot below is stale
//the moment anything gets linked; this keeps signalDoor()/receive_signal()
//addressing whatever is actually linked right now instead of a guess made
//before any linking occurred
/datum/computer/file/embedded_program/airlock/proc/_sync_tags()
	var/obj/structure/machinery/embedded_controller/radio/airlock/controller = master
	if(!istype(controller))
		return
	id_tag = controller.id_tag
	tag_exterior_door = controller.tag_exterior_door? controller.tag_exterior_door : "[id_tag]_outer"
	tag_interior_door = controller.tag_interior_door? controller.tag_interior_door : "[id_tag]_inner"
	tag_airpump = controller.tag_airpump? controller.tag_airpump : "[id_tag]_pump"
	// Every linked pump, not just the primary -- a chamber with more than one
	// vent has to pressurise/depressurise as a unit or it never reaches target.
	tag_airpumps = controller.get_airpump_tags()
	if(!length(tag_airpumps))
		tag_airpumps = list(tag_airpump)
	tag_chamber_sensor = controller.tag_chamber_sensor? controller.tag_chamber_sensor : "[id_tag]_sensor"
	tag_exterior_sensor = controller.tag_exterior_sensor
	tag_interior_sensor = controller.tag_interior_sensor
	tag_airlock_mech_sensor = controller.tag_airlock_mech_sensor? controller.tag_airlock_mech_sensor : "[id_tag]_airlock_mech"
	tag_shuttle_mech_sensor = controller.tag_shuttle_mech_sensor? controller.tag_shuttle_mech_sensor : "[id_tag]_shuttle_mech"

/datum/computer/file/embedded_program/airlock/receive_signal(datum/signal/signal, receive_method, receive_param)
	_sync_tags()
	var/receive_tag = signal.data["tag"]
	if(!receive_tag) return

	if(receive_tag==tag_chamber_sensor)
		if(signal.data["pressure"])
			memory["chamber_sensor_pressure"] = text2num(signal.data["pressure"])

	else if(receive_tag==tag_exterior_sensor)
		memory["external_sensor_pressure"] = text2num(signal.data["pressure"])

	else if(receive_tag==tag_interior_sensor)
		memory["internal_sensor_pressure"] = text2num(signal.data["pressure"])

	else if(receive_tag==tag_exterior_door)
		memory["exterior_status"]["state"] = signal.data["door_status"]
		memory["exterior_status"]["lock"] = signal.data["lock_status"]

	else if(receive_tag==tag_interior_door)
		memory["interior_status"]["state"] = signal.data["door_status"]
		memory["interior_status"]["lock"] = signal.data["lock_status"]

	else if(receive_tag==tag_airpump || receive_tag==tag_pump_out_internal)
		if(signal.data["power"])
			memory["pump_status"] = signal.data["direction"]
		else
			memory["pump_status"] = "off"

	else if(receive_tag==id_tag)
		if(istype(master, /obj/structure/machinery/embedded_controller/radio/airlock/access_controller))
			switch(signal.data["command"])
				if("cycle_exterior")
					receive_user_command("cycle_ext_door")
				if("cycle_interior")
					receive_user_command("cycle_int_door")
				if("cycle")
					if(memory["interior_status"]["state"] == "open")		//handle backwards compatibility
						receive_user_command("cycle_ext")
					else
						receive_user_command("cycle_int")
		else
			switch(signal.data["command"])
				if("cycle_exterior")
					receive_user_command("cycle_ext")
				if("cycle_interior")
					receive_user_command("cycle_int")
				if("cycle")
					if(memory["interior_status"]["state"] == "open")		//handle backwards compatibility
						receive_user_command("cycle_ext")
					else
						receive_user_command("cycle_int")


/datum/computer/file/embedded_program/airlock/receive_user_command(command)
	_sync_tags()
	var/shutdown_pump = 0
	switch(command)
		if("cycle_ext")
			//If airlock is already cycled in this direction, just toggle the doors.
			if(!memory["purge"] && IsInRange(memory["external_sensor_pressure"], memory["chamber_sensor_pressure"] - SENSOR_TOLERANCE, memory["chamber_sensor_pressure"] + SENSOR_TOLERANCE))
				toggleDoor(memory["exterior_status"], tag_exterior_door, memory["secure"], "toggle")
			//only respond to these commands if the airlock isn't already doing something
			//prevents the controller from getting confused and doing strange things
			else if(state == target_state)
				begin_cycle_out()

		if("cycle_int")
			if(!memory["purge"] && IsInRange(memory["internal_sensor_pressure"], memory["chamber_sensor_pressure"] - SENSOR_TOLERANCE, memory["chamber_sensor_pressure"] + SENSOR_TOLERANCE))
				toggleDoor(memory["interior_status"], tag_interior_door, memory["secure"], "toggle")
			else if(state == target_state)
				begin_cycle_in()

		if("cycle_ext_door")
			cycleDoors(TARGET_OUTOPEN)

		if("cycle_int_door")
			cycleDoors(TARGET_INOPEN)

		if("abort")
			stop_cycling()

		if("force_ext")
			toggleDoor(memory["exterior_status"], tag_exterior_door, memory["secure"], "toggle")

		if("force_int")
			toggleDoor(memory["interior_status"], tag_interior_door, memory["secure"], "toggle")

		if("purge")
			memory["purge"] = !memory["purge"]
			if(memory["purge"])
				close_doors()
				state = STATE_PREPARE
				target_state = TARGET_NONE

		if("secure")
			memory["secure"] = !memory["secure"]
			if(memory["secure"])
				signalDoor(tag_interior_door, "lock")
				signalDoor(tag_exterior_door, "lock")
			else
				signalDoor(tag_interior_door, "unlock")
				signalDoor(tag_exterior_door, "unlock")

	if(shutdown_pump)
		signalAirpumps(0)		//send a signal to stop pressurizing
		if(cycle_to_external_air)
			signalPump(tag_pump_out_internal, 0)
			signalPump(tag_pump_out_external, 0)

/// Resolves the linked airpump by tag and reports why it can't run, if it
/// can't. "Pump Status: off" on its own is a dead end -- a vent_pump defaults
/// to POWER_USE_OFF and silently force-disables itself whenever it has no
/// pipe node (vent_pump.dm's process()), which is indistinguishable from
/// "never commanded" from the controller's side.
/// Condition line covering EVERY linked pump, one entry each.
/datum/computer/file/embedded_program/airlock/proc/_get_all_pump_conditions()
	if(!length(tag_airpumps))
		return "no pump linked"
	var/list/lines = list()
	for(var/pump_tag in tag_airpumps)
		lines += _get_pump_condition(pump_tag)
	return jointext(lines, " || ")

/datum/computer/file/embedded_program/airlock/proc/_get_pump_condition(pump_tag)
	if(!pump_tag)
		return "no pump linked"
	var/obj/structure/machinery/atmospherics/unary/vent_pump/V = _resolve_pump_by_tag(pump_tag)
	if(!V)
		return "pump NOT FOUND (tag '[pump_tag]')"
	var/list/faults = list()
	if(V.stat & BROKEN)
		faults += "BROKEN"
	if(V.stat & NOPOWER)
		faults += "NO POWER"
	if(V.welded)
		faults += "WELDED"
	if(!V.node)
		// Say exactly what atmos_init() sees at the one tile it's allowed to
		// look at (get_step(V, V.dir)), instead of just "NO PIPE" -- that
		// boolean alone can't distinguish "nothing there", "something there
		// but it's not an atmos object", "found it but wrong connect_types",
		// and "found it but its initialize_directions doesn't include the
		// direction back to this pump" (e.g. a manifold rotated so its one
		// closed side -- the direction matching ITS OWN dir -- happens to be
		// the side facing this pump).
		var/turf/probe_turf = get_step(V, V.dir)
		var/list/probe_lines = list()
		if(!probe_turf)
			probe_lines += "off the map"
		else
			var/found_any = FALSE
			for(var/obj/structure/machinery/atmospherics/candidate in probe_turf)
				found_any = TRUE
				var/back_dir = get_dir(candidate, V)
				var/dir_ok = candidate.initialize_directions & back_dir
				var/type_ok = candidate.connect_types & V.connect_types
				var/list/init_dir_names = list()
				for(var/bit in list(NORTH, SOUTH, EAST, WEST))
					if(candidate.initialize_directions & bit)
						init_dir_names += dir2text(bit)
				probe_lines += "[candidate.type] own_dir=[dir2text(candidate.dir)] init_dirs=[jointext(init_dir_names, "|")] need_dir=[dir2text(back_dir)] dir_match=[dir_ok ? "yes" : "NO"] type_match=[type_ok ? "yes" : "NO"] (candidate.connect_types=[candidate.connect_types] vs V.connect_types=[V.connect_types])"
			if(!found_any)
				probe_lines += "nothing at ([probe_turf.x],[probe_turf.y],[probe_turf.z]) -- empty tile, no atmos object of any kind"
		faults += "NO PIPE (facing [dir2text(V.dir)], checked ([probe_turf ? "[probe_turf.x],[probe_turf.y],[probe_turf.z]" : "n/a"]): [jointext(probe_lines, " || ")])"
	if(!V.use_power)
		faults += "not running"
	// Report the pump's live settings alongside any faults -- "off"/"ready"
	// alone can't distinguish "never commanded", "commanded but physically
	// unable", and "running but moving nothing because it's pointed the wrong
	// way or bounded wrong".
	var/turf/PT = get_turf(V)
	var/where = PT ? "([PT.x],[PT.y],[PT.z])" : "nowhere"
	// Name the AREA and its ENVIRON power flag explicitly. A vent pump is
	// power_channel = AREA_USAGE_ENVIRON, and can_pump() refuses outright on
	// NOPOWER -- but blueprint-created areas start with power_environ = FALSE
	// (finalize_area(), freelook/blueprints/blueprints.dm) and stay that way
	// until an APC inside them runs update(). That is the usual reason a
	// player-built cycler is dead while a mapped one works.
	var/area/PA = PT ? get_area(PT) : null
	if(PA)
		where += " in '[PA.name]' (environ power: [PA.power_environ ? "ON" : "OFF"])"
	var/settings = "pwr=[V.use_power] dir=[V.pump_direction ? "release" : "siphon"] ext_bound=[round(V.external_pressure_bound, 0.1)] checks=[V.pressure_checks]"
	var/env_desc = ""
	if(PT)
		var/datum/gas_mixture/env = PT.return_air()
		if(env)
			env_desc = " env=[round(XGM_PRESSURE(env), 0.1)]kPa"
	var/pipe_desc = " pipe=[V.air_contents ? "[round(XGM_PRESSURE(V.air_contents), 0.1)]kPa" : "none"]"
	if(length(faults))
		return "[english_list(faults)] | [V.name] @[where] | [settings][env_desc][pipe_desc]"
	return "ready | [V.name] @[where] | [settings][env_desc][pipe_desc]"

/// Human-readable snapshot of internal state for the console's diagnostics
/// section -- built precisely because "it just opens the door instead of
/// cycling" is otherwise impossible to tell apart from outside the object:
/// is a tag never linked, is a sensor never reporting, or is the state
/// machine genuinely stuck? This makes all three visible directly instead of
/// guessing from symptoms alone.
/datum/computer/file/embedded_program/airlock/get_diagnostics()
	var/list/state_names = list(
		"[STATE_IDLE]" = "Idle",
		"[STATE_PREPARE]" = "Preparing (securing doors)",
		"[STATE_PRESSURIZE]" = "Pressurizing",
		"[STATE_DEPRESSURIZE]" = "Depressurizing",
	)
	var/list/target_names = list(
		"[TARGET_NONE]" = "None",
		"[TARGET_INOPEN]" = "Interior open",
		"[TARGET_OUTOPEN]" = "Exterior open",
	)
	// tag_exterior_door/tag_interior_door/tag_airpump/tag_chamber_sensor on
	// THIS datum are _sync_tags()'s synced copies, which always carry a
	// synthetic "[id_tag]_outer"-style fallback when the controller's real
	// var is null -- reading those here would never show "not linked" even
	// when nothing is actually connected (the exact bug that hid the pump
	// never being linked). Read the controller's raw vars instead so an
	// unlinked slot genuinely reads as unlinked. tag_exterior_sensor/
	// tag_interior_sensor have no such fallback in _sync_tags(), so those
	// stay read straight off this datum below.
	var/obj/structure/machinery/embedded_controller/radio/airlock/controller = master
	var/real_exterior_door = istype(controller) ? controller.tag_exterior_door : null
	var/real_interior_door = istype(controller) ? controller.tag_interior_door : null
	var/real_chamber_sensor = istype(controller) ? controller.tag_chamber_sensor : null
	return list(
		"state" = state_names["[state]"] || "Unknown ([state])",
		"target_state" = target_names["[target_state]"] || "Unknown ([target_state])",
		"chamber_pressure" = round(memory["chamber_sensor_pressure"], 0.1),
		"external_pressure" = round(memory["external_sensor_pressure"], 0.1),
		"internal_pressure" = round(memory["internal_sensor_pressure"], 0.1),
		"pump_status" = memory["pump_status"],
		"pump_condition" = _get_all_pump_conditions(),
		"tag_exterior_door" = real_exterior_door || "not linked",
		"tag_interior_door" = real_interior_door || "not linked",
		"tag_airpump" = length(tag_airpumps) ? jointext(tag_airpumps, ", ") : "not linked",
		"tag_chamber_sensor" = real_chamber_sensor || "not linked",
		"tag_exterior_sensor" = tag_exterior_sensor || "not linked",
		"tag_interior_sensor" = tag_interior_sensor || "not linked",
	)

/datum/computer/file/embedded_program/airlock/process()
	// Every pump/door signal below is addressed with these tags, but they were
	// only refreshed in receive_signal()/receive_user_command() -- so a relink
	// while a cycle was mid-flight left this loop signalling stale tags.
	_sync_tags()

	// Read the pump's true state straight off the object instead of waiting
	// for a radio status broadcast. The broadcast only fires from the pump's
	// own process() after it accepts a command, so any break in radio
	// delivery left this pinned at "unknown"/"off" permanently and the cycle
	// could never conclude the pump had finished.
	// Across ALL linked pumps: report running if any of them is, so a cycle
	// isn't declared finished while a second vent is still moving air.
	var/any_pump_found = FALSE
	var/running_status = null
	for(var/pump_tag in tag_airpumps)
		var/obj/structure/machinery/atmospherics/unary/vent_pump/live_pump = _resolve_pump_by_tag(pump_tag)
		if(!live_pump)
			continue
		any_pump_found = TRUE
		if(live_pump.use_power)
			running_status = live_pump.pump_direction ? "release" : "siphon"
	if(any_pump_found)
		memory["pump_status"] = running_status || "off"

	// Stall watchdog, measured against PROGRESS rather than elapsed time. It
	// used to abort on total wall-clock spent outside STATE_IDLE, which killed
	// perfectly healthy cycles partway through whenever a chamber was large
	// enough that reaching target legitimately took longer than the timeout.
	// Now the clock only runs while chamber pressure isn't moving, so a slow
	// cycle finishes and only a genuinely stuck one (unlinked/unpowered pump
	// that will never report completion) gets dumped back to idle.
	if(state == STATE_IDLE)
		state_stall_start = 0
		last_progress_pressure = null
	else
		var/current_pressure = memory["chamber_sensor_pressure"]
		if(isnull(last_progress_pressure) || abs(current_pressure - last_progress_pressure) > AIRLOCK_CYCLE_PROGRESS_EPSILON)
			last_progress_pressure = current_pressure
			state_stall_start = world.time
		else if(!state_stall_start)
			state_stall_start = world.time
		else if(world.time - state_stall_start > AIRLOCK_CYCLE_STALL_TIMEOUT)
			log_world("Airlock cycler [master] made no pressure progress for over [AIRLOCK_CYCLE_STALL_TIMEOUT / 10] seconds in cycle state [state] (likely an unlinked, unpowered or unpiped pump) -- auto-aborting to idle.")
			stop_cycling()
			state_stall_start = 0
			last_progress_pressure = null

	if(!state) //Idle
		if(target_state)
			switch(target_state)
				if(TARGET_INOPEN)
					memory["target_pressure"] = memory["internal_sensor_pressure"]
				if(TARGET_OUTOPEN)
					memory["target_pressure"] = memory["external_sensor_pressure"]

			//lock down the airlock before activating pumps
			close_doors()

			state = STATE_PREPARE
		else
			//make sure to return to a sane idle state
			if(memory["pump_status"] != "off")	//send a signal to stop pumping
				signalAirpumps(0)
				if(cycle_to_external_air)
					signalPump(tag_pump_out_internal, 0)
					signalPump(tag_pump_out_external, 0)

	if ((state == STATE_PRESSURIZE || state == STATE_DEPRESSURIZE) && !check_doors_secured())
		//the airlock will not allow itself to continue to cycle when any of the doors are forced open.
		stop_cycling()

	switch(state)
		if(STATE_PREPARE)
			if(check_doors_secured())
				var/chamber_pressure = memory["chamber_sensor_pressure"]
				var/target_pressure = memory["target_pressure"]

				if(memory["purge"])
					//purge apparently means clearing the airlock chamber to vacuum (then refilling, handled later)
					target_pressure = 0
					state = STATE_DEPRESSURIZE
					if(!cycle_to_external_air || target_state == TARGET_OUTOPEN) // if going outside, pump internal air into air tank
						signalAirpumps(1, 0, target_pressure)	//send a signal to start depressurizing
					else
						signalPump(tag_pump_out_internal, 1, 0, target_pressure) // if going inside, pump external air out of the airlock
						signalPump(tag_pump_out_external, 1, 1, 1000) // make sure the air is actually going outside

				else if(chamber_pressure <= target_pressure)
					state = STATE_PRESSURIZE
					if(!cycle_to_external_air || target_state == TARGET_INOPEN) // if going inside, pump air into airlock
						signalAirpumps(1, 1, target_pressure)	//send a signal to start pressurizing
					else
						signalPump(tag_pump_out_internal, 1, 1, target_pressure) // if going outside, fill airlock with external air
						signalPump(tag_pump_out_external, 1, 0, 0)

				else if(chamber_pressure > target_pressure)
					if(!cycle_to_external_air)
						state = STATE_DEPRESSURIZE
						signalAirpumps(1, 0, target_pressure)	//send a signal to start depressurizing
					else
						memory["purge"] = 1 // should always purge first if using external air, chamber pressure should never be higher than target pressure here

				memory["target_pressure"] = target_pressure

		if(STATE_PRESSURIZE)
			if(memory["chamber_sensor_pressure"] >= memory["target_pressure"] - SENSOR_TOLERANCE)
				//not done until the pump has reported that it's off
				if(memory["pump_status"] != "off")
					signalAirpumps(0)
					if(cycle_to_external_air)
						signalPump(tag_pump_out_internal, 0)
						signalPump(tag_pump_out_external, 0)
				else
					cycleDoors(target_state)
					state = STATE_IDLE
					target_state = TARGET_NONE
			else
				// Target not reached -- re-assert the run command every tick
				// rather than relying on the single one sent on entry above.
				// A vent_pump defaults to POWER_USE_OFF and force-disables
				// itself whenever it has no pipe node (vent_pump.dm), so one
				// missed/undone command used to strand the cycle permanently
				// until the stall watchdog gave up. Repeating it also lets a
				// cycle recover on its own the moment the pump becomes usable.
				if(!cycle_to_external_air || target_state == TARGET_INOPEN)
					signalAirpumps(1, 1, memory["target_pressure"])
				else
					signalPump(tag_pump_out_internal, 1, 1, memory["target_pressure"])
					signalPump(tag_pump_out_external, 1, 0, 0)


		if(STATE_DEPRESSURIZE)
			if(memory["chamber_sensor_pressure"] <= memory["target_pressure"] + SENSOR_TOLERANCE)
				if(memory["pump_status"] != "off")
					signalAirpumps(0)
					if(cycle_to_external_air)
						signalPump(tag_pump_out_internal, 0)
						signalPump(tag_pump_out_external, 0)
				else
					if(memory["purge"])
						memory["purge"] = 0
						memory["target_pressure"] = (target_state == TARGET_INOPEN ? memory["internal_sensor_pressure"] : memory["external_sensor_pressure"])
						if (memory["target_pressure"] > SENSOR_TOLERANCE)
							state = STATE_PREPARE
					else
						cycleDoors(target_state)
						state = STATE_IDLE
						target_state = TARGET_NONE
			else
				// Target not reached -- re-assert the run command every tick.
				// Mirrors the STATE_PRESSURIZE branch above; see its comment.
				if(!cycle_to_external_air || target_state == TARGET_OUTOPEN)
					signalAirpumps(1, 0, memory["target_pressure"])
				else
					signalPump(tag_pump_out_internal, 1, 0, memory["target_pressure"])
					signalPump(tag_pump_out_external, 1, 1, 1000)


	memory["processing"] = (state != target_state)

	return 1

//these are here so that other types don't have to make so many assumptions about our implementation

/datum/computer/file/embedded_program/airlock/proc/begin_cycle_in()
	state = STATE_IDLE
	target_state = TARGET_INOPEN
	memory["purge"] = cycle_to_external_air

/datum/computer/file/embedded_program/airlock/proc/begin_dock_cycle()
	state = STATE_IDLE
	target_state = TARGET_INOPEN

/datum/computer/file/embedded_program/airlock/proc/begin_cycle_out()
	state = STATE_IDLE
	target_state = TARGET_OUTOPEN
	memory["purge"] = cycle_to_external_air

/datum/computer/file/embedded_program/airlock/proc/close_doors()
	toggleDoor(memory["interior_status"], tag_interior_door, 1, "close")
	toggleDoor(memory["exterior_status"], tag_exterior_door, 1, "close")

/datum/computer/file/embedded_program/airlock/proc/stop_cycling()
	state = STATE_IDLE
	target_state = TARGET_NONE

/datum/computer/file/embedded_program/airlock/proc/done_cycling()
	return (state == STATE_IDLE && target_state == TARGET_NONE)

//are the doors closed and locked?
/datum/computer/file/embedded_program/airlock/proc/check_exterior_door_secured()
	return (memory["exterior_status"]["state"] == "closed" &&  memory["exterior_status"]["lock"] == "locked")

/datum/computer/file/embedded_program/airlock/proc/check_interior_door_secured()
	return (memory["interior_status"]["state"] == "closed" &&  memory["interior_status"]["lock"] == "locked")

/datum/computer/file/embedded_program/airlock/proc/check_doors_secured()
	var/ext_closed = check_exterior_door_secured()
	var/int_closed = check_interior_door_secured()
	return (ext_closed && int_closed)

/datum/computer/file/embedded_program/airlock/proc/signalDoor(tag, command)
	var/datum/signal/signal = new
	signal.data["tag"] = tag
	signal.data["command"] = command
	post_signal(signal, RADIO_AIRLOCK)

/// Resolves a vent pump by id_tag, cached so process() isn't scanning all
/// machinery every tick.
/datum/computer/file/embedded_program/airlock/proc/_resolve_pump_by_tag(pump_tag)
	if(!pump_tag)
		return null
	// Cache per tag -- a multi-pump chamber resolves several different tags
	// every tick, so a single-slot cache would thrash and rescan all machinery
	// once per pump per tick.
	var/obj/structure/machinery/atmospherics/unary/vent_pump/hit = LAZYACCESS(cached_pumps, pump_tag)
	if(hit && !QDELETED(hit) && hit.id_tag == pump_tag)
		return _ensure_pump_piped(hit)
	LAZYREMOVE(cached_pumps, pump_tag)
	// Prefer a match on the controller's OWN z-level. Legacy saved tags can be
	// bare auto-assigned uid numbers (see vent_pump's _ensure_id_tag()) which
	// aren't unique across boots, so a naive first-match can bind a cycler to
	// a vent in an unrelated room on a different z entirely.
	var/turf/here = master ? get_turf(master) : null
	var/obj/structure/machinery/atmospherics/unary/vent_pump/fallback
	for(var/obj/structure/machinery/atmospherics/unary/vent_pump/V in SSmachinery.machinery)
		if(V.id_tag != pump_tag)
			continue
		var/turf/there = get_turf(V)
		if(here && there && there.z == here.z)
			LAZYSET(cached_pumps, pump_tag, V)
			return _ensure_pump_piped(V)
		if(!fallback)
			fallback = V
	if(fallback)
		LAZYSET(cached_pumps, pump_tag, fallback)
	return _ensure_pump_piped(fallback)

/// A resolved pump with no pipe node is permanently self-disabled
/// (vent_pump/process(): `if(!node) update_use_power(POWER_USE_OFF)`), even
/// though it's a perfectly valid, correctly-linked pump as far as the
/// controller is concerned -- e.g. two vents on the same run, one linked
/// before the pipe network between them had actually settled/merged. The
/// one-shot rescan at link time (_link_to_airpump()) only catches this if
/// the pipe is already there at that exact moment. Retrying here means a
/// linked-but-unpiped pump keeps trying to pick up its connection on every
/// cycle instead of staying dead until someone manually relinks it --
/// atmos_init() itself already no-ops instantly once node is set, so this
/// costs nothing once the pump is actually working.
///
/// Also re-derives the pump's NOPOWER stat bit the same way. That bit is a
/// cache that only updates in response to specific events (area power
/// broadcasts, or power_change() being called directly) -- restoring a
/// pump's saved worldstate_vars after a reboot copies the var values
/// straight across but never re-triggers those side effects, so a pump
/// that gets recreated before its area's own power state has settled can
/// come back permanently stuck reporting NOPOWER even once the area is
/// genuinely fine, with nothing to ever correct it short of a manual
/// relink (which happens to call power_change() itself). Checking it here
/// closes that gap the same way as the pipe rescan above -- power_change()
/// itself is cheap and a no-op whenever the cached bit already matches
/// reality.
/datum/computer/file/embedded_program/airlock/proc/_ensure_pump_piped(obj/structure/machinery/atmospherics/unary/vent_pump/V)
	if(!V)
		return V
	if(!V.node)
		V.atmos_init()
		V.build_network()
	if(V.stat & NOPOWER)
		V.power_change()
	return V

/// Issues the same command to EVERY linked chamber vent pump. A chamber with
/// two vents has to drive both together -- commanding only the primary leaves
/// the other idle (or worse, still running its old air-alarm settings and
/// fighting the cycle), and the chamber never reaches target pressure.
/datum/computer/file/embedded_program/airlock/proc/signalAirpumps(power, direction, pressure)
	if(!length(tag_airpumps))
		signalPump(tag_airpump, power, direction, pressure)
		return
	var/dead_tags = list()
	for(var/pump_tag in tag_airpumps)
		if(!_resolve_pump_by_tag(pump_tag))
			dead_tags += pump_tag
		signalPump(pump_tag, power, direction, pressure)
	// A tag that resolves to nothing means signalPump()'s direct-apply
	// silently no-ops and only the (equally unreachable) radio broadcast goes
	// out, so that pump just never runs with no indication why. Say so.
	if(length(dead_tags) && world.time > next_dead_pump_warning)
		next_dead_pump_warning = world.time + 30 SECONDS
		log_world("Airlock cycler [master]: [length(dead_tags)] of [length(tag_airpumps)] linked pump tag\s resolve to no live pump ([jointext(dead_tags, ", ")]) -- those vents cannot be driven. Relink them.")

/datum/computer/file/embedded_program/airlock/proc/signalPump(tag, power, direction, pressure)
	// Apply the command DIRECTLY to the pump as well as broadcasting it.
	// Radio delivery only lands if the pump happens to be registered on the
	// same frequency AND a filter this controller's broadcast reaches, and
	// when it doesn't the failure is completely silent -- the pump simply
	// never acts and never reports, leaving pump_status stuck on its
	// New()-time "unknown" forever while the cycle waits on a reply that can
	// never come. Mirrors exactly what the pump's own receive_signal() would
	// have done with this signal.
	var/obj/structure/machinery/atmospherics/unary/vent_pump/V = _resolve_pump_by_tag(tag)
	if(V)
		V.hibernate = 0
		if(!isnull(direction))
			V.pump_direction = direction
		if(!isnull(pressure))
			V.external_pressure_bound = between(0, pressure, MAX_VENT_PRESSURE)
		V.pressure_checks = 1
		// Lift the vent's per-tick turf flow cap only while we're actually
		// driving it -- see vent_pump.dm's cycler_boost.
		V.cycler_boost = !!power
		V.update_use_power(power)
		V.broadcast_status_next_process = TRUE

	var/datum/signal/signal = new
	signal.data = list(
		"tag" = tag,
		"sigtype" = "command",
		"power" = power,
		"direction" = direction,
		"set_external_pressure" = pressure,
		// Force PRESSURE_CHECK_EXTERNAL rather than inheriting whatever the
		// pump was last left on. get_pressure_delta() (vent_pump.dm) branches
		// entirely on this mask, and a mapped-in pump previously configured by
		// an air alarm can be sitting on PRESSURE_CHECK_INTERNAL -- where a
		// siphon computes internal_pressure_bound - pipe_pressure, frequently
		// <= 0, so the pump silently moves nothing while still reporting
		// itself powered. External is correct for both directions the cycler
		// uses: siphon compares environment - external_bound, release compares
		// external_bound - environment.
		"checks" = 1
	)
	post_signal(signal)

//this is called to set the appropriate door state at the end of a cycling process, or for the exterior buttons
/datum/computer/file/embedded_program/airlock/proc/cycleDoors(var/target)
	switch(target)
		if(TARGET_OUTOPEN)
			toggleDoor(memory["interior_status"], tag_interior_door, memory["secure"], "close")
			toggleDoor(memory["exterior_status"], tag_exterior_door, memory["secure"], "open")

		if(TARGET_INOPEN)
			toggleDoor(memory["exterior_status"], tag_exterior_door, memory["secure"], "close")
			toggleDoor(memory["interior_status"], tag_interior_door, memory["secure"], "open")
		if(TARGET_NONE)
			var/command = "unlock"
			if(memory["secure"])
				command = "lock"
			signalDoor(tag_exterior_door, command)
			signalDoor(tag_interior_door, command)

/datum/computer/file/embedded_program/airlock/proc/signal_mech_sensor(var/command, var/sensor)
	var/datum/signal/signal = new
	signal.data["tag"] = sensor
	signal.data["command"] = command
	post_signal(signal)

/datum/computer/file/embedded_program/airlock/proc/enable_mech_regulation()
	signal_mech_sensor("enable", tag_shuttle_mech_sensor)
	signal_mech_sensor("enable", tag_airlock_mech_sensor)

/datum/computer/file/embedded_program/airlock/proc/disable_mech_regulation()
	signal_mech_sensor("disable", tag_shuttle_mech_sensor)
	signal_mech_sensor("disable", tag_airlock_mech_sensor)

/*----------------------------------------------------------
toggleDoor()

Sends a radio command to a door to either open or close. If
the command is 'toggle' the door will be sent a command that
reverses it's current state.
Can also toggle whether the door bolts are locked or not,
depending on the state of the 'secure' flag.
Only sends a command if it is needed, i.e. if the door is
already open, passing an open command to this proc will not
send an additional command to open the door again.
----------------------------------------------------------*/
/datum/computer/file/embedded_program/airlock/proc/toggleDoor(var/list/doorStatus, var/doorTag, var/secure, var/command)
	var/doorCommand = null

	if(command == "toggle")
		if(doorStatus["state"] == "open")
			command = "close"
		else if(doorStatus["state"] == "closed")
			command = "open"

	switch(command)
		if("close")
			if(secure)
				if(doorStatus["state"] == "open")
					doorCommand = "secure_close"
				else if(doorStatus["lock"] == "unlocked")
					doorCommand = "lock"
			else
				if(doorStatus["state"] == "open")
					if(doorStatus["lock"] == "locked")
						signalDoor(doorTag, "unlock")
					doorCommand = "close"
				else if(doorStatus["lock"] == "locked")
					doorCommand = "unlock"

		if("open")
			if(secure)
				if(doorStatus["state"] == "closed")
					doorCommand = "secure_open"
				else if(doorStatus["lock"] == "unlocked")
					doorCommand = "lock"
			else
				if(doorStatus["state"] == "closed")
					if(doorStatus["lock"] == "locked")
						signalDoor(doorTag,"unlock")
					doorCommand = "open"
				else if(doorStatus["lock"] == "locked")
					doorCommand = "unlock"

	if(doorCommand)
		signalDoor(doorTag, doorCommand)


#undef STATE_IDLE
#undef STATE_DEPRESSURIZE
#undef STATE_PRESSURIZE

#undef TARGET_NONE
#undef TARGET_INOPEN
#undef TARGET_OUTOPEN

#undef SENSOR_TOLERANCE

#undef AIRLOCK_CYCLE_STALL_TIMEOUT
