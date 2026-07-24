/*
 * Colony Radio -- a player-purchasable (Cargo Order, Operations, 100000cr)
 * consumable that requests founding a "station" away site (the bare 10x10
 * buildable platform template, maps/away/away_site/station/station.dm) at a
 * chosen overmap location. Unlike the admin "Generate Away Site" verb, this
 * never spawns anything directly -- it submits a /datum/colony_radio_request
 * for admin approval. Approved requests found a permanent (reboot-surviving)
 * station; denied requests refund a fresh radio to the requester.
 */
/obj/item/colony_radio
	name = "colony radio"
	desc = "A modified beacon transponder that broadcasts a colonial land claim to the Hub authority for review. Consumed when used."
	icon = 'icons/obj/radio.dmi'
	icon_state = "radio" // same disguise sprite /obj/item/radio/uplink uses
	w_class = WEIGHT_CLASS_SMALL

/obj/item/colony_radio/attack_self(mob/user)
	if(!SSatlas.current_map.overmap_z)
		to_chat(user, SPAN_WARNING("This map has no overmap."))
		return

	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
	var/pick_x = tgui_input_number(user, "Overmap X ([map_low]-[map_high]):", "Colony Radio", map_low, map_high, map_low)
	if(isnull(pick_x))
		return
	var/pick_y = tgui_input_number(user, "Overmap Y ([map_low]-[map_high]):", "Colony Radio", map_low, map_high, map_low)
	if(isnull(pick_y))
		return
	pick_x = clamp(pick_x, map_low, map_high)
	pick_y = clamp(pick_y, map_low, map_high)

	var/turf/target_tile = locate(pick_x, pick_y, SSatlas.current_map.overmap_z)
	if(!target_tile)
		to_chat(user, SPAN_WARNING("No overmap tile at ([pick_x],[pick_y])."))
		return
	var/obj/effect/overmap/visitable/occupant = locate() in target_tile
	if(occupant)
		to_chat(user, SPAN_WARNING("([pick_x],[pick_y]) is already occupied by '[occupant.name]' -- pick another tile."))
		return

	var/datum/colony_radio_request/request = new(user, pick_x, pick_y)
	GLOB.colony_radio_requests += request

	to_chat(user, SPAN_NOTICE("You transmit a colonial claim request for overmap ([pick_x],[pick_y]) to Central Command. Awaiting review."))
	log_game("[key_name(user)] submitted a Colony Radio request for overmap ([pick_x],[pick_y]).")

	var/turf/user_turf = get_turf(user)
	message_admins("[key_name_admin(user)] requested a colony station at overmap ([pick_x],[pick_y])[user_turf ? " [ADMIN_JMP(user_turf)]" : ""]. \
		<a href='byond://?src=[REF(request)];colony_radio_approve=1'>APPROVE</a> - \
		<a href='byond://?src=[REF(request)];colony_radio_deny=1'>DENY</a>")

	qdel(src)

GLOBAL_LIST_EMPTY(colony_radio_requests)

/datum/colony_radio_request
	var/requester_ckey
	var/requester_name
	var/pick_x
	var/pick_y
	var/requested_at
	var/resolved = FALSE

/datum/colony_radio_request/New(mob/requester, x, y)
	. = ..()
	requester_ckey = requester?.ckey
	requester_name = requester?.real_name
	pick_x = x
	pick_y = y
	requested_at = world.time

/datum/colony_radio_request/proc/describe()
	return "#[REF(src)] -- [requester_name] ([requester_ckey]) requested overmap ([pick_x],[pick_y]) [round((world.time - requested_at) / (1 MINUTE))] minute\s ago"

/datum/colony_radio_request/Topic(href, href_list)
	. = ..()
	if(!check_rights(R_ADMIN))
		return
	if(href_list["colony_radio_approve"])
		approve(usr)
	else if(href_list["colony_radio_deny"])
		deny(usr)

/// Finds the requester's current mob, if still connected/alive in the world.
/datum/colony_radio_request/proc/_find_requester_mob()
	for(var/mob/M in GLOB.player_list)
		if(M.ckey == requester_ckey)
			return M
	return null

