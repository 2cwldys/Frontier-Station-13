/obj/item/circuitboard/bioprinter
	name = T_BOARD("organ bioprinter")
	build_path = /obj/structure/machinery/bioprinter
	board_type = BOARD_MACHINE
	origin_tech = list(TECH_DATA = 3, TECH_BIO = 3)
	req_components = list(
							"/obj/item/stock_parts/matter_bin" = 1,
							"/obj/item/stock_parts/manipulator" = 1)

/obj/item/circuitboard/bioprinter/prosthetics
	name = T_BOARD("prosthetics fabricator")
	build_path = /obj/structure/machinery/bioprinter/prosthetics
