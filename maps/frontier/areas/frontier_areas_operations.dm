/// OPERATIONS_AREAS
/area/frontier/operations
	name = "Ops (PARENT AREA - DON'T USE)"
	icon_state = "operations"
	area_lighting = LIGHT_ENGINEERING_COLORS
	ambience = AMBIENCE_ENGINEERING
	holomap_color = HOLOMAP_AREACOLOR_OPERATIONS
	department = LOC_OPERATIONS
	area_blurb = "The halls of Operations ever resound with the clamor of pallets and materiel and rustling paper."

/area/frontier/operations/warehouse
	name = "Warehouse"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	area_blurb = "Scuff marks scar the floor from the movement of many crates and stored goods."
	horizon_deck = 1

/area/frontier/operations/ship_supply_warehouse
	name = "Ship Supply Warehouse"
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	area_blurb = "Scuff marks scar the floor from the movement of many crates and stored goods."
	horizon_deck = 2

/area/frontier/operations/package_conveyors
	name = "Package Conveyors"
	horizon_deck = 1

/area/frontier/operations/lobby
	name = "Lobby"
	horizon_deck = 2

/area/frontier/operations/loading
	name = "Loading Bay"
	icon_state = "quartloading"
	horizon_deck = 1

/area/frontier/operations/break_room
	name = "Break Room"
	icon_state = "blue"
	horizon_deck = 2

/area/frontier/operations/office
	name = "Office"
	icon_state = "quartoffice"
	sound_environment = SOUND_AREA_MEDIUM_SOFTFLOOR
	horizon_deck = 2

/area/frontier/operations/office_aux
	name = "Auxiliary Office"
	icon_state = "quartoffice"
	sound_environment = SOUND_AREA_MEDIUM_SOFTFLOOR
	horizon_deck = 3

/area/frontier/operations/mail_room
	name = "Mail Room"
	icon_state = "red"
	horizon_deck = 2

/area/frontier/operations/commissary
	name = "Commissary"
	horizon_deck = 2
	area_blurb = "Even here, all the way out into the depths of space, retail work is found. The commissary room is eerily bare when not run— with empty shelves being such a rarity in the 25th century for most worlds, seeing them here is almost unnatural. Where are your treats?"
	lightswitch = FALSE

/area/frontier/operations/secure_ammunition_storage
	name = "Secure Ammunitions Storage"
	icon_state = "ammo"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	ambience = AMBIENCE_FOREBODING
	holomap_color = HOLOMAP_AREACOLOR_OPERATIONS
	horizon_deck = 2
	area_blurb = "Armor-piercing, bunker-busting, high-explosive... Don't sneeze!"

/// OPERATIONS_AREAS - HANGAR_AREAS
/area/frontier/hangar
	name = "Hangar (PARENT AREA - DON'T USE)"
	icon_state = "hangar"
	area_lighting = LIGHT_ENGINEERING_COLORS
	ambience = AMBIENCE_HANGAR
	sound_environment = SOUND_ENVIRONMENT_HANGAR
	holomap_color = HOLOMAP_AREACOLOR_HANGAR
	horizon_deck = 1
	department = LOC_HANGAR

/area/frontier/hangar/airstation
	name = "Hangar Air Station"
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	ambience = list(AMBIENCE_ENGINEERING, AMBIENCE_ATMOS)
	area_blurb = "A small area of the hangar serving the shuttles with fresh air and \
	giving the access to dispose of any bad air the shuttles brought back during their expeditions."

/area/frontier/hangar/control
	name = "Hangar Control Room"
	holomap_color = HOLOMAP_AREACOLOR_COMMAND
	sound_environment = SOUND_AREA_SMALL_ENCLOSED

/area/frontier/hangar/intrepid
	name = "Primary Hangar"
	area_blurb = "A big, open room, home to the SCCV Frontier's largest shuttle, the Intrepid."

/area/frontier/hangar/intrepid/interstitial
	name = "Intrepid Hangar Access"

/area/frontier/hangar/operations
	name = "Starboard Auxiliary Hangar"
	holomap_color = HOLOMAP_AREACOLOR_OPERATIONS
	area_blurb = "A big, open room, home to the SCCV Frontier's mining shuttle, the Spark."

