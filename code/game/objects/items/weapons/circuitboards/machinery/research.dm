/obj/item/circuitboard/rdserver
	name = T_BOARD("R&D server")
	build_path = /obj/structure/machinery/r_n_d/server
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_DATA = 3)
	req_components = list(
							"/obj/item/stack/cable_coil" = 2,
							"/obj/item/stock_parts/scanning_module" = 1)

/obj/item/circuitboard/rdtechprocessor
	name = T_BOARD("R&D tech processor")
	build_path = /obj/structure/machinery/r_n_d/tech_processor
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_DATA = 3)
	req_components = list(
							"/obj/item/stack/cable_coil" = 2,
							"/obj/item/stock_parts/scanning_module" = 2
	)

/obj/item/circuitboard/destructive_analyzer
	name = T_BOARD("destructive analyzer")
	build_path = /obj/structure/machinery/r_n_d/destructive_analyzer
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_MAGNET = 2, TECH_ENGINEERING = 2, TECH_DATA = 2)
	req_components = list(
							"/obj/item/stock_parts/scanning_module" = 1,
							"/obj/item/stock_parts/manipulator" = 1,
							"/obj/item/stock_parts/micro_laser" = 1)

/obj/item/circuitboard/autolathe
	name = T_BOARD("autolathe")
	build_path = /obj/structure/machinery/fabricator/autolathe
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_ENGINEERING = 2, TECH_DATA = 2)
	req_components = list(
							"/obj/item/stock_parts/matter_bin" = 3,
							"/obj/item/stock_parts/manipulator" = 1,
							"/obj/item/stock_parts/micro_laser" = 1,
							"/obj/item/stock_parts/console_screen" = 1)

/obj/item/circuitboard/microlathe
	name = T_BOARD("microlathe")
	build_path = /obj/structure/machinery/fabricator/microlathe
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_ENGINEERING = 2, TECH_DATA = 2)
	req_components = list(
							"/obj/item/stock_parts/matter_bin" = 3,
							"/obj/item/stock_parts/manipulator" = 1,
							"/obj/item/stock_parts/micro_laser" = 1,
							"/obj/item/stock_parts/console_screen" = 1)

/obj/item/circuitboard/protolathe
	name = T_BOARD("protolathe")
	build_path = /obj/structure/machinery/r_n_d/protolathe
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_ENGINEERING = 2, TECH_DATA = 2)
	req_components = list(
							"/obj/item/stock_parts/matter_bin" = 2,
							"/obj/item/stock_parts/manipulator" = 2,
							"/obj/item/reagent_containers/glass/beaker" = 2)


/obj/item/circuitboard/circuit_imprinter
	name = T_BOARD("circuit imprinter")
	build_path = /obj/structure/machinery/r_n_d/circuit_imprinter
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_ENGINEERING = 2, TECH_DATA = 2)
	req_components = list(
							"/obj/item/stock_parts/matter_bin" = 1,
							"/obj/item/stock_parts/manipulator" = 1,
							"/obj/item/reagent_containers/glass/beaker" = 2)

/obj/item/circuitboard/mechfab
	name = T_BOARD("mechatronic fabricator")
	build_path = /obj/structure/machinery/mecha_part_fabricator
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_DATA = 3, TECH_ENGINEERING = 3)
	req_components = list(
							"/obj/item/stock_parts/matter_bin" = 2,
							"/obj/item/stock_parts/manipulator" = 1,
							"/obj/item/stock_parts/micro_laser" = 1,
							"/obj/item/stock_parts/console_screen" = 1)

/obj/item/circuitboard/telesci_pad
	name = T_BOARD("telepad")
	build_path = /obj/structure/machinery/telepad
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_DATA = 4, TECH_ENGINEERING = 3, TECH_MATERIAL = 3, TECH_BLUESPACE = 4)
	req_components = list(
							"/obj/item/bluespace_crystal" = 2,
							"/obj/item/stock_parts/capacitor" = 1,
							"/obj/item/stack/cable_coil" = 1,
							"/obj/item/stock_parts/console_screen" = 1)

/// Simpler, lower-tier than telesci_pad above -- a fixed-link travel pad,
/// not a targeted portal projector, pitched at the same tech level as the
/// telepad_beacon item's own gate (this is effectively that single-use
/// item's permanent-structure upgrade).
/obj/item/circuitboard/travel_pad
	name = T_BOARD("Travel Pad")
	build_path = /obj/structure/machinery/telepad_cargo/travel
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_BLUESPACE = 3, TECH_DATA = 2, TECH_ENGINEERING = 2)
	req_components = list(
							"/obj/item/bluespace_crystal/artificial" = 1,
							"/obj/item/stock_parts/capacitor" = 1,
							"/obj/item/stock_parts/console_screen" = 1,
							"/obj/item/stack/cable_coil" = 2)

/// Same tech tier as travel_pad above -- a standing, walk-through gangway
/// between two matched pads instead of a one-shot teleport. Replaces the
/// old automatic drydock docking umbilical with a player-built, player-coded
/// equivalent.
/obj/item/circuitboard/umbilical_pad
	name = T_BOARD("Umbilical Pad")
	build_path = /obj/structure/machinery/telepad_cargo/umbilical
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_BLUESPACE = 3, TECH_DATA = 2, TECH_ENGINEERING = 2)
	req_components = list(
							"/obj/item/bluespace_crystal/artificial" = 1,
							"/obj/item/stock_parts/capacitor" = 1,
							"/obj/item/stock_parts/console_screen" = 1,
							"/obj/item/stack/cable_coil" = 2)

/obj/item/circuitboard/ntnet_relay
	name = T_BOARD("NTNet Quantum Relay")
	build_path = /obj/structure/machinery/ntnet_relay
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_DATA = 4)
	req_components = list(
							"/obj/item/stack/cable_coil" = 15)
