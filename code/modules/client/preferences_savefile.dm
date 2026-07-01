#define SAVEFILE_VERSION_MIN	8
#define SAVEFILE_VERSION_MAX	12

/datum/preferences/proc/load_path(ckey,filename="preferences.sav")
	if(!ckey)	return
	path = "data/player_saves/[copytext(ckey,1,2)]/[ckey]/[filename]"
	savefile_version = SAVEFILE_VERSION_MAX

/datum/preferences/proc/load_preferences()
	var/savefile/S
	if (!GLOB.config.sql_saves)
		if (!path)
			return 0
		if (!fexists(path))
			return 0
		S = new /savefile(path)
		if (!S)
			return 0
		S.cd = "/"

		S["version"] >> savefile_version

	player_setup.load_preferences(S)

	if (!GLOB.config.sql_saves)
		loaded_preferences = S

	return 1

/datum/preferences/proc/save_preferences()
	var/savefile/S
	if (!GLOB.config.sql_saves)
		if(!path)
			return 0
		S = new /savefile(path)
		if(!S)
			return 0
		S.cd = "/"

		S["version"] << SAVEFILE_VERSION_MAX

	player_setup.save_preferences(S)

	if (!GLOB.config.sql_saves)
		loaded_preferences = S

	return 1

/datum/preferences/proc/load_character(slot)
	var/savefile/S
	var/mob/abstract/new_player/NP = src.client.mob
	var/readied
	if(istype(NP) && NP.ready)
		readied = TRUE
		SSticker.update_ready_list(NP, force_urdy=TRUE)

	if (!GLOB.config.sql_saves)
		if (!path)
			return 0
		if (!fexists(path))
			return 0
		S = new /savefile(path)
		if (!S)
			return 0
		S.cd = "/"
		if (!slot)
			slot = default_slot
		slot = sanitize_integer(slot, 1, GLOB.config.admin_character_slots, initial(default_slot))
		if(slot != default_slot)
			default_slot = slot
			S["default_slot"] << slot
		S.cd = "/character[slot]"
	else if (slot)
		current_character = slot

	player_setup.load_character(S)
	clear_character_previews() // Recalculate them on next show

	if (!GLOB.config.sql_saves)
		loaded_character = S
	else
		save_preferences()

	if(istype(NP) && readied)
		SSticker.update_ready_list(NP)

	return 1

/datum/preferences/proc/save_character()
	// Block saves only for characters that have already entered the world (first_spawned_at set).
	// A new character has current_character > 0 but first_spawned_at NULL -- still editable.
	if(GLOB.config.sql_saves && current_character && SSdbcore.Connect())
		var/datum/db_query/lock_q = SSdbcore.NewQuery(
			"SELECT first_spawned_at FROM ss13_characters WHERE id = :id AND deleted_at IS NULL LIMIT 1",
			list("id" = current_character))
		lock_q.Execute()
		if(lock_q.NextRow() && lock_q.item[1])
			qdel(lock_q)
			return 0  // character has spawned -- locked
		qdel(lock_q)

	var/savefile/S
	if(!GLOB.config.sql_saves)
		if(!path)
			return 0
		S = new /savefile(path)
		if(!S)
			return 0
		S.cd = "/character[default_slot]"
		S["version"] << SAVEFILE_VERSION_MAX

	// For new characters (current_character == 0), create the DB row now via SSdbcore.
	// This is deferred from ui_act("create") so the slot only appears AFTER Save is clicked.
	if(!current_character && GLOB.config.sql_saves && SSdbcore.Connect())
		var/ckey_val = client ? client.ckey : null
		if(ckey_val && real_name)
			var/datum/db_query/ins_q = SSdbcore.NewQuery(
				"INSERT INTO ss13_characters (ckey, name, species) VALUES (:ckey, :name, :species)",
				list("ckey" = ckey_val, "name" = real_name, "species" = species || SPECIES_HUMAN))
			ins_q.Execute()
			qdel(ins_q)
			var/datum/db_query/id_q = SSdbcore.NewQuery(
				{"SELECT id FROM ss13_characters WHERE ckey = :ckey AND name = :name
				AND deleted_at IS NULL ORDER BY id DESC LIMIT 1"},
				list("ckey" = ckey_val, "name" = real_name))
			id_q.Execute()
			if(id_q.NextRow())
				current_character = text2num(id_q.item[1]) || 0
			qdel(id_q)

	// Force all groups dirty so handle_sql_saving runs UPDATE for all appearance columns
	if(GLOB.config.sql_saves)
		for(var/datum/category_group/player_setup_category/PS in player_setup.categories)
			PS.modified = 1

	player_setup.save_character(S)

	if(!GLOB.config.sql_saves)
		loaded_character = S

	return S

/datum/preferences/proc/sanitize_preferences()
	player_setup.sanitize_setup(GLOB.config.sql_saves)
	return 1

/datum/preferences/proc/update_setup(var/savefile/preferences, var/savefile/character)
	if(!preferences || !character)
		return 0
	return player_setup.update_setup(preferences, character)

#undef SAVEFILE_VERSION_MAX
#undef SAVEFILE_VERSION_MIN
