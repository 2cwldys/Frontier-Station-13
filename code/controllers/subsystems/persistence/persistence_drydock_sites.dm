/*
 * Drydock roster -- the admin-side counterpart to the colony radio.
 *
 * Ships may only be stashed, retrieved or commissioned within one overmap tile of
 * a site founded as a drydock (_drydock_site_nearby(), persistence_shuttles.dm), so
 * a world with no drydock at all is a world where no ship can be put away. This
 * verb is what makes that hard requirement safe to run: it lists what exists,
 * establishes new ones, and retires them.
 *
 * Creating a drydock here PINS it, unlike a colony-radio founding (which leaves
 * pinning to whichever faction beacon eventually claims the site) -- an
 * admin-established drydock exists precisely because someone needs it to still be
 * there after the next reboot.
 */

/datum/admins/proc/view_drydocks()
	set name = "View Drydocks"
	set category = "Persistence.Ships & Drydock"
	set desc = "List, establish, or retire the drydock sites ships may be stashed, retrieved and built at."

	if(!check_rights(R_ADMIN))
		return
	if(!SSatlas.current_map.use_overmap || !SSatlas.current_map.overmap_z)
		to_chat(usr, SPAN_WARNING("This map has no overmap."))
		return

	while(usr && usr.client)
		var/list/drydock_zs = list()
		for(var/dz in GLOB.persistence_site_kind_by_z)
			if(GLOB.persistence_site_kind_by_z[dz] == AWAY_SITE_KIND_DRYDOCK)
				drydock_zs |= text2num(dz)

		var/choice = tgui_input_list(usr, "Drydocks ([length(drydock_zs)] established)[GLOB.drydock_legacy_stashing ? " -- LEGACY STASHING ON" : ""]:", "View Drydocks", \
			list("List Drydocks", "Make This Site A Drydock", "Found New Drydock", "Retire A Drydock", "Jump To A Drydock", "Toggle Legacy Stashing", "Done"))
		if(!choice || choice == "Done")
			return

		switch(choice)
			if("List Drydocks")
				_drydock_roster_list(drydock_zs)

			if("Toggle Legacy Stashing")
				var/turning_on = !GLOB.drydock_legacy_stashing
				if(tgui_alert(usr, turning_on \
					? "Turn legacy stashing ON? Ships will stop needing a drydock and fall back to the old secured-beacon rule, and drydock access policy will be ignored entirely. Resets to OFF on reboot." \
					: "Turn legacy stashing OFF? Ships will require a drydock again.", \
					"View Drydocks", list(turning_on ? "Turn On" : "Turn Off", "Cancel")) == "Cancel")
					continue
				GLOB.drydock_legacy_stashing = turning_on
				to_chat(usr, SPAN_GOOD("Legacy stashing is now [GLOB.drydock_legacy_stashing ? "ON -- drydocks are not required" : "OFF -- drydocks are required"]."))
				log_and_message_admins("turned legacy ship stashing [GLOB.drydock_legacy_stashing ? "ON (drydock requirement bypassed)" : "OFF (drydock requirement restored)"]", usr)

			if("Make This Site A Drydock")
				var/here_z = usr.z
				if(drydock_z_is_drydock(here_z))
					to_chat(usr, SPAN_WARNING("This site is already a drydock."))
					continue
				var/datum/map_template/here_template = GLOB.map_templates["[here_z]"]
				if(!istype(here_template, /datum/map_template/ruin/away_site))
					to_chat(usr, SPAN_WARNING("z=[here_z] isn't an away site -- stand on one first (Generate Away Site can place a bare 'station' platform)."))
					continue
				// Returns FALSE when the site was already pinned for some other
				// reason, in which case only the kind still needs changing.
				if(!persistence_pin_site_at_z(here_z, "Admin-established drydock", AWAY_SITE_KIND_DRYDOCK))
					persistence_set_site_kind(here_z, AWAY_SITE_KIND_DRYDOCK)
				to_chat(usr, SPAN_GOOD("z=[here_z] is now a drydock."))
				log_and_message_admins("marked the away site at z=[here_z] as a drydock", usr)

			if("Found New Drydock")
				_drydock_roster_found_new()

			if("Retire A Drydock")
				if(!length(drydock_zs))
					to_chat(usr, SPAN_WARNING("No drydocks established."))
					continue
				var/list/retire_choices = list()
				for(var/dz in drydock_zs)
					retire_choices[_drydock_roster_label(dz)] = dz
				var/retire_pick = tgui_input_list(usr, "Retire which drydock? The site itself stays, it just stops accepting ships.", "View Drydocks", retire_choices)
				if(!retire_pick)
					continue
				var/retire_z = retire_choices[retire_pick]
				if(tgui_alert(usr, "Retire the drydock at z=[retire_z]? Ships can no longer be stashed, retrieved or built there.", "View Drydocks", list("Retire", "Cancel")) != "Retire")
					continue
				persistence_set_site_kind(retire_z, AWAY_SITE_KIND_SIMULATED)
				to_chat(usr, SPAN_GOOD("z=[retire_z] is no longer a drydock."))
				log_and_message_admins("retired the drydock at z=[retire_z]", usr)

			if("Jump To A Drydock")
				if(!length(drydock_zs))
					to_chat(usr, SPAN_WARNING("No drydocks established."))
					continue
				var/list/jump_choices = list()
				for(var/dz in drydock_zs)
					var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[dz]"]
					if(marker)
						jump_choices[_drydock_roster_label(dz)] = marker
				if(!length(jump_choices))
					to_chat(usr, SPAN_WARNING("No drydock has a resolvable overmap marker."))
					continue
				var/jump_pick = tgui_input_list(usr, "Jump to which drydock's overmap tile?", "View Drydocks", jump_choices)
				if(!jump_pick)
					continue
				var/obj/effect/overmap/visitable/jump_marker = jump_choices[jump_pick]
				var/turf/dest = get_turf(jump_marker)
				if(!dest)
					to_chat(usr, SPAN_WARNING("That marker isn't on a turf right now."))
					continue
				usr.forceMove(dest)

