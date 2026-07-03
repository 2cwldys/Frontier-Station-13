///SCI TELEPAD///
/obj/structure/machinery/telepad
	name = "telepad"
	desc = "A bluespace telepad used for creating bluespace portals."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "pad-idle"
	anchored = 1
	use_power = POWER_USE_IDLE
	idle_power_usage = 200
	active_power_usage = 5000
	var/efficiency

	component_types = list(
		/obj/item/circuitboard/telesci_pad,
		/obj/item/bluespace_crystal/artificial = 2,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil{amount = 1}
	)

	parts_power_mgmt = FALSE

/obj/structure/machinery/telepad/upgrade_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "Upgraded <b>capacitors</b> will improve the power efficiency of the telepad."

/obj/structure/machinery/telepad/RefreshParts()
	..()
	var/E
	for(var/obj/item/stock_parts/capacitor/C in component_parts)
		E += C.rating
	efficiency = E

/obj/structure/machinery/telepad/attackby(obj/item/attacking_item, mob/user, params)
	if(default_deconstruction_screwdriver(user, attacking_item))
		return

	if(panel_open)
		if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
			var/obj/item/multitool/M = attacking_item
			M.buffer = src
			to_chat(user, "<span class='caution'>You save the data in the [attacking_item.name]'s buffer.</span>")
	else
		if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
			to_chat(user, "<span class='caution'>You should open [src]'s maintenance panel first.</span>")

	default_deconstruction_crowbar(user, attacking_item)

/obj/structure/machinery/telepad/update_icon()
	switch (panel_open)
		if (1)
			icon_state = "pad-idle-o"
		if (0)
			icon_state = "pad-idle"

//CARGO TELEPAD//
/obj/structure/machinery/telepad_cargo
	name = "cargo telepad"
	desc = "A telepad used by the Rapid Crate Sender."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "pad-idle"
	anchored = 1
	use_power = POWER_USE_IDLE
	idle_power_usage = 20
	active_power_usage = 500
	var/stage = 0
	/// Faction UID, "public", or "" (unmanaged). Routes supply deliveries to this pad.
	var/persistent_network = ""
	/// If TRUE and persistent_network is set, this pad accepts deliveries for that network.
	var/persistent_spawn   = FALSE
	/// TRUE when a player has claimed this pad for their faction; only officers+ can release.
	var/faction_shackled   = FALSE

/obj/structure/machinery/telepad_cargo/verb/link_faction_network()
	set name = "Link to Faction"
	set category = "Object"
	set src in oview(1)

	var/mob/user = usr
	var/obj/item/card/id/I = user.GetIdCard()
	if(!I || !I.employer_faction)
		to_chat(user, SPAN_WARNING("Your ID is not issued by a faction."))
		return

	var/card_faction = normalize_faction_uid(I.employer_faction)

	if(faction_shackled && persistent_network != card_faction)
		to_chat(user, SPAN_WARNING("This telepad is claimed by [get_faction_name(persistent_network)]. Only their officers can release it."))
		return

	if(faction_shackled && persistent_network == card_faction)
		to_chat(user, SPAN_NOTICE("This telepad is already linked to [get_faction_name(card_faction)]."))
		return

	var/confirm = tgui_alert(user, "Link this cargo telepad to [get_faction_name(card_faction)] ([card_faction])? Only officers of that faction can release it.", "Link to Faction", list("Confirm", "Cancel"))
	if(confirm != "Confirm")
		return

	persistent_network = card_faction
	persistent_spawn   = TRUE
	faction_shackled   = TRUE
	to_chat(user, SPAN_GOOD("Cargo telepad linked to [get_faction_name(card_faction)]. It will now receive deliveries for that faction."))
	log_game("[key_name(user)] linked cargo telepad at ([x],[y],[z]) to faction '[card_faction]'.")

