/*
 * First Responder -- Hub security rapid-response teleportation.
 * Lists recent highsec offenses (fed by zone_security_record_offense) and
 * lets accredited security jump near the offender through a brief fading
 * bluespace portal, then return to their faction's security telepad.
 *
 * Gating: RESPOND requires the host computer to be on the "Hub" faction
 * network (Hub law -- other factions cannot use the jump to raid) plus
 * ACCESS_SECURITY. RETURN works for the computer's own network: it finds a
 * security telepad linked to that faction (factions may install their own
 * pad for the return leg).
 */

#define FIRST_RESPONDER_COOLDOWN 30 SECONDS
#define FIRST_RESPONDER_OFFENSE_MAX_AGE 15 MINUTES

/datum/computer_file/program/security/first_responder
	filename = "firstresponder"
	filedesc = "First Responder"
	program_icon_state = "security"
	program_key_icon_state = "red_key"
	extended_desc = "Hub security rapid-response system. Alerts accredited responders to highsec offenses and opens short-lived bluespace portals to the scene, with a return link to the faction's security telepad. Anyone can also send a distress call to Hub security from a highsec zone."
	// Open to everyone -- privileged actions (respond/return/prisoner tagging)
	// are gated per-action via can_run() below instead, so civilians can still
	// download and open this to send a distress call.
	required_access_run = null
	required_access_download = null
	usage_flags = PROGRAM_CONSOLE | PROGRAM_LAPTOP | PROGRAM_TABLET
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	// Small enough to fit a stock PDA drive alongside the factory programs --
	// at 8, persistence restores failed with "hard drive full" (log-diagnosed)
	size = 3
	color = LIGHT_COLOR_RED
	tgui_id = "FirstResponder"
	ui_auto_update = TRUE

	var/next_jump_time = 0
	/// Weakrefs to apprehended mobs tagged for transport on the next Return
	var/list/tagged_prisoners = list()
	/// What tapping a mob with the device does -- "tag" (prisoner transport
	/// tag, the original behavior) or "repossess" (force-stash AND seize
	/// ownership for the Hub). "repossess" requires a Hub-network terminal
	/// (set_tap_mode below refuses to switch into it otherwise); "tag" stays
	/// available on any network at any rank. Force-stashing any deployed ship
	/// (no seizure) and scuttling an already-repossessed ship are both
	/// console actions instead ("force_stash_picker"/"scuttle_repossessed"
	/// below) -- neither needs a physical target to tap.
	var/tap_mode = "tag"

#define FIRST_RESPONDER_MAX_PRISONERS 4
/// Prisoners must be within this range of the responder when Return fires
#define FIRST_RESPONDER_TRANSPORT_RANGE 2

