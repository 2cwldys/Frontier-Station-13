#define DEFAULT_PRESSURE_DELTA 10000

#define EXTERNAL_PRESSURE_BOUND ONE_ATMOSPHERE
#define INTERNAL_PRESSURE_BOUND 0
#define PRESSURE_CHECKS 1

#define PRESSURE_CHECK_EXTERNAL 1
#define PRESSURE_CHECK_INTERNAL 2

/// Multiplier applied to a vent's per-tick turf flow cap while an airlock
/// cycler is driving it. See cycler_boost.
#define VENT_PUMP_CYCLER_FLOW_BOOST 25

/obj/structure/machinery/atmospherics/unary/vent_pump
	name = "air vent"
	desc = "Has a valve and pump attached to it."
	icon = 'icons/atmos/vent_pump.dmi'
	icon_state = "map_vent"

	use_power = POWER_USE_OFF
	idle_power_usage = 150		//internal circuitry, friction losses and stuff
	power_rating = 30000			//30000 W ~ 40 HP

	connect_types = CONNECT_TYPE_REGULAR|CONNECT_TYPE_SUPPLY //connects to regular and supply pipes

	var/area/initial_loc
	level = 1
	var/area_uid
	var/id_tag = null

	var/hibernate = 0 //Do we even process?
	var/pump_direction = 1 //0 = siphoning, 1 = releasing

	var/external_pressure_bound = EXTERNAL_PRESSURE_BOUND
	var/internal_pressure_bound = INTERNAL_PRESSURE_BOUND

	var/pressure_checks = PRESSURE_CHECKS
	//1: Do not pass external_pressure_bound
	//2: Do not pass internal_pressure_bound
	//3: Do not pass either

	// Used when handling incoming radio signals requesting default settings
	var/external_pressure_bound_default = EXTERNAL_PRESSURE_BOUND
	var/internal_pressure_bound_default = INTERNAL_PRESSURE_BOUND
	var/pressure_checks_default = PRESSURE_CHECKS

	var/welded = 0 // Added for aliens -- TLE

	var/frequency = 1439
	var/datum/radio_frequency/radio_connection

	var/radio_filter_out
	var/radio_filter_in

	var/broadcast_status_next_process = FALSE

	/// TRUE while an airlock cycler is actively driving this vent (set by the
	/// controller's signalPump(), cleared when it powers the vent back off).
	/// Lifts the per-tick turf flow cap in process() so an airlock chamber
	/// actually evacuates/fills on demand instead of at ambient-upkeep rate.
	var/cycler_boost = FALSE

/obj/structure/machinery/atmospherics/unary/vent_pump/mechanics_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "This pumps the contents of the attached pipe out into the atmosphere, if needed."
	. += "It can be controlled from an Air Alarm."

/obj/structure/machinery/atmospherics/unary/vent_pump/feedback_hints(mob/user, distance, is_adjacent)
	. += ..()
	if(distance <= 1)
		. += "A small gauge in the corner reads [round(last_flow_rate, 0.1)] L/s at [round(last_power_draw)] W."
	else
		. += "You are too far away to read the gauge."
	if(welded)
		. += "It seems welded shut."

/obj/structure/machinery/atmospherics/unary/vent_pump/on
	use_power = POWER_USE_IDLE
	icon_state = "map_vent_out"

/obj/structure/machinery/atmospherics/unary/vent_pump/siphon
	pump_direction = 0
	frequency = 1441

/obj/structure/machinery/atmospherics/unary/vent_pump/siphon/atmos
	icon_state = "map_vent"
	external_pressure_bound = 0
	external_pressure_bound_default = 0
	internal_pressure_bound = PRESSURE_ONE_THOUSAND * 2
	internal_pressure_bound_default = PRESSURE_ONE_THOUSAND * 2
	pressure_checks = 2
	pressure_checks_default = 2

/obj/structure/machinery/atmospherics/unary/vent_pump/siphon/on
	use_power = POWER_USE_IDLE
	icon_state = "map_vent_in"

