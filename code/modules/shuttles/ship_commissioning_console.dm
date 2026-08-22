/*
 * Ship Commissioning Console
 *
 * A player-buildable, cargo-orderable machine that turns a hull someone
 * physically built themselves into a real, independently-owned drydock
 * shuttle -- own ledger row (/datum/drydock_ship, persistence_shuttles.dm),
 * own schematic, own dedicated Z, stashes/retrieves exactly like any
 * template-bought ship from that point on. See docs on drydockCommission()
 * (persistence_shuttles.dm) for the actual capture/payment/ledger logic --
 * this file is only the console: previewing the buildable envelope and
 * collecting the player's choices before handing off to that proc.
 *
 * Deliberately separate from, but tied to, a nearby docking_beacon
 * (docking_beacon.dm) -- the beacon marks the spot; this console is where
 * you stand to build around it and commission the result. The console
 * itself is never consumed or destroyed by a successful commission -- it's
 * a reusable shipyard fixture, ready for the next hull the moment the
 * previous one launches.
 */

/// tag string -> live device object, for the three linkable device types
/// (docking_beacon -- keyed by its own landmark_tag; docking_transponder and
/// the buildable shuttle_control console -- each keyed by a lazily-minted
/// id_tag). Lets a saved link (linked_beacon_tag/linked_transponder_tag/
/// linked_shuttle_console_tag below) be resolved back to whichever live
/// object currently carries that tag after a restart re-creates everything
/// fresh from the DB -- a raw object reference can't survive that, but a
/// stable string plus this lookup can.
GLOBAL_LIST_EMPTY(drydock_linkable_devices_by_tag)

/obj/structure/machinery/computer/ship_commissioning
	name = "ship commissioning console"
	desc = "Surveys a build envelope and files the paperwork to commission a completed hull as a real, independently-owned shuttle."
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "engines"
	icon_keyboard = "tech_key"
	icon_keyboard_emis = "tech_key_mask"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1
	anchored = FALSE // starts unanchored -- won't register while in a crate or being carried
	use_power = POWER_USE_IDLE
	idle_power_usage = 20
	component_types = list(
		/obj/item/circuitboard/ship_commissioning,
		/obj/item/stock_parts/capacitor,
		/obj/item/stock_parts/console_screen,
		/obj/item/stack/cable_coil = 2
	)

	/// This console's own configurable build envelope size -- defaults to
	/// SUBSHIP_FOOTPRINT_X/Y (the shared standard every other footprint check
	/// in the game still uses), but adjustable per-console via "Set Build
	/// Size" in the TGUI (ui_act()'s "set_build_size" case below), bounded to
	/// PLAYER_BUILD_ENVELOPE_MIN/MAX. Every SUBSHIP_FOOTPRINT_X/Y reference
	/// elsewhere in this file reads these instead.
	var/build_envelope_x = SUBSHIP_FOOTPRINT_X
	var/build_envelope_y = SUBSHIP_FOOTPRINT_Y

	/// Turf-highlight indicators from the last Preview Build Envelope, if any
	/// -- cleared/replaced on the next preview or on commission.
	var/list/obj/effect/shuttle_warning/envelope_indicators = list()
	/// Snapshot from the last Preview: TRUE if every envelope tile was
	/// either open space or genuinely empty floor (no walls, no mobs, no
	/// objects) -- what gates "Generate Build Floor" in the TGUI. Only a UI
	/// convenience; _generate_build_floor() below always re-checks fresh
	/// before actually touching anything, never trusts this alone.
	var/envelope_clean_for_generate = FALSE

	/// The three devices this console is explicitly linked to -- set only by
	/// multitool Buffer-then-apply (see attackby() below), required before
	/// this console will do anything at all. Replaces proximity/envelope-scan
	/// discovery entirely, per explicit design direction: a beacon behind a
	/// wall, or two beacons in range, should never leave any ambiguity about
	/// which one this specific console is building for. An invalid-but-not-
	/// destroyed link (beacon deactivated, device moved) is reported invalid
	/// by the _valid_linked_*() checks below but is NOT cleared here --
	/// only _on_linked_device_deleted() (a destroyed device) actually forgets
	/// a link.
	var/obj/structure/machinery/docking_beacon/linked_beacon
	var/obj/structure/machinery/docking_transponder/linked_transponder
	var/obj/structure/machinery/computer/shuttle_control/linked_shuttle_console

	/// Tag strings mirroring the three links above, saved/restored via
	/// persistent_objects_get_content()/apply_content() below -- a raw
	/// object reference can't survive a restart (everything gets destroyed
	/// and recreated fresh from the DB), but a stable tag plus
	/// GLOB.drydock_linkable_devices_by_tag can. Only consulted as a lazy
	/// fallback inside the _valid_linked_*() checks when the live var above
	/// is null but a saved tag exists -- resolved once, then cached into the
	/// live var itself exactly as if freshly multitool-linked.
	var/linked_beacon_tag
	var/linked_transponder_tag
	var/linked_shuttle_console_tag

