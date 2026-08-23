/*
 * Persistence - Cargo Imports
 * Admin-managed overrides for the purchase ("import") price of cargo items,
 * letting the economy be tuned live instead of by editing the ~654
 * /singleton/cargo_item definitions under code/modules/cargo/items/ and
 * recompiling.
 *
 * Sparse by design: a row exists only for an item an admin actually repriced.
 * No row means "use the compile-time default", so an empty table is a complete
 * no-op and deleting a row IS the restore-to-code-default operation. That is
 * why there is no seeding step or seeded-marker table here, unlike
 * ss13_cargo_exports -- nothing is being replaced, only overridden.
 *
 * CODE WINS ON CHANGE. An override is a decision made against a specific code
 * definition, so if that definition moves the override is auto-pruned at boot
 * and the item goes back to its compile-time price. Two triggers:
 *   - the item was renamed in code (item_name column vs the live name), or
 *   - the item no longer exists at all (type path resolves to nothing).
 * Both are logged, never silent. The deliberate consequence is that a rename
 * costs the override -- the type path still identifies the row, but a changed
 * name is taken as "this entry is not the thing the admin priced any more".
 *
 * DB-backed (ss13_cargo_imports, V139 + V140), scoped per map_path, with an
 * in-memory cache so nothing hits the database off the ordering path.
 */

/// type path string -> list("price" = credits, "name" = item name recorded when
/// the override was set). Loaded at boot, updated live by the Modify Cargo
/// Imports admin verb. Absence of a key means the item is running at its
/// compile-time initial(price).
GLOBAL_LIST_EMPTY(cargo_import_prices)

/**
 * Pushes a price onto a live cargo item singleton.
 *
 * adjusted_price -- not price -- is what the order console quotes
 * (SScargo.get_items_for_category, controllers/subsystems/cargo.dm) and what an
 * order actually charges (/datum/cargo_order_item/calculate_price, datums/cargo.dm).
 * It is derived from price by get_adjusted_price(), so assigning price and
 * recomputing here is what makes an override take effect everywhere at once,
 * with no cargo call site needing to know overrides exist. It also keeps the
 * supplier/category/sector modifiers applying on top of the admin's number
 * exactly as they do for an un-overridden item.
 */
/proc/_apply_cargo_import_price(var/singleton/cargo_item/I, var/price)
	if(!istype(I) || isnull(price))
		return FALSE
	I.price = price
	I.get_adjusted_price()
	return TRUE

/// Resolves a type path string to its live cargo item singleton.
/// SScargo.cargo_items is keyed by display name, not type, hence the scan --
/// only used by the admin verb and by single-item edits, never per-order.
/proc/get_cargo_item_by_type(type_path)
	var/tp = "[type_path]"
	for(var/item_name in SScargo.cargo_items)
		var/singleton/cargo_item/I = SScargo.cargo_items[item_name]
		if(istype(I) && "[I.type]" == tp)
			return I
	return null

/**
 * Loads the import price overrides and applies them to the live catalog.
 * Called from SSpersistence.Initialize().
 *
 * Safe to apply here: SScargo is init_order SS_INIT_CARGO (13) and SSpersistence
 * is INIT_ORDER_PERSISTENCE (-10), and higher initialises first -- so
 * SScargo.cargo_items is fully built by the time this runs.
 */
