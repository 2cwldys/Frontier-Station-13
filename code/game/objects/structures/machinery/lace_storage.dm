/*
 * Lace Storage Vault
 * Server rack holding extracted neural laces (with or without a preserved
 * consciousness). Can be networked to a faction or public, like cryopods.
 * Uncollected laces auto-transfer here via the lace's 4-hour timer.
 * Contents persist across restarts via ss13_neural_lace_vault (V059) --
 * registration data survives; a stored consciousness is round-local and
 * comes back as "was occupied" so an admin can rebind via Assign Consciousness.
 */

/obj/structure/machinery/lace_storage
	name = "lace storage vault"
	desc = "A secure server rack for preserving extracted neural laces and the consciousness patterns within them."
	icon = 'icons/obj/machinery/research.dmi'
	icon_state = "RD-server-off"
	anchored = TRUE
	density = TRUE

	/// Faction UID, "public", or "" (unmanaged)
	var/persistent_network = ""
	/// Neural laces stored in this vault
	var/list/stored_laces = list()
	/// DB row ids parallel to stored_laces (0 = not persisted, e.g. DB down)
	var/list/stored_lace_row_ids = list()
	/// Row flags parallel to stored_laces: lace held a consciousness before a
	/// restart wiped it (round-local minds cannot be restored)
	var/list/stored_lace_was_occupied = list()
	/// Maximum number of laces this vault can hold. 0 = unlimited.
	var/capacity = 0

/obj/structure/machinery/lace_storage/Initialize()
	. = ..()
	update_icon()

/obj/structure/machinery/lace_storage/update_icon()
	icon_state = length(stored_laces) ? "RD-server-on" : "RD-server-off"

/obj/structure/machinery/lace_storage/proc/has_free_slot()
	return !capacity || length(stored_laces) < capacity

/obj/structure/machinery/lace_storage/get_examine_text(mob/user, distance, is_adjacent, infix, suffix)
	. = ..()
	if(capacity)
		. += SPAN_NOTICE("It holds [length(stored_laces)] of [capacity] neural laces.")
	else
		. += SPAN_NOTICE("It holds [length(stored_laces)] neural laces.")

/obj/structure/machinery/lace_storage/attackby(obj/item/attacking_item, mob/user)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(!attacking_item.tool_use_check(user, 0))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("You secure \the [src] in place.") : SPAN_NOTICE("You unsecure \the [src]."))
		attacking_item.degrade_durability(attacking_item.durability_per_use)
		return TRUE
	if(istype(attacking_item, /obj/item/organ/internal/neural_lace))
		var/obj/item/organ/internal/neural_lace/lace = attacking_item
		if(!has_free_slot())
			to_chat(user, SPAN_WARNING("\The [src] is full."))
			return TRUE
		if(!user.unEquip(lace, src))
			return TRUE
		store_lace(lace, user)
		return TRUE
	return ..()

/// Stash a lace into the vault: physical move, bookkeeping, DB row.
/// Used by attackby() and by the lace's auto-transfer timer.
/obj/structure/machinery/lace_storage/proc/store_lace(obj/item/organ/internal/neural_lace/lace, mob/user)
	if(!istype(lace) || !has_free_slot())
		return FALSE
	if(lace.loc != src)
		lace.forceMove(src)
	if(lace.auto_transfer_timer)
		deltimer(lace.auto_transfer_timer)
		lace.auto_transfer_timer = null
	stored_laces += lace
	stored_lace_row_ids += _vault_db_insert(lace)
	stored_lace_was_occupied += FALSE
	update_icon()
	if(lace.registered_ckey && lace.registered_name)
		SSpersistence.lacePositionSave(lace.registered_ckey, lace.registered_name, get_turf(src))
	if(user)
		to_chat(user, SPAN_NOTICE("You slot the neural lace into \the [src]."))
	if(lace.lace_mob)
		to_chat(lace.lace_mob, SPAN_NOTICE("Your lace has been secured in a storage vault. You are preserved until retrieved."))
	log_game("Neural lace ([lace.registered_name]/[lace.registered_ckey]) stored in vault at ([x],[y],[z])[user ? " by [key_name(user)]" : " via auto-transfer"].")
	return TRUE