/obj/structure/machinery/atmospherics/unary/vent_pump/siphon/on/atmos
	use_power = POWER_USE_IDLE
	icon_state = "map_vent_in"
	external_pressure_bound = 0
	external_pressure_bound_default = 0
	internal_pressure_bound = PRESSURE_ONE_THOUSAND * 2
	internal_pressure_bound_default = PRESSURE_ONE_THOUSAND * 2
	pressure_checks = 2
	pressure_checks_default = 2

/obj/structure/machinery/atmospherics/unary/vent_pump/aux
	icon_state = "map_vent_aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX //connects to aux pipes

/obj/structure/machinery/atmospherics/unary/vent_pump/Initialize(mapload)
	if(mapload)
		var/turf/T = loc
		var/image/I = image(icon, T, icon_state, dir, pixel_x, pixel_y)
		I.plane = ABOVE_LIGHTING_PLANE
		I.color = color
		I.alpha = 125
		LAZYADD(T.blueprints, I)

	. = ..()
	air_contents.volume = ATMOS_DEFAULT_VOLUME_PUMP

	initial_loc = loc.loc
	area_uid = initial_loc.uid
	if (!id_tag)
		assign_uid()
		id_tag = num2text(uid)
	setup_radio()

/// A vent defaults to POWER_USE_OFF (above), which makes the base
/// post_machine_initialize() (power_usage.dm) return BEFORE it reaches
/// setup_area_power_relationship() -- the only thing in the codebase that
/// subscribes a machine to COMSIG_AREA_POWER_CHANGE. At init the area's APC
/// hasn't restored its power channels yet (areas.dm), so power_change() sets
/// stat |= NOPOWER, and with no subscription that bit can never be cleared
/// again. receive_signal() below hard-returns on it, so the vent silently
/// ignored every air alarm and tank-console command for the rest of its life.
///
/// POWER_USE_OFF here means "idle right now", not "never draws power" -- these
/// switch themselves to POWER_USE_IDLE/ACTIVE at runtime -- so the area
/// relationship has to exist regardless of the starting mode. The /on subtypes
/// only ever worked because they start POWER_USE_IDLE and thus never hit that
/// early return.
/obj/structure/machinery/atmospherics/unary/vent_pump/post_machine_initialize()
	..()
	setup_area_power_relationship()

/obj/structure/machinery/atmospherics/unary/vent_pump/proc/setup_radio()
	//some vents work his own special way
	radio_filter_in = frequency == 1439 ? (RADIO_FROM_AIRALARM) : null
	radio_filter_out = frequency == 1439 ? (RADIO_TO_AIRALARM) : null
	if(frequency)
		radio_connection = register_radio(src, frequency, frequency, radio_filter_in)

// Different from the above.
/obj/structure/machinery/atmospherics/unary/vent_pump/atmos_init()
	..()
	broadcast_status()

/obj/structure/machinery/atmospherics/unary/vent_pump/Destroy()
	unregister_radio(src, frequency)

	if(initial_loc)
		initial_loc.air_vent_info -= id_tag
		initial_loc.air_vent_names -= id_tag

	return ..()

/obj/structure/machinery/atmospherics/unary/vent_pump/high_volume
	name = "Large Air Vent"
	power_channel = AREA_USAGE_EQUIP
	power_rating = 45000	//45 kW ~ 60 HP

/obj/structure/machinery/atmospherics/unary/vent_pump/high_volume/Initialize()
	. = ..()
	air_contents.volume = ATMOS_DEFAULT_VOLUME_PUMP + 800

/obj/structure/machinery/atmospherics/unary/vent_pump/high_volume/aux
	icon_state = "map_vent_aux"
	icon_connect_type = "-aux"
	connect_types = CONNECT_TYPE_AUX //connects to aux pipes

/obj/structure/machinery/atmospherics/unary/vent_pump/engine
	name = "Reactor Core Vent"
	power_channel = AREA_USAGE_ENVIRON
	power_rating = 30000	//30 kW ~ 40 HP

/obj/structure/machinery/atmospherics/unary/vent_pump/engine/Initialize()
	. = ..()
	air_contents.volume = ATMOS_DEFAULT_VOLUME_PUMP + 500 //meant to match air injector

