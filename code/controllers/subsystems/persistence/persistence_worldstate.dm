/*
 * Persistence - World State
 * Saves and restores station machinery state across rounds via SQL.
 * Each machine is identified by its (type, x, y, z) position.
 *
 * Pattern (Persistent-Bay inspired):
 *   - Types declare /atom/movable/var/list/worldstate_vars = list("var1", "var2", ...)
 *   - Base procs read/write those vars using BYOND's runtime vars[] accessor automatically
 *   - Types with complex serialization (vending stock, closet contents, etc.) override the procs directly
 *   - worldstateInitialize / worldstateFinalize use blanket loops — no per-type loop needed
 *
 * Adding a new type: just set worldstate_vars on the type. No loop edits required.
 */

/// Cache of worldstate data keyed by "[typepath]|[x]|[y]|[z]"
GLOBAL_LIST_EMPTY(persistence_worldstate_cache)

// =====================================================================
// BASE PROCS — declarative var list drives automatic save/restore
// =====================================================================

/// Set this list on any type to have worldstate save/restore those vars automatically.
/// Leave null (default) to opt out of worldstate entirely.
/atom/movable/var/list/worldstate_vars = null

/// Generic get — reads each var in worldstate_vars via BYOND runtime src.vars[] accessor.
/// Types with complex state (nested objects, list-encoded fields) override this proc directly.
/atom/movable/proc/worldstate_get_content()
	if(!worldstate_vars) return null
	var/list/content = list()
	for(var/v in worldstate_vars)
		content[v] = src.vars[v]
	return content

/// Generic apply — writes each var from the saved content dict back to the object.
/// Calls update_icon() afterward; types needing different post-apply hooks override this proc.
/atom/movable/proc/worldstate_apply_content(list/content)
	if(!worldstate_vars) return
	for(var/v in worldstate_vars)
		if((v in content) && !isnull(content[v]))
			src.vars[v] = content[v]
	update_icon()

// =====================================================================
// SUBSYSTEM PROCS
// =====================================================================

/**
 * Load saved machinery state from the database into the in-memory cache,
 * then apply it to all matching map objects.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/worldstateInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_worldstate_cache = list()

	if(!SSatlas.current_map)
		log_subsystem_persistence_info("Worldstate: Map is not SCCV Horizon, skipping worldstate init.")
		return

	if(!databaseCheckConnection("worldstateInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, content FROM ss13_worldstate_objects"
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "worldstateInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		CHECK_TICK
		var/cache_key = "[query.item[1]]|[query.item[2]]|[query.item[3]]|[query.item[4]]"
		GLOB.persistence_worldstate_cache[cache_key] = query.item[5]
		loaded++

	qdel(query)
	log_subsystem_persistence_info("Worldstate: Loaded [loaded] machine state entries from database.")

	if(!loaded)
		return

	var/applied = 0

	// Single blanket loop — covers all /obj/structure subtypes (machinery, closets, tables, grilles, etc.)
	// Only types with worldstate_vars set or explicit proc overrides will actually save/load.
	for(var/obj/structure/S in world)
		applied += worldstateApplyToMachine(S)

	// Items that need worldstate but aren't structures
	for(var/obj/item/radio/intercom/IC in world)
		applied += worldstateApplyToMachine(IC)

	log_subsystem_persistence_info("Worldstate: Applied saved state to [applied] machines.")

/**
 * Looks up the cache entry for this machine and applies its saved content.
 * Returns 1 if state was applied, 0 otherwise.
 */
/datum/controller/subsystem/persistence/proc/worldstateApplyToMachine(atom/movable/S)
	PRIVATE_PROC(TRUE)
	try
		var/turf/T = get_turf(S)
		if(!T || !T.z)
			return 0
		var/cache_key = "[S.type]|[T.x]|[T.y]|[T.z]"
		var/json = GLOB.persistence_worldstate_cache[cache_key]
		if(!json)
			return 0
		var/list/content = json_decode(json)
		if(!islist(content))
			return 0
		S.worldstate_apply_content(content)
		return 1
	catch(var/exception/e)
		log_subsystem_persistence_error("Worldstate: Failed to apply content to [S] at [get_turf(S)]: [e]")
		return 0

/**
 * Save current state of all tracked machinery types to the database.
 * Clears all previous worldstate data first so destroyed objects don't persist.
 * Called from SSpersistence.Shutdown().
 */
/datum/controller/subsystem/persistence/proc/worldstateFinalize()
	PRIVATE_PROC(TRUE)

	if(!SSatlas.current_map)
		log_subsystem_persistence_info("Worldstate: Map is not SCCV Horizon, skipping worldstate save.")
		return

	if(!databaseCheckConnection("worldstateFinalize"))
		return

	// Delete all previous worldstate data — destroyed objects won't be re-inserted
	var/datum/db_query/delete_all = SSdbcore.NewQuery("DELETE FROM ss13_worldstate_objects")
	delete_all.Execute()
	databaseCheckQueryResult(delete_all, "worldstateFinalize delete all")
	qdel(delete_all)

	var/saved = 0

	for(var/obj/structure/S in world)
		saved += worldstateSaveOneMachine(S)

	for(var/obj/item/radio/intercom/IC in world)
		saved += worldstateSaveOneMachine(IC)

	log_subsystem_persistence_info("Worldstate: Saved state for [saved] machines.")

