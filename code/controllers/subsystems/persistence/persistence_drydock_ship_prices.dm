/*
 * Persistence - Drydock Ship Prices
 * Admin-managed overrides for drydock ship purchase prices, letting the
 * economy be tuned live instead of by editing each hull's
 * /datum/map_template/drydock_ship subtype under maps/drydock_ships/ and
 * recompiling.
 *
 * Sparse by design: a row exists only for a ship an admin actually repriced.
 * No row means "use the compile-time default", so an empty table is a
 * complete no-op and deleting a row IS the restore-to-code-default operation.
 *
 * CODE WINS ON CHANGE. An override is a decision made against a specific
 * ship definition, so if that definition moves the override is auto-pruned
 * at boot and the ship goes back to its compile-time price. Two triggers:
 *   - the ship was renamed in code (ship_name column vs the live name), or
 *   - the ship no longer exists at all (id no longer resolves).
 * Both are logged, never silent.
 *
 * DB-backed (ss13_drydock_ship_prices, V141), scoped per map_path, with an
 * in-memory cache so nothing hits the database off the purchase path.
 */

/// ship id -> list("price" = credits, "name" = ship name recorded when the
/// override was set). Loaded at boot, updated live by the Modify Ship Prices
/// admin verb. Absence of a key means the ship is running at its
/// compile-time initial(price).
GLOBAL_LIST_EMPTY(drydock_ship_price_overrides)

/**
 * Pushes a price onto a live drydock ship template singleton.
 * drydockBuy() (persistence_shuttles.dm) reads template.price directly at
 * purchase time, so assigning here takes effect everywhere at once.
 */
/proc/_apply_drydock_ship_price(datum/map_template/drydock_ship/T, price)
	if(!istype(T) || isnull(price))
		return FALSE
	T.price = price
	return TRUE

/**
 * Loads the ship price overrides and applies them to the live templates.
 * Called from SSpersistence.Initialize().
 *
 * Safe to apply here: SSmapping is init_order INIT_ORDER_AWAY_MAPS (-2) and
 * SSpersistence is INIT_ORDER_PERSISTENCE (-10), and higher initialises
 * first -- so SSmapping.drydock_ship_templates is fully built by the time
 * this runs.
 */
