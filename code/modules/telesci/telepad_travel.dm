/*
 * Travel Pad
 *
 * A player-buildable telepad_cargo subtype that links to any other travel pad
 * sharing its access code, letting a player step directly between them --
 * "beam me to my paired pad, wherever it is," reusing the exact same flat
 * world-search-by-shared-key model persistence_find_cargo_telepad() already
 * uses for cargo delivery (persistence_cryo.dm), just matched on a
 * player-set link_code instead of persistent_network, and delivering a
 * living mob instead of items.
 *
 * Deliberately independent of faction membership -- any player can build and
 * link one, no faction tagger/officer rank involved, unlike every other
 * telepad_cargo subtype in this codebase.
 */

/// One spark+sound pulse at each of origin/destination (either may be null to
/// skip -- e.g. a system that only wants a destination-side warning). Shared
/// by every "channel for N seconds, then arrive somewhere" mechanic
/// (personal_travel.dm, drydock board/disembark, pod warp) so a bystander at
/// the destination gets the same "something's about to portal in" warning the
/// traveler's own origin tile already gave. still_valid is a CALLBACK
/// returning FALSE once the travel this pulse belongs to has been aborted or
/// has already completed -- callers must flip whatever it checks on every one
/// of their own abort paths, or a pulse scheduled before the abort will still
/// fire after the fact.
/proc/_travel_spool_pulse(turf/origin, turf/destination, datum/callback/still_valid)
	if(still_valid && !still_valid.Invoke())
		return
	if(origin)
		spark(origin, 2, GLOB.alldirs)
		playsound(origin, 'sound/effects/sparks4.ogg', 20, 1)
	if(destination)
		spark(destination, 2, GLOB.alldirs)
		playsound(destination, 'sound/effects/sparks4.ogg', 20, 1)

/// Third-person line for bystanders at the moment a channeled travel actually
/// completes: "materializes" on the tile being arrived at, "dematerializes" on
/// the one being left. Shared by personal_travel.dm and drydock
/// board/disembark so both ends of every jump read the same way.
///
/// The traveller is skipped. They already get their own first-person feedback
/// ("You leap through a bluespace rift.", "You board the ship."), and since
/// every caller invokes this while the mob is standing on the turf in question,
/// they would otherwise appear in viewers() for both halves.
///
/// **Ordering is what makes this correct**: viewers() is resolved from the turf
/// at call time, so the dematerialize half must be called BEFORE the forceMove
/// and the materialize half after it. Called in the wrong order, both lines
/// reach the same set of bystanders.
///
/// show_message type 1 is a visual message, so a blind bystander correctly gets
/// nothing rather than seeing an event they could not have witnessed.
/proc/_travel_announce_phase(mob/living/L, turf/T, materializing)
	if(!L || !T)
		return
	var/message = SPAN_NOTICE("[L] [materializing ? "materializes" : "dematerializes"].")
	for(var/mob/M in viewers(T))
		if(M == L)
			continue
		M.show_message(message, 1)
	L.show_message(SPAN_NOTICE("You [materializing ? "materialize" : "dematerialize"]."), 1)

/// Fires _travel_spool_pulse() immediately, then every 5 seconds until
/// duration -- personal_travel.dm's original 15s/3-pulse cadence (t=0/5/10),
/// generalized to any duration so a 3-second channel (pod warp) still gets
/// its one t=0 pulse without extra repeats.
/// show_phase_effect (opt-in, default off): also spawns a continuous blue
/// "teleporting here" visual (temp_visual/phase/spool) at both ends for the
/// duration of the channel -- see _travel_spool_visual_tick() below. Only
/// drydock board/disembark and Personal Travel ask for this; pod warp
/// (warp.dm) deliberately doesn't, so it stays off by default rather than
/// every future caller of this shared proc getting it automatically.
/// facing_dir (optional, only meaningful with show_phase_effect): the
/// traveling mob's own current dir, passed straight through to both
/// effects -- mirrors the rig teleporter's own phase_in()/phase_out()
/// (ninja.dm), which likewise face the effect the same way as the mob using
/// it, rather than each object picking its own random dir (temp_visual's
/// own default).
/proc/_start_travel_spool_pulses(turf/origin, turf/destination, duration, datum/callback/still_valid, show_phase_effect = FALSE, facing_dir)
	_travel_spool_pulse(origin, destination, still_valid)
	if(show_phase_effect)
		var/obj/effect/temp_visual/phase/spool/origin_fx = origin ? new(origin, facing_dir) : null
		var/obj/effect/temp_visual/phase/spool/destination_fx = destination ? new(destination, facing_dir) : null
		_travel_spool_visual_tick(origin_fx, destination_fx, still_valid, duration)
		_start_travel_transport_pulses(origin, destination, duration, still_valid)
	var/t = 5 SECONDS
	while(t < duration)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_travel_spool_pulse), origin, destination, still_valid), t)
		t += 5 SECONDS

