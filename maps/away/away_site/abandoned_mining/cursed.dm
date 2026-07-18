/datum/map_template/ruin/away_site/cursed
	name = "lone asteroid"
	description = "A lone asteroid with a hangar. Latest data from this sector shows it as a Hephaestus mining station, two years ago."

	prefix = "away_site/abandoned_mining/"
	suffix = "cursed.dmm"

	sectors = list(ALL_TAU_CETI_SECTORS, ALL_BADLAND_SECTORS, ALL_COALITION_SECTORS)
	sectors_blacklist = list(ALL_SPECIFIC_SECTORS) //you're not gonna have a station left alone for 2 years in the middle of inhabited space
	spawn_weight = 3
	spawn_cost = 1
	auto_despawn_when_depleted = TRUE
	id = "cursed"

	unit_test_groups = list(1)

/singleton/submap_archetype/cursed
	map = "lone asteroid"
	descriptor = "A lone asteroid with a hangar. Latest data from this sector shows it was a Hephaestus mining station, two years ago."

/obj/effect/overmap/visitable/sector/cursed
	name = "lone asteroid"
	desc = "A lone asteroid with a hangar. Latest data from this sector shows it was a Hephaestus mining station, two years ago. Unknown biological lifesigns have been detected inside, though the station is cold. There's various low and high frequency radiation sources across the spectrum within the rock. Extraordinarily high exotic particle counts are being detected as well."


/area/cursed
	name="cursed station"
	icon_state = "outpost_mine_main"
	requires_power = TRUE
	area_flags = AREA_FLAG_HIDE_FROM_HOLOMAP

/area/cursed/hangar
	name="hangar"
	icon_state = "outpost_mine_main"
/area/cursed/living_area
	name="crew quarters"
	icon_state = "fitness"
/area/cursed/bridge
	name="mining outpost control"
	icon_state = "bridge"
/area/cursed/engineering
	name="mining outpost engineering"
	icon_state = "outpost_engine"
/area/cursed/computer_core
	name="computer core"
	icon_state = "ai"
/area/cursed/storage
	name="warehouse"
	icon_state = "storage"
/area/cursed/medical
	name="medical"
	icon_state = "exam_room"
/area/cursed/eva_storage
	name="eva storage"
	icon_state = "eva"
/area/cursed/mineral_processing
	name="mineral processing"
	icon_state = "mining"

// Ore deposit turf -- lets a mining drill be used here too, alongside the
// existing pickaxe-only wall veins. Ore type is picked once, when this
// specific turf instance loads, and stays fixed for that instance's
// lifetime -- not re-rolled per tick or per harvest.
/turf/simulated/floor/exoplanet/asteroid/ash/rocky/cursed_deposit
	name = "ore deposit"
	desc = "A vein of common ore, exposed by old mining efforts. You can drill it to extract it."
	var/mineral_amount = 250

/turf/simulated/floor/exoplanet/asteroid/ash/rocky/cursed_deposit/Initialize()
	..()
	var/turf/T = get_turf(src)
	if(T)
		T.has_resources = TRUE
		if(!T.resources)
			T.resources = list()
		var/static/list/possible_ores = list(ORE_IRON, ORE_SILVER, ORE_GOLD)
		T.resources[pick(possible_ores)] = mineral_amount
	return INITIALIZE_HINT_NORMAL
