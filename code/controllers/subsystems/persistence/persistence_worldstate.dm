/*
 * Persistence - World State
 * Saves and restores station machinery state across rounds via SQL.
 * Each machine is identified by its (type, x, y, z) position.
 *
 * Pattern (Persistent-Bay inspired):
 *   - Types declare /atom/movable/var/list/worldstate_vars = list("var1", "var2", ...)
 *   - Base procs read/write those vars using BYOND's runtime vars[] accessor automatically
 *   - Types with complex serialization (vending stock, closet contents, etc.) override the procs directly
 *   - worldstateInitialize / worldstateFinalize use blanket loops  no per-type loop needed
 *
 * Adding a new type: just set worldstate_vars on the type. No loop edits required.
 */

/// Cache of worldstate data keyed by "[typepath]|[x]|[y]|[z]"
GLOBAL_LIST_EMPTY(persistence_worldstate_cache)

// =====================================================================
// BASE PROCS  declarative var list drives automatic save/restore
// =====================================================================

/// Set this list on any type to have worldstate save/restore those vars automatically.
/// Leave null (default) to opt out of worldstate entirely.
/atom/movable/var/list/worldstate_vars = null

/// Generic get  reads each var in worldstate_vars via BYOND runtime src.vars[] accessor.
/// Types with complex state (nested objects, list-encoded fields) override this proc directly.
/atom/movable/proc/worldstate_get_content()
	if(!worldstate_vars) return null
	var/list/content = list()
	for(var/v in worldstate_vars)
		content[v] = src.vars[v]
	return content

