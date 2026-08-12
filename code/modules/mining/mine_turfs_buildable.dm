/**********************Buildable asteroid rock (RFD A-Class)**************************/
// Marker subtypes of the real asteroid rock/floor turfs, placed by
// /obj/item/rfd/asteroid, so player-built terrain can be told apart from
// real map-placed rock without changing how it looks or behaves.

/turf/simulated/mineral/buildable

/turf/simulated/floor/exoplanet/asteroid/ash/rocky/buildable
	has_resources = FALSE

/turf/simulated/floor/exoplanet/asteroid/ash/rocky/buildable/gets_dug(mob/user)
	AddOverlays("asteroid_dug")

	if(dug <= 10)
		dug += 1
		AddOverlays("asteroid_dug")
	else
		var/turf/below = GET_TURF_BELOW(src)
		if(below)
			var/area/below_area = get_area(below)
			if(below_area.station_area)
				if(user)
					to_chat(user, SPAN_ALERT("You strike metal!"))
				below.spawn_roof(ROOF_FORCE_SPAWN)
			else
				ChangeTurf(/turf/space)
