/// SCIENCE_AREAS
/area/frontier/rnd
	area_lighting = LIGHT_RESEARCH_COLORS
	holomap_color = HOLOMAP_AREACOLOR_SCIENCE
	department = LOC_SCIENCE
	horizon_deck = 2
	icon_state = "research"
	area_flags = AREA_FLAG_FIRING_RANGE //Lets science shoot guns inside their own department.
	area_blurb = "The science sectors of the ship lend themselves to a clean, functional sterility; at least when everything is going well."

/area/frontier/rnd/conference
	name = "Conference Room"

/area/frontier/rnd/hallway
	name = "Hallway"
	holomap_color = HOLOMAP_AREACOLOR_CIVILIAN
	lightswitch = TRUE
	area_flags = null //Shouldn't be shooting in the public hallway.
	location_ew = LOC_PORT

/area/frontier/rnd/hallway/secondary
	name = "Hallway"
	lightswitch = TRUE
	location_ns = LOC_AFT

/area/frontier/rnd/telesci
	name = "Telescience"

/area/frontier/rnd/chemistry
	name = "Exploratory Chemistry"
	icon_state = "chem"

/area/frontier/rnd/lab
	name = "Research & Development"
	icon_state = "toxlab"

/area/frontier/rnd/server
	name = "Server Room"
	icon_state = "server"

/area/frontier/rnd/xenological
	name = "Xenological Studies"
	icon_state = "xeno_log"

/area/frontier/rnd/xenobiology
	name = "Primary Laboratory"
	icon_state = "xeno_lab"
	subdepartment = SUBLOC_XENOBIO

/area/frontier/rnd/xenobiology/dissection
	name = "Dissection"

/area/frontier/rnd/xenobiology/foyer
	name = "Foyer"

/area/frontier/rnd/xenobiology/xenoflora
	name = "Grow Lab"
	icon_state = "xeno_f_lab"
	no_light_control = TRUE
	subdepartment = SUBLOC_XENOBOT

/area/frontier/rnd/test_range
	name = "Weapons Testing Range"
	area_flags = AREA_FLAG_FIRING_RANGE
	horizon_deck = 1

/area/frontier/rnd/eva
	name = "EVA Preparation"
	icon_state = "blue"
	horizon_deck = 1

/area/frontier/rnd/xenoarch
	name = "Xenoarchaology - PARENT AREA DO NOT USE"
	icon_state = "research"
	horizon_deck = 1
	subdepartment = SUBLOC_XENOARCH

/area/frontier/rnd/xenoarch/atrium
	name = "Atrium"

/area/frontier/rnd/xenoarch/storage
	name = "General Storage"
	icon_state = "purple"
	lightswitch = FALSE

/area/frontier/rnd/xenoarch/presentation
	name = "Xenoarchaeology Presentation"

/area/frontier/rnd/xenoarch/hallway/elevator
	name = "Xenoarchaeology Hallway"

/area/frontier/rnd/xenoarch/hallway/hangar
	name = "Xenoarchaeology Hanger Hallway"

/area/frontier/rnd/xenoarch/anomaly_storage
	name = "Artifact Storage"
	lightswitch = FALSE

/area/frontier/rnd/xenoarch/spectrometry
	name = "Spectrometry"

/area/frontier/rnd/xenoarch/isolation_a
	name = "Anomaly Isolation A"
	icon_state = "blue"

/area/frontier/rnd/xenoarch/isolation_b
	name = "Anomaly Isolation B"
	icon_state = "red"

/area/frontier/rnd/xenoarch/isolation_c
	name = "Anomaly Isolation C"
	icon_state = "green"