/datum/controller/subsystem/persistence/proc/drydockShipPricesInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.drydock_ship_price_overrides = list()

	if(!databaseCheckConnection("drydockShipPricesInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ship_id, price, ship_name FROM ss13_drydock_ship_prices WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "drydockShipPricesInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.drydock_ship_price_overrides[query.item[1]] = list("price" = text2num(query.item[2]), "name" = query.item[3])
	qdel(query)

	if(!length(GLOB.drydock_ship_price_overrides))
		log_subsystem_persistence_info("Drydock ship prices: no price overrides configured -- every ship at its code default.")
		return

	var/total = length(GLOB.drydock_ship_price_overrides)
	var/applied = 0
	var/list/to_prune = list()
	for(var/ship_id in GLOB.drydock_ship_price_overrides)
		CHECK_TICK
		var/list/entry = GLOB.drydock_ship_price_overrides[ship_id]
		var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[ship_id]
		if(!T)
			to_prune[ship_id] = "no longer exists in code"
			continue
		// Renamed in code since the override was set: the definition moved, so
		// the override no longer describes a decision anyone actually made
		// about this ship. Hand it back to the code rather than applying a
		// stale price.
		if(entry["name"] != T.name)
			to_prune[ship_id] = "renamed in code ('[entry["name"]]' -> '[T.name]')"
			continue
		if(_apply_drydock_ship_price(T, entry["price"]))
			applied++

	var/pruned = 0
	for(var/ship_id in to_prune)
		CHECK_TICK
		if(_prune_drydock_ship_price_override(ship_id))
			pruned++
			log_subsystem_persistence_info("Drydock ship prices: pruned override for '[ship_id]' -- [to_prune[ship_id]]. Ship is back on its code default.")
		else
			log_subsystem_persistence_error("Drydock ship prices: failed to prune override for '[ship_id]' ([to_prune[ship_id]]) -- database error. Row left in place and NOT applied; will retry next boot.")

	log_subsystem_persistence_info("Drydock ship prices: applied [applied] of [total] price override(s)[pruned ? ", pruned [pruned] stale" : ""].")

/// Drops an override row and its cache entry. Does not touch any template --
/// callers decide whether the live template needs restoring (the boot-time
/// pruner never applied it in the first place, so it does not).
/proc/_prune_drydock_ship_price_override(ship_id)
	if(!SSpersistence.databaseCheckConnection("_prune_drydock_ship_price_override"))
		return FALSE
	var/datum/db_query/delq = SSdbcore.NewQuery(
		"DELETE FROM ss13_drydock_ship_prices WHERE ship_id = :sid AND map_path = :mp",
		list("sid" = ship_id, "mp" = "[SSatlas.current_map.path]")
	)
	delq.Execute()
	var/delete_ok = SSpersistence.databaseCheckQueryResult(delq, "_prune_drydock_ship_price_override")
	qdel(delq)
	if(!delete_ok)
		return FALSE
	GLOB.drydock_ship_price_overrides -= ship_id
	return TRUE

/**
 * Sets the price override for a drydock ship, or -- when price is null --
 * clears the override and restores the ship's compile-time default.
 * Persists, updates the live cache, and applies to the template immediately.
 *
 * The ship's current name is recorded alongside the price so a later code
 * rename can be detected and auto-pruned at boot.
 *
 * The database write happens first and the live template is only touched
 * once it succeeded, so the running world never disagrees with what is
 * stored.
 */
/proc/set_drydock_ship_price(ship_id, price)
	if(!SSpersistence.databaseCheckConnection("set_drydock_ship_price"))
		return FALSE
	var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[ship_id]

	if(isnull(price))
		if(!_prune_drydock_ship_price_override(ship_id))
			return FALSE
		if(T)
			_apply_drydock_ship_price(T, initial(T.price))
		return TRUE

	// Setting a price requires the live template -- its name is half the record.
	if(!T)
		return FALSE

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_drydock_ship_prices (map_path, ship_id, price, ship_name)
		VALUES (:mp, :sid, :price, :nm)
		ON DUPLICATE KEY UPDATE price = VALUES(price), ship_name = VALUES(ship_name)"},
		list("mp" = "[SSatlas.current_map.path]", "sid" = ship_id, "price" = price, "nm" = T.name)
	)
	q.Execute()
	var/update_ok = SSpersistence.databaseCheckQueryResult(q, "set_drydock_ship_price")
	qdel(q)
	if(!update_ok)
		return FALSE
	GLOB.drydock_ship_price_overrides[ship_id] = list("price" = price, "name" = T.name)
	_apply_drydock_ship_price(T, price)
	return TRUE

/// Clears every ship price override for this map and puts the whole catalog
/// back to its compile-time prices.
/proc/reset_all_drydock_ship_prices()
	if(!SSpersistence.databaseCheckConnection("reset_all_drydock_ship_prices"))
		return FALSE
	var/datum/db_query/wipeq = SSdbcore.NewQuery(
		"DELETE FROM ss13_drydock_ship_prices WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	wipeq.Execute()
	var/wipe_ok = SSpersistence.databaseCheckQueryResult(wipeq, "reset_all_drydock_ship_prices")
	qdel(wipeq)
	if(!wipe_ok)
		return FALSE
	GLOB.drydock_ship_price_overrides = list()
	for(var/ship_id in SSmapping.drydock_ship_templates)
		CHECK_TICK
		var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[ship_id]
		if(!istype(T) || T.price == initial(T.price))
			continue
		_apply_drydock_ship_price(T, initial(T.price))
	return TRUE

/// Menu label for one ship: live price, plus its code default when overridden.
/// Parentheses rather than square brackets on purpose -- square brackets are
/// string interpolation in DM.
/proc/_drydock_ship_price_label(datum/map_template/drydock_ship/T)
	if(T.id in GLOB.drydock_ship_price_overrides)
		return "[T.name] -- [T.price] cr (OVERRIDDEN, code default [initial(T.price)] cr)"
	return "[T.name] -- [T.price] cr (default)"

// ============================================================
// MODIFY SHIP PRICES ADMIN VERB
// ============================================================

/datum/admins/proc/modify_ship_prices()
	set name = "Modify Ship Prices"
	set category = "Persistence"
	set desc = "Override drydock ship purchase prices, or restore them to code defaults."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- ship price overrides cannot be saved."))
		return

	while(usr && usr.client)
		var/choice = tgui_input_list(usr, "Drydock ship prices ([length(GLOB.drydock_ship_price_overrides)] override(s) active; every other ship uses its code default):", "Modify Ship Prices", list("Set Ship Price", "Restore Ship to Code Default", "Restore All to Code Defaults", "View Overrides", "Done"))
		if(!choice || choice == "Done")
			return

		if(choice == "Set Ship Price")
			var/list/ship_choices = list()
			for(var/ship_id in SSmapping.drydock_ship_templates)
				var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[ship_id]
				if(istype(T))
					ship_choices[_drydock_ship_price_label(T)] = T
			if(!length(ship_choices))
				to_chat(usr, SPAN_WARNING("No drydock ship templates are loaded."))
				continue
			var/ship_pick = tgui_input_list(usr, "Which ship?", "Modify Ship Prices", ship_choices)
			if(!ship_pick)
				continue
			var/datum/map_template/drydock_ship/chosen = ship_choices[ship_pick]

			var/code_default = initial(chosen.price)
			var/new_price = tgui_input_number(usr, "Purchase price for '[chosen.name]' in credits (code default: [code_default] cr):", "Modify Ship Prices", chosen.price, 1000000000, 0)
			if(isnull(new_price))
				continue

			// Typing the code value back in is the same as clearing the override --
			// don't leave a redundant row that would mask a later code change.
			if(new_price == code_default)
				if(set_drydock_ship_price(chosen.id, null))
					log_and_message_admins("set drydock ship price of '[chosen.name]' ([chosen.id]) back to its code default ([code_default] cr), clearing the override", usr)
					to_chat(usr, SPAN_GOOD("'[chosen.name]' is at its code default ([code_default] cr); override cleared."))
				else
					to_chat(usr, SPAN_WARNING("Failed to save -- database error."))
				continue

			if(set_drydock_ship_price(chosen.id, new_price))
				log_and_message_admins("set drydock ship price of '[chosen.name]' ([chosen.id]) to [new_price] cr (code default [code_default] cr)", usr)
				to_chat(usr, SPAN_GOOD("'[chosen.name]' now purchases at [new_price] cr (code default [code_default] cr)."))
			else
				to_chat(usr, SPAN_WARNING("Failed to save -- database error."))

		if(choice == "Restore Ship to Code Default")
			if(!length(GLOB.drydock_ship_price_overrides))
				to_chat(usr, SPAN_NOTICE("No overrides -- every ship is already at its code default."))
				continue
			var/list/restore_choices = list()
			for(var/ship_id in GLOB.drydock_ship_price_overrides)
				var/list/entry = GLOB.drydock_ship_price_overrides[ship_id]
				var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[ship_id]
				if(T)
					restore_choices["[T.name] -- [entry["price"]] cr (code default [initial(T.price)] cr)"] = ship_id
				else
					restore_choices["[entry["name"] || ship_id] -- [entry["price"]] cr (STALE: no such ship)"] = ship_id
			var/restore_pick = tgui_input_list(usr, "Restore which ship to its code default?", "Modify Ship Prices", restore_choices)
			if(!restore_pick)
				continue
			var/restore_id = restore_choices[restore_pick]
			if(set_drydock_ship_price(restore_id, null))
				log_and_message_admins("restored drydock ship price of '[restore_id]' to its code default", usr)
				to_chat(usr, SPAN_GOOD("'[restore_id]' restored to its code default."))
			else
				to_chat(usr, SPAN_WARNING("Failed to restore -- database error."))

		if(choice == "Restore All to Code Defaults")
			if(!length(GLOB.drydock_ship_price_overrides))
				to_chat(usr, SPAN_NOTICE("No overrides to clear."))
				continue
			var/wipe_count = length(GLOB.drydock_ship_price_overrides)
			var/confirm = tgui_alert(usr, "Clear all [wipe_count] ship price override(s)? Every ship reverts to its code default. Cannot be undone.", "Restore All to Code Defaults", list("Restore All", "Cancel"))
			if(confirm != "Restore All")
				continue
			if(reset_all_drydock_ship_prices())
				log_and_message_admins("cleared all [wipe_count] drydock ship price override(s) -- every ship back to its code default", usr)
				to_chat(usr, SPAN_GOOD("Cleared [wipe_count] override(s); every ship is back to its code default."))
			else
				to_chat(usr, SPAN_WARNING("Failed to clear -- database error."))

		if(choice == "View Overrides")
			if(!length(GLOB.drydock_ship_price_overrides))
				to_chat(usr, SPAN_NOTICE("No drydock ship price overrides -- every ship is at its code default."))
				continue
			var/msg = "<b>Drydock ship price overrides:</b>\n"
			for(var/ship_id in GLOB.drydock_ship_price_overrides)
				var/list/entry = GLOB.drydock_ship_price_overrides[ship_id]
				var/datum/map_template/drydock_ship/T = SSmapping.drydock_ship_templates[ship_id]
				if(T)
					msg += "  [T.name] ([ship_id]): [entry["price"]] cr -- code default [initial(T.price)] cr\n"
				else
					msg += "  [entry["name"] || "?"] ([ship_id]): [entry["price"]] cr -- STALE, no such ship template\n"
			to_chat(usr, SPAN_NOTICE(msg))