/datum/computer_file/program/security/first_responder/ui_data(mob/user)
	var/list/data = initial_data()
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""

	data["faction_uid"]  = net
	data["faction_name"] = net ? get_faction_name(net) : null
	data["is_hub"]       = (net == "hub")
	var/list/telepads = net ? persistence_find_security_telepads(net) : list()
	data["has_telepad"]  = length(telepads) > 0
	data["telepad_choices"] = list()
	if(length(telepads) > 1)
		for(var/obj/structure/machinery/telepad_security/pad in telepads)
			var/area/A = get_area(pad)
			data["telepad_choices"] += list(list(
				"ref" = "\ref[pad]",
				"area_name" = A ? A.name : "Unknown Area"
			))
	data["cooldown"]     = max(0, round((next_jump_time - world.time) / 10))
	data["can_secure"]   = can_run(user, FALSE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE)
	data["in_highsec"]   = (zone_security_get(user.z) == ZONE_HIGHSEC)
	data["tap_mode"]     = tap_mode
	data["can_scuttle_ships"] = (net == "hub") && can_configure_faction_shackle(user, "hub", 1)

	// Ships the Hub has repossessed -- visible from any Hub terminal so any
	// hub member can hand one back. "Retrieve as Hub" needs no extra UI here:
	// faction_uid = "hub" already makes it show up in the ordinary Drydock
	// program's own ship list for any hub security member.
	var/list/repossessed_ships = list()
	if(net == "hub")
		for(var/sid in GLOB.drydock_ships)
			var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
			if(DS && DS.repossessed)
				repossessed_ships += list(list("shuttle_id" = DS.shuttle_id, "display_name" = DS.display_name()))
	data["repossessed_ships"] = repossessed_ships
	var/last_distress = user.ckey ? GLOB.hub_distress_last_called[user.ckey] : null
	data["distress_cooldown"] = last_distress ? max(0, round((last_distress + DISTRESS_CALL_COOLDOWN - world.time) / 10)) : 0

	// Prisoners tagged for transport on the next Return
	var/list/tagged = list()
	var/turf/here = get_turf(computer)
	for(var/datum/weakref/pwr in tagged_prisoners)
		var/mob/living/prisoner = pwr.resolve()
		if(QDELETED(prisoner))
			continue
		tagged += list(list(
			"ref"        = "\ref[pwr]",
			"name"       = prisoner.name,
			"restrained" = !!prisoner.restrained(),
			"in_range"   = (here && get_dist(here, get_turf(prisoner)) <= FIRST_RESPONDER_TRANSPORT_RANGE)
		))
	data["tagged"] = tagged

	// Recent highsec offenses, newest first, pruned by age
	var/list/offenses = list()
	for(var/i = length(GLOB.highsec_offense_log) to 1 step -1)
		var/list/entry = GLOB.highsec_offense_log[i]
		if(world.time - entry["time"] > FIRST_RESPONDER_OFFENSE_MAX_AGE)
			continue
		var/datum/weakref/wr = entry["ref"]
		var/mob/offender = wr ? wr.resolve() : null
		// Live-checked, not cached at record time -- zone tiers can change
		// (beacon claim/loss, admin toggle) between when this was logged and
		// when a responder actually looks at the list.
		var/is_highsec = (zone_security_get(entry["z"]) == ZONE_HIGHSEC)
		offenses += list(list(
			"index"       = i,
			"name"        = entry["name"],
			"age"         = "[round((world.time - entry["time"]) / (1 MINUTE))] min ago",
			"tracked"     = !QDELETED(offender) && offender.z,
			"type"        = entry["type"] || "offense",
			"can_jump"    = is_highsec,
			"sector_info" = is_highsec ? null : zone_security_overmap_location(entry["z"])
		))
	data["offenses"] = offenses

	return data

