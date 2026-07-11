/// HOLODECK_AREAS
/area/frontier/holodeck_control
	name = "Holodeck Alpha"
	icon_state = "holodeck_control"
	area_flags = AREA_FLAG_RAD_SHIELDED
	holomap_color = HOLOMAP_AREACOLOR_CIVILIAN
	horizon_deck = 3
	area_blurb = "One of the SCCV Frontier's very expensive holodecks."
	department = LOC_CREW
	lightswitch = FALSE

/area/frontier/holodeck_control/beta
	name = "Holodeck Beta"

/area/frontier/holodeck
	name = "Holodeck (PARENT AREA - DON'T USE)"
	icon_state = "Holodeck"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	no_light_control = TRUE
	base_lighting_alpha = 255
	area_flags = AREA_FLAG_RAD_SHIELDED | AREA_FLAG_NO_GHOST_TELEPORT_ACCESS
	holomap_color = HOLOMAP_AREACOLOR_CIVILIAN
	horizon_deck = 3
	area_blurb = "One of the SCCV Frontier's very expensive holodecks."
	department = LOC_CREW

/area/frontier/holodeck/alphadeck
	name = "Holodeck Alpha"
	base_lighting_alpha = 0

/area/frontier/holodeck/betadeck
	name = "Holodeck Beta"
	base_lighting_alpha = 0

/area/frontier/holodeck/source_plating
	name = "Holodeck - Off"

/area/frontier/holodeck/source_chapel
	name = "Holodeck - Chapel"

/area/frontier/holodeck/source_gym
	name = "Holodeck - Gym"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_range
	name = "Holodeck - Range"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_emptycourt
	name = "Holodeck - Empty Court"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_boxingcourt
	name = "Holodeck - Boxing Court"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_basketball
	name = "Holodeck - Basketball Court"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_thunderdomecourt
	name = "Holodeck - Thunderdome Court"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_courtroom
	name = "Holodeck - Courtroom"
	sound_environment = SOUND_ENVIRONMENT_AUDITORIUM

/area/frontier/holodeck/source_burntest
	name = "Holodeck - Atmospheric Burn Test"

/area/frontier/holodeck/source_wildlife
	name = "Holodeck - Wildlife Simulation"

/area/frontier/holodeck/source_meetinghall
	name = "Holodeck - Meeting Hall"
	sound_environment = SOUND_ENVIRONMENT_AUDITORIUM

/area/frontier/holodeck/source_theatre
	name = "Holodeck - Callistean Theatre"
	sound_environment = SOUND_ENVIRONMENT_CONCERT_HALL

/area/frontier/holodeck/source_picnicarea
	name = "Holodeck - Picnic Area"
	sound_environment = SOUND_ENVIRONMENT_PLAIN

/area/frontier/holodeck/source_dininghall
	name = "Holodeck - Dining Hall"
	sound_environment = SOUND_ENVIRONMENT_PLAIN

/area/frontier/holodeck/source_snowfield
	name = "Holodeck - Bursa Tundra"
	sound_environment = SOUND_ENVIRONMENT_FOREST

/area/frontier/holodeck/source_desert
	name = "Holodeck - Desert"
	sound_environment = SOUND_ENVIRONMENT_PLAIN

/area/frontier/holodeck/source_space
	name = "Holodeck - Space"
	has_gravity = FALSE
	sound_environment = SOUND_AREA_SPACE

/area/frontier/holodeck/source_battlemonsters
	name = "Holodeck - Battlemonsters Arena"
	sound_environment = SOUND_ENVIRONMENT_ARENA

/area/frontier/holodeck/source_chessboard
	name = "Holodeck - Chessboard"

/area/frontier/holodeck/source_adhomai
	name = "Holodeck - Adhomian Campfire"

/area/frontier/holodeck/source_beach
	name = "Holodeck - Silversunner Coast"
	sound_environment = SOUND_ENVIRONMENT_PLAIN

/area/frontier/holodeck/source_pool
	name = "Holodeck - Swimming Pool"

/area/frontier/holodeck/source_sauna
	name = "Holodeck - Sauna"

/area/frontier/holodeck/source_jupiter
	name = "Holodeck - Jupiter Upper Atmosphere"

/area/frontier/holodeck/source_konyang
	name = "Holodeck - Konyanger Boardwalk"

/area/frontier/holodeck/source_moghes
	name = "Holodeck - Moghresian Jungle"

/area/frontier/holodeck/source_biesel
	name = "Holodeck - Foggy Mendell Skyline"

/area/frontier/holodeck/source_tribunal
	name = "Holodeck - Tribunalist Chapel"

/area/frontier/holodeck/source_trinary
	name = "Holodeck - Trinarist Chapel"

/area/frontier/holodeck/source_luceism
	name = "Holodeck - Luceian Chapel"

/area/frontier/holodeck/source_cafe
	name = "Holodeck - Animal Cafe"

/area/frontier/holodeck/source_lasertag
	name = "Holodeck - Laser Tag Arena"

/area/frontier/holodeck/source_combat_training
	name = "Holodeck - Combat Training Arena"