/obj/structure/machinery/atmospherics/unary/vent_pump/update_icon(safety = 0)
	if (!node)
		update_use_power(POWER_USE_OFF)

	var/vent_icon = ""

	if(welded)
		vent_icon += "weld"
	else if(!powered())
		vent_icon += "off"
	else
		vent_icon += "[use_power ? "[pump_direction ? "out" : "in"]" : "off"]"

	icon_state = vent_icon

	update_underlays()

/obj/structure/machinery/atmospherics/unary/vent_pump/update_underlays()
	if(..())
		underlays.Cut()
		var/turf/T = get_turf(src)
		if(!istype(T))
			return
		if(!T.is_plating() && node && node.level == 1 && istype(node, /obj/structure/machinery/atmospherics/pipe))
			return
		else
			if(node)
				add_underlay(T, node, dir, node.icon_connect_type)
			else
				add_underlay(T,, dir)
			underlays += "frame"

/obj/structure/machinery/atmospherics/unary/vent_pump/hide()
	queue_icon_update()

/obj/structure/machinery/atmospherics/unary/vent_pump/proc/can_pump()
	if(stat & (NOPOWER|BROKEN))
		return 0
	if(!use_power)
		return 0
	if(welded)
		return 0
	return 1

/obj/structure/machinery/atmospherics/unary/vent_pump/process(seconds_per_tick)
	..()

	if (broadcast_status_next_process)
		broadcast_status()
		broadcast_status_next_process = FALSE

	if (hibernate > world.time)
		return 1

	if (!node)
		update_use_power(POWER_USE_OFF)
	if(!can_pump())
		return 0

	if(!loc) return FALSE

	var/datum/gas_mixture/environment = loc.return_air()

	var/power_draw = -1

	//Figure out the target pressure difference
	var/pressure_delta = get_pressure_delta(environment)
	//src.visible_message("DEBUG >>> [src]: pressure_delta = [pressure_delta]")

	if((environment.temperature || air_contents.temperature) && pressure_delta > 0.5)
		if(pump_direction) //internal -> external
			var/transfer_moles = calculate_transfer_moles(air_contents, environment, pressure_delta)
			power_draw = pump_gas(src, air_contents, environment, transfer_moles, power_rating)
		else //external -> internal
			var/transfer_moles = calculate_transfer_moles(environment, air_contents, pressure_delta, (network)? network.volume : 0)

			//limit flow rate from turfs
			// The cap is this vent's own internal volume as a FRACTION of the
			// whole zone's volume, so the larger the room the less each tick
			// can move. Fine for ambient upkeep, but an airlock chamber has to
			// fully evacuate on demand -- and a player-built chamber is much
			// bigger than the 2-3 tile mapped airlocks this was tuned against,
			// which is why cycling one crawls. While a cycler is actively
			// driving this vent, lift the cap so it evacuates at a rate
			// appropriate to an airlock. Untouched for every other vent.
			var/flow_cap = environment.total_moles*air_contents.volume/environment.volume	//group_multiplier gets divided out here
			if(cycler_boost)
				flow_cap *= VENT_PUMP_CYCLER_FLOW_BOOST
			transfer_moles = min(transfer_moles, flow_cap)
			power_draw = pump_gas(src, environment, air_contents, transfer_moles * seconds_per_tick, power_rating)

	else
		//If we're in an area that is fucking ideal, and we don't have to do anything, chances are we won't next tick either so why redo these calculations?
		//JESUS FUCK.  THERE ARE LITERALLY 250 OF YOU MOTHERFUCKERS ON ZLEVEL ONE AND YOU DO THIS SHIT EVERY TICK WHEN VERY OFTEN THERE IS NO REASON TO
		if(pump_direction && pressure_checks == PRESSURE_CHECK_EXTERNAL) //99% of all vents
			hibernate = world.time + (rand(100,200))


	if (power_draw >= 0)
		last_power_draw = power_draw
		use_power_oneoff(power_draw * seconds_per_tick)
		if(network)
			network.update = 1

	return 1