/// Remove the lace at the given index; hands it to the user if possible.
/obj/structure/machinery/lace_storage/proc/retrieve_lace(index, mob/user)
	if(index < 1 || index > length(stored_laces))
		return FALSE
	var/obj/item/organ/internal/neural_lace/lace = stored_laces[index]
	var/row_id = stored_lace_row_ids[index]
	stored_laces.Cut(index, index + 1)
	stored_lace_row_ids.Cut(index, index + 1)
	stored_lace_was_occupied.Cut(index, index + 1)
	if(row_id)
		_vault_db_delete(row_id)
	if(QDELETED(lace))
		update_icon()
		return FALSE
	if(user && user.put_in_hands(lace))
		to_chat(user, SPAN_NOTICE("You carefully remove [lace.registered_name ? "[lace.registered_name]'s" : "the"] neural lace from \the [src]."))
	else
		lace.forceMove(get_turf(src))
	update_icon()
	log_game("Neural lace ([lace.registered_name]/[lace.registered_ckey]) retrieved from vault at ([x],[y],[z])[user ? " by [key_name(user)]" : ""].")
	return TRUE

/// INSERT a vault row for this lace; returns the row id (0 if DB unavailable).
/obj/structure/machinery/lace_storage/proc/_vault_db_insert(obj/item/organ/internal/neural_lace/lace)
	if(!GLOB.config.sql_enabled || !SSpersistence.databaseCheckConnection("lace_vault insert"))
		return 0
	var/datum/db_query/ins = SSdbcore.NewQuery(
		{"INSERT INTO ss13_neural_lace_vault (map_path, vault_x, vault_y, vault_z, registered_name, registered_ckey, owner_faction, lace_damage, was_occupied)
		VALUES (:mp, :x, :y, :z, :name, :ckey, :faction, :damage, :occupied)"},
		list(
			"mp"       = "[SSatlas.current_map.path]",
			"x"        = x,
			"y"        = y,
			"z"        = z,
			"name"     = lace.registered_name || "",
			"ckey"     = lace.registered_ckey || "",
			"faction"  = lace.owner_faction || "",
			"damage"   = lace.lace_damage,
			"occupied" = lace.lace_occupied ? 1 : 0
		)
	)
	ins.Execute()
	SSpersistence.databaseCheckQueryResult(ins, "lace_vault insert")
	var/row_id = ins.last_insert_id || 0
	qdel(ins)
	return row_id

/// DELETE a vault row by id.
/obj/structure/machinery/lace_storage/proc/_vault_db_delete(row_id)
	if(!GLOB.config.sql_enabled || !SSpersistence.databaseCheckConnection("lace_vault delete"))
		return
	var/datum/db_query/dq = SSdbcore.NewQuery(
		"DELETE FROM ss13_neural_lace_vault WHERE id = :id",
		list("id" = row_id)
	)
	dq.Execute()
	SSpersistence.databaseCheckQueryResult(dq, "lace_vault delete")
	qdel(dq)

// ============================================================
// TGUI
// ============================================================

/obj/structure/machinery/lace_storage/attack_hand(mob/user)
	ui_interact(user)

/obj/structure/machinery/lace_storage/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LaceVault", name, 420, 480)
		ui.open()

/obj/structure/machinery/lace_storage/ui_data(mob/user)
	var/list/data = list()
	data["network"]  = persistent_network
	data["capacity"] = capacity
	var/list/laces_out = list()
	for(var/i in 1 to length(stored_laces))
		var/obj/item/organ/internal/neural_lace/lace = stored_laces[i]
		if(QDELETED(lace))
			continue
		var/faction_name = lace.owner_faction ? (get_faction_name(lace.owner_faction) || lace.owner_faction) : null
		laces_out += list(list(
			"index"        = i,
			"name"         = lace.registered_name || "unregistered",
			"faction"      = faction_name,
			"damage"       = lace.lace_damage,
			"occupied"     = !!lace.lace_mob,
			"was_occupied" = stored_lace_was_occupied[i]
		))
	data["laces"] = laces_out
	return data

/obj/structure/machinery/lace_storage/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return TRUE
	switch(action)
		if("retrieve")
			retrieve_lace(text2num(params["index"]), usr)
			return TRUE

// Faction-network assignment moved to the faction tagger tool (see
// faction_tagger_set() in persistence_faction_tagger.dm). This verb now
// only handles the "public vault" designation, which isn't a faction
// concept and the tagger doesn't cover.
/obj/structure/machinery/lace_storage/verb/configure_public_vault()
	set name = "Configure Public Vault"
	set category = "Persistence.Misc"
	set desc = "Mark this vault as public (receives anyone's auto-transferred laces), or clear it."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	to_chat(usr, SPAN_NOTICE("Current network: [persistent_network ? persistent_network : "(unmanaged)"]"))

	var/confirm = tgui_alert(usr, "Mark this vault public (receives anyone's laces)? This clears any faction tag currently set.", "Configure Public Vault", list("Mark Public", "Clear", "Cancel"))
	if(confirm == "Cancel" || !confirm)
		return

	persistent_network = (confirm == "Mark Public") ? "public" : ""
	to_chat(usr, SPAN_GOOD("Lace vault network set to: [persistent_network ? persistent_network : "(unmanaged)"]"))
	log_admin("[key_name(usr)] configured lace vault at ([x],[y],[z]) network='[persistent_network]'")

/obj/structure/machinery/lace_storage/worldstate_get_content()
	if(!persistent_network)
		return list()
	return list("network" = persistent_network)

/obj/structure/machinery/lace_storage/worldstate_apply_content(list/content)
	persistent_network = content["network"] || ""
	update_icon()

/// Cargo-ordered copy -- starts unanchored so it can be moved out of its
/// crate before being wrenched into place. The base type's anchored = TRUE
/// (whatever's already mapped in) is left untouched.
/obj/structure/machinery/lace_storage/crate
	anchored = FALSE

/// Find an available lace storage vault for the given faction (or public)
/proc/persistence_find_lace_storage(faction_uid = null)
	// Priority 1: faction vault
	if(faction_uid)
		for(var/obj/structure/machinery/lace_storage/pod in world)
			if(is_station_level(pod.z) && pod.persistent_network == faction_uid && pod.has_free_slot())
				return pod
	// Priority 2: public vault
	for(var/obj/structure/machinery/lace_storage/pod in world)
		if(is_station_level(pod.z) && pod.persistent_network == "public" && pod.has_free_slot())
			return pod
	return null
