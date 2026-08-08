/*
 * Umbilical Pad
 *
 * A player-buildable telepad_cargo subtype that links to any other umbilical
 * pad sharing its access code, same link_code/_linked_pads() matching as
 * telepad_cargo/travel (telepad_travel.dm) -- but instead of a one-shot
 * teleport-on-interact, a matching code keeps a standing, walk-through
 * /obj/effect/portal/dock_link connection open at both pads for as long as
 * the codes keep matching and the pad is enabled.
 *
 * Replaces the automatic docking umbilical drydock ships used to open on
 * landing (drydock_ship.dm) -- that system opened an invisible-until-you-
 * walk-into-it gangway the instant a ship docked, with no player action or
 * awareness involved. This makes docking connections opt-in and visible --
 * someone has to build and code a pad on each end.
 */
/obj/structure/machinery/telepad_cargo/umbilical
	name = "umbilical pad"
	desc = "A tuned telepad that opens a standing bluespace conduit to any other umbilical pad sharing its access code."
	color = "#ffaa44"
	accepts_cargo = FALSE
	anchored = FALSE
	component_types = list(
		/obj/item/circuitboard/umbilical_pad,
		/obj/item/bluespace_crystal/artificial,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil = 2
	)

	/// Player-set string; any pad sharing this exact (normalized) code is a
	/// valid tether partner. Empty = inert -- never opens a connection.
	var/link_code = ""
	/// Explicit stop/disable switch, independent of link_code -- lets a pad
	/// be taken offline without losing its configured code.
	var/enabled = TRUE
	/// This pad's own half of the standing connection.
	var/obj/effect/portal/dock_link/local_link
	/// The far end, sitting at the currently tethered pad.
	var/obj/effect/portal/dock_link/remote_link

/obj/structure/machinery/telepad_cargo/umbilical/Initialize(mapload, ...)
	. = ..()
	verbs -= /obj/structure/machinery/telepad_cargo/verb/configure_supply_network
	_reconcile_link()

/obj/structure/machinery/telepad_cargo/umbilical/Destroy()
	_sever_link()
	return ..()

/// Base telepad_cargo/attackby() (telepad.dm) handles the wrench-to-anchor
/// toggle generically -- reconcile afterward so wrenching down an already-
/// coded pad opens its connection immediately, and unwrenching one severs
/// it, instead of waiting for some other trigger to notice.
/obj/structure/machinery/telepad_cargo/umbilical/attackby(obj/item/attacking_item, mob/user, params)
	. = ..()
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		_reconcile_link()

/obj/structure/machinery/telepad_cargo/umbilical/attack_hand(mob/user)
	if(..())
		return TRUE
	if(!anchored)
		to_chat(user, SPAN_WARNING("\The [src] needs to be secured to the floor with a wrench first."))
		return TRUE
	ui_interact(user)
	return TRUE

/obj/structure/machinery/telepad_cargo/umbilical/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "UmbilicalPad", "Umbilical Pad")
		ui.open()

/obj/structure/machinery/telepad_cargo/umbilical/ui_data(mob/user)
	var/list/data = list()
	data["link_code"] = link_code
	data["enabled"] = enabled
	data["connected"] = !!local_link

	data["linked_pads"] = list()
	for(var/obj/structure/machinery/telepad_cargo/umbilical/pad in _linked_pads())
		data["linked_pads"] += list(list(
			"ref" = "\ref[pad]",
			"name" = pad.name,
			"location" = "([pad.x],[pad.y],[pad.z])"
		))
	return data

/obj/structure/machinery/telepad_cargo/umbilical/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("set_code")
			// Open to any player, no rights/faction gate -- same as travel
			// pad's own access-code field (telepad_travel.dm).
			var/new_code = tgui_input_text(user, "Set this pad's access code (any pad sharing this code becomes a tether partner):", "Umbilical Pad", link_code, max_length = 32)
			if(isnull(new_code))
				return TRUE
			link_code = normalize_faction_uid(new_code)
			if(!persistence_map_placed && GLOB.config.sql_enabled && GLOB.persistence_ready)
				SSpersistence.objectsRegisterTrack(src)
			to_chat(user, link_code ? SPAN_NOTICE("Umbilical pad code set to '[link_code]'.") : SPAN_NOTICE("Umbilical pad code cleared -- this pad is now inert."))
			_reconcile_link()
			. = TRUE
		if("toggle_enabled")
			enabled = !enabled
			to_chat(user, enabled ? SPAN_NOTICE("Umbilical pad enabled.") : SPAN_WARNING("Umbilical pad disabled."))
			_reconcile_link()
			. = TRUE

