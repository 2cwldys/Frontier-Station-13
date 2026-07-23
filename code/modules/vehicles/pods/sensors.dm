/*
 * Pod sensors -- a pure gate flag enabling the pod's Sector View (see
 * sector_view.dm) to reveal nearby requires_contact overmap objects, the
 * same way real ship sensors gate contact reveal on sensors.use_power
 * (code/modules/overmap/ships/computers/sensors.dm). Without an installed,
 * active sensors part, Sector View still opens (comms-gated) but only ever
 * shows `known` sectors -- those are already plane-visible regardless of
 * sensors (overmap_object.dm's Initialize(): `if(known) plane = ABOVE_LIGHTING_PLANE`).
 *
 * Deliberately not a gradual per-tick identification loop (an earlier
 * version of this file was) -- Sector View's reveal-in-view trick, adapted
 * from personal_travel.dm, is the closer-fitting real precedent for a
 * single pilot rather than a ship console.
 */
/obj/item/podcomponent/sensors
	name = "sensor array"
	desc = "A short-range sensor suite for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "sensor-g"
	power_used = 20

	/// How far (overmap tiles) this array can reveal nearby contacts while
	/// Sector View is active. Matches POD_SENSOR_RANGE, the same footprint
	/// borrowed from /obj/structure/machinery/shipsensors/weak.
	var/range = POD_SENSOR_RANGE

/obj/item/podcomponent/sensors/get_slot()
	return POD_PART_SENSORS