/datum/colony_radio_request/proc/approve(mob/admin)
	if(resolved)
		to_chat(admin, SPAN_WARNING("This request was already resolved."))
		return
	resolved = TRUE
	GLOB.colony_radio_requests -= src

	var/turf/target_tile = locate(pick_x, pick_y, SSatlas.current_map.overmap_z)
	var/obj/effect/overmap/visitable/occupant = target_tile ? (locate() in target_tile) : null
	if(!target_tile || occupant)
		to_chat(admin, SPAN_WARNING("([pick_x],[pick_y]) is no longer free[occupant ? " -- occupied by '[occupant.name]'" : ""] -- denying and refunding instead."))
		_refund_and_notify("Your requested location is no longer available.")
		return

	var/datum/map_template/ruin/away_site/station_site = SSmapping.away_sites_templates["station"]
	if(!station_site)
		to_chat(admin, SPAN_WARNING("The 'station' template no longer exists -- cannot approve."))
		_refund_and_notify("The station template is currently unavailable.")
		return

	var/site_z = _spawn_away_site_for_template(station_site, target_tile)
	if(!site_z)
		to_chat(admin, SPAN_WARNING("Failed to load the station template -- denying and refunding instead."))
		_refund_and_notify("Your station could not be constructed.")
		return

	// Pin it so it survives reboots, mirroring the admin "Pin Site I'm At"
	// insert (persistence_factions.dm) but without that flow's single-
	// instance-per-template guard -- the schema now allows many rows for
	// "station" as long as their coordinates differ.
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[site_z]"]
	var/list/live_zs = (marker && length(marker.map_z)) ? marker.map_z.Copy() : list(site_z)
	if(GLOB.config.sql_enabled && SSdbcore.Connect())
		var/datum/db_query/iq = SSdbcore.NewQuery(
			{"INSERT INTO ss13_persistent_away_sites (template_name, map_path, overmap_x, overmap_y, last_z, enabled, notes)
			VALUES (:tn, :mp, :ox, :oy, :z, 1, :notes)"},
			list(
				"tn" = "station",
				"mp" = "[SSatlas.current_map.path]",
				"ox" = pick_x,
				"oy" = pick_y,
				"z"  = site_z,
				"notes" = "Founded by [requester_name] ([requester_ckey])"
			)
		)
		iq.Execute()
		SSpersistence.databaseCheckQueryResult(iq, "colony_radio_request pin")
		qdel(iq)
	for(var/nz in live_zs)
		GLOB.persistence_pinned_site_z |= nz
		GLOB.persistence_zlevel_allow |= nz

	var/mob/requester_mob = _find_requester_mob()
	if(requester_mob)
		to_chat(requester_mob, SPAN_GOOD("Central Command has approved your colonial claim -- your station has been founded at overmap ([pick_x],[pick_y])."))

	log_and_message_admins("approved colony station request from [requester_name] ([requester_ckey]) at overmap ([pick_x],[pick_y]), z=[site_z]", admin)

/datum/colony_radio_request/proc/deny(mob/admin)
	if(resolved)
		to_chat(admin, SPAN_WARNING("This request was already resolved."))
		return
	resolved = TRUE
	GLOB.colony_radio_requests -= src
	_refund_and_notify("Central Command has denied your colonial claim request.")
	log_and_message_admins("denied colony station request from [requester_name] ([requester_ckey]) at overmap ([pick_x],[pick_y])", admin)

/// Shared refund path for both an explicit deny and an approve that failed
/// after all -- mints a fresh radio at the requester's feet if they're still
/// in the world, otherwise logs it for an admin to hand-deliver.
/datum/colony_radio_request/proc/_refund_and_notify(message)
	var/mob/requester_mob = _find_requester_mob()
	if(requester_mob)
		var/turf/requester_turf = get_turf(requester_mob)
		if(requester_turf)
			new /obj/item/colony_radio(requester_turf)
		to_chat(requester_mob, SPAN_WARNING("[message] Your colony radio has been refunded."))
	else
		log_admin("Colony Radio: could not deliver refund to [requester_name] ([requester_ckey]) -- not found in world. Manual delivery needed.")

/datum/admins/proc/review_colony_radio_requests()
	set name = "Review Colony Radio Requests"
	set category = "Persistence"

	if(!check_rights(R_ADMIN))
		return
	if(!length(GLOB.colony_radio_requests))
		to_chat(usr, SPAN_NOTICE("No pending colony radio requests."))
		return

	var/list/choices = list()
	for(var/datum/colony_radio_request/request in GLOB.colony_radio_requests)
		choices[request.describe()] = request

	var/pick = tgui_input_list(usr, "Select a request to review:", "Colony Radio Requests", choices)
	if(!pick)
		return
	var/datum/colony_radio_request/request = choices[pick]
	if(!request || request.resolved)
		return

	var/action = tgui_input_list(usr, "Overmap ([request.pick_x],[request.pick_y]) requested by [request.requester_name]:", "Colony Radio Requests", list("Approve", "Deny", "Cancel"))
	if(action == "Approve")
		request.approve(usr)
	else if(action == "Deny")
		request.deny(usr)