/// Generic apply  writes each var from the saved content dict back to the object.
/// Calls update_icon() afterward; types needing different post-apply hooks override this proc.
/atom/movable/proc/worldstate_apply_content(list/content)
	if(!worldstate_vars) return
	for(var/v in worldstate_vars)
		if((v in content) && !isnull(content[v]))
			// Faction uids saved before normalization may be raw display names
			if(v == "persistent_network")
				src.vars[v] = normalize_faction_uid(content[v])
			else
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

	if(!databaseCheckConnection("worldstateInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type, x, y, z, content FROM ss13_worldstate_objects WHERE map_path = :map_path",
		list("map_path" = SSatlas.current_map.path)
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

	// Single blanket loop  covers all /obj/structure subtypes (machinery, closets, tables, grilles, etc.)
	// Only types with worldstate_vars set or explicit proc overrides will actually save/load.
	for(var/obj/structure/S in world)
		if(persistence_z_excluded(S.z)) continue
		applied += worldstateApplyToMachine(S)

	// Items that need worldstate but aren't structures
	for(var/obj/item/radio/intercom/IC in world)
		if(persistence_z_excluded(IC.z)) continue
		applied += worldstateApplyToMachine(IC)

	for(var/obj/item/modular_computer/MC in world)
		if(persistence_z_excluded(MC.z)) continue
		applied += worldstateApplyToMachine(MC)

	log_subsystem_persistence_info("Worldstate: Applied saved state to [applied] machines.")

/**
 * Deterministic power-state resync, called as the final step of
 * SSpersistence.Initialize() AFTER makepowernets(). The worldstate restore
 * above overwrites APC channels/autoflag/cell charge (and SMES charge) but
 * only calls update_icon() -- area.power_light/equip/environ are ONLY written
 * by apc/update(), so without this sweep the area flags and every machine's
 * cached NOPOWER stat are left to converge via racy timers (batteryless
 * modular computers refuse to turn on, ATMs render lit but reject use, etc).
 */
/datum/controller/subsystem/persistence/proc/powerstateFinalize()
	var/apc_count = 0
	var/list/apc_areas = list()
	for(var/obj/structure/machinery/power/apc/A in world)
		if(!A.z) continue
		if(A.cell)
			A.update_channels()  // re-derive channel bits from the RESTORED cell charge
		A.update()               // write area power flags (broadcasts on change)
		A.update_icon()          // refresh the visible charge/equipment/lighting overlays to match
		if(A.area)
			apc_areas |= A.area
			// Flags the exact bug class where an APC got recreated before its
			// real area was restored, permanently binding it to the background
			// area instead -- self-reporting if this ever regresses.
			if(A.area.area_flags & AREA_FLAG_IS_BACKGROUND)
				log_subsystem_persistence_error("Worldstate: APC '[A.name]' at ([A.x],[A.y],[A.z]) resolved to background area '[A.area.name]' -- likely restored before its real area, or was never claimed by one.")
		apc_count++

	var/solar_count = 0
	for(var/obj/structure/machinery/power/solar_control/SC in world)
		if(!SC.z) continue
		// search_for_connected() only scans an already-established powernet --
		// if the control's own Initialize()-time connect_to_network() ran before
		// player-modified cabling was restored, powernet is still null here and
		// the scan would silently no-op forever. Re-attempt the connection now
		// that makepowernets() has finalized the real topology.
		if(!SC.powernet)
			SC.connect_to_network()
		SC.search_for_connected()
		SC.update() // sync cdir/panel angle to the current sun position immediately, instead of waiting up to SSsun's 1-minute tick
		solar_count++

	// Force every machine to re-read its area's power flags: machines cache
	// stat & NOPOWER and only refresh on this signal, so ones that sampled
	// power mid-restore would otherwise keep stale state until something
	// happens to flip their area again.
	for(var/area/AR in apc_areas)
		SEND_SIGNAL(AR, COMSIG_AREA_POWER_CHANGE)

	log_subsystem_persistence_info("Worldstate: Power state finalized -- [apc_count] APC(s), [solar_count] solar controller(s), [length(apc_areas)] area(s) rebroadcast.")

/**
 * Clear atmos alarm state latched during boot, called AFTER atmosApply()
 * has put the real saved air back. While turfs/zones rebuild, live air
 * alarms sample transient vacuum/cold and latch danger levels that close
 * the area firedoors; the reset path can't recover from a frozen
 * danger_level, so we zero every alarm and re-derive each area once the
 * air is correct. Genuinely bad zones re-trigger within one process tick.
 */
/datum/controller/subsystem/persistence/proc/atmosAlarmsReset()
	var/alarms_reset = 0
	var/list/alarmed_areas = list()
	for(var/obj/structure/machinery/alarm/AA in SSmachinery.machinery)
		if(!AA.z)
			continue
		AA.danger_level = 0
		// Clear the environment memo so the next process() re-samples the
		// restored air instead of short-circuiting on "unchanged".
		AA.previous_environment_gas = list()
		AA.previous_environment_temperature = null
		AA.previous_environment_total_moles = null
		AA.previous_environment_volume = null
		AA.previous_environment_group_multiplier = null
		// Re-apply the restored mode so vents/scrubbers actually match it --
		// worldstate only writes the var.
		AA.apply_mode()
		if(AA.alarm_area && AA.alarm_area.atmosalm)
			alarmed_areas |= AA.alarm_area
		alarms_reset++
	// With every alarm zeroed the recompute clears the area alarm and
	// air_doors_open() lifts the shutters (welded doors stay put).
	for(var/area/AR in alarmed_areas)
		AR.atmosalert(0, null)
	log_subsystem_persistence_info("Worldstate: Atmos alarms reset -- [alarms_reset] alarm(s), [length(alarmed_areas)] latched area(s) cleared.")

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

	if(!databaseCheckConnection("worldstateFinalize"))
		return

	// DB-side clock (not DM's) to avoid clock skew. Anything re-saved below
	// gets a fresh saved_at via ON DUPLICATE KEY UPDATE and survives the
	// cutoff; only rows nothing touched this cycle (destroyed objects) get
	// removed, and only after the resave loop below completes. If the loop
	// is interrupted (crash, disconnect), nothing is deleted at all -- the
	// previous save stays intact instead of being wiped up front.
	var/datum/db_query/clock = SSdbcore.NewQuery("SELECT NOW(6)")
	clock.Execute()
	var/cutoff
	if(databaseCheckQueryResult(clock, "worldstateFinalize clock") && clock.NextRow())
		cutoff = clock.item[1]
	qdel(clock)
	if(!cutoff)
		return

	var/saved = 0

	for(var/obj/structure/S in world)
		if(persistence_z_excluded(S.z)) continue
		saved += worldstateSaveOneMachine(S)

	for(var/obj/item/radio/intercom/IC in world)
		if(persistence_z_excluded(IC.z)) continue
		saved += worldstateSaveOneMachine(IC)

	for(var/obj/item/modular_computer/MC in world)
		if(persistence_z_excluded(MC.z)) continue
		saved += worldstateSaveOneMachine(MC)

	var/datum/db_query/delete_stale = SSdbcore.NewQuery(
		"DELETE FROM ss13_worldstate_objects WHERE saved_at < :cutoff AND map_path = :map_path",
		list("cutoff" = cutoff, "map_path" = SSatlas.current_map.path)
	)
	delete_stale.Execute()
	databaseCheckQueryResult(delete_stale, "worldstateFinalize delete stale")
	qdel(delete_stale)

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
			"INSERT INTO ss13_worldstate_objects (map_path, type, x, y, z, content, saved_at) \
			 VALUES (:map_path, :type, :x, :y, :z, :content, NOW()) \
			 ON DUPLICATE KEY UPDATE content=VALUES(content), saved_at=NOW()",
			list(
				"map_path" = SSatlas.current_map.path,
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

/obj/structure/machinery/telepad_cargo
	worldstate_vars = list("persistent_network", "persistent_spawn", "faction_shackled")

// Full override instead of worldstate_vars -- also saves/restores downloaded
// software via the shared helpers in modular_computer/faction.dm, so a
// stationary shackled computer keeps its installed programs across restarts
// the same way a dynamically-tracked one does via persistent_objects_*_content().
/obj/item/modular_computer/worldstate_get_content()
	var/list/content = list("persistent_network" = persistent_network, "faction_shackled" = faction_shackled)
	var/list/programs = modcomp_save_programs()
	if(length(programs))
		content["programs"] = json_encode(programs)
	return content

/obj/item/modular_computer/worldstate_apply_content(list/content)
	if(!isnull(content["persistent_network"]))
		persistent_network = normalize_faction_uid(content["persistent_network"]) || ""
	if(!isnull(content["faction_shackled"]))
		faction_shackled = content["faction_shackled"]
	if(content["programs"])
		modcomp_restore_programs(json_decode(content["programs"]))

/obj/structure/machinery/door/airlock
	worldstate_vars = list("name", "welded", "locked", "ai_disabled_id_scanner", "req_access_faction", "req_access", "req_one_access", "id_tag", "frequency")

/obj/structure/machinery/door/airlock/worldstate_get_content()
	var/list/content = ..()
	if(!content) content = list()
	if(wires && length(wires.cut_wires))
		content["cut_wires"] = json_encode(wires.cut_wires)
	return content

/obj/structure/machinery/door/airlock/worldstate_apply_content(list/content)
	..()
	if(content && content["cut_wires"] && wires)
		var/list/cut = json_decode(content["cut_wires"])
		if(islist(cut))
			wires.cut_wires = cut
	// The generic apply above only sets the raw frequency var -- it takes an
	// actual set_frequency() call to re-register with SSradio, or a restored
	// door with a restored id_tag would sit on the right frequency var but
	// never actually receive anything.
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/door/blast
	worldstate_vars = list("density")

/obj/structure/machinery/power/smes
	worldstate_vars = list("charge", "input_attempt", "input_level", "output_attempt", "output_level")

// ------- SMES buildable (nested coil composition, not a flat var) -------
// capacity/input_level_max/output_level_max are derived from component_parts
// each boot (recalc_coils()), and Initialize() unconditionally rebuilds
// component_parts from cur_coils copies of the base-tier coil -- neither the
// coil count nor the upgraded coil types survive a restart without this.

/obj/structure/machinery/power/smes/buildable/worldstate_get_content()
	var/list/content = ..() // base smes worldstate_vars: charge, input_attempt, input_level, output_attempt, output_level
	if(!content) content = list()
	var/list/coil_types = list()
	for(var/obj/item/smes_coil/C in component_parts)
		coil_types += "[C.type]"
	content["coil_types"] = coil_types
	return content

/obj/structure/machinery/power/smes/buildable/worldstate_apply_content(list/content)
	..() // restores charge/input_attempt/etc via the inherited worldstate_vars list
	if(content && islist(content["coil_types"]) && length(content["coil_types"]))
		for(var/obj/item/smes_coil/C in component_parts)
			qdel(C)
		component_parts = list()
		for(var/type_str in content["coil_types"])
			var/coil_type = text2path(type_str)
			if(ispath(coil_type, /obj/item/smes_coil))
				component_parts += new coil_type(src)
		cur_coils = length(component_parts)
		recalc_coils()

/obj/structure/machinery/atmospherics/binary/pump
	worldstate_vars = list("use_power", "target_pressure")

/obj/structure/machinery/atmospherics/unary/vent_scrubber
	worldstate_vars = list("use_power", "scrubbing", "welded")

/obj/structure/machinery/atmospherics/unary/vent_pump
	worldstate_vars = list("use_power", "pump_direction", "external_pressure_bound", "internal_pressure_bound", "pressure_checks", "welded", "frequency")

/obj/structure/machinery/atmospherics/unary/vent_pump/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/portable_atmospherics/canister
	worldstate_vars = list("valve_open", "release_pressure", "release_flow_rate", "can_label")

/obj/structure/machinery/portable_atmospherics/canister/worldstate_get_content()
	var/list/content = ..()
	if(air_contents)
		content["air_gas"] = json_encode(air_contents.gas)
		content["air_temperature"] = air_contents.temperature
	return content

/obj/structure/machinery/portable_atmospherics/canister/worldstate_apply_content(list/content)
	..()
	if(!air_contents || !content["air_gas"])
		return
	var/list/gases = json_decode(content["air_gas"])
	if(islist(gases))
		air_contents.gas = gases
	if(!isnull(content["air_temperature"]))
		air_contents.temperature = text2num(content["air_temperature"])
	air_contents.update_values()

// Airlock cycler parts (section 8): buildstage/panel_open + dir so a still-
// under-construction frame/circuit survives a restart mid-build, plus every
// tag/frequency link a multitool sets up, so a player-built cycler doesn't
// need to be rewired after a restart.
/obj/structure/machinery/airlock_sensor
	worldstate_vars = list("buildstage", "panel_open", "dir", "id_tag", "master_tag", "frequency", "on")

/obj/structure/machinery/airlock_sensor/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/access_button
	worldstate_vars = list("buildstage", "panel_open", "dir", "master_tag", "frequency", "on")

/obj/structure/machinery/access_button/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller
	worldstate_vars = list("buildstage", "panel_open", "dir", "id_tag", "frequency", "tag_exterior_door", "tag_interior_door", "tag_airpump", "tag_chamber_sensor", "tag_exterior_sensor", "tag_interior_sensor")

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/worldstate_apply_content(list/content)
	..()
	if(frequency)
		set_frequency(frequency)

// ------- Telecomms machinery (section 9) -------
// Full override instead of worldstate_vars: freq_listening is list-valued
// (json-encoded, same as camera's network list above) and links/
// links_by_telecomms_type are object references, not JSON-safe -- saved as
// [x,y,z] coordinates and restored via add_new_link(), which already
// rebuilds links_by_telecomms_type as a side effect (it's a derived index,
// not independently saved). Message logs (pda_msgs/rc_msgs -- themselves
// unfinished, see the TODO already in message_server.dm) and the server's
// NTSL2 script (rawcode is dead/unreferenced outside its own declaration;
// the actual compiled Program datum isn't a simple var dump) are both
// deliberately NOT persisted here -- out of scope for this pass, flagged
// rather than silently skipped.
/obj/structure/machinery/telecomms/worldstate_get_content()
	var/list/link_coords = list()
	for(var/obj/structure/machinery/telecomms/L in links)
		link_coords += list(list(L.x, L.y, L.z))
	return list(
		"id" = id,
		"network" = network,
		"use_power" = use_power,
		"integrity" = integrity,
		"persistent_network" = persistent_network,
		"freq_listening" = json_encode(freq_listening),
		"links" = json_encode(link_coords),
	)

/obj/structure/machinery/telecomms/worldstate_apply_content(list/content)
	if(content["id"])
		id = content["id"]
	if(content["network"])
		network = content["network"]
	if(!isnull(content["use_power"]))
		use_power = text2num(content["use_power"])
	if(!isnull(content["integrity"]))
		integrity = text2num(content["integrity"])
	if(!isnull(content["persistent_network"]))
		persistent_network = normalize_faction_uid(content["persistent_network"]) || ""
	if(content["freq_listening"])
		var/list/freqs = json_decode(content["freq_listening"])
		if(islist(freqs))
			freq_listening = freqs
	if(content["links"])
		var/list/coords = json_decode(content["links"])
		if(islist(coords))
			for(var/list/pair in coords)
				if(!islist(pair) || length(pair) < 3)
					continue
				var/turf/T = locate(pair[1], pair[2], pair[3])
				if(!T)
					continue
				for(var/obj/structure/machinery/telecomms/other in T)
					add_new_link(other)
	update_icon()

/obj/structure/machinery/telecomms/bus
	worldstate_vars = list("change_frequency")

/obj/structure/machinery/telecomms/message_server
	worldstate_vars = list("decryptkey", "spamfilter_limit")

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

/obj/structure/machinery/floodlight/worldstate_apply_content(list/content)
	. = ..()
	// The restore writes "on" as a raw var -- the dynamic light listens to
	// set_light_on()'s signal, which a raw write never fires.
	set_light_on(on)

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

/obj/structure/machinery/power/portgen/basic
	worldstate_vars = list("active", "open", "power_output", "sheets", "sheet_left", "anchored")

/obj/structure/machinery/power/portgen/basic/worldstate_apply_content(list/content)
	. = ..()
	// The generic restore above only sets vars directly -- it doesn't re-run
	// the side effect that normally accompanies anchored becoming true.
	// Initialize() already tries this, but runs BEFORE this restore applies
	// the saved value, so it sees the class default (unanchored) and skips
	// it. Without this, a restored generator reports anchored/active/fueled
	// correctly but never actually rejoins its powernet -- it silently
	// contributes zero power, and anything drawing from that grid falls back
	// to draining its own cell until it reads as unpowered.
	if(anchored)
		connect_to_network()

/obj/structure/machinery/power/solar_control
	worldstate_vars = list("track", "trackrate")

/obj/structure/machinery/power/generator
	worldstate_vars = list("anchored")

// =====================================================================
// EXPLICIT PROCS  complex serialization that needs custom logic
// =====================================================================

// ------- APC (nested cell.charge) -------

/obj/structure/machinery/power/apc/worldstate_get_content()
	var/list/content = list()
	content["name"]       = name
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
	// Only overrides the formula-derived "[area] APC" name when it was
	// actually customized (e.g. via an area bulk-rename) -- the areasInitialize()
	// reorder above already makes the formula-derived name correct on its own,
	// this just preserves a manual override on top of that.
	if(!isnull(content["name"]) && length(content["name"]))
		name = content["name"]
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
	// Only apply non-empty network strings  don't let a stale empty DB value wipe the "public" default
	if(!isnull(content["persistent_network"]) && length(content["persistent_network"]))
		persistent_network = normalize_faction_uid(content["persistent_network"])
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

// ------- Suit storage unit (saves SUIT/HELMET/MASK item state) -------

/obj/structure/machinery/suit_storage_unit/worldstate_get_content()
	var/list/content = list()
	if(SUIT)
		var/list/s = serializePersistentItem(SUIT)
		if(s) content["suit"] = json_encode(s)
	if(HELMET)
		var/list/h = serializePersistentItem(HELMET)
		if(h) content["helmet"] = json_encode(h)
	if(MASK)
		var/list/m = serializePersistentItem(MASK)
		if(m) content["mask"] = json_encode(m)
	if(!length(content)) return list()
	return content

/obj/structure/machinery/suit_storage_unit/worldstate_apply_content(list/content)
	if(SUIT)   { qdel(SUIT);   SUIT   = null }
	if(HELMET) { qdel(HELMET); HELMET = null }
	if(MASK)   { qdel(MASK);   MASK   = null }
	if(content["suit"])
		SUIT   = deserializePersistentItem(json_decode(content["suit"]),   src)
	if(content["helmet"])
		HELMET = deserializePersistentItem(json_decode(content["helmet"]), src)
	if(content["mask"])
		MASK   = deserializePersistentItem(json_decode(content["mask"]),   src)
	update_icon()

// ------- Solar control (trigger panel scan after apply) -------

/obj/structure/machinery/power/solar_control/worldstate_apply_content(list/content)
	..()
	if(track > 0)
		search_for_connected()

// ------- Ladder (save/restore target_up and target_down by position) -------

/obj/structure/ladder/worldstate_get_content()
	var/list/content = list("allowed_directions" = allowed_directions)
	if(target_down)
		var/turf/TL = get_turf(target_down)
		if(TL) { content["td_x"] = TL.x; content["td_y"] = TL.y; content["td_z"] = TL.z }
	if(target_up)
		var/turf/TU = get_turf(target_up)
		if(TU) { content["tu_x"] = TU.x; content["tu_y"] = TU.y; content["tu_z"] = TU.z }
	if(length(content) <= 1 && !target_up && !target_down) return list()
	return content

/obj/structure/ladder/worldstate_apply_content(list/content)
	if(content["allowed_directions"])
		allowed_directions = text2num(content["allowed_directions"])
	if(content["td_x"])
		var/turf/T = locate(text2num(content["td_x"]), text2num(content["td_y"]), text2num(content["td_z"]))
		if(T) for(var/obj/structure/ladder/BL in T)
			if(BL.allowed_directions & UP) { target_down = BL; BL.target_up = src; break }
	if(content["tu_x"])
		var/turf/T = locate(text2num(content["tu_x"]), text2num(content["tu_y"]), text2num(content["tu_z"]))
		if(T) for(var/obj/structure/ladder/BL in T)
			if(BL.allowed_directions & DOWN) { target_up = BL; BL.target_down = src; break }
	update_icon()
