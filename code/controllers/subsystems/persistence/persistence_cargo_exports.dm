/*
 * Persistence - Cargo Exports
 * Admin-managed list of sellable item types and their export price, replacing
 * the old hardcoded per-material /datum/export price list (code/modules/cargo/exports/,
 * e.g. materials.dm, sheets.dm -- left in place as inert legacy data, their costs migrated into this
 * table as starting defaults, see _cargoExportsSeedDefaults()). Anything NOT
 * in this list still sells, at CARGO_EXPORT_BASE_PRICE -- the export flow
 * accepts any item, not just a fixed catalog.
 * DB-backed (ss13_cargo_exports, V086) with an in-memory cache so every sale
 * doesn't hit the database.
 */

/// Flat floor price for any item with no specific configured export price.
#define CARGO_EXPORT_BASE_PRICE 10

/// type path string -> price (credits). Loaded at boot, updated live by the
/// Manage Cargo Exports admin verb.
GLOBAL_LIST_EMPTY(cargo_export_prices)

/**
 * Load the export price list into the cache, seeding it from the existing
 * hardcoded /datum/export subtypes on first boot (empty table) so nothing
 * regresses to the base price on day one.
 * Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/cargoExportsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.cargo_export_prices = list()

	if(!databaseCheckConnection("cargoExportsInitialize"))
		return

	var/datum/db_query/countq = SSdbcore.NewQuery(
		"SELECT COUNT(*) FROM ss13_cargo_exports WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	countq.Execute()
	var/existing_count = 0
	if(databaseCheckQueryResult(countq, "cargoExportsInitialize count") && countq.NextRow())
		existing_count = text2num(countq.item[1])
	qdel(countq)

	if(!existing_count)
		_cargoExportsSeedDefaults()

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type_path, price, label, is_illegal FROM ss13_cargo_exports WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "cargoExportsInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.cargo_export_prices[query.item[1]] = list("price" = text2num(query.item[2]), "label" = query.item[3], "illegal" = text2num(query.item[4]) ? TRUE : FALSE)
	qdel(query)
	log_subsystem_persistence_info("Cargo exports: loaded [length(GLOB.cargo_export_prices)] priced export type(s).")

/// One-time seed from the existing hardcoded /datum/export subtypes' cost +
/// export_types, so the new DB list starts with today's prices instead of
/// everything falling to the base price the moment this ships.
/datum/controller/subsystem/persistence/proc/_cargoExportsSeedDefaults()
	PRIVATE_PROC(TRUE)
	var/seeded = 0
	for(var/subtype in subtypesof(/datum/export))
		CHECK_TICK
		var/datum/export/E = new subtype
		if(E.export_types && E.export_types.len)
			for(var/t in E.export_types)
				var/datum/db_query/seedq = SSdbcore.NewQuery(
					{"INSERT INTO ss13_cargo_exports (map_path, type_path, price, label)
					VALUES (:mp, :tp, :price, :label)
					ON DUPLICATE KEY UPDATE price = price"},
					list(
						"mp" = "[SSatlas.current_map.path]",
						"tp" = "[t]",
						"price" = E.cost,
						"label" = E.unit_name != "" ? E.unit_name : null
					)
				)
				seedq.Execute()
				databaseCheckQueryResult(seedq, "cargoExportsSeedDefaults")
				qdel(seedq)
				seeded++
		qdel(E)
	log_subsystem_persistence_info("Cargo exports: seeded [seeded] default export price(s) from legacy /datum/export subtypes.")

/**
 * Resolves the export price for an item: exact type match, then walks up
 * the type hierarchy for the nearest configured parent type, else the flat
 * base price -- every item is sellable, not just a fixed catalog.
 *
 * An entry flagged illegal only actually pays its configured price while an
 * operational piracy beacon (code/game/objects/structures/machinery/piracy_beacon.dm)
 * is present on thing's own current Z -- otherwise it quietly falls back to
 * the normal base price, same as an unlisted item. This is the single choke
 * point every real export path (cargo shuttle, export scanner, Cargo Exports
 * Terminal, Cargo Control) already shares, so the rule applies everywhere
 * automatically with no other call site needing to know about it.
 */