/obj/structure/machinery/telepad_cargo/verb/release_faction_link()
	set name = "Release Faction Link"
	set category = "Object"
	set src in oview(1)

	var/mob/user = usr

	if(!faction_shackled || !persistent_network)
		to_chat(user, SPAN_WARNING("This telepad is not currently linked to a faction."))
		return

	var/cur_faction = persistent_network
	var/is_admin = check_rights(R_ADMIN, 0, user)
	if(!is_admin)
		var/list/member = get_faction_member(user.ckey, cur_faction)
		var/user_rank = member ? (member["rank"] || 0) : -1
		if(user_rank < 1)
			to_chat(user, SPAN_WARNING("You need officer access in [get_faction_name(cur_faction)] to release this link."))
			return

	var/confirm = tgui_alert(user, "Release this telepad from [get_faction_name(cur_faction)]? It will become unclaimed.", "Release Faction Link", list("Release", "Cancel"))
	if(confirm != "Release")
		return

	persistent_network = ""
	persistent_spawn   = FALSE
	faction_shackled   = FALSE
	to_chat(user, SPAN_GOOD("Faction link released. Telepad is now unclaimed."))
	log_game("[key_name(user)] released faction link on cargo telepad at ([x],[y],[z]) (was '[cur_faction]').")

/obj/structure/machinery/telepad_cargo/verb/configure_supply_network()
	set name = "Configure Supply Network"
	set category = "Admin"
	set desc = "Set this telepad's faction supply network."
	set src in oview(1)

	if(!check_rights(R_ADMIN))
		return

	var/current = "[persistent_network ? persistent_network : "(none)"] | delivery=[persistent_spawn]"
	to_chat(usr, SPAN_NOTICE("Current config: [current]"))

	var/new_network = tgui_input_text(usr, "Enter network ID (a faction UID, 'public', or leave blank to clear):", "Configure Supply Network", persistent_network, max_length = 32)
	if(new_network == null)
		return

	persistent_network = normalize_faction_uid(new_network)

	if(new_network)
		var/spawn_choice = tgui_alert(usr, "Accept deliveries on this pad for network '[new_network]'?", "Configure Supply Network", list("Yes", "No"))
		persistent_spawn = (spawn_choice == "Yes")
	else
		persistent_spawn = FALSE

	var/label = persistent_network ? "[persistent_network][persistent_spawn ? " (delivery active)" : " (delivery inactive)"]" : "unmanaged"
	to_chat(usr, SPAN_GOOD("Cargo telepad network set to: [label]"))
	log_admin("[key_name(usr)] configured cargo telepad at ([x],[y],[z]) network='[persistent_network]' spawn=[persistent_spawn]")

