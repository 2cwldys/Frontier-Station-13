/*
 * Persistence - Custom Outfit Templates
 * Admin-authored, DB-backed, runtime-editable equipment loadouts captured
 * directly off a human mob's currently worn/held gear -- mirrors the exact
 * shape persistence_hostile_npcs.dm already uses (a cached GLOBAL_LIST, an
 * Initialize() proc called from SSpersistence.Initialize(), an admin verb
 * that mutates the DB row and the cached entry together with no restart
 * needed, and a small lookup helper).
 *
 * Exists because GLOB.outfit_cache (misc_late.dm) only ever contains
 * compile-time /obj/outfit subtypes -- dressing a hostile NPC in any other
 * combination of gear would otherwise require writing and recompiling a new
 * subtype. This lets an admin dress a human body exactly how they want and
 * capture that loadout as a reusable, named template instead.
 *
 * Consumed by: manage_hostile_npc_presets()'s outfit picker
 * (persistence_hostile_npcs.dm) and apply_hostile_preset() (hostile_npc.dm).
 */

/// Maps /obj/outfit slot var names to their equivalent
/// /mob/living/carbon/human var names -- several differ (mask vs wear_mask,
/// wrist vs wrists, l_pocket/r_pocket vs l_store/r_store, suit_store vs
/// s_store, id vs wear_id, suit vs wear_suit, uniform vs w_uniform).
/// Shared by both capture (mob -> slots) and apply (slots -> outfit
/// instance) so the mapping only needs to be written once.
GLOBAL_LIST_INIT(outfit_template_slot_map, list(
	"uniform"    = "w_uniform",
	"suit"       = "wear_suit",
	"back"       = "back",
	"belt"       = "belt",
	"gloves"     = "gloves",
	"wrist"      = "wrists",
	"pants"      = "pants",
	"shoes"      = "shoes",
	"head"       = "head",
	"mask"       = "wear_mask",
	"l_ear"      = "l_ear",
	"r_ear"      = "r_ear",
	"glasses"    = "glasses",
	"l_pocket"   = "l_store",
	"r_pocket"   = "r_store",
	"suit_store" = "s_store",
	"id"         = "wear_id",
	"l_hand"     = "l_hand",
	"r_hand"     = "r_hand",
))

/// Cached custom outfit templates: list of list(id, name, slots, description).
/// "slots" is the decoded assoc list outfit_slot_var -> item typepath string.
GLOBAL_LIST_EMPTY(custom_outfit_templates)

/**
 * Load custom outfit templates into the cache. Called from SSpersistence.Initialize().
 */
