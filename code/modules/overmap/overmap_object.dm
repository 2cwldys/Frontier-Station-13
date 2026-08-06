/obj/effect/overmap
	name = "map object"
	icon = 'icons/obj/overmap/overmap_effects.dmi'
	icon_state = "object"
	color = "#fffffe"
	mouse_opacity = MOUSE_OPACITY_ICON
	layer = OVERMAP_SECTOR_LAYER
	set_dir_on_move = FALSE

//RP fluff details to appear on scan readouts for any object we want to include these details with
	var/scanimage = "no_data.png"
	/// The shipyard or designer of the object if applicable.
	var/designer = "Unknown"
	/// Length height width of the object in tiles ingame.
	var/volume = "Unestimated"
	/// The expected armament or scale of armament that the design comes with if applicable. Can vary in visibility for obvious reasons.
	var/weapons = "Not apparent"
	/// The class of the design if applicable. Not a prefix. Should be things like battlestations or corvettes.
	var/sizeclass = "Unknown"
	/// The designated purpose of the design. Should briefly describe whether it's a combatant or study vessel for example.
	var/shiptype = "Unknown"

	/// For landing sites. Allows the crew to know if they're landing somewhere bad or not.
	var/alignment = "Unknown"

	///Used to give basic scan descriptions of every generic overmap object that excludes noteworthy locations, ships and exoplanets.
	var/generic_object = TRUE
	/// Used to expand scan details for visible space stations.
	var/static_vessel = FALSE
	/// Used for unique landing sites that occupy the same overmap tile as another - for example, the implementation of Point Verdant and Konyang.
	var/landing_site = FALSE

	var/list/map_z = list()

	/// Shows up on nav computers automatically
	var/known = 0
	/// If set to TRUE will show up on ship sensors for detailed scans
	var/scannable
	/// A unique identifier used when this entity is scanned. Assigned in Initialize().
	var/unknown_id
	/// Whether or not the effect must be identified by ship sensors before being seen.
	var/requires_contact = TRUE
	/// Do we instantly identify ourselves to any ship in sensors range?
	var/instant_contact  = FALSE
	/// When true, this overmap object will be scanned with range instead of view.
	var/sensor_range_override = FALSE

	/// How likely it is to increase identification process each scan.
	var/sensor_visibility = 10
	/// Metric tonnes, very rough number, affects acceleration provided by engines
	var/vessel_mass = 10000

	/// TRUE when a cloaking device (or similar) has made this object
	/// completely undetectable -- checked independently by every detection
	/// surface (contact_sensors.dm, sensors.dm, helm.dm, overmap_shuttle.dm,
	/// personal_travel.dm, sector_view.dm), since none of them share a single
	/// central enumeration helper. See is_detectable()/set_cloaked() below.
	var/cloaked = FALSE

	var/image/targeted_overlay

/obj/effect/overmap/Destroy()
	QDEL_NULL(targeted_overlay)
	return ..()

/// Central check every detection surface should call alongside (not instead
/// of) its own existing scannable/requires_contact logic. viewer is optional
/// (omitting it preserves the old context-free "cloaked hides from
/// everyone" behavior) and may be either a mob (a specific viewer is asking
/// -- sees this ship if they're its own owner/faction/crew, or physically
/// aboard it) or another overmap ship (a console's own shared identification
/// tick with no specific mob in scope -- sees this ship if the two ships
/// share ownership/faction, see _drydock_ships_share_ownership()).
/// _drydock_full_access_check()/_drydock_ships_share_ownership()
/// (telepad_drydock_boarding.dm) are the shared access rules.
/obj/effect/overmap/proc/is_detectable(viewer)
	if(!cloaked)
		return TRUE
	if(!viewer)
		return FALSE
	if(ismob(viewer))
		var/mob/M = viewer
		if(GET_Z(M) in map_z)
			return TRUE
		return _drydock_full_access_check(M, length(map_z) ? map_z[1] : GET_Z(src))
	if(istype(viewer, /obj/effect/overmap/visitable))
		var/obj/effect/overmap/visitable/asking_ship = viewer
		var/asking_z = length(asking_ship.map_z) ? asking_ship.map_z[1] : GET_Z(asking_ship)
		return _drydock_ships_share_ownership(asking_z, length(map_z) ? map_z[1] : GET_Z(src))
	return FALSE

/// Flips the cloak state. Powering on immediately purges any sensor console
/// that had already identified this object, rather than just blocking future
/// scans -- see _purge_existing_sensor_contacts().
/obj/effect/overmap/proc/set_cloaked(new_state)
	if(cloaked == new_state)
		return
	cloaked = new_state
	if(cloaked)
		_purge_existing_sensor_contacts()

