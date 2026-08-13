/turf/unsimulated/wall
	name = "wall"
	icon = 'icons/turf/walls.dmi'
	icon_state = "riveted"
	opacity = TRUE
	density = TRUE
	blocks_air = TRUE
	pass_flags_self = PASSCLOSEDTURF

/turf/unsimulated/wall/examine_descriptor(mob/user)
	return "wall"

/turf/unsimulated/wall/fakeglass
	name = "window"
	icon = 'icons/turf/walls.dmi'
	icon_state = "fakewindows"
	opacity = FALSE

/turf/unsimulated/wall/other
	icon = 'icons/turf/walls.dmi'
	icon_state = "rock"

// pretty much just a prettier /turf/unsimulated/wall
/turf/unsimulated/wall/riveted
	icon = 'icons/turf/smooth/riveted.dmi'
	icon_state = "riveted"
	desc = "It's a wall. It appears to be composed of a highly durable alloy."
	smoothing_flags = SMOOTH_TRUE
	canSmoothWith = list(
		/turf/unsimulated/wall/riveted,
		/obj/structure/machinery/door/airlock/centcom,
		/turf/unsimulated/wall/fakepdoor,
		/obj/structure/window_frame,
		/obj/structure/window_frame/unanchored,
		/obj/structure/window_frame/empty,
		/obj/structure/arch
	)

/turf/unsimulated/wall/fakepdoor
	icon = 'icons/obj/doors/rapid_pdoor.dmi'
	icon_state = "pdoor1"
	name = "blast door"
	desc = "That looks like it doesn't open easily."

/turf/unsimulated/wall/steel
	// A turf literal, not a /material, so it never runs through
	// update_material()'s own picker on its own -- Initialize() below calls
	// the same pick_wall_icon_variant() helper directly instead. Pinned here
	// to variant 1 as the value BEFORE Initialize() overrides it (so it's a
	// sane fallback if, say, that override is ever skipped by a subtype).
	icon = 'icons/turf/smooth/composite_solid_color_rust_1.dmi'
	icon_state = "map_white"
	desc = "It's a wall. It appears to be composed of a highly durable alloy and plated with steel."
	color = "#262c40"
	smoothing_flags = SMOOTH_TRUE
	canSmoothWith = list(
		/turf/unsimulated/wall/steel,
		/obj/structure/window_frame,
		/obj/structure/window_frame/unanchored,
		/obj/structure/window_frame/empty
	)

/turf/unsimulated/wall/steel/get_rust_weathering_variants()
	// Reuses /material/steel's OWN live variant list rather than a second,
	// hand-copied file list -- so a CentCom wall can never drift out of sync
	// with what real steel walls actually offer as their pool.
	var/material/steel = SSmaterials.get_material_by_name(DEFAULT_WALL_MATERIAL)
	return steel?.wall_icon_variants

/turf/unsimulated/wall/steel/Initialize(mapload)
	. = ..()
	var/list/variants = get_rust_weathering_variants()
	if(length(variants) > 1)
		GLOB.rust_variant_weathered_walls |= src
		icon = GLOB.rust_variants_enabled ? pick_wall_icon_variant(x, y, z, variants) : variants[length(variants)]

/turf/unsimulated/wall/steel/Destroy()
	GLOB.rust_variant_weathered_walls -= src
	return ..()

/turf/unsimulated/wall/darkshuttlewall
	// Base/fallback value before Initialize() below picks a variant -- see the
	// same reasoning on /turf/unsimulated/wall/steel above.
	icon = 'icons/turf/smooth/shuttle_wall_dark_rust.dmi'
	icon_state = "map-shuttle"
	desc = "It's a wall. It appears to be composed of a highly durable alloy."
	smoothing_flags = SMOOTH_TRUE
	color = "#262c40"
	canSmoothWith = list(
		/turf/unsimulated/wall/darkshuttlewall,
		/turf/unsimulated/wall/riveted,
		/obj/structure/window_frame,
		/obj/structure/window_frame/unanchored,
		/obj/structure/window_frame/empty
	)

/turf/unsimulated/wall/darkshuttlewall/get_rust_weathering_variants()
	// Only two entries -- shuttle_wall_dark.dmi was never baked into a 4-file
	// pool of its own, so this reuses the one existing weathered bake plus the
	// plain source sheet as "clean", rather than generating three more variants
	// just for this one CentCom subtype.
	return list(
		'icons/turf/smooth/shuttle_wall_dark_rust.dmi',
		'icons/turf/smooth/shuttle_wall_dark.dmi',
	)

/turf/unsimulated/wall/darkshuttlewall/Initialize(mapload)
	. = ..()
	// Same picker, same x/y/z hash as steel.
	var/list/variants = get_rust_weathering_variants()
	GLOB.rust_variant_weathered_walls |= src
	icon = GLOB.rust_variants_enabled ? pick_wall_icon_variant(x, y, z, variants) : variants[length(variants)]

/turf/unsimulated/wall/darkshuttlewall/Destroy()
	GLOB.rust_variant_weathered_walls -= src
	return ..()

/turf/unsimulated/wall/fakeairlock
	icon = 'icons/obj/doors/Doorele.dmi'
	icon_state = "door_closed"
	name = "airlock"
	desc = "It opens and closes."

/turf/unsimulated/wall/konyang
	name = "wall"
	icon = 'icons/turf/smooth/building-konyang.dmi'
	canSmoothWith = list(
		/turf/simulated/wall,
		/turf/simulated/wall/r_wall,
		/turf/simulated/wall/shuttle/scc_space_ship,
		/turf/unsimulated/wall,
		/obj/structure/window_frame,
		/obj/structure/window_frame/unanchored,
		/obj/structure/window_frame/empty,
		/obj/structure/machinery/door,
		/obj/structure/machinery/door/airlock
	)
	smoothing_flags = SMOOTH_MORE
	icon_state = "map_white"

/turf/unsimulated/wall/shuttle/scc_space_ship/cardinal
	name = "reinforced plastitanium alloy wall"
	desc = "Effectively impervious to conventional methods of destruction."
	icon = 'icons/turf/smooth/scc_ship/scc_ship_exterior.dmi'
	icon_state = "map-wall"
	smoothing_flags = SMOOTH_MORE
	canSmoothWith = list(
		/turf/simulated/wall,
		/turf/simulated/wall/r_wall,
		/turf/unsimulated/wall/shuttle/scc_space_ship,
		/turf/simulated/wall/shuttle/scc_space_ship,
		/obj/structure/window/shuttle/scc_space_ship,
		/obj/structure/machinery/door/airlock
	)