/**
 * Serialize one machine and INSERT/UPDATE its row in the database.
 * Returns 1 on success, 0 if skipped or failed.
 */
/datum/controller/subsystem/persistence/proc/worldstateSaveOneMachine(atom/movable/S)
	PRIVATE_PROC(TRUE)
	CHECK_TICK
	var/datum/db_query/insert
	try
		var/turf/T = get_turf(S)
		if(!T || !T.z)
			return 0
		var/list/content = S.worldstate_get_content()
		if(!islist(content) || !length(content))
			return 0
		insert = SSdbcore.NewQuery(
			"INSERT INTO ss13_worldstate_objects (type, x, y, z, content, saved_at) \
			 VALUES (:type, :x, :y, :z, :content, NOW()) \
			 ON DUPLICATE KEY UPDATE content=VALUES(content), saved_at=NOW()",
			list(
				"type"    = "[S.type]",
				"x"       = T.x,
				"y"       = T.y,
				"z"       = T.z,
				"content" = json_encode(content)
			)
		)
		insert.Execute()
		databaseCheckQueryResult(insert, "worldstateSaveOneMachine [S.type]")
		qdel(insert)
		return 1
	catch(var/exception/e)
		if(insert)
			qdel(insert)
		log_subsystem_persistence_error("Worldstate: Failed to save [S] at [get_turf(S)]: [e]")
		return 0

// =====================================================================
// DECLARATIVE VAR LISTS
// Types listed here get full save/restore automatically via the base procs.
// To add a new type: just set worldstate_vars. No loop edits required.
// =====================================================================

// ------- Non-machinery structures -------

/obj/structure/grille
	worldstate_vars = list("density")  // density = FALSE when cut with wirecutters

// ------- Machinery -------

/obj/structure/machinery/door/airlock
	worldstate_vars = list("welded", "locked", "ai_disabled_id_scanner")

/obj/structure/machinery/door/blast
	worldstate_vars = list("density")

/obj/structure/machinery/power/smes
	worldstate_vars = list("charge", "input_attempt", "input_level", "output_attempt", "output_level")

/obj/structure/machinery/atmospherics/binary/pump
	worldstate_vars = list("use_power", "target_pressure")

/obj/structure/machinery/atmospherics/unary/vent_scrubber
	worldstate_vars = list("use_power", "scrubbing", "welded")

/obj/structure/machinery/atmospherics/unary/vent_pump
	worldstate_vars = list("use_power", "pump_direction", "external_pressure_bound", "internal_pressure_bound", "pressure_checks", "welded")

/obj/structure/machinery/light
	worldstate_vars = list("status")

/obj/structure/machinery/firealarm
	worldstate_vars = list("detecting", "working")

/obj/structure/machinery/suit_cycler
	worldstate_vars = list("locked", "safeties", "radiation_level", "target_department", "target_species")

/obj/structure/machinery/porta_turret
	worldstate_vars = list("enabled", "lethal", "locked", "check_arrest", "check_records", "check_weapons", "check_access", "check_wildlife", "check_synth", "target_borgs", "auto_repair")

/obj/structure/machinery/disposal
	worldstate_vars = list("is_on", "can_flush")

/obj/structure/machinery/turret_control
	worldstate_vars = list("enabled", "lethal", "locked", "check_arrest", "check_records", "check_weapons", "check_access", "check_wildlife", "check_synth", "target_borgs")

/obj/structure/machinery/atmospherics/unary/cryo_cell
	worldstate_vars = list("on", "temperature_warning_threshold", "temperature_danger_threshold")

/obj/structure/machinery/spaceheater
	worldstate_vars = list("on", "set_temperature", "high_power_cell")

/obj/structure/machinery/sleeper
	worldstate_vars = list("filtering", "pump", "stasis")

/obj/structure/machinery/chem_heater
	worldstate_vars = list("target_temperature", "should_heat", "slow_mode")

/obj/structure/machinery/biogenerator
	worldstate_vars = list("points", "build_eff", "eat_eff", "processing_time_divisor")

/obj/structure/machinery/stasis_bed
	worldstate_vars = list("stasis_enabled", "stasis_can_toggle")

/obj/structure/machinery/stasis_cage
	worldstate_vars = list("safety")

/obj/structure/machinery/newscaster
	worldstate_vars = list("c_locked", "securityCaster")

/obj/structure/machinery/flasher
	worldstate_vars = list("disable")

/obj/structure/machinery/optable
	worldstate_vars = list("suppressing")

/obj/structure/machinery/floodlight
	worldstate_vars = list("on", "unlocked", "open")

/obj/structure/machinery/hologram/holopad
	worldstate_vars = list("long_range", "hacked")