/obj/structure/machinery/atmospherics/unary/vent_pump/proc/get_pressure_delta(datum/gas_mixture/environment)
	var/pressure_delta = DEFAULT_PRESSURE_DELTA
	var/environment_pressure = XGM_PRESSURE(environment)

	if(pump_direction) //internal -> external
		if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
			pressure_delta = min(pressure_delta, external_pressure_bound - environment_pressure) //increasing the pressure here
		if(pressure_checks & PRESSURE_CHECK_INTERNAL)
			pressure_delta = min(pressure_delta, XGM_PRESSURE(air_contents) - internal_pressure_bound) //decreasing the pressure here
	else //external -> internal
		if(pressure_checks & PRESSURE_CHECK_EXTERNAL)
			pressure_delta = min(pressure_delta, environment_pressure - external_pressure_bound) //decreasing the pressure here
		if(pressure_checks & PRESSURE_CHECK_INTERNAL)
			pressure_delta = min(pressure_delta, internal_pressure_bound - XGM_PRESSURE(air_contents)) //increasing the pressure here

	return pressure_delta

/obj/structure/machinery/atmospherics/unary/vent_pump/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	signal.source = src

	signal.data = list(
		"area" = src.area_uid,
		"tag" = src.id_tag,
		"device" = "AVP",
		"power" = use_power,
		"direction" = pump_direction?("release"):("siphon"),
		"checks" = pressure_checks,
		"internal" = internal_pressure_bound,
		"external" = external_pressure_bound,
		"timestamp" = world.time,
		"sigtype" = "status",
		"power_draw" = last_power_draw,
		"flow_rate" = last_flow_rate
	)

	var/area/A = get_area(src)
	// Only auto-name a vent that still carries its type-default name. The
	// number is just "how many entries this area's list has", and the vent
	// registers under whatever id_tag it holds AT THAT MOMENT -- but
	// atmos_init() broadcasts during Initialize, before persistence restores
	// the saved id_tag, so each pump claimed one slot under its throwaway
	// startup tag and another under its restored one. The counter climbed
	// every boot (#1/#2 becoming #5/#6). A pump with a restored name now
	// keeps it and stops consuming numbers.
	if(!A.air_vent_names[id_tag] && name == initial(name))
		var/new_name = "[A.name] Vent Pump #[A.air_vent_names.len+1]"
		A.air_vent_names[id_tag] = new_name
		src.name = new_name
	A.air_vent_info[id_tag] = signal.data

	radio_connection.post_signal(src, signal, radio_filter_out)

	return 1

/obj/structure/machinery/atmospherics/unary/vent_pump/receive_signal(datum/signal/signal)
	if(stat & (NOPOWER|BROKEN))
		return

	hibernate = 0

	//LOG_DEBUG("DEBUG \[[world.timeofday]\]: /obj/structure/machinery/atmospherics/unary/vent_pump/receive_signal([signal.debug_print()])")
	if(!signal.data["tag"] || (signal.data["tag"] != id_tag) || (signal.data["sigtype"]!="command"))
		return 0

	if(signal.data["purge"] != null)
		pressure_checks &= ~1
		pump_direction = 0

	if(signal.data["stabalize"] != null)
		pressure_checks |= 1
		pump_direction = 1

	if(signal.data["power"] != null)
		update_use_power(text2num(signal.data["power"]))

	if(signal.data["power_toggle"] != null)
		update_use_power(!use_power)

	if(signal.data["checks"] != null)
		if (signal.data["checks"] == "default")
			pressure_checks = pressure_checks_default
		else
			pressure_checks = text2num(signal.data["checks"])

	if(signal.data["checks_toggle"] != null)
		pressure_checks = (pressure_checks?0:3)

	if(signal.data["direction"] != null)
		pump_direction = text2num(signal.data["direction"])

	if(signal.data["set_internal_pressure"] != null)
		if (signal.data["set_internal_pressure"] == "default")
			internal_pressure_bound = internal_pressure_bound_default
		else
			var/set_pressure = text2num(signal.data["set_internal_pressure"])
			internal_pressure_bound = between(0, set_pressure, MAX_VENT_PRESSURE)

	if(signal.data["set_external_pressure"] != null)
		if (signal.data["set_external_pressure"] == "default")
			external_pressure_bound = external_pressure_bound_default
		else
			var/set_pressure = text2num(signal.data["set_external_pressure"])
			external_pressure_bound = between(0, set_pressure, MAX_VENT_PRESSURE)

	if(signal.data["adjust_internal_pressure"] != null)
		var/set_pressure = internal_pressure_bound + text2num(signal.data["adjust_internal_pressure"])
		internal_pressure_bound = between(0, set_pressure, MAX_VENT_PRESSURE)

	if(signal.data["adjust_external_pressure"] != null)
		var/set_pressure = external_pressure_bound + text2num(signal.data["adjust_external_pressure"])
		external_pressure_bound = between(0, set_pressure, MAX_VENT_PRESSURE)

	if(signal.data["init"] != null)
		name = signal.data["init"]
		return

	if(signal.data["status"] != null)
		broadcast_status_next_process = TRUE
		return //do not update_icon

	broadcast_status_next_process = TRUE
	update_icon()