/obj/structure/machinery/computer/ship_commissioning/Initialize()
	. = ..()
	if(GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/// Saves the three link TAGS (not raw references -- see linked_beacon_tag's
/// own doc comment above). Reads the tag straight off whichever device is
/// currently live-linked, if any -- if a tag was only ever lazily resolved
/// from a previous restore and never re-confirmed live, linked_beacon_tag
/// etc. below already holds it regardless, so this still saves correctly.
/obj/structure/machinery/computer/ship_commissioning/persistent_objects_get_content()
	var/list/content = list()
	content["linked_beacon_tag"] = linked_beacon ? linked_beacon.landmark_tag : linked_beacon_tag
	content["linked_transponder_tag"] = linked_transponder ? linked_transponder.id_tag : linked_transponder_tag
	if(istype(linked_shuttle_console, /obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable))
		var/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable/console = linked_shuttle_console
		content["linked_shuttle_console_tag"] = console.id_tag
	else
		content["linked_shuttle_console_tag"] = linked_shuttle_console_tag
	return content

/// Restores the three tags as plain strings only -- deliberately does NOT
/// eagerly resolve them to live objects here. This runs during
/// objectsInstantiateRows()'s single restore pass, where the beacon/
/// transponder/console this console links to may not have been instantiated
/// yet (ordering hazard) -- lazy resolution inside _valid_linked_*() (called
/// on demand, well after boot completes) avoids that entirely.
/obj/structure/machinery/computer/ship_commissioning/persistent_objects_apply_content(content, x, y, z)
	..()
	if(content["linked_beacon_tag"])
		linked_beacon_tag = content["linked_beacon_tag"]
	if(content["linked_transponder_tag"])
		linked_transponder_tag = content["linked_transponder_tag"]
	if(content["linked_shuttle_console_tag"])
		linked_shuttle_console_tag = content["linked_shuttle_console_tag"]

/obj/structure/machinery/computer/ship_commissioning/Destroy()
	QDEL_LIST(envelope_indicators)
	if(linked_beacon)
		UnregisterSignal(linked_beacon, COMSIG_QDELETING)
	if(linked_transponder)
		UnregisterSignal(linked_transponder, COMSIG_QDELETING)
	if(linked_shuttle_console)
		UnregisterSignal(linked_shuttle_console, COMSIG_QDELETING)
	return ..()

/// Common linking logic for all three slots -- swaps out whichever device is
/// currently linked in that slot, moving the QDELETING signal registration
/// across so a destroyed linked device always clears itself (never a
/// dangling reference), matching the same safety multitool.dm's own
/// buffer_object already guarantees.
/obj/structure/machinery/computer/ship_commissioning/proc/_link_device(slot, atom/movable/new_link)
	var/atom/movable/old_link
	switch(slot)
		if("beacon")
			old_link = linked_beacon
		if("transponder")
			old_link = linked_transponder
		if("console")
			old_link = linked_shuttle_console
	if(old_link)
		UnregisterSignal(old_link, COMSIG_QDELETING)
	switch(slot)
		if("beacon")
			linked_beacon = new_link
		if("transponder")
			linked_transponder = new_link
		if("console")
			linked_shuttle_console = new_link
	RegisterSignal(new_link, COMSIG_QDELETING, PROC_REF(_on_linked_device_deleted))

/obj/structure/machinery/computer/ship_commissioning/proc/_on_linked_device_deleted(datum/source)
	SIGNAL_HANDLER
	if(source == linked_beacon)
		linked_beacon = null
	if(source == linked_transponder)
		linked_transponder = null
	if(source == linked_shuttle_console)
		linked_shuttle_console = null

/// Unlinks all three devices at once -- lets a player start over (re-link to
/// a different beacon/transponder/console) without having to remember which
/// slot still holds a stale link, or destroy/rebuild anything to force a
/// clean slate.
/obj/structure/machinery/computer/ship_commissioning/proc/_clear_all_links()
	if(linked_beacon)
		UnregisterSignal(linked_beacon, COMSIG_QDELETING)
		linked_beacon = null
	if(linked_transponder)
		UnregisterSignal(linked_transponder, COMSIG_QDELETING)
		linked_transponder = null
	if(linked_shuttle_console)
		UnregisterSignal(linked_shuttle_console, COMSIG_QDELETING)
		linked_shuttle_console = null
	linked_beacon_tag = null
	linked_transponder_tag = null
	linked_shuttle_console_tag = null
	QDEL_LIST(envelope_indicators)
	envelope_clean_for_generate = FALSE

/// Base /obj/structure/machinery/computer's own attackby() only ever handles
/// the screwdriver (deconstruct-if-anchored-and-broken) -- wrench-to-secure
/// has to be added here ourselves, same pattern docking_beacon.dm uses.
/obj/structure/machinery/computer/ship_commissioning/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		to_chat(user, anchored ? SPAN_NOTICE("Commissioning console secured in place.") : SPAN_NOTICE("Commissioning console unsecured."))
		return TRUE
	// Applies whatever's currently buffered in the multitool (Buffer choice
	// on a docking_beacon/docking_transponder, or the buildable shuttle_control
	// console's own multitool handler) -- see linked_beacon's own doc comment
	// above for why this replaced proximity/envelope-scan discovery entirely.
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		if(!istype(attacking_item, /obj/item/multitool))
			to_chat(user, SPAN_WARNING("\The [attacking_item] can't hold a buffer."))
			return TRUE
		var/obj/item/multitool/tool = attacking_item
		var/atom/buffered = tool.get_buffer()
		if(!buffered)
			to_chat(user, SPAN_WARNING("Nothing buffered in \the [tool] -- multitool a beacon, transponder, or shuttle control console first and choose Buffer, then multitool this console."))
			return TRUE
		if(istype(buffered, /obj/structure/machinery/docking_beacon))
			_link_device("beacon", buffered)
			to_chat(user, SPAN_NOTICE("Linked to docking beacon '[buffered]'."))
		else if(istype(buffered, /obj/structure/machinery/docking_transponder))
			_link_device("transponder", buffered)
			to_chat(user, SPAN_NOTICE("Linked to docking transponder '[buffered]'."))
		else if(istype(buffered, /obj/structure/machinery/computer/shuttle_control))
			_link_device("console", buffered)
			to_chat(user, SPAN_NOTICE("Linked to shuttle control console '[buffered]'."))
		else
			to_chat(user, SPAN_WARNING("\The [buffered] isn't something this console can link to."))
		return TRUE
	return ..(attacking_item, user, params)

/obj/structure/machinery/computer/ship_commissioning/attack_hand(mob/user)
	if(..())
		return TRUE
	if(!anchored)
		to_chat(user, SPAN_WARNING("\The [src] needs to be secured to the floor with a wrench first."))
		return TRUE
	ui_interact(user)
	return TRUE

/obj/structure/machinery/computer/ship_commissioning/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShipCommissioning", "Ship Commissioning")
		ui.open()

/obj/structure/machinery/computer/ship_commissioning/ui_data(mob/user)
	var/list/data = list()
	var/obj/structure/machinery/docking_beacon/beacon = _valid_linked_beacon()
	data["beacon_found"] = !!beacon
	data["beacon_label"] = beacon ? (beacon.dock_label || "Docking Port") : null
	data["beacon_link_broken"] = !!linked_beacon && !beacon
	data["footprint_x"] = build_envelope_x
	data["footprint_y"] = build_envelope_y
	data["price"] = SHIP_COMMISSION_PRICE
	var/obj/item/card/id/ID = user.GetIdCard()
	data["own_faction"] = (ID && ID.employer_faction) ? ID.employer_faction : null
	data["own_faction_name"] = data["own_faction"] ? get_faction_name(data["own_faction"]) : null
	// Live-polled every UI update, same as beacon_found -- greys the
	// Commission buttons out (not just refused after the fact) whenever
	// anyone, dead or alive, is still standing in the build envelope. See
	// _drydock_envelope_has_occupants() (persistence_shuttles.dm), the same
	// check drydockCommission() itself enforces server-side.
	var/list/turf/envelope = beacon ? _get_envelope_turfs() : null
	data["envelope_occupied"] = envelope ? _drydock_envelope_has_occupants(envelope) : FALSE
	// Linked transponder/console must still be physically inside the current
	// envelope -- same safety property the old envelope-scan discovery had,
	// just checked against a specific linked device instead of "find any."
	var/obj/structure/machinery/docking_transponder/transponder = _valid_linked_transponder(envelope)
	data["transponder_found"] = !!transponder
	data["transponder_link_broken"] = !!linked_transponder && !transponder
	data["transponder_aligned"] = (transponder && beacon) ? (turn(transponder.dir, 180) == beacon.dir) : FALSE
	data["console_found"] = !!_valid_linked_console(envelope)
	data["console_link_broken"] = !!linked_shuttle_console && !_valid_linked_console(envelope)
	data["propulsion_required"] = SHIP_COMMISSION_MIN_PROPULSION
	data["propulsion_count"] = envelope ? _drydock_envelope_count_propulsion(envelope) : 0
	data["propulsion_found"] = data["propulsion_count"] >= SHIP_COMMISSION_MIN_PROPULSION
	data["helm_found"] = envelope ? !!_drydock_envelope_find_helm(envelope) : FALSE
	data["navigation_found"] = envelope ? !!_drydock_envelope_find_navigation(envelope) : FALSE
	data["engine_control_found"] = envelope ? !!_drydock_envelope_find_engine_control(envelope) : FALSE
	// Either a piped nozzle engine or a self-contained ion engine satisfies
	// the engine requirement -- see _drydockCommissionRun()'s own matching
	// check (persistence_shuttles.dm). No fuel port check here -- it's
	// backup/emergency fuel only, never required to commission.
	data["ship_engine_found"] = envelope ? !!_drydock_envelope_find_ship_engine(envelope) : FALSE
	data["ion_engine_found"] = envelope ? !!_drydock_envelope_find_ion_engine(envelope) : FALSE
	data["sensors_terminal_found"] = envelope ? !!_drydock_envelope_find_sensors_terminal(envelope) : FALSE
	data["sensor_array_found"] = envelope ? !!_drydock_envelope_find_sensor_array(envelope) : FALSE
	// Snapshot from the last Preview -- see envelope_clean_for_generate's
	// own doc comment for why this isn't re-checked live here.
	data["can_generate_floor"] = data["beacon_found"] && envelope_clean_for_generate
	// Gates the admin-only envelope wipe below. Re-checked server-side in
	// ui_act() too -- never trust client-side hiding alone.
	data["is_admin"] = !!check_rights(R_ADMIN, 0, user)
	// Deliberately NOT beacon_found -- see _admin_envelope_beacon()'s own doc
	// comment for why the admin wipe must still work with a deactivated or
	// out-of-range beacon.
	data["admin_wipe_available"] = !!_admin_envelope_beacon()
	return data

/obj/structure/machinery/computer/ship_commissioning/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		// Admin-only counterpart to the "Clear Docking Beacons" verb
		// (persistence_shuttles.dm), scoped to just this console's own
		// envelope: wipes it back to open space and forgets its saved rows,
		// for clearing a half-built or leftover hull without hunting down the
		// beacon it belongs to.
		if("admin_wipe_envelope")
			if(!check_rights(R_ADMIN, 0, user))
				return
			var/list/turf/wipe_envelope = _get_admin_envelope_turfs()
			if(!length(wipe_envelope))
				to_chat(user, SPAN_WARNING("No beacon linked to this console (or it's on another z) -- there's no envelope to define. Link one first."))
				return
			// Never wipe with anyone still inside -- refuse rather than leave
			// them floating in open space. Re-checked here (not just at the
			// prompt) so someone stepping in mid-dialog is still caught. Same
			// gate commissioning itself uses, so it also covers an occupied
			// neural lace lying there, not just a body.
			if(_drydock_envelope_has_occupants(wipe_envelope))
				to_chat(user, SPAN_WARNING("Someone (or an occupied neural lace) is still inside the build envelope -- refusing to wipe."))
				return
			if(tgui_alert(user, "Wipe this console's entire build envelope back to open space and forget its saved turf/object rows? This cannot be undone.", "Wipe Build Envelope", list("Wipe", "Cancel")) != "Wipe")
				return
			if(_drydock_envelope_has_occupants(wipe_envelope))
				to_chat(user, SPAN_WARNING("Someone stepped into the build envelope -- refusing to wipe."))
				return
			// Physical guard, independent of any docking bookkeeping -- a
			// shuttle area covering these tiles means a real hull is on them.
			// See _drydock_envelope_shuttle_turf() (persistence_shuttles.dm):
			// trusting current_location instead of the turfs is exactly what
			// let the Clear Docking Beacons verb delete a live ship.
			var/turf/occupied_by_ship = _drydock_envelope_shuttle_turf(wipe_envelope)
			if(occupied_by_ship)
				to_chat(user, SPAN_WARNING("A ship's hull is currently sitting on this envelope ([get_area(occupied_by_ship)]) -- refusing to wipe. Undock it first."))
				log_and_message_admins("admin envelope wipe REFUSED -- a ship's hull ([get_area(occupied_by_ship)]) is on the envelope.", user, occupied_by_ship)
				return
			for(var/turf/T in wipe_envelope)
				T.ChangeTurf(get_base_turf_by_area(T))
			SSpersistence.turfsForget(wipe_envelope)
			SSpersistence.objectsForget(wipe_envelope)
			envelope_clean_for_generate = FALSE
			log_and_message_admins("wiped a ship commissioning build envelope ([length(wipe_envelope)] tiles) and forgot its persistence rows.", user, get_turf(src))
			to_chat(user, SPAN_GOOD("Build envelope wiped to open space and forgotten ([length(wipe_envelope)] tiles)."))
			. = TRUE

		if("clear_links")
			_clear_all_links()
			to_chat(user, SPAN_NOTICE("Cleared all device links -- multitool a beacon, transponder, and shuttle control console (Buffer), then multitool this console to relink them."))
			. = TRUE
		if("set_build_size")
			var/new_x = tgui_input_number(user, "Build envelope width (X), [PLAYER_BUILD_ENVELOPE_MIN]-[PLAYER_BUILD_ENVELOPE_MAX]:", "Set Build Size", build_envelope_x, PLAYER_BUILD_ENVELOPE_MAX, PLAYER_BUILD_ENVELOPE_MIN)
			if(isnull(new_x))
				return TRUE
			var/new_y = tgui_input_number(user, "Build envelope height (Y), [PLAYER_BUILD_ENVELOPE_MIN]-[PLAYER_BUILD_ENVELOPE_MAX]:", "Set Build Size", build_envelope_y, PLAYER_BUILD_ENVELOPE_MAX, PLAYER_BUILD_ENVELOPE_MIN)
			if(isnull(new_y))
				return TRUE
			build_envelope_x = clamp(new_x, PLAYER_BUILD_ENVELOPE_MIN, PLAYER_BUILD_ENVELOPE_MAX)
			build_envelope_y = clamp(new_y, PLAYER_BUILD_ENVELOPE_MIN, PLAYER_BUILD_ENVELOPE_MAX)
			// Stale relative to the new size -- force a fresh Preview before
			// Generate Build Floor/Commission can be trusted again.
			QDEL_LIST(envelope_indicators)
			envelope_clean_for_generate = FALSE
			to_chat(user, SPAN_NOTICE("Build envelope size set to [build_envelope_x]x[build_envelope_y] -- preview again to see it."))
			. = TRUE
		if("preview")
			_show_envelope_preview(user)
			. = TRUE
		if("generate_floor")
			_generate_build_floor(user)
			. = TRUE
		if("commission")
			var/as_faction = params["as_faction"] ? TRUE : FALSE
			var/dock_at_beacon = params["dock_at_beacon"] ? TRUE : FALSE
			var/obj/item/card/id/ID = user.GetIdCard()
			var/faction_uid = as_faction ? ((ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null) : null
			var/new_name = tgui_input_text(user, "Name this shuttle:", "Commission Shuttle", max_length = 64)
			if(!new_name)
				return TRUE
			SSpersistence.drydockCommission(src, user, faction_uid, new_name, dock_at_beacon)
			. = TRUE

/// Validated linked_beacon, or null -- must still exist, be anchored and
/// active, and (kept as a sanity bound, not a discovery mechanism -- an
/// explicitly linked beacon halfway across the map would make every
/// envelope computation below nonsensical) be on the same z and within
/// BUILD_ENVELOPE_BEACON_RANGE of this console. Deactivated/out-of-range is
/// reported invalid here but NOT cleared -- see linked_beacon's own doc
/// comment above.
/obj/structure/machinery/computer/ship_commissioning/proc/_valid_linked_beacon()
	// Lazy tag resolution -- only reached post-boot (this proc is only ever
	// called on demand, from ui_data()/ui_act()/preview/generate, never
	// during the restore pass itself), so the target device has always had
	// a chance to finish instantiating by now. Resolves once, then caches
	// into linked_beacon itself exactly as if freshly multitool-linked --
	// see linked_beacon_tag's own doc comment above.
	if(!linked_beacon && linked_beacon_tag)
		var/atom/movable/resolved = GLOB.drydock_linkable_devices_by_tag[linked_beacon_tag]
		if(istype(resolved, /obj/structure/machinery/docking_beacon))
			_link_device("beacon", resolved)
	if(!linked_beacon)
		return null
	if(!linked_beacon.anchored || !linked_beacon.beacon_active)
		return null
	if(linked_beacon.z != z || get_dist(src, linked_beacon) > BUILD_ENVELOPE_BEACON_RANGE)
		return null
	return linked_beacon

/// Validated linked_transponder, or null -- must still be physically inside
/// the given (already-beacon-derived) envelope. Preserves the original
/// safety property the old "find any transponder in the envelope" discovery
/// had (the linked device must genuinely be part of the built hull), just
/// checked against a specific identity instead of scanning for any match.
/obj/structure/machinery/computer/ship_commissioning/proc/_valid_linked_transponder(list/turf/envelope)
	if(!linked_transponder && linked_transponder_tag)
		var/atom/movable/resolved = GLOB.drydock_linkable_devices_by_tag[linked_transponder_tag]
		if(istype(resolved, /obj/structure/machinery/docking_transponder))
			_link_device("transponder", resolved)
	if(!linked_transponder || !envelope)
		return null
	if(!(get_turf(linked_transponder) in envelope))
		return null
	return linked_transponder

/// Same shape as _valid_linked_transponder() above, for the required
/// shuttle_control console.
/obj/structure/machinery/computer/ship_commissioning/proc/_valid_linked_console(list/turf/envelope)
	if(!linked_shuttle_console && linked_shuttle_console_tag)
		var/atom/movable/resolved = GLOB.drydock_linkable_devices_by_tag[linked_shuttle_console_tag]
		if(istype(resolved, /obj/structure/machinery/computer/shuttle_control))
			_link_device("console", resolved)
	if(!linked_shuttle_console || !envelope)
		return null
	if(!(get_turf(linked_shuttle_console) in envelope))
		return null
	return linked_shuttle_console

/// Bottom-left corner turf of the build envelope for the given beacon (or
/// null if it/its turf is gone) -- the shared reference point
/// _get_envelope_turfs(), _show_envelope_preview(), and
/// _drydockCommissionRun() (persistence_shuttles.dm) all derive the same
/// SUBSHIP_FOOTPRINT_X x SUBSHIP_FOOTPRINT_Y block from, so the preview and
/// the actual capture can never disagree about which tiles are covered.
///
/// The box sits one tile clear of the beacon on whichever side it's
/// currently facing, not centered on it and not flush against it -- rotate
/// the beacon (multitool) to choose which of the four cardinal directions
/// the hull gets built in. The beacon's own tile always sits just OUTSIDE
/// the box (one tile of open floor between the beacon and the hull's
/// nearest edge, like a real dock marker standing clear of the airlock it
/// serves) -- excluded from capture/wipe by object reference regardless,
/// see _drydockCommissionRun(), but no longer inside the envelope's own
/// bounds at all. That nearest edge is also the exact one
/// _show_envelope_preview() tints -- turn(beacon.dir, 180), the direction a
/// docking_transponder needs to face, always lands on that same edge.
/// Beacon resolution for the ADMIN envelope wipe specifically -- deliberately
/// looser than _valid_linked_beacon() above.
///
/// That proc additionally requires the beacon be anchored, `beacon_active`,
/// and within BUILD_ENVELOPE_BEACON_RANGE, which is correct for deciding
/// whether a player may commission -- but it means the admin wipe goes dead
/// exactly when it's most needed, since deactivating or unlinking the beacon
/// is precisely what happens while cleaning up an abandoned build. Only the
/// same-z requirement is kept, because envelope geometry is meaningless
/// without it.
/obj/structure/machinery/computer/ship_commissioning/proc/_admin_envelope_beacon()
	if(!linked_beacon && linked_beacon_tag)
		var/atom/movable/resolved = GLOB.drydock_linkable_devices_by_tag[linked_beacon_tag]
		if(istype(resolved, /obj/structure/machinery/docking_beacon))
			linked_beacon = resolved
	if(!linked_beacon || linked_beacon.z != z)
		return null
	return linked_beacon

/// The envelope block for the admin wipe, resolved through
/// _admin_envelope_beacon() rather than the commission-grade validity check.
/obj/structure/machinery/computer/ship_commissioning/proc/_get_admin_envelope_turfs()
	var/obj/structure/machinery/docking_beacon/beacon = _admin_envelope_beacon()
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		return null
	return block(corner, locate(corner.x + build_envelope_x - 1, corner.y + build_envelope_y - 1, corner.z))

/// Thin wrapper over the shared beacon geometry (docking_beacon_envelope_corner(),
/// docking_beacon.dm) at THIS console's own configured build size -- the pad
/// cleanup sweeps resolve the same beacon through the same proc at the
/// beacon's own max footprint instead, so the two can never disagree about
/// where a pad's tiles actually are.
/obj/structure/machinery/computer/ship_commissioning/proc/_get_envelope_corner(obj/structure/machinery/docking_beacon/beacon)
	return docking_beacon_envelope_corner(beacon, build_envelope_x, build_envelope_y)

/// The SUBSHIP_FOOTPRINT_X x SUBSHIP_FOOTPRINT_Y block of turfs the build
/// envelope covers, positioned per _get_envelope_corner() -- null if no
/// beacon is currently linked (or the link isn't valid right now). Shared by
/// the preview and the commission validation so they always agree on
/// exactly the same tiles.
/obj/structure/machinery/computer/ship_commissioning/proc/_get_envelope_turfs()
	var/obj/structure/machinery/docking_beacon/beacon = _valid_linked_beacon()
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		return null
	return block(corner, locate(corner.x + build_envelope_x - 1, corner.y + build_envelope_y - 1, corner.z))

/// Highlights the build envelope, same shuttle_warning indicator any ship
/// landing preview already uses -- except the one edge matching where the
/// docking transponder needs to face (the exact opposite of the beacon's
/// own dir, same comparison drydockCommission() enforces) is tinted to
/// match the transponder's own color, so it's visually obvious which side
/// of the box to build your airlock on instead of having to reason about
/// facings abstractly.
/obj/structure/machinery/computer/ship_commissioning/proc/_show_envelope_preview(mob/user)
	QDEL_LIST(envelope_indicators)
	envelope_clean_for_generate = FALSE
	var/obj/structure/machinery/docking_beacon/beacon = _valid_linked_beacon()
	if(!beacon)
		to_chat(user, linked_beacon \
			? SPAN_WARNING("Linked beacon isn't valid right now -- deactivated, unanchored, or out of range. Reactivate it, or multitool a different beacon (Buffer) and link it to this console.") \
			: SPAN_WARNING("No beacon linked -- multitool a docking beacon, choose Buffer, then multitool this console to link it."))
		return
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		to_chat(user, SPAN_WARNING("The build envelope runs off the edge of the map."))
		return
	var/list/turf/envelope = block(corner, locate(corner.x + build_envelope_x - 1, corner.y + build_envelope_y - 1, corner.z))
	envelope_clean_for_generate = !_envelope_generate_conflict(envelope, beacon)
	var/required_facing = turn(beacon.dir, 180)
	for(var/turf/T in envelope)
		var/is_airlock_edge = FALSE
		switch(required_facing)
			if(EAST)
				is_airlock_edge = (T.x == corner.x + build_envelope_x - 1)
			if(WEST)
				is_airlock_edge = (T.x == corner.x)
			if(NORTH)
				is_airlock_edge = (T.y == corner.y + build_envelope_y - 1)
			if(SOUTH)
				is_airlock_edge = (T.y == corner.y)
		var/obj/effect/shuttle_warning/indicator = new(T)
		if(is_airlock_edge)
			indicator.color = "#3a2210"
		envelope_indicators += indicator
	addtimer(CALLBACK(src, PROC_REF(_clear_envelope_preview)), 10 SECONDS)
	to_chat(user, SPAN_NOTICE("Build envelope highlighted -- [build_envelope_x]x[build_envelope_y] tiles, extending [dir2text(beacon.dir)] from the beacon. The tinted edge (facing [dir2text(required_facing)]) is where your airlock and transponder need to go."))
	to_chat(user, envelope_clean_for_generate \
		? SPAN_NOTICE("Envelope is clear -- Generate Build Floor is available.") \
		: SPAN_WARNING("Envelope already has something built or standing in it -- Generate Build Floor is unavailable until it's clear."))

/obj/structure/machinery/computer/ship_commissioning/proc/_clear_envelope_preview()
	QDEL_LIST(envelope_indicators)

/// TRUE if any tile in the envelope is neither open space nor genuinely
/// empty floor -- a dense turf (wall), a dense or loose object, or a mob
/// (dead or alive) all count. The beacon's own tile and this console's own
/// tile (if it happens to sit inside the envelope) are never a conflict --
/// same exclusion _drydockCommissionRun()'s own capture pass uses -- and
/// /obj/effect instances (indicators, landmarks) don't count either, since
/// they're not real placed structures.
/obj/structure/machinery/computer/ship_commissioning/proc/_envelope_generate_conflict(list/turf/envelope, obj/structure/machinery/docking_beacon/beacon)
	for(var/turf/T in envelope)
		if(T == get_turf(beacon) || T == get_turf(src))
			continue
		if(isspaceturf(T) || isopenspace(T))
			continue // open space -- exactly what Generate is meant to fill in
		if(T.density)
			return TRUE
		for(var/atom/movable/M in T)
			if(istype(M, /obj/effect))
				continue
			return TRUE // something is already built or standing here
	return FALSE

/// Fills every currently-open-space tile in the envelope with plain
/// plating -- an unfinished subfloor, not a finished floor, so the sealed-
/// hull check at commission time still requires the player to actually
/// wall it in. Never touches a tile that already has anything on it (walls,
/// objects, mobs) or that's already ordinary floor -- re-verifies the
/// conflict check fresh here rather than trusting whatever the TGUI showed
/// from the last Preview, since the envelope could have changed since then.
/obj/structure/machinery/computer/ship_commissioning/proc/_generate_build_floor(mob/user)
	var/obj/structure/machinery/docking_beacon/beacon = _valid_linked_beacon()
	if(!beacon)
		to_chat(user, linked_beacon \
			? SPAN_WARNING("Linked beacon isn't valid right now -- deactivated, unanchored, or out of range.") \
			: SPAN_WARNING("No beacon linked -- multitool a docking beacon, choose Buffer, then multitool this console to link it."))
		return
	var/turf/corner = _get_envelope_corner(beacon)
	if(!corner)
		to_chat(user, SPAN_WARNING("The build envelope runs off the edge of the map."))
		return
	var/list/turf/envelope = block(corner, locate(corner.x + build_envelope_x - 1, corner.y + build_envelope_y - 1, corner.z))
	if(_envelope_generate_conflict(envelope, beacon))
		to_chat(user, SPAN_WARNING("Can't generate a build floor -- something's already built or standing in the envelope. Preview again to see what's blocking it."))
		return
	var/filled = 0
	for(var/turf/T in envelope)
		if(T == get_turf(beacon) || T == get_turf(src))
			continue
		if(isspaceturf(T) || isopenspace(T))
			T.ChangeTurf(/turf/simulated/floor/plating)
			filled++
	to_chat(user, SPAN_GOOD("Build floor generated -- [filled] tile[filled == 1 ? "" : "s"] filled in. Wall it in and build your hull."))