/// Removes any existing sensor-console identification of this object, so
/// cloaking is immediate rather than only preventing future identification.
/// Mirrors the existing "sensors lost power" cleanup at
/// contact_sensors.dm's qdel(record) -- overmap_contact/Destroy() already
/// correctly detargets weapons locks and strips pushed images from viewers.
/obj/effect/overmap/proc/_purge_existing_sensor_contacts()
	for(var/obj/structure/machinery/computer/ship/sensors/S in world)
		var/datum/overmap_contact/record = S.contact_datums[src]
		if(record)
			qdel(record)
		S.objects_in_view -= src

//Overlay of how this object should look on other skyboxes
/obj/effect/overmap/proc/get_skybox_representation()
	return

/obj/effect/overmap/proc/get_scan_data(mob/user)
	if(static_vessel == TRUE)
		if(instant_contact)
			. += "<br>It is broadcasting a distress signal."
		. += "<hr>"
		. += "<br><center><large><b>Scan Details</b></large>"
		. += "<br><large><b>[name]</b></large></center>"
		. += "<br><small><b>Estimated Mass:</b> [vessel_mass]"
		. += "<br><b>Projected Volume:</b> [volume]"
		. += "<hr>"
		. += "<br><center><b>Native Database Specifications</b>"
		. += "<br><img src = [scanimage]></center>"
		. += "<br><small><b>Manufacturer:</b> [designer]"
		. += "<br><b>Class Designation:</b> [sizeclass]"
		. += "<br><b>Weapons Estimation:</b> [weapons]</small>"
		. += "<hr>"
		. += "<br><center><b>Native Database Notes</b></center>"
		. += "<br><small>[desc]</small>"
		return
	else if(landing_site == TRUE)
		. += "<hr>"
		. += "<br><center><large><b>Designated Landing Zone Details</b></large>"
		. += "<br><large><b>[name]</b></large></center>"
		. += "<hr>"
		. += "<br><center><b>Native Database Specifications</b>"
		. += "<br><img src = [scanimage]></center>"
		. += "<br><small><b>Governing Body:</b> [alignment]</small>"
		. += "<hr>"
		. += "<br><center><b>Native Database Notes</b></center>"
		. += "<br><small>[desc]</small>"
	else if(generic_object == TRUE)
		return desc

/// Returns the direction the overmap object is moving in, rather than just the way it's facing
/obj/effect/overmap/proc/get_heading()
	return dir

/obj/effect/overmap/proc/handle_wraparound()
	var/nx = x
	var/ny = y
	var/low_edge = 1
	var/high_edge = SSatlas.current_map.overmap_size - 1

	var/heading = get_heading()

	if((heading & WEST) && x == low_edge)
		nx = high_edge
	else if((heading & EAST) && x == high_edge)
		nx = low_edge
	if((heading & SOUTH)  && y == low_edge)
		ny = high_edge
	else if((heading & NORTH) && y == high_edge)
		ny = low_edge
	if((x == nx) && (y == ny))
		return //we're not flying off anywhere

	var/turf/T = locate(nx,ny,z)
	if(T)
		forceMove(T)

/obj/effect/overmap/Initialize()
	. = ..()
	if(!SSatlas.current_map.use_overmap)
		return INITIALIZE_HINT_QDEL

	if(known)
		plane = ABOVE_LIGHTING_PLANE
		for(var/obj/structure/machinery/computer/ship/helm/H in SSmachinery.machinery)
			H.get_known_sectors()
	update_icon()

	if(requires_contact)
		set_invisibility(INVISIBILITY_OVERMAP)// Effects that require identification have their images cast to the client via sensors.

	var/static/list/loc_connections = list(
		COMSIG_ATOM_ENTERED = PROC_REF(on_entered),
		COMSIG_ATOM_EXITED = PROC_REF(on_exit),
	)

	AddElement(/datum/element/connect_loc, loc_connections)

/obj/effect/overmap/proc/on_entered(datum/source, atom/movable/arrived, atom/old_loc, list/atom/old_locs)
	SIGNAL_HANDLER

	if(istype(arrived, /obj/effect/overmap/visitable))
		for(var/obj/effect/overmap/visitable/O in loc)
			SSskybox.rebuild_skyboxes(O.map_z)

/obj/effect/overmap/proc/on_exit(atom/movable/gone, direction)
	SIGNAL_HANDLER

	if(istype(gone, /obj/effect/overmap/visitable))
		var/obj/effect/overmap/visitable/V = gone
		SSskybox.rebuild_skyboxes(V.map_z)
		for(var/obj/effect/overmap/visitable/O in loc)
			SSskybox.rebuild_skyboxes(O.map_z)

/obj/effect/overmap/proc/signal_hit(var/list/hit_data)
	return