/obj/structure/machinery/mass_driver
	worldstate_vars = list("power")

/obj/structure/machinery/teleporter
	worldstate_vars = list("calibration", "ignore_distance")

/obj/structure/machinery/gumballmachine
	worldstate_vars = list("amountleft", "broken", "on")

/obj/structure/machinery/alarm
	worldstate_vars = list("mode", "target_temperature", "breach_detection", "locked", "aidisabled", "highpower", "frequency")

// =====================================================================
// EXPLICIT PROCS — complex serialization that needs custom logic
// =====================================================================

// ------- APC (nested cell.charge) -------

/obj/structure/machinery/power/apc/worldstate_get_content()
	var/list/content = list()
	content["lighting"]   = lighting
	content["equipment"]  = equipment
	content["environ"]    = environ
	content["chargemode"] = chargemode
	content["autoflag"]   = autoflag
	content["aidisabled"] = aidisabled
	content["locked"]     = locked
	if(cell)
		content["cell_charge"] = cell.charge
	return content

/obj/structure/machinery/power/apc/worldstate_apply_content(list/content)
	if(!isnull(content["lighting"]))   lighting   = content["lighting"]
	if(!isnull(content["equipment"]))  equipment  = content["equipment"]
	if(!isnull(content["environ"]))    environ    = content["environ"]
	if(!isnull(content["chargemode"])) chargemode = content["chargemode"]
	if(!isnull(content["autoflag"]))   autoflag   = content["autoflag"]
	if(!isnull(content["aidisabled"])) aidisabled = content["aidisabled"]
	if(!isnull(content["locked"]))     locked     = content["locked"]
	if(cell && !isnull(content["cell_charge"]))
		cell.charge = text2num(content["cell_charge"])
	update_icon()

// ------- Camera (network is a list) -------

/obj/structure/machinery/camera/worldstate_get_content()
	return list("network" = json_encode(network), "status" = status)

/obj/structure/machinery/camera/worldstate_apply_content(list/content)
	if(content["network"])
		network = json_decode(content["network"])
	if(!isnull(content["status"]))
		status = text2num(content["status"])

// ------- Vending machine (stock loop) -------

/obj/structure/machinery/vending/worldstate_get_content()
	var/list/stock = list()
	for(var/datum/data/vending_product/P in product_records)
		stock["[P.product_path]"] = P.amount
	return list("active" = active, "emagged" = emagged, "stock" = json_encode(stock))

/obj/structure/machinery/vending/worldstate_apply_content(list/content)
	if(!isnull(content["active"]))  active  = content["active"]
	if(!isnull(content["emagged"])) emagged = content["emagged"]
	if(content["stock"])
		var/list/stock = json_decode(content["stock"])
		for(var/datum/data/vending_product/P in product_records)
			var/key = "[P.product_path]"
			if(key in stock)
				P.amount = text2num(stock[key])

// ------- Cryopod (null guard for unconfigured pods) -------

/obj/structure/machinery/cryopod/worldstate_get_content()
	if(!persistent_network)
		return null
	return list("persistent_network" = persistent_network, "persistent_spawn" = persistent_spawn)

/obj/structure/machinery/cryopod/worldstate_apply_content(list/content)
	// Only apply non-empty network strings — don't let a stale empty DB value wipe the "public" default
	if(!isnull(content["persistent_network"]) && length(content["persistent_network"]))
		persistent_network = content["persistent_network"]
	if(!isnull(content["persistent_spawn"]))
		persistent_spawn = content["persistent_spawn"]

// ------- Conveyor switch (needs update() not update_icon()) -------

/obj/structure/machinery/conveyor_switch/worldstate_get_content()
	return list("position" = position)

/obj/structure/machinery/conveyor_switch/worldstate_apply_content(list/content)
	position = text2num(content["position"])
	update()

// ------- Navigation beacon (needs set_codes() after apply) -------

/obj/structure/machinery/navbeacon/worldstate_get_content()
	return list(
		"location"  = location,
		"locked"    = locked,
		"freq"      = freq,
		"codes_txt" = codes_txt,
		"open"      = open
	)

/obj/structure/machinery/navbeacon/worldstate_apply_content(list/content)
	location = content["location"]
	locked   = content["locked"]
	open     = content["open"]
	if(!isnull(content["freq"]))
		freq = text2num(content["freq"]) || freq
	if(content["codes_txt"])
		codes_txt = content["codes_txt"]
		set_codes()
	update_icon()

// ------- Intercom (needs set_frequency() after apply) -------

/obj/item/radio/intercom/worldstate_get_content()
	return list(
		"default_frequency"      = default_frequency,
		"should_be_broadcasting" = should_be_broadcasting,
		"should_be_listening"    = should_be_listening
	)

/obj/item/radio/intercom/worldstate_apply_content(list/content)
	default_frequency      = text2num(content["default_frequency"]) || default_frequency
	should_be_broadcasting = content["should_be_broadcasting"]
	should_be_listening    = content["should_be_listening"]
	set_frequency(default_frequency)