/// Every OTHER umbilical pad sharing this pad's link_code -- empty list if
/// unlinked (no code set) or no matches. Same flat world-search shape as
/// telepad_cargo/travel's own _linked_pads() (telepad_travel.dm).
/obj/structure/machinery/telepad_cargo/umbilical/proc/_linked_pads()
	. = list()
	if(!link_code)
		return
	for(var/obj/structure/machinery/telepad_cargo/umbilical/pad in world)
		if(pad == src)
			continue
		if(!pad.z)
			continue
		if(pad.link_code == link_code)
			. += pad

/**
 * Brings this pad's standing connection in line with its current
 * link_code/enabled state. Idempotent -- safe to call from Initialize(),
 * set_code, toggle_enabled, or after a persistence restore, any number of
 * times, without ever double-spawning a portal pair: if a matching
 * dock_link already sits at this pad's own turf (because the OTHER pad
 * reconciled first), it's adopted instead of duplicated.
 */
/obj/structure/machinery/telepad_cargo/umbilical/proc/_reconcile_link()
	if(!anchored || !enabled || !link_code)
		_sever_link()
		return

	var/list/candidates = _linked_pads()
	if(!length(candidates))
		_sever_link()
		return

	// First-match-wins -- this is a 1:1 dock connection, not a multi-pad
	// broadcast network like travel pads. Use distinct codes per dock pair.
	var/obj/structure/machinery/telepad_cargo/umbilical/target = candidates[1]
	var/turf/my_turf = get_turf(src)
	var/turf/target_turf = get_turf(target)
	if(!my_turf || !target_turf || my_turf == target_turf)
		_sever_link()
		return

	if(local_link && local_link.target == target_turf && !QDELETED(local_link))
		return // already connected to the right partner

	_sever_link()

	var/obj/effect/portal/dock_link/existing = locate() in my_turf
	if(existing && existing.target == target_turf)
		_adopt_link(existing, locate(/obj/effect/portal/dock_link) in target_turf)
		return

	var/obj/effect/portal/dock_link/new_local = new(my_turf, target_turf, src)
	var/obj/effect/portal/dock_link/new_remote = new(target_turf, my_turf, src)
	_adopt_link(new_local, new_remote)

/// Tracks a portal pair (whether freshly created or adopted from the other
/// side) and watches both for deletion so a pad can never hold a stale ref
/// -- e.g. if the OTHER pad's own _sever_link() deletes the shared pair
/// first.
/obj/structure/machinery/telepad_cargo/umbilical/proc/_adopt_link(obj/effect/portal/dock_link/new_local, obj/effect/portal/dock_link/new_remote)
	local_link = new_local
	remote_link = new_remote
	if(local_link)
		RegisterSignal(local_link, COMSIG_QDELETING, PROC_REF(_on_local_link_qdel))
	if(remote_link)
		RegisterSignal(remote_link, COMSIG_QDELETING, PROC_REF(_on_remote_link_qdel))

/obj/structure/machinery/telepad_cargo/umbilical/proc/_on_local_link_qdel()
	SIGNAL_HANDLER
	local_link = null

/obj/structure/machinery/telepad_cargo/umbilical/proc/_on_remote_link_qdel()
	SIGNAL_HANDLER
	remote_link = null

/obj/structure/machinery/telepad_cargo/umbilical/proc/_sever_link()
	if(local_link)
		UnregisterSignal(local_link, COMSIG_QDELETING)
	if(remote_link)
		UnregisterSignal(remote_link, COMSIG_QDELETING)
	QDEL_NULL(local_link)
	QDEL_NULL(remote_link)

// Persistence -- both paths, matching telepad_cargo/travel's own pattern
// (telepad_travel.dm) exactly. Reconciling again after either restore path
// means a pad that was tethered before a reboot re-establishes (or adopts)
// its connection once both sides are back in the world.
/obj/structure/machinery/telepad_cargo/umbilical/worldstate_get_content()
	var/list/content = ..()
	if(!content)
		content = list()
	content["link_code"] = link_code
	content["enabled"] = enabled
	return content

/obj/structure/machinery/telepad_cargo/umbilical/worldstate_apply_content(list/content)
	..()
	if(!isnull(content["link_code"]))
		link_code = content["link_code"]
	if(!isnull(content["enabled"]))
		enabled = content["enabled"]
	_reconcile_link()

/obj/structure/machinery/telepad_cargo/umbilical/persistent_objects_get_content()
	var/list/content = ..()
	content["link_code"] = link_code
	content["enabled"] = enabled
	return content

/obj/structure/machinery/telepad_cargo/umbilical/persistent_objects_apply_content(content, x, y, z)
	..()
	if(islist(content))
		if(!isnull(content["link_code"]))
			link_code = content["link_code"]
		if(!isnull(content["enabled"]))
			enabled = content["enabled"]
	_reconcile_link()