/obj/effect/overmap/Click(location, control, params)
	. = ..()
	if(ishuman(usr))
		var/mob/living/carbon/human/H = usr
		var/client/C = H.client
		if(H.machine && istype(H.machine, /obj/structure/machinery/computer/ship/targeting) && istype(C.eye, /obj/effect/overmap))
			var/obj/structure/machinery/computer/ship/targeting/GS = H.machine
			if(GS.targeting)
				return
			if(!istype(GS.linked.loc, /turf/unsimulated/map))
				to_chat(H, SPAN_WARNING("The safeties won't let you target while you're not on the Overmap!"))
				return
			var/my_sector = GLOB.map_sectors["[H.z]"]
			if(istype(my_sector, /obj/effect/overmap/visitable))
				var/obj/effect/overmap/visitable/V = my_sector
				if(V != src && length(V.ship_weapons)) //no guns, no lockon
					if(!V.targeting)
						V.target(src, H.machine)
					else
						if(V.targeting == src)
							V.detarget(src, H.machine)
						else
							V.detarget(V.targeting, C)
							V.target(src, H.machine)
			GS.targeting = FALSE //Extra safety.

/obj/effect/overmap/MouseEntered(location, control, params)
	. = ..()
	var/list/modifiers = params2list(params)
	if(modifiers["shift"])
		params = replacetext(params, "shift=1;", "") // tooltip doesn't appear unless this is stripped
		var/description = get_tooltip_description()
		openToolTip(usr, src, params, name, description)

/obj/effect/overmap/proc/get_tooltip_description()
	if(!desc)
		return ""
	var/description = "<ul>"
	description += "<li>[desc]</li>"
	description += "</ul>"
	return description

/obj/effect/overmap/MouseExited(location, control, params)
	. = ..()
	closeToolTip(usr)

/obj/effect/overmap/visitable/proc/target(var/obj/effect/overmap/O, var/obj/structure/machinery/computer/ship/C)
	// Supply Beacons have no Z-level at all (code/modules/overmap/
	// supply_beacon.dm) -- there's nothing behind the marker for a weapon to
	// actually hit, so refuse the lock outright instead of letting one
	// through that firing_command() would have to handle later. Unlike the
	// bombardment-protection check below, this never needs a defense-in-
	// depth fire-time recheck -- a beacon's targetability never changes.
	if(istype(O, /obj/effect/overmap/supply_beacon))
		to_chat(usr, SPAN_WARNING("Your computer refuses to fire at automated trade beacons."))
		return
	// Ship-to-site bombardment only -- ship targets (including drydock
	// ships) are untouched, matching this codebase's own deliberate "log,
	// don't block" stance on ship-to-ship combat (see the fire handler's
	// highsec offense check, _targeting_console.dm).
	if(istype(O, /obj/effect/overmap/visitable/sector) && site_bombardment_protected(O, usr))
		to_chat(usr, SPAN_WARNING("Tactical sensors refuse to establish a lock -- the target is under active protection."))
		return
	C.targeting = TRUE
	usr.visible_message(SPAN_WARNING("[usr] starts calibrating the targeting systems, swiping around the holographic screen..."), SPAN_WARNING("You start calibrating the targeting systems, swiping around the screen as you focus..."))
	if(do_after(usr, 5 SECONDS))
		C.targeting = FALSE
		targeting = O
		O.targeted_overlay = icon('icons/obj/overmap/overmap_effects.dmi', "lock")
		O.AddOverlays(O.targeted_overlay)
		if(designation && class && !obfuscated)
			if(!O.maptext)
				O.maptext = SMALL_FONTS(6, "[class] [designation]")
			else
				O.maptext += SMALL_FONTS(6, " [class] [designation]")
		else
			if(!O.maptext)
				O.maptext = SMALL_FONTS(6, "[capitalize_first_letters(name)]")
			else
				O.maptext = SMALL_FONTS(6, " [capitalize_first_letters(name)]")
		O.maptext_y = 32
		O.maptext_x = -10
		O.maptext_width = 72
		O.maptext_height = 32
		playsound(C, 'sound/items/goggles_charge.ogg', 70)
		C.visible_message(SPAN_DANGER("[usr] engages the targeting systems, acquiring a lock on the target!"))
		if(istype(O, /obj/effect/overmap/visitable/ship))
			var/obj/effect/overmap/visitable/ship/S = O
			for(var/obj/structure/machinery/computer/ship/SH in S.consoles)
				if(istype(SH, /obj/structure/machinery/computer/ship/sensors))
					playsound(SH, 'sound/effects/ship_weapons/locked_on.ogg', 70)
					SH.visible_message(SPAN_DANGER("<font size=4>\The [SH] beeps alarmingly, signaling an enemy lock-on!</font>"))
	else
		C.targeting = FALSE

/obj/effect/overmap/visitable/proc/detarget(var/obj/effect/overmap/O,  var/obj/structure/machinery/computer/C)
	if(C)
		playsound(C, 'sound/items/rfd_interrupt.ogg', 70)
	if(O)
		O.CutOverlays(O.targeted_overlay)
		O.maptext = null
	targeting = null