/// One forward/reversed "transport" cue at each of origin/destination --
/// same still_valid contract as _travel_spool_pulse(). reverted picks
/// transport_reverse.ogg instead of transport.ogg. Each play is left to run
/// its own natural length (6.34s) even if the next scheduled beat lands
/// before it finishes -- no forced cutoff.
/proc/_travel_transport_pulse(turf/origin, turf/destination, datum/callback/still_valid, reverted)
	if(still_valid && !still_valid.Invoke())
		return
	var/transport_sound = reverted ? 'sound/effects/transport_reverse.ogg' : 'sound/effects/transport.ogg'
	if(origin)
		playsound(origin, transport_sound, 40, FALSE)
	if(destination)
		playsound(destination, transport_sound, 40, FALSE)

/// Schedules _travel_transport_pulse() on four beats -- t=0, 5, 10, and
/// duration itself (not just the three t=0/5/10 spark-pulse timestamps) --
/// alternating normal -> reverted -> normal -> reverted, so the very last
/// beat (right as the channel ends and the traveler actually arrives) is
/// always the reversed cue. Only called from _start_travel_spool_pulses()'s
/// show_phase_effect branch, so pod warp never gets this.
/proc/_start_travel_transport_pulses(turf/origin, turf/destination, duration, datum/callback/still_valid)
	var/reverted = FALSE
	var/t = 0
	while(t <= duration)
		if(t == 0)
			_travel_transport_pulse(origin, destination, still_valid, reverted)
		else
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_travel_transport_pulse), origin, destination, still_valid, reverted), t)
		reverted = !reverted
		t += 5 SECONDS

/// One-shot "someone's arriving via phase" cue at T -- the same phasein-blue
/// sprite/loop as the spool variant above, but fixed at a short 2 seconds
/// with no forward/reverse alternation, plus a single transport.ogg play.
/// For instant-delivery telepads with no 15-second spool-up channel at all
/// (Travel Pad, First Responder) that used to show the old fading portal
/// sprite + phasein.ogg instead.
/proc/_telepad_phase_arrival(turf/T)
	if(!T)
		return
	new /obj/effect/temp_visual/phase/spool/short(T)
	playsound(T, 'sound/effects/transport.ogg', 40, FALSE)

/// Keeps origin_fx/destination_fx (temp_visual/phase/spool instances, either
/// of which may be null) alive for up to `remaining` more deciseconds,
/// re-checking still_valid every second -- same still_valid contract
/// _travel_spool_pulse() already uses -- so the visual disappears the moment
/// its travel is aborted instead of lingering for the rest of the nominal
/// channel. Also hard-capped at `remaining` reaching 0 as a backstop.
/proc/_travel_spool_visual_tick(obj/effect/temp_visual/phase/spool/origin_fx, obj/effect/temp_visual/phase/spool/destination_fx, datum/callback/still_valid, remaining)
	if(remaining <= 0 || (still_valid && !still_valid.Invoke()))
		QDEL_NULL(origin_fx)
		QDEL_NULL(destination_fx)
		return
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(_travel_spool_visual_tick), origin_fx, destination_fx, still_valid, remaining - 1 SECONDS), 1 SECONDS)

/// Generic still_valid callback target for callers with no existing sequence
/// var of their own (drydock board/disembark, pod warp) -- token is a
/// one-element list acting as a mutable box, e.g. `list(TRUE)`; set
/// `token[1] = FALSE` on whatever abort path ends the spool-up early.
/proc/_spool_token_valid(list/token)
	return token && token[1]

