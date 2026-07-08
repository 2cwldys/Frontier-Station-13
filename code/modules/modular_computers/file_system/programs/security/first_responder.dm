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
	extended_desc = "Hub security rapid-response system. Alerts accredited responders to highsec offenses and opens short-lived bluespace portals to the scene, with a return link to the faction's security telepad."
	required_access_run = ACCESS_SECURITY
	required_access_download = ACCESS_SECURITY
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

#define FIRST_RESPONDER_MAX_PRISONERS 4
/// Prisoners must be within this range of the responder when Return fires
#define FIRST_RESPONDER_TRANSPORT_RANGE 2

/datum/computer_file/program/security/first_responder/ui_data(mob/user)
	var/list/data = initial_data()
	var/net = computer ? normalize_faction_uid(computer.persistent_network) : ""

	data["faction_uid"]  = net
	data["faction_name"] = net ? get_faction_name(net) : null
	data["is_hub"]       = (net == "hub")
	data["has_telepad"]  = net ? !!persistence_find_security_telepad(net) : FALSE
	data["cooldown"]     = max(0, round((next_jump_time - world.time) / 10))

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
		offenses += list(list(
			"index"    = i,
			"name"     = entry["name"],
			"age"      = "[round((world.time - entry["time"]) / (1 MINUTE))] min ago",
			"tracked"  = !QDELETED(offender) && offender.z
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
		if("respond")
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
			// Live offender position preferred; recorded coordinates fallback
			var/turf/target_turf
			var/datum/weakref/wr = entry["ref"]
			var/mob/offender = wr ? wr.resolve() : null
			if(!QDELETED(offender) && offender.z)
				target_turf = get_turf(offender)
			else
				target_turf = locate(entry["x"], entry["y"], entry["z"])
			if(!target_turf)
				to_chat(user, SPAN_WARNING("Cannot resolve the offense location."))
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
			if(world.time < next_jump_time)
				to_chat(user, SPAN_WARNING("Teleporter recharging."))
				return TRUE
			var/net = normalize_faction_uid(computer.persistent_network)
			var/turf/pad_turf = persistence_find_security_telepad(net)
			if(!pad_turf)
				to_chat(user, SPAN_WARNING("No security telepad found for [net ? get_faction_name(net) : "this network"]."))
				return TRUE
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
			var/target_ref = params["ref"]
			for(var/datum/weakref/pwr in tagged_prisoners)
				if("\ref[pwr]" == target_ref)
					tagged_prisoners -= pwr
					return TRUE
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
		new /obj/effect/portal(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
		playsound(origin, 'sound/effects/phasein.ogg', 50, 1)
	new /obj/effect/portal(dest, null, null, 5 SECONDS, 0)
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

#undef FIRST_RESPONDER_COOLDOWN
#undef FIRST_RESPONDER_OFFENSE_MAX_AGE
#undef FIRST_RESPONDER_MAX_PRISONERS
#undef FIRST_RESPONDER_TRANSPORT_RANGE
