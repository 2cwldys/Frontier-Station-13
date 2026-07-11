/// ENGINEERING_AREAS
/area/frontier/engineering
	name = "Engineering (PARENT AREA - DON'T USE)"
	area_lighting = LIGHT_ENGINEERING_COLORS
	icon_state = "engineering"
	ambience = AMBIENCE_ENGINEERING
	holomap_color = HOLOMAP_AREACOLOR_ENGINEERING
	department = LOC_ENGINEERING
	area_blurb = "The engineering sectors of the ship tend to be a little noisier and more utilitarian than most."

/area/frontier/engineering/drone_fabrication
	name = "Drone Fabrication"
	icon_state = "drone_fab"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	horizon_deck = 2

/area/frontier/engineering/storage_hard/upper
	name = "Hard Storage"
	icon_state = "engineering_storage"
	horizon_deck = 2
	lightswitch = FALSE

/area/frontier/engineering/storage_hard/lower
	name = "Hard Storage"
	icon_state = "engineering_storage"
	horizon_deck = 1
	lightswitch = FALSE

/area/frontier/engineering/equipment
	name = "Equipment"
	icon_state = "engineering_storage"
	horizon_deck = 2

/area/frontier/engineering/washroom
	name = "Washroom"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	horizon_deck = 2
	area_blurb = "The air in here not only smells like aggresive cleaning reagents, but everything you find around the whole department, oil, paint and other highly flammable chemicals... Unfortunately."

/area/frontier/engineering/break_room
	name = "Break Room"
	icon_state = "engineering_break"
	sound_environment = SOUND_AREA_MEDIUM_SOFTFLOOR
	area_blurb = "The intermixed odors of coffee and oil lingers in the air."
	horizon_deck = 3

/area/frontier/engineering/locker_room
	name = "Locker Room"
	icon_state = "engineering_locker"
	horizon_deck = 2

/area/frontier/engineering/gravity_gen
	name = "Gravity Generator"
	icon_state = "engine"
	horizon_deck = 1
	area_flags = AREA_FLAG_RAD_SHIELDED
	area_blurb = "The air in here tastes like copper, sour sugar, and smoke; none of the angles seem right. That probably means everything is working."

/area/frontier/engineering/lobby
	name = "Lobby"
	horizon_deck = 2

/area/frontier/engineering/storage/tech
	name = "Technical Storage"
	icon_state = "auxstorage"
	horizon_deck = 1
	lightswitch = FALSE

/area/frontier/engineering/storage/lower
	name = "Lower Deck Storage"
	horizon_deck = 1
	lightswitch = FALSE

/area/frontier/engineering/aft_airlock
	name = "Aft Stowage Airlock"
	horizon_deck = 2

/area/frontier/engineering/bluespace_drive
	name = "Bluespace Drive"
	icon_state = "engine"
	horizon_deck = 1

/area/frontier/engineering/bluespace_drive/monitoring
	name = "Bluespace Drive Monitoring"
	area_flags = AREA_FLAG_RAD_SHIELDED
	icon_state = "engineering"
	horizon_deck = 1

/area/frontier/engineering/shields
	name = "Shield Control"
	icon_state = "eva"
	horizon_deck = 3

/// Engineering Hallways
/area/frontier/engineering/hallway
	name = "Engineering Hallway (PARENT AREA - DON'T USE)"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	horizon_deck = 2

/area/frontier/engineering/hallway/fore
	// Location is defined here relative to the department center itself. Whatever.
	name = "Fore Hallway"
	area_blurb = "Filled with the sounds of machinery and an atmosphere of meaningful, directed purpose. Machine oil, ozone, welding fumes, and combustion products scent the air."

/area/frontier/engineering/hallway/aft
	// Location is defined here relative to the department center itself. Whatever.
	name = "Aft Hallway"
	area_blurb = "Filled with the sounds of machinery and an atmosphere of meaningful, directed purpose. Machine oil, ozone, welding fumes, and combustion products scent the air. \
	<br><br>The tops of the exterior stowage tanks are visible from the aft windows, hunched like patient stones."

/area/frontier/engineering/hallway/interior
	// Location is defined here relative to the department center itself. Whatever.
	name = "Amidships Hallway"
	area_blurb = "Filled with the sounds of machinery and an atmosphere of meaningful, directed purpose. Machine oil, ozone, welding fumes, and combustion products scent the air."

/// ENGINEERING_AREAS - ATMOSIA_AREAS
/area/frontier/engineering/atmos
	name = "Distribution Control"
	icon_state = "atmos"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	no_light_control = 1
	ambience = list(AMBIENCE_ENGINEERING, AMBIENCE_ATMOS)
	area_blurb = "Many volume tanks filled with gas reside here, some providing vital gases for the vessel's life support systems. \
	Through the aft windows, exterior stowage tanks filled mostly with hazardous or volatile gases loom patiently."
	horizon_deck = 1
	subdepartment = SUBLOC_ATMOS

/area/frontier/engineering/atmos/storage
	name = "Atmos Storage"
	icon_state = "atmos_storage"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_blurb = "The softly reassuring sounds of churning humming whirring resound gently from the distribution control compartment below."
	horizon_deck = 2

