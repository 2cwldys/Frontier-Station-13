/*
 * Modular Computer -- Faction Shackling
 * Players can claim a modular computer for their faction by swiping their ID on it.
 * Once shackled, only officers+ of that faction (or admins) can release it.
 * Programs read computer.persistent_network at runtime to know their faction context.
 *
 * Persistence: persistent_network and faction_shackled are saved via the persistent
 * objects content system so shackled machines survive server restarts without a beacon.
 * Downloaded software (hard_drive.stored_files) is also saved here -- see
 * modcomp_save_programs()/modcomp_restore_programs() below, shared with the
 * worldstate persistence path (persistence_worldstate.dm) for stationary
 * computers that never go through the persistent-objects track system.
 */

/// Factory-default programs install_default_programs() always recreates on
/// Initialize() -- redundant to save/restore.
GLOBAL_LIST_INIT(modcomp_factory_default_programs, list("computerconfig", "clientmanager", "pai_access_lock"))

/obj/item/modular_computer/persistent_objects_get_content()
	var/list/content = list()
	if(persistent_network)
		content["persistent_network"] = persistent_network
	if(faction_shackled)
		content["faction_shackled"] = TRUE
	var/list/programs = modcomp_save_programs()
	if(length(programs))
		content["programs"] = programs
	// ID card sitting in the card slot (PDAs) -- name/assignment/access etc.
	if(card_slot && card_slot.stored_card)
		content["stored_id_type"] = "[card_slot.stored_card.type]"
		content["stored_id"] = card_slot.stored_card.persistent_objects_get_content()
	return content

/obj/item/modular_computer/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	// Diagnostic: prove the apply side runs and what it received
	var/list/content_keys = list()
	for(var/ck in content)
		content_keys += "[ck]"
	log_subsystem_persistence_info("Modcomp apply: [src] keys=\[[content_keys.Join(", ")]\] programs=[islist(content["programs"]) ? length(content["programs"]) : "none"]")
	if("persistent_network" in content)
		// Normalize on restore: older saves may carry raw display names
		persistent_network = normalize_faction_uid(content["persistent_network"]) || ""
	if("faction_shackled" in content)
		faction_shackled = !!content["faction_shackled"]
	if("programs" in content)
		modcomp_restore_programs(content["programs"])
	if(islist(content["stored_id"]) && card_slot && !card_slot.stored_card)
		var/id_path = text2path(content["stored_id_type"]) || /obj/item/card/id
		if(ispath(id_path, /obj/item/card/id))
			var/obj/item/card/id/restored_id = new id_path(src)
			restored_id.persistent_objects_apply_content(content["stored_id"], null, null, null)
			// insert_id() also re-applies the computer's name suffix
			card_slot.insert_id(restored_id)

/// Returns the filenames of every non-factory-default program currently
/// installed, suitable for saving and later passing to modcomp_restore_programs().
/obj/item/modular_computer/proc/modcomp_save_programs()
	var/list/saved = list()
	if(hard_drive)
		for(var/datum/computer_file/program/P in hard_drive.stored_files)
			if(P.filename in GLOB.modcomp_factory_default_programs)
				continue
			saved += P.filename
	return saved