/datum/controller/subsystem/persistence/proc/outfitTemplatesInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.custom_outfit_templates = list()

	if(!databaseCheckConnection("outfitTemplatesInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT id, name, slots_json, description FROM ss13_outfit_templates WHERE map_path = :mp",
		list("mp" = "[SSatlas.current_map.path]")
	)
	query.Execute()
	if(!databaseCheckQueryResult(query, "outfitTemplatesInitialize"))
		qdel(query)
		return
	while(query.NextRow())
		GLOB.custom_outfit_templates += list(list(
			"id"          = text2num(query.item[1]),
			"name"        = query.item[2],
			"slots"       = json_decode(query.item[3]) || list(),
			"description" = query.item[4] || ""
		))
	qdel(query)
	log_subsystem_persistence_info("Custom outfit templates: loaded [length(GLOB.custom_outfit_templates)] template(s).")

/// Finds a cached outfit template by numeric id, or null.
/proc/get_outfit_template(id)
	if(isnull(id))
		return null
	for(var/list/template in GLOB.custom_outfit_templates)
		if(template["id"] == id)
			return template
	return null

/// Finds a cached outfit template by name, or null.
/proc/get_outfit_template_by_name(name)
	if(!name)
		return null
	for(var/list/template in GLOB.custom_outfit_templates)
		if(template["name"] == name)
			return template
	return null

/**
 * Walks H's currently worn/held equipment via outfit_template_slot_map and
 * records each non-empty slot's item type. Only bare typepaths are stored --
 * per-item customization (paint, custom names, forensics) is not captured,
 * matching how every other outfit in this codebase already behaves.
 */
/proc/capture_outfit_template_from_mob(mob/living/carbon/human/H)
	var/list/slots = list()
	for(var/outfit_var in GLOB.outfit_template_slot_map)
		var/mob_var = GLOB.outfit_template_slot_map[outfit_var]
		var/obj/item/I = H.vars[mob_var]
		if(!I)
			continue
		// A live /obj/item/offhand placeholder means the capturing admin
		// happened to have a two-handed weapon wielded themselves -- it's
		// bookkeeping created by toggle_wield(), not gear, and re-equipping
		// a fresh unlinked copy of it later does nothing useful.
		if(istype(I, /obj/item/offhand))
			continue
		slots[outfit_var] = "[I.type]"
	return slots

/**
 * Builds a fresh /obj/outfit instance from a cached template's slots --
 * ready to hand straight to preEquipOutfit()/equipOutfit(), both of which
 * already accept a live instance as readily as a typepath (inventory.dm).
 */
/proc/build_outfit_instance_from_template(list/template)
	var/obj/outfit/O = new()
	var/list/slots = template["slots"]
	for(var/outfit_var in slots)
		O.vars[outfit_var] = text2path(slots[outfit_var])
	return O

/datum/admins/proc/modify_outfit_templates()
	set name = "Modify Outfit Templates"
	set category = "Persistence.Cargo & Economy"
	set desc = "Add, recapture, rename, or remove admin-authored custom outfit templates captured from a human mob's current equipment."

	if(!check_rights(R_ADMIN))
		return

	if(!GLOB.config.sql_enabled)
		to_chat(usr, SPAN_WARNING("SQL is not enabled -- outfit templates are inactive."))
		return

	while(usr && usr.client)
		var/msg = "Custom outfit templates ([length(GLOB.custom_outfit_templates)]):\n"
		for(var/list/template in GLOB.custom_outfit_templates)
			msg += "  #[template["id"]] [template["name"]] -- [length(template["slots"])] slot(s) captured\n"
		to_chat(usr, SPAN_NOTICE(msg))

		var/choice = tgui_input_list(usr, "Select action:", "Modify Outfit Templates", list("Add Template (capture what I'm wearing)", "Recapture Template", "Rename Template", "Remove Template", "Close"))
		if(!choice || choice == "Close")
			return

		if(choice == "Add Template (capture what I'm wearing)")
			if(!ishuman(usr))
				to_chat(usr, SPAN_WARNING("You must be playing/possessing a human body to capture your current equipment."))
				continue
			var/mob/living/carbon/human/H = usr
			var/name = tgui_input_text(usr, "Template name:", "Add Template", "", max_length = 128)
			if(!name)
				continue
			var/list/slots = capture_outfit_template_from_mob(H)
			if(!length(slots))
				to_chat(usr, SPAN_WARNING("You aren't wearing or holding anything capturable -- equip some gear first."))
				continue
			var/description = tgui_input_text(usr, "Description (optional):", "Add Template", "", max_length = 512)

			var/datum/db_query/q = SSdbcore.NewQuery(
				"INSERT INTO ss13_outfit_templates (map_path, name, slots_json, description) VALUES (:mp, :name, :slots, :desc)",
				list(
					"mp" = "[SSatlas.current_map.path]", "name" = name, "slots" = json_encode(slots),
					"desc" = (description != "" ? description : null)
				)
			)
			q.Execute()
			SSpersistence.databaseCheckQueryResult(q, "modify_outfit_templates add")
			var/new_id = text2num(q.last_insert_id)
			qdel(q)

			GLOB.custom_outfit_templates += list(list("id" = new_id, "name" = name, "slots" = slots, "description" = description))
			log_and_message_admins("captured outfit template '[name]' ([length(slots)] slots) from [key_name(H)]", usr)
			to_chat(usr, SPAN_GOOD("Captured '[name]' ([length(slots)] slot(s)): [jointext(slots, ", ")]."))

		if(choice == "Recapture Template")
			if(!length(GLOB.custom_outfit_templates))
				to_chat(usr, SPAN_NOTICE("No templates to recapture."))
				continue
			if(!ishuman(usr))
				to_chat(usr, SPAN_WARNING("You must be playing/possessing a human body to capture your current equipment."))
				continue
			var/list/recapture_choices = list()
			for(var/list/template in GLOB.custom_outfit_templates)
				recapture_choices["#[template["id"]] [template["name"]]"] = template
			var/recapture_pick = tgui_input_list(usr, "Recapture which template?", "Recapture Template", recapture_choices)
			if(!recapture_pick)
				continue
			var/list/recapture_template = recapture_choices[recapture_pick]
			var/mob/living/carbon/human/H = usr
			var/list/slots = capture_outfit_template_from_mob(H)
			if(!length(slots))
				to_chat(usr, SPAN_WARNING("You aren't wearing or holding anything capturable -- equip some gear first."))
				continue

			var/datum/db_query/rq = SSdbcore.NewQuery(
				"UPDATE ss13_outfit_templates SET slots_json = :slots WHERE id = :id",
				list("slots" = json_encode(slots), "id" = recapture_template["id"])
			)
			rq.Execute()
			SSpersistence.databaseCheckQueryResult(rq, "modify_outfit_templates recapture")
			qdel(rq)
			recapture_template["slots"] = slots
			log_and_message_admins("recaptured outfit template '[recapture_template["name"]]' ([length(slots)] slots) from [key_name(H)]", usr)
			to_chat(usr, SPAN_GOOD("Recaptured '[recapture_template["name"]]' ([length(slots)] slot(s))."))

		if(choice == "Rename Template")
			if(!length(GLOB.custom_outfit_templates))
				to_chat(usr, SPAN_NOTICE("No templates to rename."))
				continue
			var/list/rename_choices = list()
			for(var/list/template in GLOB.custom_outfit_templates)
				rename_choices["#[template["id"]] [template["name"]]"] = template
			var/rename_pick = tgui_input_list(usr, "Rename which template?", "Rename Template", rename_choices)
			if(!rename_pick)
				continue
			var/list/rename_template = rename_choices[rename_pick]
			var/new_name = tgui_input_text(usr, "New name:", "Rename Template", rename_template["name"], max_length = 128)
			if(!new_name)
				continue

			var/datum/db_query/nq = SSdbcore.NewQuery(
				"UPDATE ss13_outfit_templates SET name = :name WHERE id = :id",
				list("name" = new_name, "id" = rename_template["id"])
			)
			nq.Execute()
			SSpersistence.databaseCheckQueryResult(nq, "modify_outfit_templates rename")
			qdel(nq)
			rename_template["name"] = new_name
			log_and_message_admins("renamed outfit template #[rename_template["id"]] to '[new_name]'", usr)
			to_chat(usr, SPAN_GOOD("Renamed to '[new_name]'."))

		if(choice == "Remove Template")
			if(!length(GLOB.custom_outfit_templates))
				to_chat(usr, SPAN_NOTICE("No templates to remove."))
				continue
			var/list/remove_choices = list()
			for(var/list/template in GLOB.custom_outfit_templates)
				remove_choices["#[template["id"]] [template["name"]]"] = template
			var/remove_pick = tgui_input_list(usr, "Remove which template?", "Remove Template", remove_choices)
			if(!remove_pick)
				continue
			var/list/remove_template = remove_choices[remove_pick]
			var/datum/db_query/dq = SSdbcore.NewQuery(
				"DELETE FROM ss13_outfit_templates WHERE id = :id",
				list("id" = remove_template["id"])
			)
			dq.Execute()
			SSpersistence.databaseCheckQueryResult(dq, "modify_outfit_templates remove")
			qdel(dq)
			GLOB.custom_outfit_templates -= list(remove_template)
			log_and_message_admins("removed outfit template '[remove_template["name"]]'", usr)
			to_chat(usr, SPAN_GOOD("Removed '[remove_template["name"]]'."))