/obj/structure/machinery/telepad_cargo/travel
	name = "travel pad"
	desc = "A tuned telepad that links to any other travel pad sharing its access code, letting you step directly between them."
	color = "#44ff88"
	accepts_cargo = FALSE
	component_types = list(
		/obj/item/circuitboard/travel_pad,
		/obj/item/bluespace_crystal/artificial,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil = 2
	)

	/// Player-set string; any pad sharing this exact (normalized) code is a
	/// valid destination. Empty = inert -- can't travel from or to it.
	var/link_code = ""
	/// Static/shared across every pad instance -- matches drydock_boarding's
	/// and corvette_boarding's own last_boarded_by_ckey convention exactly
	/// (a single global spam-guard, not per-pad).
	var/static/list/last_used_by_ckey = list()

/obj/structure/machinery/telepad_cargo/travel/Initialize(mapload, ...)
	. = ..()
	verbs -= /obj/structure/machinery/telepad_cargo/verb/configure_supply_network

/obj/structure/machinery/telepad_cargo/travel/attack_hand(mob/user)
	if(..())
		return TRUE
	ui_interact(user)
	return TRUE

/obj/structure/machinery/telepad_cargo/travel/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TravelPad", "Travel Pad")
		ui.open()

/obj/structure/machinery/telepad_cargo/travel/ui_data(mob/user)
	var/list/data = list()
	data["link_code"] = link_code

	data["linked_pads"] = list()
	for(var/obj/structure/machinery/telepad_cargo/travel/pad in _linked_pads())
		data["linked_pads"] += list(list(
			"ref" = "\ref[pad]",
			"name" = pad.name,
			"location" = "([pad.x],[pad.y],[pad.z])"
		))

	var/cooldown_end = last_used_by_ckey[user.ckey] ? (last_used_by_ckey[user.ckey] + 30) : 0
	data["can_travel"] = world.time >= cooldown_end
	data["cooldown"] = max(0, round((cooldown_end - world.time) / 10))
	return data

/obj/structure/machinery/telepad_cargo/travel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("set_code")
			// Open to any player, no rights/faction gate -- this is a
			// personal/small-group travel network, not administrative
			// infrastructure like the faction beacon or the other
			// telepad_cargo subtypes.
			var/new_code = tgui_input_text(user, "Set this pad's access code (any pad sharing this code becomes a valid destination):", "Travel Pad", link_code, max_length = 32)
			if(isnull(new_code))
				return TRUE
			// normalize_faction_uid() is a plain lowercase/underscore string
			// canonicalizer despite the name -- no faction lookup involved
			// (persistence_factions.dm:134-137) -- reused here purely for
			// the case/whitespace-insensitive matching it already gives
			// every other network-code field in this codebase.
			link_code = normalize_faction_uid(new_code)
			// Belt-and-suspenders alongside the automatic registration a
			// frame-built machine already gets from
			// /obj/structure/machinery/Initialize() itself --
			// objectsRegisterTrack() is documented safe to call more than
			// once, and this covers any spawn path that ISN'T frame-
			// construction (e.g. an admin-spawned instance).
			if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
				SSpersistence.objectsRegisterTrack(src)
			to_chat(user, link_code ? SPAN_NOTICE("Travel pad code set to '[link_code]'.") : SPAN_NOTICE("Travel pad code cleared -- this pad is now inert."))
			. = TRUE
		if("travel")
			if(isliving(user))
				_travel(user, params["target"])
			. = TRUE
		if("send_cargo")
			_send_cargo(user, params["target"])
			. = TRUE

/// Every OTHER travel pad sharing this pad's link_code -- empty list if
/// unlinked (no code set) or no matches. Flat world-search, same shape as
/// persistence_find_cargo_telepad() (persistence_cryo.dm:628-647), just
/// matched on link_code instead of persistent_network, and returning every
/// match (not just one) since more than one destination can share a code.
/obj/structure/machinery/telepad_cargo/travel/proc/_linked_pads()
	. = list()
	if(!link_code)
		return
	for(var/obj/structure/machinery/telepad_cargo/travel/pad in world)
		if(pad == src)
			continue
		if(!pad.z)
			continue
		if(pad.link_code == link_code)
			. += pad

