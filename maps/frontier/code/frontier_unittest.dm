/datum/map/frontier
	ut_environ_exempt_areas = list(
		/area/space,
		/area/solar,
		/area/shuttle,
		/area/frontier/holodeck,
		/area/supply/station,
		/area/tdome,
		/area/centcom,
		/area/supply/dock,
		/area/turbolift,
		/area/mine,
		/area/frontier/exterior
	)

	ut_apc_exempt_areas = list()

	ut_atmos_exempt_areas = list(
		/area/frontier/maintenance,
		/area/frontier/engineering/atmos/storage,
		/area/frontier/rnd/server,
		/area/frontier/tcommsat/chamber,
		/area/frontier/command/bridge/aibunker,
		/area/frontier/medical/cryo,
		/area/frontier/medical/surgery/storage,
		/area/frontier/ai,
		/area/frontier/engineering/reactor/indra/smes,
		/area/frontier/rnd/xenoarch/isolation_a,
		/area/frontier/rnd/xenoarch/isolation_b,
		/area/frontier/rnd/xenoarch/isolation_c
	)

	ut_fire_exempt_areas = list(
		/area/frontier/maintenance,
		/area/frontier/command/bridge/aibunker,
		/area/frontier/medical/cryo,
		/area/frontier/crew/washroom/deck_3,
		/area/frontier/rnd/xenoarch/isolation_a,
		/area/frontier/rnd/xenoarch/isolation_b,
		/area/frontier/rnd/xenoarch/isolation_c
	)

/datum/unit_test/zas_area_test/frontier
	map_path = "frontier"

/datum/unit_test/zas_area_test/frontier/storage
	name = "ZAS: Operations Bay"
	area_path = /area/frontier/operations/warehouse
