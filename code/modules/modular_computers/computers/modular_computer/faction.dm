/*
 * Modular Computer -- Faction Shackling
 * Players can claim a modular computer for their faction by swiping their ID on it.
 * Once shackled, only officers+ of that faction (or admins) can release it.
 * Programs read computer.persistent_network at runtime to know their faction context.
 *
 * Persistence: persistent_network and faction_shackled are saved via the persistent
 * objects content system so shackled machines survive server restarts without a beacon.
 */

/obj/item/modular_computer/persistent_objects_get_content()
	var/list/content = list()
	if(persistent_network)
		content["persistent_network"] = persistent_network
	if(faction_shackled)
		content["faction_shackled"] = TRUE
	return content

/obj/item/modular_computer/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if("persistent_network" in content)
		persistent_network = content["persistent_network"] || ""
	if("faction_shackled" in content)
		faction_shackled = !!content["faction_shackled"]

/obj/item/modular_computer/verb/link_faction_network()
	set name = "Link to Faction"
	set category = "Object"
	set src in oview(1)

	var/mob/user = usr
	var/obj/item/card/id/I = user.GetIdCard()
	if(!I || !I.employer_faction)
		to_chat(user, SPAN_WARNING("Your ID is not issued by a faction."))
		return

	var/card_faction = I.employer_faction

	if(faction_shackled && persistent_network != card_faction)
		to_chat(user, SPAN_WARNING("This computer is shackled to [get_faction_name(persistent_network)] ([persistent_network]). Only an officer of that faction can release it."))
		return

	if(faction_shackled && persistent_network == card_faction)
		to_chat(user, SPAN_NOTICE("This computer is already shackled to [get_faction_name(card_faction)] ([card_faction])."))
		return

	var/confirm = tgui_alert(user, "Shackle this computer to [get_faction_name(card_faction)] ([card_faction])? Only officers of that faction will be able to release it.", "Link to Faction", list("Confirm", "Cancel"))
	if(confirm != "Confirm")
		return

	persistent_network = card_faction
	faction_shackled   = TRUE
	to_chat(user, SPAN_GOOD("Computer shackled to [get_faction_name(card_faction)]. Programs on this machine will now operate under that faction."))
	log_game("[key_name(user)] shackled [src] at ([x],[y],[z]) to faction '[card_faction]'.")

/obj/item/modular_computer/verb/release_faction_shackle()
	set name = "Release Faction Shackle"
	set category = "Object"
	set src in oview(1)

	var/mob/user = usr

	if(!faction_shackled || !persistent_network)
		to_chat(user, SPAN_WARNING("This computer is not currently shackled to any faction."))
		return

	var/current_faction = persistent_network
	var/is_admin = check_rights(R_ADMIN, 0, user)

	if(!is_admin)
		var/list/member = get_faction_member(user.ckey, current_faction)
		var/user_rank = member ? (member["rank"] || 0) : -1
		if(user_rank < 1)
			to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(current_faction)] to release this shackle."))
			return

	var/confirm = tgui_alert(user, "Release this computer from [get_faction_name(current_faction)]? It will be unclaimed and anyone can re-link it.", "Release Shackle", list("Release", "Cancel"))
	if(confirm != "Release")
		return

	persistent_network = ""
	faction_shackled   = FALSE
	to_chat(user, SPAN_GOOD("Shackle released. Computer is now unclaimed."))
	log_game("[key_name(user)] released faction shackle on [src] at ([x],[y],[z]) (was '[current_faction]').")

/obj/item/modular_computer/verb/check_faction_network()
	set name = "Check Faction Network"
	set category = "Admin"
	set src in oview(1)

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
		persistent_network = new_uid
		faction_shackled   = TRUE
		to_chat(user, SPAN_GOOD("Network force-set to '[new_uid]' and shackled."))
		log_admin("[key_name(user)] force-set faction network on [src] at ([x],[y],[z]) to '[new_uid]' (shackled).")
	else if(action == "Force-Clear Network")
		persistent_network = ""
		faction_shackled   = FALSE
		to_chat(user, SPAN_GOOD("Network cleared. Computer is now unclaimed."))
		log_admin("[key_name(user)] force-cleared faction network on [src] at ([x],[y],[z]).")