/// One drydock's identity for a pick list: its z, its marker's name, and where on
/// the overmap it sits.
/proc/_drydock_roster_label(z)
	var/obj/effect/overmap/visitable/marker = GLOB.map_sectors["[z]"]
	if(!marker)
		return "z=[z] -- no overmap marker"
	return "z=[z] -- [marker.name] ([marker.x],[marker.y])"

/// Prints the roster, including who governs each drydock's access policy and
/// whether it will actually still be there next boot.
/proc/_drydock_roster_list(list/drydock_zs)
	if(!length(drydock_zs))
		to_chat(usr, SPAN_WARNING("No drydocks established -- no ship can be stashed, retrieved or commissioned anywhere."))
		return
	to_chat(usr, SPAN_NOTICE("<b>Established drydocks:</b>"))
	for(var/dz in drydock_zs)
		var/list/governing = drydock_policy_for_z(dz)
		var/gov_uid = governing["faction_uid"]
		var/governed_by = gov_uid ? "[get_faction_name(gov_uid)]" : "ungoverned"
		var/pinned_note = (dz in GLOB.persistence_pinned_site_z) ? "" : " -- NOT PINNED, will not survive a reboot"
		to_chat(usr, SPAN_NOTICE("[_drydock_roster_label(dz)] -- access '[governing["policy"]]' ([governed_by])[pinned_note]"))

/// Spawns a fresh "station" platform at a chosen overmap tile and establishes it as
/// a drydock. Mirrors the colony radio's approval path, minus the request/refund
/// round trip, and pins it as described in this file's header.
/proc/_drydock_roster_found_new()
	var/map_low = OVERMAP_EDGE
	var/map_high = SSatlas.current_map.overmap_size - OVERMAP_EDGE
	var/pick_x = tgui_input_number(usr, "Overmap X ([map_low]-[map_high]):", "View Drydocks", map_low, map_high, map_low)
	if(isnull(pick_x))
		return
	var/pick_y = tgui_input_number(usr, "Overmap Y ([map_low]-[map_high]):", "View Drydocks", map_low, map_high, map_low)
	if(isnull(pick_y))
		return
	pick_x = clamp(pick_x, map_low, map_high)
	pick_y = clamp(pick_y, map_low, map_high)

	var/turf/target_tile = locate(pick_x, pick_y, SSatlas.current_map.overmap_z)
	if(!target_tile)
		to_chat(usr, SPAN_WARNING("No overmap tile at ([pick_x],[pick_y])."))
		return
	var/obj/effect/overmap/visitable/occupant = locate() in target_tile
	if(occupant)
		to_chat(usr, SPAN_WARNING("([pick_x],[pick_y]) is already occupied by '[occupant.name]' -- pick another tile."))
		return

	var/datum/map_template/ruin/away_site/station_site = SSmapping.away_sites_templates["station"]
	if(!station_site)
		to_chat(usr, SPAN_WARNING("The 'station' template no longer exists -- cannot found a drydock."))
		return
	var/site_z = _spawn_away_site_for_template(station_site, target_tile)
	if(!site_z)
		to_chat(usr, SPAN_WARNING("Failed to load the station template."))
		return

	persistence_pin_site_at_z(site_z, "Admin-established drydock", AWAY_SITE_KIND_DRYDOCK)
	to_chat(usr, SPAN_GOOD("Founded a drydock at overmap ([pick_x],[pick_y]), z=[site_z]."))
	log_and_message_admins("founded a drydock at overmap ([pick_x],[pick_y]), z=[site_z]", usr)