/area/frontier/engineering/atmos/storage_maintenance
	name = "Atmos Storage maintenance"
	icon_state = "atmos_storage"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_blurb = "The metal clanking of pipes being jostled; gas canister telltales blinking out from corners. \
	It's as organized as you would expect a hidden away storage to be."
	horizon_deck = 2

/area/frontier/engineering/atmos/air
	name = "Air Mixing"

/area/frontier/engineering/atmos/propulsion
	name = "Propulsion"
	subdepartment = null
	icon_state = "thrust"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_blurb = "Every bulkhead is invisibly tense with the long-term strains of powerful impulse. The subtle aromas of various fuel compounds linger in the air."
	location_ew = LOC_PORT
	location_ns = LOC_AFT_FAR

/area/frontier/engineering/atmos/propulsion/starboard
	name = "Propulsion"
	icon_state = "thrust"
	location_ew = LOC_STARBOARD

/area/frontier/engineering/atmos/turbine
	name = "Combustion Turbine"
	area_blurb = "Where temperature records are set."

/// ENGINEERING_AREAS - REACTOR_AREAS
/area/frontier/engineering/reactor
	name = "Engine (PARENT AREA - DON'T USE)"
	icon_state = "engine"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	no_light_control = 1
	ambience = AMBIENCE_SINGULARITY
	horizon_deck = 2

// We'll give this a cool custom icon one day.
/area/frontier/engineering/reactor/supermatter
	name = "Supermatter Reactor (PARENT AREA - DON'T USE)"

/area/frontier/engineering/reactor/supermatter/airlock
	name = "Supermatter Reactor Airlock"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_blurb = "It's like clambering into the gullet of a monster."

/area/frontier/engineering/reactor/supermatter/mainchamber
	name = "Supermatter Reactor Chamber"
	area_blurb = "The air throbs with subdued lethality. Phoronic science breaks the laws of thermodynamics in this chamber, and the laws of thermodynamics seem angry."

/area/frontier/engineering/reactor/supermatter/smes
	name = "Supermatter Reactor SMES"
	icon_state = "engine_smes"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_blurb = "One could almost feel bad for the PSU in here."

/area/frontier/engineering/reactor/supermatter/monitoring
	name = "Supermatter Reactor Monitoring"
	icon_state = "engine_monitoring"
	area_flags = AREA_FLAG_RAD_SHIELDED
	area_blurb = "This compartment provides a fairly convincing illusion of safety and control."

/area/frontier/engineering/reactor/supermatter/waste
	name = "Supermatter Reactor Waste Handling"
	icon_state = "engine_waste"
	no_light_control = 1
	area_blurb = "Carefully threaded systems regulate the offgas products of the Supermatter Crystal in here, their final destination to be forever argued over by Atmospheric Technicians."

// We'll give this a cool custom icon one day.
/area/frontier/engineering/reactor/indra
	name = "INDRA Reactor (PARENT AREA - DON'T USE)"

/area/frontier/engineering/reactor/indra/mainchamber
	name = "INDRA Reactor Chamber"
	ambience = AMBIENCE_SINGULARITY
	area_blurb = "The product of over four-hundred years' iteration and refinement: the INDRA Mk.II Tokamak fusion bottle and its vast supporting machineries dominate the entire compartment"

/area/frontier/engineering/reactor/indra/smes
	name = "INDRA Reactor SMES"
	icon_state = "engine_smes"
	area_blurb = "A quiet hum suffuses this compartment from grid-balancing hardware and power banks fitted beneath the floor."

/area/frontier/engineering/reactor/indra/monitoring
	name = "INDRA Reactor Monitoring"
	icon_state = "engine_monitoring"
	area_flags = AREA_FLAG_RAD_SHIELDED
	area_blurb = "Where atoms are consigned to be smashed and the pretty lights beheld."

/area/frontier/engineering/reactor/indra/office
	name = "INDRA Reactor Office"
	area_blurb = "A dingy, forgotten compartment a year or three away from looking about as well-kept as the maints."

// The engineering stairwell /area/frontier/stairwell/engineering/* are defined in './horizon_areas_crew.dm'. Bat put them there originally because they felt that made sense. If you don't, migrate them here I guess, everything's cool.

/// TCOMMS_AREAS
/area/frontier/tcommsat
	icon_state = "tcomsatcham"
	ambience = AMBIENCE_ENGINEERING
	area_lighting = LIGHT_CLINICAL_COLORS
	no_light_control = 1
	station_area = TRUE
	holomap_color = HOLOMAP_AREACOLOR_ENGINEERING
	horizon_deck = 3
	area_blurb = "Countless machines sit within these compartments, an unfathomably complex network that runs every radio and computer connection. \
	The air lacks any notable scent, having been filtered of dust and pollutants for the sake of all the sensitive machinery."
	department = LOC_COMMAND
	subdepartment = SUBLOC_TELECOMMS

/area/frontier/tcommsat/entrance
	name = "Telecomms Entrance"
	icon_state = "tcomsatentrance"
	lightswitch = TRUE

/area/frontier/tcommsat/chamber
	name = "Telecomms Central Compartment"