/proc/get_cargo_export_price(atom/movable/thing)
	if(!thing)
		return 0
	var/t = thing.type
	while(t)
		if("[t]" in GLOB.cargo_export_prices)
			var/list/entry = GLOB.cargo_export_prices["[t]"]
			if(entry["illegal"] && !piracy_beacon_active_on_z(GET_Z(thing)))
				return CARGO_EXPORT_BASE_PRICE
			return entry["price"]
		t = type2parent(t)
	return CARGO_EXPORT_BASE_PRICE

/**
 * Sets (or clears, if price is null) the export price for a type path,
 * persists it, and updates the live cache immediately.
 */
/proc/set_cargo_export_price(type_path, price, label, illegal = FALSE)
	if(!SSpersistence.databaseCheckConnection("set_cargo_export_price"))
		return FALSE
	var/tp = "[type_path]"
	if(isnull(price))
		var/datum/db_query/delq = SSdbcore.NewQuery(
			"DELETE FROM ss13_cargo_exports WHERE type_path = :tp AND map_path = :mp",
			list("tp" = tp, "mp" = "[SSatlas.current_map.path]")
		)
		delq.Execute()
		var/delete_ok = SSpersistence.databaseCheckQueryResult(delq, "set_cargo_export_price delete")
		qdel(delq)
		if(!delete_ok)
			return FALSE
		GLOB.cargo_export_prices -= tp
		return TRUE

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_cargo_exports (map_path, type_path, price, label, is_illegal)
		VALUES (:mp, :tp, :price, :label, :illegal)
		ON DUPLICATE KEY UPDATE price = VALUES(price), label = VALUES(label), is_illegal = VALUES(is_illegal)"},
		list("mp" = "[SSatlas.current_map.path]", "tp" = tp, "price" = price, "label" = label, "illegal" = illegal ? 1 : 0)
	)
	q.Execute()
	var/update_ok = SSpersistence.databaseCheckQueryResult(q, "set_cargo_export_price")
	qdel(q)
	if(!update_ok)
		return FALSE
	GLOB.cargo_export_prices[tp] = list("price" = price, "label" = label, "illegal" = illegal ? TRUE : FALSE)
	return TRUE

// ============================================================
// CARGO EXPORTS ADMIN VERB
// ============================================================