/datum/computer_file/program/security/first_responder/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return

	var/mob/user = usr
	if(!istype(user) || !computer)
		return

	switch(action)
		if("distress")
			if(zone_security_get(user.z) != ZONE_HIGHSEC)
				to_chat(user, SPAN_WARNING("No response -- Hub law is only enforced in highsec zones."))
				return TRUE
			if(!zone_security_record_distress(user))
				to_chat(user, SPAN_WARNING("You've already sent a distress call recently."))
				return TRUE
			to_chat(user, SPAN_NOTICE("Distress call sent -- Hub security has been notified of your location."))
			playsound(get_turf(computer), 'sound/machines/twobeep.ogg', 30, 1)
			return TRUE

		if("respond")
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			var/net = normalize_faction_uid(computer.persistent_network)
			if(net != "hub")
				to_chat(user, SPAN_WARNING("Response jumps require a Hub-network terminal."))
				return TRUE
			if(world.time < next_jump_time)
				to_chat(user, SPAN_WARNING("Teleporter recharging."))
				return TRUE
			var/index = text2num(params["index"])
			if(!index || index < 1 || index > length(GLOB.highsec_offense_log))
				to_chat(user, SPAN_WARNING("Offense record no longer available."))
				return TRUE
			var/list/entry = GLOB.highsec_offense_log[index]
			// Always the recorded crime SITE -- secure the scene, don't chase
			// wherever the offender may have wandered off to since.
			var/turf/target_turf = locate(entry["x"], entry["y"], entry["z"])
			if(!target_turf)
				to_chat(user, SPAN_WARNING("Cannot resolve the offense location."))
				return TRUE
			// Server-side re-check, not just trusting the client's can_jump --
			// offenses/distress calls are only ever recorded in highsec to
			// begin with, but emergencies can be logged anywhere; the portal
			// itself stays Hub-jurisdiction-only regardless of entry type.
			if(zone_security_get(target_turf.z) != ZONE_HIGHSEC)
				to_chat(user, SPAN_WARNING("Outside Hub jurisdiction -- no portal access. Travel there yourself."))
				return TRUE
			var/turf/dest = first_responder_clear_turf_near(target_turf)
			if(!dest)
				to_chat(user, SPAN_WARNING("No safe arrival point near the scene."))
				return TRUE
			first_responder_jump(user, dest)
			log_game("[key_name(user)] used First Responder to jump to offense by '[entry["name"]]' at ([dest.x],[dest.y],[dest.z]).")
			message_admins("[key_name_admin(user)] used First Responder to jump to a highsec offense by '[entry["name"]]' (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[dest.x];Y=[dest.y];Z=[dest.z]'>JMP</a>)")
			return TRUE

		if("return")
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			if(world.time < next_jump_time)
				to_chat(user, SPAN_WARNING("Teleporter recharging."))
				return TRUE
			var/net = normalize_faction_uid(computer.persistent_network)
			var/list/pads = persistence_find_security_telepads(net)
			if(!length(pads))
				to_chat(user, SPAN_WARNING("No security telepad found for [net ? get_faction_name(net) : "this network"]."))
				return TRUE
			var/obj/structure/machinery/telepad_security/chosen
			if(length(pads) == 1)
				chosen = pads[1]
			else
				var/target_ref = params["pad_ref"]
				for(var/obj/structure/machinery/telepad_security/pad in pads)
					if("\ref[pad]" == target_ref)
						chosen = pad
						break
				if(!chosen)
					to_chat(user, SPAN_WARNING("Select a destination telepad first."))
					return TRUE
			var/turf/pad_turf = get_turf(chosen)
			var/turf/departure = get_turf(user)
			first_responder_jump(user, pad_turf)
			// Bring tagged prisoners still within range of the departure point
			var/left_behind = 0
			for(var/datum/weakref/pwr in tagged_prisoners)
				var/mob/living/prisoner = pwr.resolve()
				if(QDELETED(prisoner) || !departure || get_dist(departure, get_turf(prisoner)) > FIRST_RESPONDER_TRANSPORT_RANGE)
					left_behind++
					continue
				var/turf/spot = first_responder_clear_turf_near(pad_turf)
				first_responder_jump(prisoner, spot || pad_turf, arm_cooldown = FALSE)
				log_game("[key_name(user)]'s First Responder transported prisoner [key_name(prisoner)] to the security telepad.")
			tagged_prisoners.Cut()
			if(left_behind)
				to_chat(user, SPAN_WARNING("[left_behind] transport tag\s out of range -- dropped."))
			log_game("[key_name(user)] used First Responder to return to the security telepad at ([pad_turf.x],[pad_turf.y],[pad_turf.z]).")
			return TRUE

		if("untag")
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			var/target_ref = params["ref"]
			for(var/datum/weakref/pwr in tagged_prisoners)
				if("\ref[pwr]" == target_ref)
					tagged_prisoners -= pwr
					return TRUE
			return TRUE

		if("set_tap_mode")
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			var/mode = params["mode"]
			if(!(mode in list("tag", "repossess")))
				return TRUE
			if(mode == "repossess" && normalize_faction_uid(computer.persistent_network) != "hub")
				to_chat(user, SPAN_WARNING("Ship seizure requires a Hub-network terminal."))
				return TRUE
			tap_mode = mode
			return TRUE

		if("force_stash_picker")
			// Console action, not a tap -- picks a currently-deployed,
			// already-repossessed ship from a list (same tgui_input_list
			// pattern as the admin "Force Stash Ship" verb,
			// persistence_shuttles.dm), so a Hub officer can recall a Hub
			// asset that's out and about without needing to physically find
			// and tap anyone. Deliberately scoped to repossessed ships only,
			// not every deployed ship server-wide.
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			if(normalize_faction_uid(computer.persistent_network) != "hub")
				to_chat(user, SPAN_WARNING("Ship seizure requires a Hub-network terminal."))
				return TRUE
			var/list/options = list()
			for(var/sid in GLOB.drydock_ships)
				var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
				if(DS && !DS.stashed && DS.repossessed)
					options["[DS.display_name()] (#[DS.shuttle_id], [DS.faction_uid ? "faction [DS.faction_uid]" : "owner [DS.owner_ckey]"])"] = sid
			if(!length(options))
				to_chat(user, SPAN_WARNING("No deployed repossessed ships found."))
				return TRUE
			var/pick = tgui_input_list(user, "Force-stash which ship?", "Force Stash Ship", options)
			if(!pick || !(pick in options))
				return TRUE
			var/shuttle_id = options[pick]
			var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
			if(!DS)
				return TRUE
			var/ship_name = DS.display_name()
			if(SSpersistence.drydockStash(shuttle_id, user, force = TRUE))
				to_chat(user, SPAN_GOOD("[ship_name] forcibly stashed."))
				log_and_message_admins("[key_name(user)] force-stashed [ship_name] (#[shuttle_id]) via First Responder", user)
			else
				to_chat(user, SPAN_WARNING("Failed to stash [ship_name]."))
			return TRUE

		if("return_to_owner")
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			if(normalize_faction_uid(computer.persistent_network) != "hub")
				to_chat(user, SPAN_WARNING("Requires a Hub-network terminal."))
				return TRUE
			var/shuttle_id = text2num(params["shuttle_id"])
			if(!shuttle_id)
				return TRUE
			if(SSpersistence.drydockReturnToOwner(shuttle_id, user))
				to_chat(user, SPAN_GOOD("Ship returned to its original owner."))
				log_and_message_admins("[key_name(user)] returned repossessed ship shuttle_id=[shuttle_id] to its original owner via First Responder", user)
			else
				to_chat(user, SPAN_WARNING("Failed to return ship -- it may not be repossessed."))
			return TRUE

		if("scuttle_repossessed")
			// Console action, not a tap -- a repossessed ship is always
			// stashed (drydockRepossess() runs after a force-stash) and its
			// owner_ckey is cleared, so handle_ship_seizure_tap()'s
			// _find_owned_deployed_ship() can never find it again by tapping
			// anyone. It's already fully a Hub asset at this point, so
			// scuttling it is a console action on the Repossessed Ships list
			// like Return to Owner, not a field enforcement tap.
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			if(normalize_faction_uid(computer.persistent_network) != "hub")
				to_chat(user, SPAN_WARNING("Requires a Hub-network terminal."))
				return TRUE
			if(!can_configure_faction_shackle(user, "hub", 1))
				to_chat(user, SPAN_WARNING("Scuttling a repossessed ship requires officer rank or higher in the Hub."))
				return TRUE
			var/shuttle_id = text2num(params["shuttle_id"])
			if(!shuttle_id)
				return TRUE
			var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
			if(!DS || !DS.repossessed)
				to_chat(user, SPAN_WARNING("That ship is no longer repossessed."))
				return TRUE
			var/ship_name = DS.display_name()
			if(SSpersistence.drydockScuttle(shuttle_id, user, hub_authority = TRUE))
				to_chat(user, SPAN_GOOD("[ship_name] scuttled by Hub authority."))
				log_and_message_admins("[key_name(user)] scuttled repossessed ship [ship_name] (#[shuttle_id]) via First Responder (Hub officer authority)", user)
			else
				to_chat(user, SPAN_WARNING("Failed to scuttle [ship_name]."))
			return TRUE

		if("withdraw_schematic")
			// Lets a Hub officer physically withdraw a still-repossessed
			// ship's schematic in person -- e.g. to look it over, or hand it
			// straight back to the owner as part of processing a return --
			// instead of sending them off to find a Drydock console, whose
			// own withdraw_schematic (drydock.dm) still refuses while
			// repossessed. Same officer-rank gate as scuttle_repossessed.
			if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
				return TRUE
			if(normalize_faction_uid(computer.persistent_network) != "hub")
				to_chat(user, SPAN_WARNING("Requires a Hub-network terminal."))
				return TRUE
			if(!can_configure_faction_shackle(user, "hub", 1))
				to_chat(user, SPAN_WARNING("Withdrawing a repossessed ship's schematic requires officer rank or higher in the Hub."))
				return TRUE
			var/shuttle_id = text2num(params["shuttle_id"])
			if(!shuttle_id)
				return TRUE
			var/datum/drydock_ship/DS = GLOB.drydock_ships["[shuttle_id]"]
			if(!DS || !DS.repossessed)
				to_chat(user, SPAN_WARNING("That ship is no longer repossessed."))
				return TRUE
			var/ship_name = DS.display_name()
			if(SSpersistence.drydockWithdrawSchematic(shuttle_id, user, hub_authority = TRUE))
				log_and_message_admins("[key_name(user)] withdrew the schematic for repossessed ship [ship_name] (#[shuttle_id]) via First Responder (Hub officer authority)", user)
			else
				to_chat(user, SPAN_WARNING("Failed to withdraw the schematic for [ship_name]."))
			return TRUE

