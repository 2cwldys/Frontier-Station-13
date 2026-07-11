/// CREW_AREAS
/area/frontier/crew
	name = "Crew Areas (PARENT AREA - DON'T USE)"
	icon_state = "Sleep"
	holomap_color = HOLOMAP_AREACOLOR_CIVILIAN
	department = LOC_CREW
	area_blurb = "One of the Frontier's many crew areas."

/// Hallway areas
/area/frontier/hallway
	name = "Frontier - Hallway (PARENT AREA - DON'T USE)"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	icon_state = "hallC"
	allow_nightmode = TRUE
	lightswitch = TRUE
	holomap_color = HOLOMAP_AREACOLOR_HALLWAYS
	emergency_lights = TRUE
	department = LOC_PUBLIC
	subdepartment = SUBLOC_HALLS
	area_blurb = "One of the Frontier's public areas: either bustling with purpose and noise during the primary shifts, or eerily still during the graveyards."

/area/frontier/hallway/primary/deck_3
	name = "Deck 3 Primary Hallway (PARENT AREA - DON'T USE)"
	horizon_deck = 3

/area/frontier/hallway/primary/deck_3/central
	name = "Primary Hallway"
	location_ew = LOC_AMIDSHIPS

/area/frontier/hallway/primary/deck_3/starboard
	name = "Primary Hallway"
	icon_state = "hallS"
	location_ew = LOC_STARBOARD

/area/frontier/hallway/primary/deck_3/starboard/docks
	name = "Docking Arm"
	holomap_color = HOLOMAP_AREACOLOR_DOCK
	location_ew = LOC_STARBOARD_FAR

/area/frontier/hallway/primary/deck_3/port
	name = "Primary Hallway"
	icon_state = "hallP"
	location_ew = LOC_PORT

/area/frontier/hallway/primary/deck_3/port/docks
	name = "Docking Arm"
	holomap_color = HOLOMAP_AREACOLOR_DOCK
	location_ew = LOC_PORT_FAR

/area/frontier/hallway/primary/deck_2
	name = "Deck 2 Primary Hallway (PARENT AREA - DON'T USE)"
	horizon_deck = 2

/area/frontier/hallway/primary/deck_2/central
	name = "Central Ring"
	icon_state = "hallF"
	location_ew = LOC_AMIDSHIPS

/area/frontier/hallway/primary/deck_2/fore
	name = "Primary Hallway"
	icon_state = "hallF"
	location_ns = LOC_FORE

/area/frontier/hallway/primary/deck_2/starboard
	name = "Primary Hallway"
	icon_state = "hallF"
	location_ew = LOC_STARBOARD

/area/frontier/hallway/primary/deck_1
	name = "Deck 1 Primary Hallway (PARENT AREA - DON'T USE)"
	horizon_deck = 1

/area/frontier/hallway/primary/deck_1/central
	name = "Central Ring"
	icon_state = "hallF"
	location_ew = LOC_AMIDSHIPS

// Stairwells
/area/frontier/stairwell
	name = "Stairwell (PARENT AREA - DON'T USE)"
	icon_state = "stairwell"
	area_flags = AREA_FLAG_RAD_SHIELDED
	holomap_color = HOLOMAP_AREACOLOR_HALLWAYS
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	allow_nightmode = TRUE
	lightswitch = TRUE
	emergency_lights = TRUE
	department = LOC_PUBLIC
	subdepartment = SUBLOC_STAIRS
	area_blurb = "One of the Frontier's public areas: either bustling with purpose and noise during the primary shifts, or eerily still during the graveyards."

// Starboard Stairwell (Medical/Evac)
/area/frontier/stairwell/starboard
	name = "Starboard Stairwell (PARENT AREA - DON'T USE)"
	location_ew = LOC_STARBOARD

/area/frontier/stairwell/starboard/deck_1
	name = "Starboard Stairwell"
	horizon_deck = 1

/area/frontier/stairwell/starboard/deck_2
	name = "Starboard Stairwell"
	horizon_deck = 2

/area/frontier/stairwell/starboard/deck_3
	name = "Starboard Stairwell"
	horizon_deck = 3

// Starboard Stairwell (Security/Cafe)
/area/frontier/stairwell/port
	name = "Port Stairwell (PARENT AREA - DON'T USE)"
	location_ew = LOC_PORT

/area/frontier/stairwell/port/deck_2
	name = "Port Stairwell"
	horizon_deck = 2

/area/frontier/stairwell/port/deck_3
	name = "Port Stairwell"
	horizon_deck = 3

// Bridge Stairwell (Captain/Galley/Hydro)
/area/frontier/stairwell/bridge
	name = "Frontier - Bridge Stairwell (PARENT AREA - DON'T USE)"
	icon_state = "bridge_stairs"
	ambience = AMBIENCE_HIGHSEC
	department = LOC_COMMAND
	location_ew = LOC_STARBOARD
	location_ns = LOC_FORE_FAR

/area/frontier/stairwell/bridge/deck_2
	name = "Bridge Stairwell"
	horizon_deck = 2

/area/frontier/stairwell/bridge/deck_3
	name = "Bridge Stairwell"
	horizon_deck = 3

