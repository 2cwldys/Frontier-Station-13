/*
 * Persistence - Character Rename
 *
 * Renames one character everywhere it is recorded: every persistence table
 * keyed on the character's name, the in-memory caches those restores actually
 * read from, and any live state still holding the old name.
 *
 * Character name is used as an identity key throughout this codebase rather
 * than an id -- ss13_char_health, ss13_char_inventory, ss13_mob_position and
 * friends are all keyed "(ckey, char_name)" -- so renaming by hand in one
 * table silently detaches a character from their body, gear, ship and money.
 * This does the whole set in one pass.
 */

/// Every table carrying a character-name column, mapped to the column(s) that
/// hold it. Taken from the live schema rather than assumed; ss13_drydock_ships
/// is the one table with TWO such columns (current owner and permanent title),
/// both of which have to move together or a renamed owner loses their ship.
GLOBAL_LIST_INIT(persistence_char_name_columns, list(
	"ss13_char_health"             = list("char_name"),
	"ss13_char_identity"           = list("char_name"),
	"ss13_char_inventory"          = list("char_name"),
	"ss13_crew_records"            = list("char_name"),
	"ss13_mob_position"            = list("char_name"),
	"ss13_money_accounts"          = list("char_name"),
	"ss13_faction_members"         = list("char_name"),
	"ss13_faction_shareholders"    = list("char_name"),
	"ss13_ship_crew"               = list("char_name"),
	"ss13_stock_holdings"          = list("char_name"),
	"ss13_stock_trade_log"         = list("char_name"),
	"ss13_neural_lace_vault"       = list("char_name"),
	"ss13_personal_cargo_category" = list("char_name"),
	"ss13_antag_log"               = list("char_name"),
	"ss13_drydock_ships_backup"    = list("owner_char_name"),
	"ss13_drydock_ships"           = list("owner_char_name", "title_char_name")
))

/**
 * TRUE if this name is unavailable. Checked BEFORE any write.
 *
 * Two separate reasons a name can be refused:
 *  - ANY non-deleted character anywhere already uses it. Character names are
 *    the identity key half of "(ckey, char_name)" throughout persistence, and
 *    are what ID cards, crew records and faction rosters are matched by, so
 *    two live characters sharing one name is ambiguous everywhere at once --
 *    not just for the renamed player.
 *  - This same ckey already has rows under that name in an identity table,
 *    several of which key on (ckey, char_name): the UPDATE would collide
 *    partway through the pass and leave the character split across two names.
 */
/datum/controller/subsystem/persistence/proc/_characterNameTaken(ckey, char_name)
	if(!databaseCheckConnection("_characterNameTaken"))
		return TRUE // fail closed -- refuse the rename rather than risk a partial one

	// Global uniqueness against live characters, regardless of owner.
	var/datum/db_query/global_q = SSdbcore.NewQuery(
		"SELECT COUNT(*) FROM ss13_characters WHERE name = :name AND deleted_at IS NULL",
		list("name" = char_name)
	)
	global_q.Execute()
	var/global_found = 0
	if(databaseCheckQueryResult(global_q, "_characterNameTaken global") && global_q.NextRow())
		global_found = text2num(global_q.item[1]) || 0
	qdel(global_q)
	if(global_found)
		return TRUE

	for(var/table in list("ss13_char_identity", "ss13_char_health", "ss13_mob_position"))
		var/datum/db_query/q = SSdbcore.NewQuery(
			"SELECT COUNT(*) FROM [table] WHERE ckey = :ckey AND char_name = :name",
			list("ckey" = ckey, "name" = char_name)
		)
		q.Execute()
		var/found = 0
		if(databaseCheckQueryResult(q, "_characterNameTaken [table]") && q.NextRow())
			found = text2num(q.item[1]) || 0
		qdel(q)
		if(found)
			return TRUE
	return FALSE

/**
 * Renames a character across every persistence table, the in-memory caches,
 * and live round state. Returns an assoc list of table -> rows changed, or
 * null if the rename was refused.
 */
/datum/controller/subsystem/persistence/proc/renameCharacter(ckey, old_name, new_name, mob/user)
	ckey = ckey(ckey)
	if(!ckey || !old_name || !new_name || old_name == new_name)
		return null
	if(!databaseCheckConnection("renameCharacter"))
		return null

	var/list/changed = list()

	// ss13_characters is the chargen row -- renamed separately because its
	// column is `name`, not `char_name`, and it's what the character select
	// menu lists.
	var/datum/db_query/chargen = SSdbcore.NewQuery(
		"UPDATE ss13_characters SET name = :new_name WHERE ckey = :ckey AND name = :old_name",
		list("new_name" = new_name, "ckey" = ckey, "old_name" = old_name)
	)
	chargen.Execute()
	if(databaseCheckQueryResult(chargen, "renameCharacter ss13_characters"))
		changed["ss13_characters"] = chargen.affected
	qdel(chargen)

	for(var/table in GLOB.persistence_char_name_columns)
		var/list/columns = GLOB.persistence_char_name_columns[table]
		var/table_rows = 0
		for(var/column in columns)
			// Table and column names are from the compile-time list above,
			// never from user input -- only the values are bound.
			var/datum/db_query/q = SSdbcore.NewQuery(
				"UPDATE [table] SET [column] = :new_name WHERE ckey = :ckey AND [column] = :old_name",
				list("new_name" = new_name, "ckey" = ckey, "old_name" = old_name)
			)
			q.Execute()
			if(databaseCheckQueryResult(q, "renameCharacter [table].[column]"))
				table_rows += q.affected
			qdel(q)
		if(table_rows)
			changed[table] = table_rows

	_renameCharacterCaches(ckey, old_name, new_name)
	_renameCharacterLiveState(ckey, old_name, new_name)
	return changed