/// Finds a passable turf adjacent to the target (the target itself as a
/// last resort). Skips dense turfs and turfs holding dense anchored objects.
/datum/computer_file/program/security/first_responder/proc/first_responder_clear_turf_near(turf/target)
	var/list/candidates = list()
	for(var/check_dir in GLOB.alldirs)
		var/turf/T = get_step(target, check_dir)
		if(!T || T.density)
			continue
		var/blocked = FALSE
		for(var/obj/O in T)
			if(O.density && O.anchored)
				blocked = TRUE
				break
		if(!blocked)
			candidates += T
	if(length(candidates))
		return pick(candidates)
	if(!target.density)
		return target
	return null

/// Teleports a mob with a brief fading bluespace portal, sparks, and sound
/// at BOTH ends (the departure portal sells the "they've left" moment).
/// arm_cooldown is FALSE for prisoner transports riding a responder's jump.
/datum/computer_file/program/security/first_responder/proc/first_responder_jump(mob/M, turf/dest, arm_cooldown = TRUE)
	var/turf/origin = get_turf(M)
	if(origin)
		new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
		playsound(origin, 'sound/effects/phasein.ogg', 50, 1)
	new /obj/effect/portal/decorative/fading(dest, null, null, 5 SECONDS, 0)
	spark(dest, 3, GLOB.alldirs)
	// forceMove, NOT do_teleport: the science teleport datum scatters anyone
	// carrying a bag of holding up to 100 tiles (teleport.dm setPrecision) --
	// responders would land in open space. We supply our own effects anyway.
	M.forceMove(dest)
	playsound(dest, 'sound/effects/phasein.ogg', 50, 1)
	if(arm_cooldown)
		next_jump_time = world.time + FIRST_RESPONDER_COOLDOWN