/// Cooldown/delivery shape directly mirrors _drydock_board_core()
/// (telepad_drydock_boarding.dm) -- same buckled/dead/cooldown checks, same
/// persistence_telepad_deliver() + destination.density obstruction guard.
/// target_ref selects a specific pad from the TGUI's own list (each row has
/// its own Travel button) -- falls back to auto-picking the only candidate
/// if there's just one and no ref was given.
/obj/structure/machinery/telepad_cargo/travel/proc/_travel(mob/living/L, target_ref)
	if(!istype(L))
		return FALSE
	if(!link_code)
		to_chat(L, SPAN_WARNING("This pad has no access code set."))
		return FALSE
	if(L.buckled_to)
		to_chat(L, SPAN_WARNING("You can't travel while buckled."))
		return FALSE
	if(L.stat == DEAD)
		to_chat(L, SPAN_WARNING("You can't travel while dead."))
		return FALSE
	if(last_used_by_ckey[L.ckey] && (world.time - last_used_by_ckey[L.ckey] < 30))
		to_chat(L, SPAN_WARNING("The pad is still recalibrating -- wait a moment."))
		return FALSE

	var/list/candidates = _linked_pads()
	if(!length(candidates))
		to_chat(L, SPAN_WARNING("No other pad shares this access code."))
		return FALSE

	var/obj/structure/machinery/telepad_cargo/travel/target
	if(target_ref)
		target = locate(target_ref) in candidates
		if(!target)
			to_chat(L, SPAN_WARNING("That pad is no longer available."))
			return FALSE
	else if(length(candidates) == 1)
		target = candidates[1]
	else
		to_chat(L, SPAN_WARNING("Select a destination pad first."))
		return FALSE

	if(is_centcom_level(target.z) && !can_access_hub_depot(L))
		to_chat(L, SPAN_WARNING("That pad's destination is restricted to Hub personnel."))
		return FALSE

	// This pad is deliberately independent of faction membership (see file
	// header) -- but that independence would otherwise let it bypass the
	// admin raiding kill-switch entirely: plant one pad on a locked-down
	// faction Z and freely shuttle in/out. Same check drydock boarding and
	// Personal Travel's Leap already enforce (telepad_drydock_boarding.dm).
	if(_drydock_raid_blocked(L, target.z))
		to_chat(L, SPAN_WARNING("Faction raiding is currently disabled -- you cannot enter that territory."))
		play_raid_blocked_sound(L)
		return FALSE

	var/turf/destination = get_turf(target)
	if(!destination || destination.density)
		to_chat(L, SPAN_WARNING("The destination pad is obstructed."))
		return FALSE

	// Cosmetic-only phase effect + spark burst at both ends, matching First
	// Responder's own jump effect (first_responder.dm's first_responder_jump())
	// -- this never actually teleports anything itself, the real move is
	// still the forceMove() inside persistence_telepad_deliver() below.
	var/turf/origin = get_turf(L)
	if(origin)
		_telepad_phase_arrival(origin)
		spark(origin, 3, GLOB.alldirs)
	_telepad_phase_arrival(destination)
	spark(destination, 3, GLOB.alldirs)

	last_used_by_ckey[L.ckey] = world.time
	var/list/payload = list(L)
	if(L.pulling && !QDELETED(L.pulling))
		payload += L.pulling
	persistence_telepad_deliver(payload, destination, skip_effects = TRUE)
	to_chat(L, SPAN_GOOD("You step through the pad."))
	return TRUE