/area/frontier/hangar/auxiliary
	name = "Port Auxiliary Hangar"
	area_blurb = "A big, open room, home to two of the SCCV Frontier's shuttles, the Quark and the Canary."

/// OPERATIONS_AREAS - MACHINIST_AREAS
/area/frontier/operations/machinist
	name = "Machinist Workshop"
	icon_state = "machinist_workshop"
	area_blurb = "The scents of oil and mechanical lubricants fill the air in this workshop."
	subdepartment = SUBLOC_MACHINING
	horizon_deck = 2

/area/frontier/operations/machinist/surgicalbay
	name = "Machinist Surgical Bay"
	icon_state = "machinist_workshop"
	area_blurb = "Back in the workshop's surgical bay, the sharp-edged odor of sterilized equipment predominates."
	horizon_deck = 2

/// OPERATIONS_AREAS - MINING_AREAS
/area/frontier/operations/mining_main
	name = "Mining (PARENT AREA - DON'T USE)"
	icon_state = "outpost_mine_main"
	ambience = AMBIENCE_EXPOUTPOST
	subdepartment = SUBLOC_MINING
	area_blurb = "Even louder and noisier and rowdier than the rest of Operations, which is really saying something."

/area/frontier/operations/mining_main/eva
	name = "Mining EVA Storage"
	horizon_deck = 1

/area/frontier/operations/mining_main/refinery
	name = "Mining Refinery"
	horizon_deck = 1

/// WEAPONS_AREAS
/area/frontier/weapons
	icon_state = "bridge_weapon"
	area_lighting = LIGHT_ENGINEERING_COLORS
	sound_environment = SOUND_AREA_LARGE_ENCLOSED
	ambience = AMBIENCE_HIGHSEC
	area_flags = AREA_FLAG_HIDE_FROM_HOLOMAP

/area/frontier/weapons/longbow
	name = "Longbow Weapon System"
	horizon_deck = 3
	area_blurb = "One of the SCCV Frontier's daunting weapons bays."
	department = LOC_COMMAND
	lightswitch = FALSE

/area/frontier/weapons/grauwolf
	name = "Grauwolf Weapon System"
	horizon_deck = 2
	area_blurb = "One of the SCCV Frontier's daunting weapons bays."
	department = LOC_COMMAND
	lightswitch = FALSE

/// STORAGE_AREAS
/area/frontier/storage
	name = "Storage (PARENT AREA - DON'T USE)"
	area_lighting = LIGHT_ENGINEERING_COLORS
	department = LOC_CREW
	lightswitch = FALSE

/area/frontier/storage/primary
	name = "Primary Tool Storage"
	icon_state = "primarystorage"
	horizon_deck = 2
	area_blurb = "A compartment for keeping the various things useful on any ship."

/area/frontier/storage/eva
	name = "EVA Storage"
	icon_state = "eva"
	horizon_deck = 1
	area_blurb = "Row after row of various types of void suits and the ancillary equipment for their use reside here, carefully checked and double-checked before each excursion."

/// Science-restricted section of EVA.
/area/frontier/storage/eva/expedition
	name = "Expedition EVA Storage"
	icon_state = "eva"
	horizon_deck = 1
	holomap_color = HOLOMAP_AREACOLOR_SCIENCE
	department = LOC_SCIENCE

/area/frontier/storage/secure/ops_vault
	icon_state = "storage"
	area_flags = AREA_FLAG_HIDE_FROM_HOLOMAP
	department = LOC_COMMAND
	area_lighting = LIGHT_HIGHSEC_COLORS

/// THE VAAAAAAUULLT
/area/frontier/storage/secure/ops_vault
	name = "Secure Operational Storage"
	horizon_deck = 2
	area_blurb = "A place not to be visited unless things are going either horribly wrong or horribly right."

/// THE VAAAAAAUULLT
/area/frontier/storage/secure/tech_vault
	name = "Secure Technical Storage"
	area_lighting = LIGHT_HIGHSEC_COLORS
	horizon_deck = 3
	area_blurb = "A place not to be visited unless things are going either horribly wrong or horribly right."
