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

/obj/structure/machinery/lace_storage/examine(mob/user)
	. = ..()
	if(capacity)
		. += SPAN_NOTICE("It holds [length(stored_laces)] of [capacity] neural laces.")
	else
		. += SPAN_NOTICE("It holds [length(stored_laces)] neural laces.")

/obj/structure/machinery/lace_storage/attackby(obj/item/attacking_item, mob/user)
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

/obj/structure/machinery/lace_storage/verb/configure_lace_network()
	set name = "Configure Faction Network"
	set category = "Persistence"
	set desc = "Set this vault's faction network ('public' vaults receive anyone's auto-transferred laces)."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	to_chat(usr, SPAN_NOTICE("Current network: [persistent_network ? persistent_network : "(unmanaged)"]"))

	var/new_network = tgui_input_text(usr, "Enter network ID ('public' to receive anyone's laces, a faction UID for faction-only, or leave blank to clear):", "Configure Faction Network", persistent_network, max_length = 32)
	if(new_network == null) return

	persistent_network = (new_network == "public") ? new_network : normalize_faction_uid(new_network)
	to_chat(usr, SPAN_GOOD("Lace vault network set to: [persistent_network ? persistent_network : "(unmanaged)"]"))
	log_admin("[key_name(usr)] configured lace vault at ([x],[y],[z]) network='[persistent_network]'")

/// Player-facing faction linking via ID swipe, mirroring the modular
/// computer's Link to Faction verb: your faction's members claim the vault
/// so faction laces auto-route here instead of a public vault.
/obj/structure/machinery/lace_storage/verb/link_faction_network()
	set name = "Link to Faction"
	set category = "Object"
	set src in oview(1)

	var/mob/user = usr
	var/obj/item/card/id/I = user.GetIdCard()
	if(!I || !I.employer_faction)
		to_chat(user, SPAN_WARNING("Your ID is not issued by a faction."))
		return

	// IDs carry the faction display name; the faction cache/DB key is the
	// normalized uid -- convert before storing or comparing
	var/card_faction = normalize_faction_uid(I.employer_faction)

	if(persistent_network == card_faction)
		to_chat(user, SPAN_NOTICE("This vault is already linked to [get_faction_name(card_faction)] ([card_faction])."))
		return
	if(persistent_network && persistent_network != "public")
		to_chat(user, SPAN_WARNING("This vault is linked to [get_faction_name(persistent_network)] ([persistent_network]). An admin must clear it first."))
		return

	var/confirm = tgui_alert(user, "Link this vault to [get_faction_name(card_faction)] ([card_faction])? Faction laces will auto-route here.", "Link to Faction", list("Confirm", "Cancel"))
	if(confirm != "Confirm")
		return

	persistent_network = card_faction
	to_chat(user, SPAN_GOOD("Vault linked to [get_faction_name(card_faction)]."))
	log_game("[key_name(user)] linked lace vault at ([x],[y],[z]) to faction '[card_faction]'.")

/obj/structure/machinery/lace_storage/worldstate_get_content()
	if(!persistent_network)
		return list()
	return list("network" = persistent_network)

/obj/structure/machinery/lace_storage/worldstate_apply_content(list/content)
	persistent_network = content["network"] || ""
	update_icon()

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
