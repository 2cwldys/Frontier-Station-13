/// Always-visible overmap marker for CentCom (z=4, ZTRAIT_CENTCOM/admin_levels) --
/// z4 never loads a real map file (see atlas.dm's load_map_directory()), so
/// there's nothing to physically spawn this on the way every other marker
/// gets its map_z linkage. Hardcode it instead, same pattern as
/// ship/landable/find_z_levels() and sector/temporary/New().
/obj/effect/overmap/visitable/sector/centcom
	name = "Frontier Beacon Depot"
	desc = "The remote administrative authority overseeing this sector."
	icon = 'icons/obj/overmap/overmap_stationary.dmi'
	icon_state = "depot"
	requires_contact = FALSE
	instant_contact = TRUE
	start_x = 2
	start_y = 2

/obj/effect/overmap/visitable/sector/centcom/find_z_levels()
	map_z = SSatlas.current_map.admin_levels.Copy()