/datum/controller/subsystem/persistence/proc/cargoImportsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.cargo_import_prices = list()

	if(!databaseCheckConnection("cargoImportsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT type_path, price, item_name, restricted_to_faction FROM ss13_cargo_imports WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "cargoImportsInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		// price is nullable now (V147) -- a row may exist purely to set a
		// faction restriction. isnull() rather than text2num()'s own 0/null
		// ambiguity, because 0 is a legitimate price.
		var/raw_price = query.item[2]
		GLOB.cargo_import_prices[query.item[1]] = list(
			"price"   = isnull(raw_price) ? null : text2num(raw_price),
			"name"    = query.item[3],
			"faction" = query.item[4]
		)
	qdel(query)

	if(!length(GLOB.cargo_import_prices))
		log_subsystem_persistence_info("Cargo imports: no overrides configured -- every item at its code defaults.")
		return

	var/total = length(GLOB.cargo_import_prices)

	// One pass over the catalog rather than a lookup per row -- get_cargo_item_by_type()
	// is a linear scan, so doing it per override would be quadratic at boot.
	var/applied = 0
	var/factions_applied = 0
	var/list/matched = list()
	var/list/to_prune = list()
	for(var/item_name in SScargo.cargo_items)
		CHECK_TICK
		var/singleton/cargo_item/I = SScargo.cargo_items[item_name]
		if(!istype(I))
			continue
		var/tp = "[I.type]"
		var/list/entry = GLOB.cargo_import_prices[tp]
		if(!entry)
			continue
		matched[tp] = TRUE
		// Renamed in code since the override was set: the definition moved, so
		// the override no longer describes a decision anyone actually made about
		// this item. Hand it back to the code rather than applying a stale price.
		// Covers BOTH columns -- the check keys on the row, not the field.
		if(entry["name"] != I.name)
			to_prune[tp] = "renamed in code ('[entry["name"]]' -> '[I.name]')"
			continue
		// Null price = faction-only row, leave the compile-time price alone.
		if(!isnull(entry["price"]) && _apply_cargo_import_price(I, entry["price"]))
			applied++
		// Applied AFTER the compile-time value, so the override wins at runtime
		// while the code default is what a pruned/absent row falls back to --
		// identical to how the price column already behaves.
		if(entry["faction"])
			I.restricted_to_faction = entry["faction"]
			factions_applied++

	// Overrides whose item no longer exists in code at all.
	for(var/tp in GLOB.cargo_import_prices)
		if(!matched[tp])
			to_prune[tp] = "no longer exists in code"

	// Nothing pruned here was ever applied this boot, so the affected items are
	// already sitting at their compile-time price -- only the row has to go.
	var/pruned = 0
	for(var/tp in to_prune)
		CHECK_TICK
		if(_prune_cargo_import_override(tp))
			pruned++
			log_subsystem_persistence_info("Cargo imports: pruned override for '[tp]' -- [to_prune[tp]]. Item is back on its code default.")
		else
			log_subsystem_persistence_error("Cargo imports: failed to prune override for '[tp]' ([to_prune[tp]]) -- database error. Row left in place and NOT applied; will retry next boot.")

	log_subsystem_persistence_info("Cargo imports: applied [applied] price and [factions_applied] faction override(s) from [total] row(s)[pruned ? ", pruned [pruned] stale" : ""].")

/// Drops an override row and its cache entry. Does not touch any singleton --
/// callers decide whether the live item needs restoring (the boot-time pruner
/// never applied it in the first place, so it does not).
/proc/_prune_cargo_import_override(type_path)
	if(!SSpersistence.databaseCheckConnection("_prune_cargo_import_override"))
		return FALSE
	var/tp = "[type_path]"
	var/datum/db_query/delq = SSdbcore.NewQuery(
		"DELETE FROM ss13_cargo_imports WHERE type_path = :tp AND map_path = :mp",
		list("tp" = tp, "mp" = "[SSatlas.current_map.path]")
	)
	delq.Execute()
	var/delete_ok = SSpersistence.databaseCheckQueryResult(delq, "_prune_cargo_import_override")
	qdel(delq)
	if(!delete_ok)
		return FALSE
	GLOB.cargo_import_prices -= tp
	return TRUE

/**
 * Sets the import price override for a cargo item type, or -- when price is
 * null -- clears the override and restores the item's compile-time default.
 * Persists, updates the live cache, and applies to the singleton immediately.
 *
 * The item's current name is recorded alongside the price so a later code
 * rename can be detected and auto-pruned at boot.
 *
 * The database write happens first and the live singleton is only touched once
 * it succeeded, so the running world never disagrees with what is stored.
 */
/proc/set_cargo_import_price(type_path, price)
	if(!SSpersistence.databaseCheckConnection("set_cargo_import_price"))
		return FALSE
	var/tp = "[type_path]"
	var/singleton/cargo_item/I = get_cargo_item_by_type(tp)

	var/list/existing = GLOB.cargo_import_prices[tp]
	var/existing_faction = existing ? existing["faction"] : null

	if(isnull(price))
		// Only drop the ROW when nothing else is riding on it. A row can now
		// also carry a faction restriction (V147), and "restore the code price"
		// must not silently take that with it.
		if(existing_faction)
			if(!_write_cargo_import_row(tp, null, existing_faction))
				return FALSE
		else if(!_prune_cargo_import_override(tp))
			return FALSE
		if(I)
			_apply_cargo_import_price(I, initial(I.price))
		return TRUE

	// Setting a price requires the live item -- its name is half the record.
	if(!I)
		return FALSE

	if(!_write_cargo_import_row(tp, price, existing_faction, I.name))
		return FALSE
	_apply_cargo_import_price(I, price)
	return TRUE

/**
 * Writes (or updates) one override row and its cache entry, carrying BOTH
 * columns every time.
 *
 * Shared by the price and faction setters so neither can clobber the other's
 * column -- the failure mode being that repricing an item silently drops its
 * faction restriction, or vice versa, since each setter only knows about its
 * own field. item_name defaults to whatever the row already recorded, so a
 * faction-only edit does not have to re-derive it.
 */
/proc/_write_cargo_import_row(type_path, price, faction_uid, item_name)
	if(!SSpersistence.databaseCheckConnection("_write_cargo_import_row"))
		return FALSE
	var/tp = "[type_path]"
	if(isnull(item_name))
		var/list/existing = GLOB.cargo_import_prices[tp]
		item_name = existing ? existing["name"] : null
		if(isnull(item_name))
			var/singleton/cargo_item/I = get_cargo_item_by_type(tp)
			if(!I)
				return FALSE
			item_name = I.name

	var/datum/db_query/q = SSdbcore.NewQuery(
		{"INSERT INTO ss13_cargo_imports (map_path, type_path, price, item_name, restricted_to_faction)
		VALUES (:mp, :tp, :price, :nm, :faction)
		ON DUPLICATE KEY UPDATE price = VALUES(price), item_name = VALUES(item_name), restricted_to_faction = VALUES(restricted_to_faction)"},
		list("mp" = "[SSatlas.current_map.path]", "tp" = tp, "price" = price, "nm" = item_name, "faction" = faction_uid)
	)
	q.Execute()
	var/update_ok = SSpersistence.databaseCheckQueryResult(q, "_write_cargo_import_row")
	qdel(q)
	if(!update_ok)
		return FALSE
	GLOB.cargo_import_prices[tp] = list("price" = price, "name" = item_name, "faction" = faction_uid)
	return TRUE

/**
 * Sets the faction restriction override for a cargo item type, or -- when
 * faction_uid is null -- clears it and restores the item's compile-time
 * restricted_to_faction.
 *
 * Mirrors set_cargo_import_price() exactly, including dropping the row entirely
 * once neither column is overriding anything, so the table stays sparse and
 * never accumulates no-op rows.
 */
/proc/set_cargo_item_faction(type_path, faction_uid)
	if(!SSpersistence.databaseCheckConnection("set_cargo_item_faction"))
		return FALSE
	var/tp = "[type_path]"
	var/singleton/cargo_item/I = get_cargo_item_by_type(tp)
	if(!I)
		return FALSE

	var/list/existing = GLOB.cargo_import_prices[tp]
	var/existing_price = existing ? existing["price"] : null

	if(isnull(faction_uid) || faction_uid == "")
		if(isnull(existing_price))
			// Nothing left to override -- drop the row rather than keep an
			// all-NULL one.
			if(existing && !_prune_cargo_import_override(tp))
				return FALSE
		else if(!_write_cargo_import_row(tp, existing_price, null, I.name))
			return FALSE
		I.restricted_to_faction = initial(I.restricted_to_faction)
		return TRUE

	faction_uid = normalize_faction_uid(faction_uid)
	if(!_write_cargo_import_row(tp, existing_price, faction_uid, I.name))
		return FALSE
	I.restricted_to_faction = faction_uid
	return TRUE

/// Clears every import price override for this map and puts the whole catalog
/// back to its compile-time prices.
/proc/reset_all_cargo_import_prices()
	if(!SSpersistence.databaseCheckConnection("reset_all_cargo_import_prices"))
		return FALSE
	var/datum/db_query/wipeq = SSdbcore.NewQuery(
		"DELETE FROM ss13_cargo_imports WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	wipeq.Execute()
	var/wipe_ok = SSpersistence.databaseCheckQueryResult(wipeq, "reset_all_cargo_import_prices")
	qdel(wipeq)
	if(!wipe_ok)
		return FALSE
	GLOB.cargo_import_prices = list()
	for(var/item_name in SScargo.cargo_items)
		CHECK_TICK
		var/singleton/cargo_item/I = SScargo.cargo_items[item_name]
		if(!istype(I) || I.price == initial(I.price))
			continue
		_apply_cargo_import_price(I, initial(I.price))
	return TRUE

/// Menu label for one item: live price, plus its code default when overridden.
/// Parentheses rather than square brackets on purpose -- square brackets are
/// string interpolation in DM.
/proc/_cargo_import_label(var/singleton/cargo_item/I)
	if("[I.type]" in GLOB.cargo_import_prices)
		return "[I.name] -- [I.price] cr (OVERRIDDEN, code default [initial(I.price)] cr)"
	return "[I.name] -- [I.price] cr (default)"

/// Label for the Factions menu -- shows the live restriction and, when an
/// override is in play, what code would have said instead.
/proc/_cargo_faction_label(var/singleton/cargo_item/I)
	var/live = I.restricted_to_faction
	var/coded = initial(I.restricted_to_faction)
	if(!live)
		return "[I.name] -- unrestricted"
	var/live_name = islist(live) ? english_list(live) : get_faction_name(live)
	if(live == coded)
		return "[I.name] -- [live_name] (code)"
	return "[I.name] -- [live_name] (OVERRIDE, code says [coded ? (islist(coded) ? english_list(coded) : get_faction_name(coded)) : "unrestricted"])"

/**
 * The "Factions" section of Modify Cargo Imports: which cargo items are
 * exclusive to which faction, editable live.
 *
 * Sets the same restricted_to_faction that a compile-time declaration sets
 * (cargo_items.dm), stored on the same override row as the price
 * (ss13_cargo_imports) and subject to the same code-wins-on-change pruning, so
 * there is exactly one mechanism rather than two that can disagree.
 */
/proc/_modify_cargo_faction_restrictions(mob/user)
	while(user && user.client)
		// Rebuilt each pass so edits show immediately.
		var/list/restricted = list()
		for(var/item_name in SScargo.cargo_items)
			var/singleton/cargo_item/I = SScargo.cargo_items[item_name]
			if(istype(I) && I.restricted_to_faction)
				restricted += I

		var/choice = tgui_input_list(user, "Faction-restricted cargo ([length(restricted)] item\s restricted):", "Cargo Factions", list("Restrict an Item to a Faction", "Clear an Item's Restriction", "View by Faction", "Back"))
		if(!choice || choice == "Back")
			return

		if(choice == "View by Faction")
			if(!length(restricted))
				to_chat(user, SPAN_NOTICE("No cargo items are faction-restricted."))
				continue
			// Grouped by uid rather than listed per item -- the point of this
			// view is seeing a faction's whole catalogue at once.
			var/list/by_faction = list()
			for(var/singleton/cargo_item/I as anything in restricted)
				var/key = islist(I.restricted_to_faction) ? english_list(I.restricted_to_faction) : "[I.restricted_to_faction]"
				LAZYADD(by_faction[key], _cargo_faction_label(I))
			for(var/key in by_faction)
				to_chat(user, SPAN_NOTICE("<b>[get_faction_name(key) || key]</b> ([key]):"))
				for(var/line in by_faction[key])
					to_chat(user, SPAN_NOTICE("&nbsp;&nbsp;[line]"))
			continue

		if(choice == "Clear an Item's Restriction")
			if(!length(restricted))
				to_chat(user, SPAN_NOTICE("No cargo items are faction-restricted."))
				continue
			var/list/clear_choices = list()
			for(var/singleton/cargo_item/I as anything in restricted)
				clear_choices[_cargo_faction_label(I)] = I
			var/clear_pick = tgui_input_list(user, "Clear the restriction on which item?", "Cargo Factions", clear_choices)
			if(!clear_pick)
				continue
			var/singleton/cargo_item/target = clear_choices[clear_pick]
			if(!set_cargo_item_faction("[target.type]", null))
				to_chat(user, SPAN_WARNING("Database error -- restriction not cleared."))
				continue
			to_chat(user, SPAN_GOOD("'[target.name]' is no longer faction-restricted[initial(target.restricted_to_faction) ? " by override -- it is back on its code default" : ""]."))
			log_and_message_admins("cleared the cargo faction restriction on '[target.name]' ([target.type]).", user)
			continue

		// Restrict an Item to a Faction
		var/list/cat_choices = list()
		for(var/cat_name in SScargo.cargo_categories)
			var/singleton/cargo_category/CC = SScargo.cargo_categories[cat_name]
			if(!istype(CC) || !length(CC.items))
				continue
			cat_choices["[CC.display_name] ([length(CC.items)] items)"] = CC
		if(!length(cat_choices))
			to_chat(user, SPAN_WARNING("No cargo categories are loaded."))
			continue
		var/cat_pick = tgui_input_list(user, "Which category?", "Cargo Factions", cat_choices)
		if(!cat_pick)
			continue
		var/singleton/cargo_category/chosen_cat = cat_choices[cat_pick]

		var/list/item_choices = list()
		for(var/singleton/cargo_item/I as anything in chosen_cat.items)
			if(istype(I))
				item_choices[_cargo_faction_label(I)] = I
		if(!length(item_choices))
			to_chat(user, SPAN_WARNING("'[chosen_cat.display_name]' has no items."))
			continue
		var/item_pick = tgui_input_list(user, "Restrict which item in [chosen_cat.display_name]?", "Cargo Factions", item_choices)
		if(!item_pick)
			continue
		var/singleton/cargo_item/chosen = item_choices[item_pick]

		// Live factions, plus a free-text option so an item can be pre-assigned
		// to a uid that has not been founded yet (the Hub gear case: the code
		// declares "hub" before any player faction exists).
		var/list/faction_choices = list()
		for(var/uid in GLOB.persistence_faction_cache)
			faction_choices["[get_faction_name(uid)] ([uid])"] = uid
		faction_choices["-- Enter a faction UID manually --"] = "__manual__"
		var/faction_pick = tgui_input_list(user, "Restrict '[chosen.name]' to which faction?", "Cargo Factions", faction_choices)
		if(!faction_pick)
			continue
		var/chosen_uid = faction_choices[faction_pick]
		if(chosen_uid == "__manual__")
			chosen_uid = tgui_input_text(user, "Faction UID to restrict '[chosen.name]' to:", "Cargo Factions", "", max_length = 64)
			if(!chosen_uid)
				continue

		if(!set_cargo_item_faction("[chosen.type]", chosen_uid))
			to_chat(user, SPAN_WARNING("Database error -- restriction not saved."))
			continue
		to_chat(user, SPAN_GOOD("'[chosen.name]' is now orderable only from [get_faction_name(chosen_uid) || chosen_uid] consoles."))
		log_and_message_admins("restricted cargo item '[chosen.name]' ([chosen.type]) to faction '[chosen_uid]'.", user)

// ============================================================
// CARGO IMPORTS ADMIN VERB
// ============================================================

/datum/admins/proc/modify_cargo_imports()
	set name = "Modify Cargo Imports"
	set category = "Persistence.Cargo & Economy"
	set desc = "Override cargo import prices, or restore them to code defaults."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- cargo import price overrides cannot be saved."))
		return

	while(usr && usr.client)
		var/choice = tgui_input_list(usr, "Cargo imports ([length(GLOB.cargo_import_prices)] override(s) active; every other item uses its code default):", "Modify Cargo Imports", list("Set Item Price", "Restore Item to Code Default", "Restore All to Code Defaults", "View Overrides", "Factions", "Done"))
		if(!choice || choice == "Done")
			return

		if(choice == "Factions")
			_modify_cargo_faction_restrictions(usr)
			continue

		if(choice == "Set Item Price")
			var/list/cat_choices = list()
			for(var/cat_name in SScargo.cargo_categories)
				var/singleton/cargo_category/CC = SScargo.cargo_categories[cat_name]
				if(!istype(CC) || !length(CC.items))
					continue
				cat_choices["[CC.display_name] ([length(CC.items)] items)"] = CC
			if(!length(cat_choices))
				to_chat(usr, SPAN_WARNING("No cargo categories are loaded."))
				continue
			var/cat_pick = tgui_input_list(usr, "Which category?", "Modify Cargo Imports", cat_choices)
			if(!cat_pick)
				continue
			var/singleton/cargo_category/chosen_cat = cat_choices[cat_pick]

			var/list/item_choices = list()
			for(var/singleton/cargo_item/I as anything in chosen_cat.items)
				if(istype(I))
					item_choices[_cargo_import_label(I)] = I
			if(!length(item_choices))
				to_chat(usr, SPAN_WARNING("'[chosen_cat.display_name]' has no items."))
				continue
			var/item_pick = tgui_input_list(usr, "Which item in [chosen_cat.display_name]?", "Modify Cargo Imports", item_choices)
			if(!item_pick)
				continue
			var/singleton/cargo_item/chosen = item_choices[item_pick]

			var/code_default = initial(chosen.price)
			var/new_price = tgui_input_number(usr, "Import price for '[chosen.name]' in credits (code default: [code_default] cr):", "Modify Cargo Imports", chosen.price, 1000000, 0)
			if(isnull(new_price))
				continue

			// Typing the code value back in is the same as clearing the override --
			// don't leave a redundant row that would mask a later code change.
			if(new_price == code_default)
				if(set_cargo_import_price(chosen.type, null))
					log_and_message_admins("set cargo import price of '[chosen.name]' ([chosen.type]) back to its code default ([code_default] cr), clearing the override", usr)
					to_chat(usr, SPAN_GOOD("'[chosen.name]' is at its code default ([code_default] cr); override cleared."))
				else
					to_chat(usr, SPAN_WARNING("Failed to save -- database error."))
				continue

			if(set_cargo_import_price(chosen.type, new_price))
				log_and_message_admins("set cargo import price of '[chosen.name]' ([chosen.type]) to [new_price] cr (code default [code_default] cr)", usr)
				to_chat(usr, SPAN_GOOD("'[chosen.name]' now imports at [new_price] cr (code default [code_default] cr)."))
			else
				to_chat(usr, SPAN_WARNING("Failed to save -- database error."))

		if(choice == "Restore Item to Code Default")
			if(!length(GLOB.cargo_import_prices))
				to_chat(usr, SPAN_NOTICE("No overrides -- every item is already at its code default."))
				continue
			var/list/restore_choices = list()
			for(var/tp in GLOB.cargo_import_prices)
				var/list/entry = GLOB.cargo_import_prices[tp]
				var/singleton/cargo_item/I = get_cargo_item_by_type(tp)
				if(I)
					restore_choices["[I.name] -- [entry["price"]] cr (code default [initial(I.price)] cr)"] = tp
				else
					restore_choices["[entry["name"] || tp] -- [entry["price"]] cr (STALE: no such item)"] = tp
			var/restore_pick = tgui_input_list(usr, "Restore which item to its code default?", "Modify Cargo Imports", restore_choices)
			if(!restore_pick)
				continue
			var/restore_tp = restore_choices[restore_pick]
			if(set_cargo_import_price(restore_tp, null))
				log_and_message_admins("restored cargo import price of '[restore_tp]' to its code default", usr)
				to_chat(usr, SPAN_GOOD("'[restore_tp]' restored to its code default."))
			else
				to_chat(usr, SPAN_WARNING("Failed to restore -- database error."))

		if(choice == "Restore All to Code Defaults")
			if(!length(GLOB.cargo_import_prices))
				to_chat(usr, SPAN_NOTICE("No overrides to clear."))
				continue
			var/wipe_count = length(GLOB.cargo_import_prices)
			var/confirm = tgui_alert(usr, "Clear all [wipe_count] cargo import price override(s)? Every item reverts to its code default. Cannot be undone.", "Restore All to Code Defaults", list("Restore All", "Cancel"))
			if(confirm != "Restore All")
				continue
			if(reset_all_cargo_import_prices())
				log_and_message_admins("cleared all [wipe_count] cargo import price override(s) -- every item back to its code default", usr)
				to_chat(usr, SPAN_GOOD("Cleared [wipe_count] override(s); every item is back to its code default."))
			else
				to_chat(usr, SPAN_WARNING("Failed to clear -- database error."))

		if(choice == "View Overrides")
			if(!length(GLOB.cargo_import_prices))
				to_chat(usr, SPAN_NOTICE("No cargo import price overrides -- every item is at its code default."))
				continue
			var/msg = "<b>Cargo import price overrides:</b>\n"
			for(var/tp in GLOB.cargo_import_prices)
				var/list/entry = GLOB.cargo_import_prices[tp]
				var/singleton/cargo_item/I = get_cargo_item_by_type(tp)
				if(I)
					msg += "  [I.name] ([tp]): [entry["price"]] cr -- code default [initial(I.price)] cr\n"
				else
					msg += "  [entry["name"] || "?"] ([tp]): [entry["price"]] cr -- STALE, no such /singleton/cargo_item\n"
			to_chat(usr, SPAN_NOTICE(msg))