/// Standalone cargo transfer -- moves whatever's sitting on THIS pad's own
/// tile (a crate, dropped items) to a linked pad without requiring anyone to
/// travel themselves. Living mobs are deliberately excluded here -- a
/// bystander shouldn't get scooped up by someone else sending cargo; mobs
/// only travel via _travel() above (and now bring along whatever they're
/// personally pulling, same as Personal Travel).
/obj/structure/machinery/telepad_cargo/travel/proc/_send_cargo(mob/user, target_ref)
	if(!link_code)
		to_chat(user, SPAN_WARNING("This pad has no access code set."))
		return FALSE

	var/list/candidates = _linked_pads()
	if(!length(candidates))
		to_chat(user, SPAN_WARNING("No other pad shares this access code."))
		return FALSE

	var/obj/structure/machinery/telepad_cargo/travel/target
	if(target_ref)
		target = locate(target_ref) in candidates
		if(!target)
			to_chat(user, SPAN_WARNING("That pad is no longer available."))
			return FALSE
	else if(length(candidates) == 1)
		target = candidates[1]
	else
		to_chat(user, SPAN_WARNING("Select a destination pad first."))
		return FALSE

	// Same raid lockout as _travel() -- otherwise cargo-only transfer (no
	// living passenger to check) would still let weapons/explosives through
	// onto locked-down faction territory unchecked.
	if(_drydock_raid_blocked(user, target.z))
		to_chat(user, SPAN_WARNING("Faction raiding is currently disabled -- you cannot send anything into that territory."))
		play_raid_blocked_sound(user)
		return FALSE

	var/turf/destination = get_turf(target)
	if(!destination || destination.density)
		to_chat(user, SPAN_WARNING("The destination pad is obstructed."))
		return FALSE

	var/list/payload = list()
	for(var/atom/movable/AM in get_turf(src))
		if(AM == src || QDELETED(AM) || AM.anchored || isliving(AM))
			continue
		payload += AM
	if(!length(payload))
		to_chat(user, SPAN_WARNING("There's nothing on the pad to send."))
		return FALSE

	if(last_used_by_ckey[user.ckey] && (world.time - last_used_by_ckey[user.ckey] < 30))
		to_chat(user, SPAN_WARNING("The pad is still recalibrating -- wait a moment."))
		return FALSE

	// Cargo-only transfer keeps the original decorative portal sprite (the
	// blue phase effect is for people passing through, not crates/items) --
	// only the sound changed, to transport.ogg.
	var/turf/origin = get_turf(src)
	new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
	spark(origin, 3, GLOB.alldirs)
	playsound(origin, 'sound/effects/transport.ogg', 40, FALSE)
	new /obj/effect/portal/decorative/fading(destination, null, null, 5 SECONDS, 0)
	spark(destination, 3, GLOB.alldirs)
	playsound(destination, 'sound/effects/transport.ogg', 40, FALSE)

	last_used_by_ckey[user.ckey] = world.time
	persistence_telepad_deliver(payload, destination, skip_effects = TRUE)
	to_chat(user, SPAN_GOOD("The pad hums and sends its contents through to the linked pad."))
	return TRUE

// Persistence -- both paths, matching the cryopod template
// (persistence_cryo.dm:386+) telepad_cargo's own base persistence
// (telepad.dm) now also follows:
/obj/structure/machinery/telepad_cargo/travel/worldstate_get_content()
	var/list/content = ..()
	if(!content)
		content = list()
	content["link_code"] = link_code
	return content

/obj/structure/machinery/telepad_cargo/travel/worldstate_apply_content(list/content)
	..()
	if(!isnull(content["link_code"]))
		link_code = content["link_code"]

/obj/structure/machinery/telepad_cargo/travel/persistent_objects_get_content()
	var/list/content = ..()
	content["link_code"] = link_code
	return content

/obj/structure/machinery/telepad_cargo/travel/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content) && !isnull(content["link_code"]))
		link_code = content["link_code"]

/*
 * Hub Travel Pad -- a single, admin-placed instance marking the Hub's own
 * arrival point. Personal Travel's Return to Hub action
 * (personal_travel.dm) locates this by type directly, bypassing the normal
 * link_code matching every other travel pad uses -- no code needs to be set
 * for Return to Hub to work. Still a full travel pad otherwise (inherits
 * attackby/repair/persistence from the base machine), so it can also be
 * given a link_code if admins want it to additionally participate in the
 * normal player-built pad network.
 */
/obj/structure/machinery/telepad_cargo/travel/hub
	name = "hub travel pad"
	desc = "A permanently-installed travel pad marking Hub territory. Personal Travel's Return to Hub delivers here directly."
	color = "#6699ff" // matches the hub faction beacon's own blue tint