/datum/admins/proc/manage_cargo_exports()
	set name = "Manage Cargo Exports"
	set category = "Persistence"
	set desc = "Add, remove, or reprice sellable cargo export item types."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- cargo export prices are inactive (everything sells at the base price: [CARGO_EXPORT_BASE_PRICE] cr)."))
		return

	while(usr && usr.client)
		var/choice = tgui_input_list(usr, "Cargo exports ([length(GLOB.cargo_export_prices)] priced type(s), base price [CARGO_EXPORT_BASE_PRICE] cr for anything unlisted):", "Manage Cargo Exports", list("Add/Edit Export", "Remove Export", "Wipe All Exports", "View List", "Done"))
		if(!choice || choice == "Done")
			return

		if(choice == "Add/Edit Export")
			var/typed_path = tgui_input_text(usr, "Type path to price (e.g. /obj/item/stack/sheet/mineral/plasma):", "Manage Cargo Exports", max_length = 128)
			if(!typed_path)
				continue
			var/path = text2path(typed_path)
			if(!path || !ispath(path, /obj))
				to_chat(usr, SPAN_WARNING("'[typed_path]' is not a valid /obj type path."))
				continue
			var/price = tgui_input_number(usr, "Export price for [typed_path] (credits):", "Manage Cargo Exports", GLOB.cargo_export_prices["[path]"]?["price"] || CARGO_EXPORT_BASE_PRICE, 1000000, 0)
			if(isnull(price))
				continue
			var/label = tgui_input_text(usr, "Display label (optional):", "Manage Cargo Exports", "", max_length = 64)
			var/illegal_choice = tgui_alert(usr, "Normal export, or illegal/black-market (only sells at this price with an operational piracy beacon active on that Z -- otherwise falls back to the base price)?", "Manage Cargo Exports", list("Normal", "Illegal", "Cancel"))
			if(!illegal_choice || illegal_choice == "Cancel")
				continue
			var/illegal = (illegal_choice == "Illegal")
			if(set_cargo_export_price(path, price, label != "" ? label : null, illegal))
				log_and_message_admins("set cargo export price of '[path]' to [price] cr[illegal ? " (illegal/black-market)" : ""]", usr)
				to_chat(usr, SPAN_GOOD("'[path]' now sells for [price] cr[illegal ? " -- illegal, requires an active piracy beacon" : ""]."))
			else
				to_chat(usr, SPAN_WARNING("Failed to save -- database error."))

		if(choice == "Remove Export")
			if(!length(GLOB.cargo_export_prices))
				to_chat(usr, SPAN_NOTICE("No priced exports to remove."))
				continue
			var/list/remove_choices = list()
			for(var/tp in GLOB.cargo_export_prices)
				remove_choices["[GLOB.cargo_export_prices[tp]["price"]] cr: [tp]"] = tp
			var/remove_pick = tgui_input_list(usr, "Remove which export price? (reverts to the base price)", "Manage Cargo Exports", remove_choices)
			if(!remove_pick)
				continue
			var/remove_tp = remove_choices[remove_pick]
			if(set_cargo_export_price(remove_tp, null))
				log_and_message_admins("removed cargo export price for '[remove_tp]' (reverts to base price)", usr)
				to_chat(usr, SPAN_GOOD("'[remove_tp]' removed -- now sells at the base price ([CARGO_EXPORT_BASE_PRICE] cr)."))
			else
				to_chat(usr, SPAN_WARNING("Failed to remove -- database error."))

		if(choice == "Wipe All Exports")
			if(!length(GLOB.cargo_export_prices))
				to_chat(usr, SPAN_NOTICE("No priced exports to wipe."))
				continue
			var/wipe_count = length(GLOB.cargo_export_prices)
			var/confirm = tgui_alert(usr, "Wipe all [wipe_count] priced export type(s)? Everything will revert to the base price ([CARGO_EXPORT_BASE_PRICE] cr). Cannot be undone.", "Wipe All Exports", list("Wipe", "Cancel"))
			if(confirm != "Wipe")
				continue
			if(!SSpersistence.databaseCheckConnection("wipe_all_cargo_exports"))
				to_chat(usr, SPAN_WARNING("Failed to wipe -- database connection error."))
				continue
			var/datum/db_query/wipeq = SSdbcore.NewQuery(
				"DELETE FROM ss13_cargo_exports WHERE map_path = :mp",
				list("mp" = "[SSatlas.current_map.path]")
			)
			wipeq.Execute()
			if(!SSpersistence.databaseCheckQueryResult(wipeq, "wipe_all_cargo_exports"))
				qdel(wipeq)
				to_chat(usr, SPAN_WARNING("Failed to wipe -- database error."))
				continue
			qdel(wipeq)
			GLOB.cargo_export_prices = list()
			log_and_message_admins("wiped all [wipe_count] cargo export price(s) -- everything now sells at the base price ([CARGO_EXPORT_BASE_PRICE] cr)", usr)
			to_chat(usr, SPAN_GOOD("Wiped [wipe_count] export price(s) -- everything now sells at the base price ([CARGO_EXPORT_BASE_PRICE] cr)."))

		if(choice == "View List")
			if(!length(GLOB.cargo_export_prices))
				to_chat(usr, SPAN_NOTICE("No priced exports -- everything sells at the base price ([CARGO_EXPORT_BASE_PRICE] cr)."))
				continue
			var/msg = "<b>Cargo export prices:</b>\n"
			for(var/tp in GLOB.cargo_export_prices)
				var/list/entry = GLOB.cargo_export_prices[tp]
				msg += "  [tp]: [entry["price"]] cr[entry["label"] ? " (label: [entry["label"]])" : ""][entry["illegal"] ? " (ILLEGAL)" : ""]\n"
			to_chat(usr, SPAN_NOTICE(msg))