/// Re-installs programs by filename, looking them up in the NTNet downloadable
/// software catalog and cloning a fresh instance (matches how the in-game
/// download tool itself installs software -- see ntdownloader.dm's use of
/// find_ntnet_file_by_name()+clone()). Filenames with no catalog match
/// (e.g. a program removed from the codebase since the save was made) are
/// silently skipped.
/obj/item/modular_computer/proc/modcomp_restore_programs(list/filenames)
	if(!islist(filenames) || !hard_drive)
		if(islist(filenames) && length(filenames))
			log_subsystem_persistence_error("Modcomp restore: [src] has no hard drive -- [length(filenames)] saved program(s) not restored.")
		return
	// Reconciliation pass: the fresh machine's Initialize() already installed
	// its FULL preset program set -- including programs the player deleted
	// in-game to free drive space. Saved state is authoritative: remove any
	// non-factory, deletable program that is not in the saved list FIRST, so
	// the install pass below has the same free space the player actually had
	// (fixes "hard drive full" restore failures on near-capacity PDAs).
	for(var/datum/computer_file/program/P in hard_drive.stored_files.Copy())
		if(P.filename in filenames)
			continue
		if(P.filename in GLOB.modcomp_factory_default_programs)
			continue // never saved by design -- always keep
		if(P.undeletable)
			continue
		P.kill_program(TRUE)
		hard_drive.remove_file(P, force = TRUE)
		log_subsystem_persistence_info("Modcomp restore: removed un-saved '[P.filename]' from [src] (reconcile).")
	for(var/fname in filenames)
		if(hard_drive.find_file_by_name(fname))
			continue // already present
		var/datum/computer_file/program/template = GLOB.ntnet_global.find_ntnet_file_by_name(fname)
		if(!template)
			log_subsystem_persistence_error("Modcomp restore: program '[fname]' not found in the NTNet catalog -- skipped on [src].")
			continue
		var/datum/computer_file/program/copy = template.clone(FALSE, src)
		if(hard_drive.store_file(copy))
			log_subsystem_persistence_info("Modcomp restore: installed '[fname]' on [src].")
		else
			log_subsystem_persistence_error("Modcomp restore: hard drive full -- could not install '[fname]' on [src].")

// Player-facing faction shackling for modular computers is configured via
// the faction tagger tool now (code/game/objects/items/devices/faction_tagger.dm
// + faction_tagger_compatible()/get_uid()/set() overrides in
// code/controllers/subsystems/persistence/persistence_faction_tagger.dm) --
// the player-facing link/release verbs that used to live here are gone.
// This admin-only quick-access verb stays for admins who don't want to dig
// out a tagger item.
/obj/item/modular_computer/verb/check_faction_network()
	set name = "Check Faction Network"
	set category = "Admin"
	set src in view(1)

	if(!check_rights(R_ADMIN))
		return

	var/mob/user = usr
	var/status = persistent_network ? "[get_faction_name(persistent_network)] ([persistent_network])" : "(none)"
	var/shackle_status = faction_shackled ? "SHACKLED" : "unshackled"

	// Show status in chat (avoids tgui_alert size limits)
	var/prog_lines = ""
	if(hard_drive)
		for(var/datum/computer_file/program/P in hard_drive.stored_files)
			if(istype(P, /datum/computer_file/program/card_mod) || \
			   istype(P, /datum/computer_file/program/civilian/cargocontrol) || \
			   istype(P, /datum/computer_file/program/faction_manage))
				prog_lines += "\n    [P.filename]"
	if(!prog_lines)
		prog_lines = "\n    (none)"
	to_chat(user, SPAN_NOTICE("--- Faction Network: [src] ---\nNetwork: [status]\nShackle: [shackle_status]\nFaction programs:[prog_lines]"))

	var/action = tgui_input_list(user, "Select action:", "Check Faction Network", list("Force-Set Network", "Force-Clear Network", "Close"))
	if(!action || action == "Close")
		return
	if(action == "Force-Set Network")
		var/new_uid = tgui_input_text(user, "Enter faction UID:", "Force-Set Network", persistent_network, max_length = 32)
		if(!new_uid) return
		persistent_network = normalize_faction_uid(new_uid)
		faction_shackled   = TRUE
		to_chat(user, SPAN_GOOD("Network force-set to '[new_uid]' and shackled."))
		log_admin("[key_name(user)] force-set faction network on [src] at ([x],[y],[z]) to '[new_uid]' (shackled).")
	else if(action == "Force-Clear Network")
		persistent_network = ""
		faction_shackled   = FALSE
		to_chat(user, SPAN_GOOD("Network cleared. Computer is now unclaimed."))
		log_admin("[key_name(user)] force-cleared faction network on [src] at ([x],[y],[z]).")
