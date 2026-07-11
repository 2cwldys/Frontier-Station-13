/// SHUTTLE_AREAS
/area/frontier/shuttle
	name = "Shuttle"
	icon_state = "shuttle"
	requires_power = 0
	sound_environment = SOUND_AREA_SMALL_ENCLOSED
	area_flags = AREA_FLAG_RAD_SHIELDED
	horizon_deck = 1
	department = LOC_SHUTTLE
	area_blurb = "A shuttle compartment: compact and rigidly functional."

/area/frontier/shuttle/intrepid
	name = "Intrepid"
	icon_state = "intrepid"
	requires_power = TRUE

/area/frontier/shuttle/intrepid/main_compartment
	name = "Intrepid Main Compartment"

/area/frontier/shuttle/intrepid/port_compartment
	name = "Intrepid Port Compartment"

/area/frontier/shuttle/intrepid/starboard_compartment
	name = "Intrepid Starboard Compartment"

/area/frontier/shuttle/intrepid/junction_compartment
	name = "Intrepid Junction Compartment"

/area/frontier/shuttle/intrepid/buffet
	name = "Intrepid Buffet"

/area/frontier/shuttle/intrepid/medical
	name = "Intrepid Medical Compartment"

/area/frontier/shuttle/intrepid/engineering
	name = "Intrepid Engineering Compartment"

/area/frontier/shuttle/intrepid/port_storage
	name = "Intrepid Port Nacelle"

/area/frontier/shuttle/intrepid/flight_deck
	name = "Intrepid Flight Deck"

/area/frontier/shuttle/escape_pod
	name = "Escape Pod"
	area_blurb = "If you're in here, you've probably had a bad day."

/area/frontier/shuttle/escape_pod/pod1
	name = "Escape Pod - 1"

/area/frontier/shuttle/escape_pod/pod2
	name = "Escape Pod - 2"

/area/frontier/shuttle/escape_pod/pod3
	name = "Escape Pod - 3"

/area/frontier/shuttle/escape_pod/pod4
	name = "Escape Pod - 4"

/area/frontier/shuttle/mining
	name = "Spark"
	requires_power = TRUE

/area/frontier/shuttle/canary
	name = "Canary"
	requires_power = TRUE

/area/frontier/shuttle/quark/cockpit
	name = "Quark Cockpit"
	requires_power = TRUE

/area/frontier/shuttle/quark/cargo_hold
	name = "Quark Cargo Hold"
	requires_power = TRUE