/// Sets frequency and re-derives the radio filter via setup_radio() (which
/// special-cases the reserved air-alarm frequency 1439) instead of touching
/// SSradio directly -- keeps this in sync with whatever setup_radio() does
/// on Initialize().
/obj/structure/machinery/atmospherics/unary/vent_pump/proc/set_frequency(new_frequency)
	if(radio_connection)
		SSradio.remove_object(src, frequency)
	frequency = new_frequency
	setup_radio()

/// Auto-assigns a unique id_tag the first time this pump is linked to a
/// cycler controller -- mirrors /obj/structure/machinery/door/airlock's
/// _ensure_id_tag() (airlock_control.dm). Without this, id_tag stayed null
/// forever (nothing else ever set it for a player-built pump), so
/// _link_to_airpump() (airlock_controllers.dm) silently linked the
/// controller's tag_airpump to null -- the pump could never report its
/// status back, permanently stalling any cycle that needed it to complete.
/// Also replaces a BARE NUMERIC tag, not just a null one. Initialize() above
/// falls back to `id_tag = num2text(uid)`, and assign_uid() allocates from
/// gl_uid++ -- a global counter across all machinery, handed out in
/// initialization order and reset every boot. That makes a numeric id_tag a
/// boot-order sequence number rather than an identity: a controller that
/// persists tag_airpump = "755" resolves it next boot to whatever machine
/// happens to be 755th that time, potentially a vent in another room on
/// another z-level. Restored tags collide with freshly-assigned ones too.
///
/// Mapped-in pumps always carry a descriptive .dmm tag ("merc_shuttle_pump"),
/// never a bare number, so numeric-ness cleanly identifies the unstable
/// auto-assigned form. id_tag is in this type's worldstate_vars, so the
/// stable replacement persists and keeps resolving to the same pump.
///
/// Tradeoff: area air alarms address vents by id_tag, so a retagged vent
/// drops off air-alarm control -- correct for a cycler vent, which an alarm
/// would otherwise keep re-commanding in the middle of a cycle.
/obj/structure/machinery/atmospherics/unary/vent_pump/proc/_ensure_id_tag()
	if(!id_tag || !isnull(text2num(id_tag)))
		id_tag = "cycler_[REF(src)]"
	return id_tag