/// Toggle a transport tag on an apprehended mob (tap them with the device
/// while First Responder is the active program). Requires the target to be
/// restrained, unconscious, or dead.
/datum/computer_file/program/security/first_responder/proc/toggle_prisoner_tag(mob/living/target, mob/user)
	if(!istype(target))
		return
	if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
		return
	// Untag if already tagged
	for(var/datum/weakref/pwr in tagged_prisoners)
		if(pwr.resolve() == target)
			tagged_prisoners -= pwr
			user.visible_message(SPAN_NOTICE("[user] waves [computer] over [target], clearing a transport tag."), SPAN_NOTICE("You clear the transport tag on [target]."))
			return
	if(!target.restrained() && target.stat == CONSCIOUS)
		to_chat(user, SPAN_WARNING("[target] is not apprehended -- they must be restrained or incapacitated to tag them for transport."))
		return
	if(length(tagged_prisoners) >= FIRST_RESPONDER_MAX_PRISONERS)
		to_chat(user, SPAN_WARNING("Transport tag limit reached ([FIRST_RESPONDER_MAX_PRISONERS])."))
		return
	tagged_prisoners += WEAKREF(target)
	user.visible_message(SPAN_NOTICE("[user] waves [computer] over [target], tagging [target] for transport."), SPAN_NOTICE("You tag [target] for transport -- they will be teleported with you on Return."))
	playsound(get_turf(computer), 'sound/machines/twobeep.ogg', 30, 1)

/// Finds the deployed drydock ship personally owned by target, if any.
/datum/computer_file/program/security/first_responder/proc/_find_owned_deployed_ship(mob/target)
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(DS && !DS.stashed && DS.owned_by(target))
			return DS
	return null

/// Every deployed vessel personally owned by target -- since a player may now
/// have both a ship AND a shuttle deployed at once (the category-aware deploy
/// limit, persistence_shuttles.dm), the seizure tap must offer a choice
/// instead of grabbing whichever the singular finder above happened to hit
/// first. Personal ownership only (owned_by()), same as always -- faction
/// ships are never seized this way.
/datum/computer_file/program/security/first_responder/proc/_find_owned_deployed_ships(mob/target)
	. = list()
	for(var/sid in GLOB.drydock_ships)
		var/datum/drydock_ship/DS = GLOB.drydock_ships[sid]
		if(DS && !DS.stashed && DS.owned_by(target))
			. += DS