/// Re-keys the in-memory caches. Restores read these, not the DB, so without
/// this a renamed character's body/gear/position stay attached to the old key
/// until the next reboot reloads the caches from SQL.
/datum/controller/subsystem/persistence/proc/_renameCharacterCaches(ckey, old_name, new_name)
	PRIVATE_PROC(TRUE)
	var/old_key = "[ckey]|[old_name]"
	var/new_key = "[ckey]|[new_name]"
	for(var/list/cache in list(GLOB.persistence_position_cache, GLOB.persistence_health_cache, GLOB.persistence_inventory_cache, GLOB.persistence_identity_cache))
		if(!islist(cache) || !(old_key in cache))
			continue
		cache[new_key] = cache[old_key]
		cache -= old_key

/// Anything still holding the old name in the running round. The DB rename
/// alone would be undone the next time one of these saved itself back out.
/datum/controller/subsystem/persistence/proc/_renameCharacterLiveState(ckey, old_name, new_name)
	PRIVATE_PROC(TRUE)
	// Drydock ships: both the current owner and the permanent title.
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(!DS)
			continue
		if(DS.owner_ckey == ckey && DS.owner_char_name == old_name)
			DS.owner_char_name = new_name
		if(DS.title_ckey == ckey && DS.title_char_name == old_name)
			DS.title_char_name = new_name

	// Neural laces -- a lace keeps its own copy of the registered identity and
	// is what a resleeve/vault restore renames the body back to.
	for(var/obj/item/organ/internal/neural_lace/lace in world)
		if(lace.registered_ckey == ckey && lace.registered_name == old_name)
			lace.registered_name = new_name

	// The character themselves, if they're in the round right now.
	for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
		if(H.ckey == ckey && H.real_name == old_name)
			H.real_name = new_name
			H.name = new_name

	// Every ID card still bearing the old name is REVOKED rather than
	// relabelled -- the same treatment a card gets when a replacement is
	// printed (_revoke_member_id_now(), faction_manage.dm). A card is a
	// physical credential tied to a name and its access; silently rewriting
	// one would let a renamed character keep a credential nobody reissued.
	// They print a fresh card under the new name instead.
	//
	// Matched on registered_name because ID cards carry no ckey. That is safe
	// here precisely because the rename refused any name already in use by a
	// live character, so the old name identifies exactly one person. The sweep
	// covers the whole world, not just the mob's own slot -- spares in
	// lockers, bags and on the floor all have to lose access too.
	var/revoked_cards = 0
	for(var/obj/item/card/id/card in world)
		if(card.revoked || card.registered_name != old_name)
			continue
		card.revoked = TRUE
		card.access = list()
		card.update_name()
		revoked_cards++
	if(revoked_cards)
		log_subsystem_persistence_info("Rename: revoked [revoked_cards] ID card\s still registered to '[old_name]'.")

/datum/admins/proc/rename_persistent_character()
	set name = "Rename Character"
	set category = "Persistence.Characters"
	set desc = "Renames a character across every persistence table, cache and live reference."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- character data isn't persisted."))
		return

	var/target_ckey = ckey(tgui_input_text(usr, "Ckey the character belongs to:", "Rename Character", "", max_length = 32))
	if(!target_ckey)
		return

	var/list/characters = persistence_get_saved_characters(target_ckey)
	var/old_name
	if(length(characters))
		old_name = tgui_input_list(usr, "Which character?", "Rename Character", characters)
	else
		// Cache miss doesn't mean the character doesn't exist (a never-spawned
		// chargen row has no position/health/inventory entry yet), so allow a
		// manual name rather than dead-ending here.
		old_name = tgui_input_text(usr, "No cached characters found for '[target_ckey]'. Exact current character name:", "Rename Character", "", max_length = 64, encode = FALSE)
	if(!old_name)
		return

	// encode = FALSE -- this is an identity key compared raw against real_name
	// and stored as such, not display text. HTML-encoding a name with an
	// apostrophe would silently break every exact-string match afterwards.
	var/new_name = tgui_input_text(usr, "New name for '[old_name]':", "Rename Character", old_name, max_length = 64, encode = FALSE)
	if(!new_name || new_name == old_name)
		return

	if(SSpersistence._characterNameTaken(target_ckey, new_name))
		to_chat(usr, SPAN_WARNING("'[new_name]' is already in use by a living character (or by another of this ckey's records) -- pick another name. Nothing was changed."))
		return

	if(tgui_alert(usr, "Rename '[old_name]' to '[new_name]' for [target_ckey]?\n\nThis rewrites every persistence record for that character, and REVOKES any ID card still registered to the old name -- they will need to print a replacement.", "Rename Character", list("Rename", "Cancel")) != "Rename")
		return

	var/list/changed = SSpersistence.renameCharacter(target_ckey, old_name, new_name, usr)
	if(isnull(changed))
		to_chat(usr, SPAN_WARNING("Rename failed -- see the persistence log. Nothing may have been changed."))
		return

	var/total = 0
	var/list/report = list()
	for(var/table in changed)
		total += changed[table]
		report += "[table]: [changed[table]]"
	to_chat(usr, SPAN_GOOD("Renamed '[old_name]' to '[new_name]' for [target_ckey] -- [total] row\s across [length(changed)] table\s."))
	if(length(report))
		to_chat(usr, SPAN_NOTICE(report.Join(" | ")))
	to_chat(usr, SPAN_NOTICE("Any ID card registered to the old name has been revoked -- they'll need to print a replacement."))

	log_and_message_admins("renamed persistent character '[old_name]' to '[new_name]' for [target_ckey] ([total] rows).", usr)
	feedback_add_details("admin_verb", "RPC")