/obj/structure/machinery/atmospherics/unary/vent_pump/attackby(obj/item/attacking_item, mob/user)

	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/controller = MT.get_buffer(/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller)
		if(controller)
			controller._link_to_airpump(src, user)
			MT.set_buffer(null)
			return TRUE
		// Any atmos console with device-linking support (atmo_control.dm) -- an
		// additional consumer of a buffered vent pump, checked alongside the
		// cycler above rather than replacing it, so this pump can serve as a
		// console's Output. Base type, not just large_tank_control specifically,
		// so this also covers supermatter_core (get_buffer() matches via
		// istype(), so a base-type request matches every subtype).
		var/obj/structure/machinery/computer/general_air_control/tank_console = MT.get_buffer(/obj/structure/machinery/computer/general_air_control)
		if(tank_console)
			tank_console._link_atmos_device(src, user)
			MT.set_buffer(null)
			return TRUE
		MT.set_buffer(src)
		to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
		return TRUE

	if(attacking_item.tool_behaviour == TOOL_WELDER)
		var/obj/item/weldingtool/WT = attacking_item
		if (!WT.welding)
			to_chat(user, SPAN_DANGER("\The [WT] must be turned on!"))
		else if (WT.use(0,user))
			to_chat(user, SPAN_NOTICE("Now welding the vent."))
			if(attacking_item.use_tool(src, user, 30, volume = 50))
				if(!src || !WT.isOn())
					return TRUE
				welded = !welded
				update_icon()
				playsound(src, 'sound/items/welder_pry.ogg', 50, 1)
				user.visible_message(SPAN_NOTICE("\The [user] [welded ? "welds \the [src] shut" : "unwelds \the [src]"]."), \
										SPAN_NOTICE("You [welded ? "weld \the [src] shut" : "unweld \the [src]"]."), \
										"You hear welding.")
			else
				to_chat(user, SPAN_NOTICE("You fail to complete the welding."))
		else
			to_chat(user, SPAN_WARNING("You need more welding fuel to complete this task."))
		return TRUE


	else if(istype(attacking_item, /obj/item/melee/arm_blade))
		if(!welded)
			to_chat(user, SPAN_WARNING("\The [attacking_item] can only be used to tear open welded air vents!"))
			return TRUE
		user.visible_message(SPAN_WARNING("\The [user] starts using \the [attacking_item] to hack open \the [src]!"), SPAN_NOTICE("You start hacking open \the [src] with \the [attacking_item]..."))
		user.do_attack_animation(src, used_item = attacking_item)
		playsound(loc, 'sound/weapons/smash.ogg', 60, TRUE)
		var/cut_amount = 3
		for(var/i = 0; i <= cut_amount; i++)
			if(!attacking_item || !do_after(user, 30, src))
				return TRUE
			user.do_attack_animation(src, used_item = attacking_item)
			user.visible_message(SPAN_WARNING("\The [user] smashes \the [attacking_item] into \the [src]!"), SPAN_NOTICE("You smash \the [attacking_item] into \the [src]."))
			playsound(loc, 'sound/weapons/smash.ogg', 60, TRUE)
			if(i == cut_amount)
				welded = FALSE
				spark(get_turf(src), 3, GLOB.alldirs)
				playsound(loc, 'sound/items/welder_pry.ogg', 50, TRUE)
				update_icon()

	else if(attacking_item.tool_behaviour == TOOL_WRENCH)

		if(!(stat & NOPOWER) && use_power)
			to_chat(user, SPAN_WARNING("You cannot unwrench \the [src], turn it off first."))

		else

			var/turf/T = src.loc

			if(node && node.level==1 && isturf(T) && !T.is_plating())
				to_chat(user, SPAN_WARNING("You must remove the plating first."))

			else if(loc)
				var/datum/gas_mixture/int_air = return_air()
				var/datum/gas_mixture/env_air = loc.return_air()

				if((XGM_PRESSURE(int_air)-XGM_PRESSURE(env_air)) > PRESSURE_EXERTED)
					to_chat(user, SPAN_WARNING("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
					add_fingerprint(user)

				else
					to_chat(user, SPAN_NOTICE("You begin to unfasten \the [src]..."))

					if(attacking_item.use_tool(src, user, istype(attacking_item, /obj/item/pipewrench) ? 80 : 40, volume = 50))
						user.visible_message(SPAN_NOTICE("\The [user] unfastens \the [src]."), \
												SPAN_NOTICE("You have unfastened \the [src]."), \
												"You hear a ratchet.")
						new /obj/item/pipe(loc, make_from=src)
						qdel(src)

		return ..()

/obj/structure/machinery/atmospherics/unary/vent_pump/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		update_icon()

#undef DEFAULT_PRESSURE_DELTA

#undef EXTERNAL_PRESSURE_BOUND
#undef INTERNAL_PRESSURE_BOUND
#undef PRESSURE_CHECKS

#undef PRESSURE_CHECK_EXTERNAL
#undef PRESSURE_CHECK_INTERNAL
