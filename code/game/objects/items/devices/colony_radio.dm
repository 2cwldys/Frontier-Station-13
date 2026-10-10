/*
 * Colony Radio -- a player-purchasable (Cargo Order, Operations, 100000cr)
 * consumable that requests founding a "station" away site (the bare 10x10
 * buildable platform template, maps/away/away_site/station/station.dm) at a
 * chosen overmap location. Unlike the admin "Generate Away Site" verb, this
 * never spawns anything directly -- it submits a /datum/colony_radio_request
 * for admin approval. Approved requests found a permanent (reboot-surviving)
 * station; denied requests refund a fresh radio to the requester.
 *
 * The claim declares what the site is FOR: a colony, or a drydock. Both load the
 * same "station" template, so the only difference is the site_kind recorded on
 * the pinned row (AWAY_SITE_KIND_*, code/__DEFINES/persistence.dm) -- a drydock
 * is where ships may be stashed, retrieved and commissioned, which
 * _drydock_site_nearby() (persistence_shuttles.dm) enforces by overmap distance.
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

	var/list/kind_choices = list(
		"Colony" = AWAY_SITE_KIND_COLONY,
		"Drydock" = AWAY_SITE_KIND_DRYDOCK
	)
	var/kind_pick = tgui_input_list(user, "What is this claim for?", "Colony Radio", kind_choices)
	if(isnull(kind_pick))
		return
	var/claim_kind = kind_choices[kind_pick]

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

	var/datum/colony_radio_request/request = new(user, pick_x, pick_y, claim_kind)
	GLOB.colony_radio_requests += request

	to_chat(user, SPAN_NOTICE("You transmit a [claim_kind] claim request for overmap ([pick_x],[pick_y]) to the Hub. Awaiting review."))
	log_game("[key_name(user)] submitted a Colony Radio request for a [claim_kind] at overmap ([pick_x],[pick_y]).")

	var/turf/user_turf = get_turf(user)
	message_admins("[key_name_admin(user)] requested a [claim_kind] station at overmap ([pick_x],[pick_y])[user_turf ? " [ADMIN_JMP(user_turf)]" : ""]. \
		<a href='byond://?src=[REF(request)];colony_radio_approve=1'>APPROVE</a> - \
		<a href='byond://?src=[REF(request)];colony_radio_deny=1'>DENY</a>")

	qdel(src)

GLOBAL_LIST_EMPTY(colony_radio_requests)

/datum/colony_radio_request
	var/requester_ckey
	var/requester_name
	var/pick_x
	var/pick_y
	/// AWAY_SITE_KIND_COLONY or AWAY_SITE_KIND_DRYDOCK -- what the claim is for.
	var/site_kind = AWAY_SITE_KIND_COLONY
	var/requested_at
	var/resolved = FALSE

/datum/colony_radio_request/New(mob/requester, x, y, kind = AWAY_SITE_KIND_COLONY)
	. = ..()
	requester_ckey = requester?.ckey
	requester_name = requester?.real_name
	pick_x = x
	pick_y = y
	site_kind = kind
	requested_at = world.time

/datum/colony_radio_request/proc/describe()
	return "#[REF(src)] -- [requester_name] ([requester_ckey]) requested a [site_kind] at overmap ([pick_x],[pick_y]) [round((world.time - requested_at) / (1 MINUTE))] minute\s ago"

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

	// Deliberately NOT pinned here. Founding a site and making it survive reboots
	// are separate acts: a faction or hub beacon placed on the site is what pins
	// it (persistence_pin_site_at_z(), via the beacon's own network apply), and
	// that proc reads the kind recorded just below rather than being told it.
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[site_z]"]
	var/list/live_zs = (marker && length(marker.map_z)) ? marker.map_z.Copy() : list(site_z)
	for(var/nz in live_zs)
		GLOB.persistence_site_kind_by_z["[nz]"] = site_kind
	if(site_kind == AWAY_SITE_KIND_DRYDOCK)
		apply_drydock_marker_appearance(marker)

	var/mob/requester_mob = _find_requester_mob()
	if(requester_mob)
		to_chat(requester_mob, SPAN_GOOD("The Hub has approved your claim -- your [site_kind] has been founded at overmap ([pick_x],[pick_y])."))
		to_chat(requester_mob, SPAN_NOTICE("It will not survive a reboot until a faction or hub beacon is established on it."))

	log_and_message_admins("approved [site_kind] station request from [requester_name] ([requester_ckey]) at overmap ([pick_x],[pick_y]), z=[site_z]", admin)

/datum/colony_radio_request/proc/deny(mob/admin)
	if(resolved)
		to_chat(admin, SPAN_WARNING("This request was already resolved."))
		return
	resolved = TRUE
	GLOB.colony_radio_requests -= src
	_refund_and_notify("The Hub has denied your colonial claim request.")
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
	set category = "Persistence.Misc"

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