// Engineering Stairwell (Engineering/Atmos)
/area/frontier/stairwell/engineering
	name = "Frontier - Engineering Stairwell (PARENT AREA - DON'T USE)"
	ambience = AMBIENCE_HIGHSEC
	holomap_color = HOLOMAP_AREACOLOR_ENGINEERING
	department = LOC_ENGINEERING
	location_ns = LOC_AFT

/area/frontier/stairwell/engineering/deck_1
	name = "Engineering Stairwell"
	horizon_deck = 1
	area_blurb = "The exterior stowage tanks are visible from the window, hunched like patient stones."

/area/frontier/stairwell/engineering/deck_2
	name = "Engineering Stairwell"
	horizon_deck = 2
	area_blurb = "Filled with the sounds of machinery and an atmosphere of meaningful, directed purpose."

/// Cryogenics
// This area is the only one post-reorg that isn't used on the actual map and it makes me sad and I refuse to delete the definition.
// Bring back dedicated cryo compartments! They're so cool! - Bat
/area/frontier/crew/cryo
	name = "Cryogenic Storage"
	area_flags = AREA_FLAG_RAD_SHIELDED
	icon_state = "Sleep"
	horizon_deck = 3
	subdepartment = SUBLOC_CRYO

/// Residential Deck (access)
/area/frontier/crew/resdeck/living_quarters_lift
	name = "Living Quarters Lift"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_flags = AREA_FLAG_RAD_SHIELDED
	horizon_deck = 1
	subdepartment = SUBLOC_RESDECK
	area_blurb = "This compartment is a primary access point between the Operations Decks and the Residential Decks of the SCCV Frontier."

/// Fitness Center (legacy)
/area/frontier/crew/fitness
	name = "Frontier - Fitness Center (PARENT AREA - DON'T USE)"
	icon_state = "fitness"
	horizon_deck = 3

/area/frontier/crew/fitness/gym
	name = "Gym"
	icon_state = "fitness_gym"
	area_blurb = "It smells like sweat and sterilizing agents. Get pumped!"

// This area contains the Cryo pods. Spawn area = rad shielding.
/area/frontier/crew/fitness/changing
	name = "Changing Room"
	area_flags = AREA_FLAG_RAD_SHIELDED
	icon_state = "fitness_changingroom"

/area/frontier/crew/fitness/showers
	name = "Showers"
	icon_state = "showers"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_blurb = "Kept cleaner than most communal showers on ResDeck 3."

/// Representative and Consular offices.
// Yeah yeah I know, they're technically not 'Crew,' but they're also not Command...
/area/frontier/repoffice
	name = "Representative Office (PARENT AREA - DON'T USE)"
	icon_state = "law"
	area_lighting = LIGHT_HIGHSEC_COLORS
	sound_environment = SOUND_AREA_MEDIUM_SOFTFLOOR
	holomap_color = HOLOMAP_AREACOLOR_CIVILIAN
	horizon_deck = 3
	department = LOC_COMMAND
	area_blurb = "An office well-suited to the powerful: a useful lair for the consular or representative to withdraw with victims found after prowling the ship for themselves."
	lightswitch = FALSE

/area/frontier/repoffice/consular_one
	name = "Consular Office A"
	icon_state = "law_con"

/area/frontier/repoffice/consular_two
	name = "Consular Office B"
	icon_state = "law_con_b"

/area/frontier/repoffice/representative_one
	name = "Representative Office A"
	icon_state = "law_rep"

/area/frontier/repoffice/representative_two
	name = "Representative Office B"
	icon_state = "law_rep_b"

/// Uncategorized/general
/area/frontier/crew/journalistoffice
	name = "Journalist's Office"
	sound_environment = SOUND_AREA_SMALL_SOFTFLOOR
	horizon_deck = 3
	lightswitch = FALSE

/area/frontier/crew/lounge
	name = "Crew Lounge"
	icon_state = "lounge"
	horizon_deck = 3

/area/frontier/crew/chargebay
	name = "Charge Bay"
	icon_state = "mechbay"
	horizon_deck = 1
	area_blurb = "A discrete compartment frequented by the ship's many synthetics and IPCs."

// In case we make all the supply closets their own /areas in future.
/area/frontier/crew/emergency_closet/deck_2/starboard
	name = "Emergency Supply Closet"
	icon_state = "maintenance"
	horizon_deck = 2
	area_blurb = "Contains emergency supplies, surprisingly enough."

// Rad shielded because common afk area.
/area/frontier/crew/washroom
	name = "Frontier - Head (PARENT AREA - DON'T USE)"
	icon_state = "washroom"
	area_flags = AREA_FLAG_RAD_SHIELDED
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	lightswitch = FALSE

/area/frontier/crew/washroom/deck_2
	name = "Head"
	icon_state = "washroom"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	horizon_deck = 2

/area/frontier/crew/washroom/deck_3
	name = "Head"
	icon_state = "washroom"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	horizon_deck = 3

/area/frontier/crew/vacantoffice
	name = "Vacant Office"
	no_light_control = 0
	horizon_deck = 3
	lightswitch = FALSE