/// Shared force-stash + repossess + notify tail, used by both the single-
/// vessel and the picker paths of handle_ship_seizure_tap() below, plus
/// handle_ship_seizure_tap_item()'s direct-schematic-tap path. target is
/// null when the schematic that was tapped wasn't sitting in anyone's
/// inventory (dropped on the ground, stored in a container, etc).
/datum/computer_file/program/security/first_responder/proc/_seize_deployed_vessel(datum/drydock_ship/DS, mob/target, mob/user)
	if(!SSpersistence.drydockStash(DS.shuttle_id, user, force = TRUE))
		to_chat(user, SPAN_WARNING("Failed to stash [DS.display_name()]."))
		return
	SSpersistence.drydockRepossess(DS.shuttle_id, user)
	to_chat(user, SPAN_GOOD("[DS.display_name()] stashed and repossessed by the Hub."))
	if(target)
		log_and_message_admins("[key_name(user)] repossessed [target]'s ship [DS.display_name()] via First Responder", user)
	else
		log_and_message_admins("[key_name(user)] repossessed [DS.display_name()] via First Responder (schematic tapped directly)", user)

/// Tap handler for tap_mode == "stash"/"repossess" (interaction.dm's
/// modular_computer/attack() branches here instead of toggle_prisoner_tag()
/// when a mode other than "tag" is active). Adjacency is inherent -- attack()
/// only fires on adjacent mobs, which is exactly the field "1:1 tile range"
/// this is meant to have.
/datum/computer_file/program/security/first_responder/proc/handle_ship_seizure_tap(mob/living/target, mob/user)
	if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
		return
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : null
	if(net != "hub")
		to_chat(user, SPAN_WARNING("Ship seizure requires a Hub-network terminal."))
		return
	var/list/owned = _find_owned_deployed_ships(target)
	if(!length(owned))
		to_chat(user, SPAN_WARNING("[target] has no deployed ship to seize."))
		return

	var/datum/drydock_ship/DS
	if(length(owned) == 1)
		DS = owned[1]
	else
		// More than one deployed vessel owned by target -- let the officer
		// choose which to seize rather than grabbing one at random. Same
		// tgui_input_list + choices[pick] pattern as
		// _drydock_board_resolve_ship() (telepad_drydock_boarding.dm).
		var/list/choices = list()
		for(var/datum/drydock_ship/candidate in owned)
			choices["[candidate.display_name()] -- Ship #[candidate.shuttle_id]"] = candidate
		var/pick = tgui_input_list(user, "Which vessel do you want to repossess from [target]?", "Repossess Vessel", choices)
		if(!pick)
			return
		var/datum/drydock_ship/chosen = choices[pick]
		if(!istype(chosen))
			return
		// Re-validate after the async menu -- tgui_input_list yields, so the
		// tap's inherent adjacency no longer holds and the vessel may have
		// been stashed/repossessed in the meantime.
		DS = GLOB.drydock_ships["[chosen.shuttle_id]"]
		if(!DS || DS.stashed || !DS.owned_by(target))
			to_chat(user, SPAN_WARNING("That vessel is no longer available to seize."))
			return
		if(QDELETED(target) || !user.Adjacent(target))
			to_chat(user, SPAN_WARNING("You're no longer within reach of [target]."))
			return

	_seize_deployed_vessel(DS, target, user)

/// Direct-item counterpart to handle_ship_seizure_tap() above -- fires when
/// the schematic itself is tapped with the device (ship_schematic.dm's
/// attackby()) rather than tapping whoever's currently holding it. Resolves
/// the ship straight off the item, so no inventory search is needed.
/datum/computer_file/program/security/first_responder/proc/handle_ship_seizure_tap_item(obj/item/ship_schematic/schematic, mob/user)
	if(!can_run(user, TRUE, ACCESS_SECURITY, PROGRAM_ACCESS_ONE))
		return
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : null
	if(net != "hub")
		to_chat(user, SPAN_WARNING("Ship seizure requires a Hub-network terminal."))
		return
	var/datum/drydock_ship/DS = schematic.resolve_ship()
	if(!DS)
		to_chat(user, SPAN_WARNING("[schematic] doesn't correspond to any live ship."))
		return
	if(DS.stashed)
		to_chat(user, SPAN_WARNING("[DS.display_name()] isn't currently deployed -- there's nothing to seize."))
		return
	var/mob/holder = ismob(schematic.loc) ? schematic.loc : null
	_seize_deployed_vessel(DS, holder, user)

#undef FIRST_RESPONDER_COOLDOWN
#undef FIRST_RESPONDER_OFFENSE_MAX_AGE
#undef FIRST_RESPONDER_MAX_PRISONERS
#undef FIRST_RESPONDER_TRANSPORT_RANGE
