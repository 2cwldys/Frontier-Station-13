/obj/item/frame
	name = "frame"
	desc = "Used for building machines."
	icon = 'icons/obj/monitors.dmi'
	icon_state = ""
	obj_flags = OBJ_FLAG_CONDUCTABLE
	var/build_machine_type
	var/refund_amt = 2
	var/refund_type = /obj/item/stack/material/steel

/obj/item/frame/assembly_hints()
	. = list()
	. += ..()
	. += "It could be installed by using it on an adjacent <b>wall</b>."

/obj/item/frame/attackby(obj/item/attacking_item, mob/user)
	if (attacking_item.tool_behaviour == TOOL_WRENCH)
		new refund_type( get_turf(src.loc), refund_amt)
		qdel(src)
		return TRUE
	return ..()

/obj/item/frame/proc/try_build(turf/on_wall, mob/user)
	if(!build_machine_type)
		return

	if (get_dist(on_wall,usr)>1)
		return

	var/ndir = get_dir(usr,on_wall)
	if (!(ndir in GLOB.cardinals))
		to_chat(user, SPAN_WARNING("You need to stand in front of the wall, directly, to build \the [src]!"))
		return

	var/turf/loc = get_turf(usr)
	var/area/A = loc.loc
	if (!istype(loc, /turf/simulated/floor))
		to_chat(usr, SPAN_WARNING("\The [src] cannot be placed on this spot."))
		return
	if (istype(A, /area/space) || istype(A, /area/mine))
		to_chat(usr, SPAN_WARNING("\The [src] cannot be placed in this area."))
		return

	if(gotwallitem(loc, ndir))
		to_chat(usr, SPAN_WARNING("There's already an item on this wall!"))
		return

	var/obj/structure/machinery/M = new build_machine_type(loc, ndir, 1)
	M.fingerprints = src.fingerprints
	M.fingerprintshidden = src.fingerprintshidden
	M.fingerprintslast = src.fingerprintslast
	user.remove_from_mob(src) //Prevents gripper duplication
	qdel(src)

/obj/item/frame/fire_alarm
	name = "fire alarm frame"
	desc = "Used for building fire alarms."
	icon_state = "firealarm"
	build_machine_type = /obj/structure/machinery/firealarm

/obj/item/frame/air_alarm
	name = "air alarm frame"
	desc = "Used for building air alarms."
	icon_state = "alarm_bitem"
	build_machine_type = /obj/structure/machinery/alarm

/obj/item/frame/light
	name = "light fixture frame"
	desc = "Used for building lights."
	icon = 'icons/obj/machinery/light.dmi'
	icon_state = "tube-construct-item"
	build_machine_type = /obj/structure/machinery/light_construct

/obj/item/frame/light/small
	name = "small light fixture frame"
	icon_state = "bulb-construct-item"
	refund_amt = 1
	build_machine_type = /obj/structure/machinery/light_construct/small

/obj/item/frame/light/spot
	name = "spotlight fixture frame"
	icon_state = "slight-construct-item"
	refund_amt = 3
	build_machine_type = /obj/structure/machinery/light_construct/spot

/obj/item/frame/access_button
	name = "access button frame"
	desc = "Used for building airlock access buttons."
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_button_standby"
	build_machine_type = /obj/structure/machinery/access_button

/// Builds a labeled interior-side button (command = "cycle_interior") instead
/// of the generic frame's plain "cycle" toggle. The generic command only ever
/// resolves to cycle_int unless memory["interior_status"]["state"] happens to
/// already be "open" (airlock_program.dm's receive_signal()), so a cycler
/// built from two generic buttons -- exactly what the Airlock Cycler Crate
/// used to hand out -- could never reliably reach cycle_ext at all: every
/// press just fell through to the interior toggle.
/obj/item/frame/access_button/airlock_interior
	name = "interior access button frame"
	build_machine_type = /obj/structure/machinery/access_button/airlock_interior

/// Builds a labeled exterior-side button (command = "cycle_exterior"). See
/// airlock_interior above.
/obj/item/frame/access_button/airlock_exterior
	name = "exterior access button frame"
	build_machine_type = /obj/structure/machinery/access_button/airlock_exterior

/obj/item/frame/airlock_sensor
	name = "chamber airlock sensor frame"
	desc = "Used for building airlock pressure sensors. This one reads the real pressure of the room it's built in -- mount it inside the airlock chamber."
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_sensor_off"
	build_machine_type = /obj/structure/machinery/airlock_sensor

/// Builds the interior-reference sensor -- reports a constant one atmosphere
/// rather than sampling its own turf. See airlock_sensor's pressure_override.
/obj/item/frame/airlock_sensor/airlock_interior
	name = "interior airlock sensor frame"
	desc = "Used for building airlock pressure sensors. This one reports the station-side reference pressure to the controller."
	build_machine_type = /obj/structure/machinery/airlock_sensor/airlock_interior

/// Builds the exterior-reference sensor -- reports a constant vacuum.
/obj/item/frame/airlock_sensor/airlock_exterior
	name = "exterior airlock sensor frame"
	desc = "Used for building airlock pressure sensors. This one reports the outside reference pressure to the controller."
	build_machine_type = /obj/structure/machinery/airlock_sensor/airlock_exterior

/obj/item/frame/airlock_controller
	name = "airlock controller frame"
	desc = "Used for building airlock cycler controllers."
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "airlock_sensor_off"
	build_machine_type = /obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller
