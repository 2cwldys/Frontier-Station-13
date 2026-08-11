/datum/design/circuit/electronics
	p_category = "Electronics Designs"

/datum/design/circuit/electronics/secure_airlock
	name = "Secure Airlock Electronics"
	desc = "Allows for the construction of a tamper-resistant airlock electronics."
	req_tech = list(TECH_DATA = 3)
	build_path = /obj/item/airlock_electronics/secure

/datum/design/circuit/electronics/keypad_airlock
	name = "Keypad Airlock Electronics"
	desc = "Allows for the construction of numeric keypad airlock electronics."
	req_tech = list(TECH_DATA = 2)
	build_path = /obj/item/airlock_electronics/keypad