/obj/structure/machinery/telepad_cargo/attackby(obj/item/attacking_item, mob/user, params)
	// ID card swipe — link or release faction
	if(istype(attacking_item, /obj/item/card/id))
		var/obj/item/card/id/I = attacking_item
		if(!I.employer_faction)
			to_chat(user, SPAN_WARNING("This ID is not issued by a faction."))
			return TRUE
		var/card_faction = normalize_faction_uid(I.employer_faction)

		if(faction_shackled && persistent_network == card_faction)
			// Same faction — offer to release if officer+
			var/list/member = get_faction_member(user.ckey, card_faction)
			var/rank = member ? (member["rank"] || 0) : -1
			if(rank < 1 && !check_rights(R_ADMIN, 0, user))
				to_chat(user, SPAN_WARNING("This telepad is linked to [get_faction_name(card_faction)]. You need officer rank to release it."))
				return TRUE
			var/confirm = tgui_alert(user, "Release this telepad from [get_faction_name(card_faction)]?", "Release Faction Link", list("Release", "Cancel"))
			if(confirm == "Release")
				persistent_network = ""
				persistent_spawn   = FALSE
				faction_shackled   = FALSE
				to_chat(user, SPAN_GOOD("Faction link released. Telepad is now unclaimed."))
				log_game("[key_name(user)] released cargo telepad at ([x],[y],[z]) from faction '[card_faction]' via ID swipe.")
			return TRUE

		if(faction_shackled && persistent_network != card_faction)
			to_chat(user, SPAN_WARNING("This telepad is claimed by [get_faction_name(persistent_network)]. Only their officers can release it."))
			return TRUE

		// Unclaimed — link to this faction
		var/confirm = tgui_alert(user, "Link this telepad to [get_faction_name(card_faction)]?", "Link to Faction", list("Confirm", "Cancel"))
		if(confirm == "Confirm")
			persistent_network = card_faction
			persistent_spawn   = TRUE
			faction_shackled   = TRUE
			to_chat(user, SPAN_GOOD("Cargo telepad linked to [get_faction_name(card_faction)]."))
			log_game("[key_name(user)] linked cargo telepad at ([x],[y],[z]) to faction '[card_faction]' via ID swipe.")
		return TRUE

	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		anchored = 0
		attacking_item.play_tool_sound(get_turf(src), 50)
		if(anchored)
			anchored = 0
			to_chat(user, "<span class='caution'>\The [src] can now be moved.</span>")
		else if(!anchored)
			anchored = 1
			to_chat(user, "<span class='caution'>\The [src] is now secured.</span>")
	if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
		if(stage == 0)
			attacking_item.play_tool_sound(get_turf(src), 50)
			to_chat(user, "<span class='caution'>You unscrew the telepad's tracking beacon.</span>")
			stage = 1
		else if(stage == 1)
			attacking_item.play_tool_sound(get_turf(src), 50)
			to_chat(user, "<span class='caution'>You screw in the telepad's tracking beacon.</span>")
			stage = 0
	if(attacking_item.tool_behaviour == TOOL_WELDER && stage == 1)
		playsound(src, 'sound/items/Welder.ogg', 50, 1)
		to_chat(user, "<span class='caution'>You disassemble the telepad.</span>")
		new /obj/item/stack/material/steel(get_turf(src))
		new /obj/item/stack/material/glass(get_turf(src))
		qdel(src)

///TELEPAD CALLER///
/obj/item/telepad_beacon
	name = "telepad beacon"
	desc = "Use to warp in a cargo telepad."
	icon = 'icons/obj/radio.dmi'
	icon_state = "beacon"
	item_state = "signaler"

	origin_tech = list(TECH_BLUESPACE = 3)

/obj/item/telepad_beacon/attack_self(mob/user)
	if(user)
		to_chat(user, "<span class='caution'>Locked In</span>")
		new /obj/structure/machinery/telepad_cargo(user.loc)
		playsound(src, 'sound/effects/pop.ogg', 100, 1, 1)
		qdel(src)
	return

///HANDHELD TELEPAD USER///
/obj/item/rcs
	name = "rapid-crate-sender (RCS)"
	desc = "Use this to send crates and closets to cargo telepads."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "rcs"
	obj_flags = OBJ_FLAG_CONDUCTABLE
	force = 15
	throwforce = 10
	throw_speed = 2
	throw_range = 5
	var/rcharges = 10
	var/obj/structure/machinery/pad = null
	var/last_charge = 30
	var/mode = 0
	var/rand_x = 0
	var/rand_y = 0
	var/emagged = 0
	var/teleporting = 0

/obj/item/rcs/feedback_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "There are [rcharges] charge\s left."

/obj/item/rcs/process()
	if(rcharges > 10)
		rcharges = 10
	if(last_charge == 0)
		rcharges++
		last_charge = 30
	else
		last_charge--

/obj/item/rcs/attack_self(mob/user)
	if(emagged)
		if(mode == 0)
			mode = 1
			playsound(src.loc, 'sound/effects/pop.ogg', 50, 0)
			to_chat(user, "<span class='caution'>The telepad locator has become uncalibrated.</span>")
		else
			mode = 0
			playsound(src.loc, 'sound/effects/pop.ogg', 50, 0)
			to_chat(user, "<span class='caution'>You calibrate the telepad locator.</span>")

/obj/item/rcs/attackby(obj/item/attacking_item, mob/user)
	if (istype(attacking_item, /obj/item/card/emag) && !emagged)
		emagged = 1
		spark(src, 5, GLOB.alldirs)
		to_chat(user, "<span class='caution'>You emag the RCS. Click on it to toggle between modes.</span>")
