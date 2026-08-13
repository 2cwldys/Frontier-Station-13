//base type for controllers of two-door systems
/obj/structure/machinery/embedded_controller/radio/airlock
	obj_flags = OBJ_FLAG_MOVES_UNSUPPORTED
	// Setup parameters only
	radio_filter = RADIO_AIRLOCK
	var/tag_exterior_door
	var/tag_interior_door
	/// Additional exterior/interior door tags beyond the primary singular
	/// slot above -- mirrors tag_airpumps' own extra-tag pattern below. A
	/// chamber wide enough to need more than one door on a side gets one
	/// entry here per extra door; every open/close/lock/unlock command goes
	/// to all of them together (see get_exterior_door_tags()/
	/// get_interior_door_tags()).
	var/list/tag_exterior_doors
	var/list/tag_interior_doors
	/// Primary chamber vent pump tag. Kept as a plain string for mapped-in
	/// cyclers, which set it directly in their .dmm.
	var/tag_airpump
	/// Additional chamber vent pump tags beyond tag_airpump. A chamber wide
	/// enough to need more than one vent gets one entry here per extra pump;
	/// every cycle command is issued to all of them together (see
	/// get_airpump_tags()).
	var/list/tag_airpumps
	var/tag_chamber_sensor
	var/tag_exterior_sensor
	var/tag_interior_sensor
	var/tag_airlock_mech_sensor
	var/tag_shuttle_mech_sensor
	var/tag_secure = FALSE
	var/tag_air_alarm
	var/cycle_to_external_air = FALSE
	var/has_interior_sensor
	var/has_exterior_sensor
	/// Faction tagger compatible var -- "" (untagged) or a real faction_uid.
	/// Tagging a cycler controller locks its LINKS: only people employed by
	/// that faction (or an admin) can add, remove or reset the doors, pumps and
	/// sensors it drives. Without it, anyone with a multitool could rewire or
	/// wipe a faction's airlock cycler -- which is both an access bypass (link
	/// a chamber to doors you shouldn't control) and a griefing vector (clear
	/// the links and strand the cycler mid-cycle). Untagged controllers behave
	/// exactly as before, so ordinary construction is unaffected.
	/// Persisted via worldstate_vars (persistence_worldstate.dm).
	var/persistent_network = ""

// ------- Faction tagger compatibility -------

/obj/structure/machinery/embedded_controller/radio/airlock/faction_tagger_compatible()
	return TRUE

/obj/structure/machinery/embedded_controller/radio/airlock/faction_tagger_get_uid()
	return persistent_network

/obj/structure/machinery/embedded_controller/radio/airlock/faction_tagger_set(new_uid, mob/user)
	var/old_uid = persistent_network
	persistent_network = new_uid || ""
	// Ownership changing hands drops every link. Otherwise links made while the
	// cycler was untagged survive the tag: someone wires a chamber to their own
	// doors and sensors, a faction then claims the cycler, and the original
	// wiring keeps working from outside the faction entirely -- the guards only
	// stop links being CHANGED, not ones that already exist. Releasing a tag
	// clears them for the same reason in reverse.
	if(old_uid != persistent_network)
		_clear_links_on_faction_change(user, old_uid)
	return TRUE

/// Drops every door/sensor/button/pump link, because this cycler just changed
/// hands. Separate from _reset_links() (the player-facing multitool action):
/// this one is not refusable and reports itself as a consequence of the retag.
/obj/structure/machinery/embedded_controller/radio/airlock/proc/_clear_links_on_faction_change(mob/user, old_uid)
	var/cleared = 0
	// Doors need no per-door clearing: an airlock has no master_tag of its own,
	// so dropping this controller's own door slots below is what unlinks them.
	for(var/obj/structure/machinery/airlock_sensor/S in SSmachinery.machinery)
		if(S.master_tag == id_tag)
			S.master_tag = null
			cleared++
	for(var/obj/structure/machinery/access_button/B in SSmachinery.machinery)
		if(B.master_tag == id_tag)
			B.master_tag = null
			cleared++
	if(tag_exterior_door || tag_interior_door || length(tag_exterior_doors) || length(tag_interior_doors) || tag_airpump || length(tag_airpumps) || tag_chamber_sensor || tag_exterior_sensor || tag_interior_sensor)
		cleared++
	tag_exterior_door = null
	tag_interior_door = null
	tag_exterior_doors = null
	tag_interior_doors = null
	tag_airpump = null
	tag_airpumps = null
	tag_chamber_sensor = null
	tag_exterior_sensor = null
	tag_interior_sensor = null
	if(cleared && user)
		to_chat(user, SPAN_WARNING("\The [src] changed hands -- its existing links have been cleared and must be set up again."))
	if(cleared)
		log_game("Airlock cycler at [COORD(src)] changed faction ('[old_uid || "unassigned"]' -> '[persistent_network || "unassigned"]'), clearing its links.")

/// Whether user may change this controller's links.
///
/// Untagged and "public" controllers stay open to everyone; a real faction tag
/// needs EMPLOYMENT by that faction. See can_rewire_faction_device()
/// (persistence_factions.dm) for the shared rule -- printing yourself an ID does
/// not count, that registers as FACTION_RANK_CIVILIAN (card.dm).
/obj/structure/machinery/embedded_controller/radio/airlock/proc/can_modify_links(mob/user)
	return can_rewire_faction_device(user, persistent_network)

/obj/structure/machinery/embedded_controller/radio/airlock/Initialize(mapload, given_id_tag, given_frequency, given_tag_exterior_door, given_tag_interior_door, given_tag_airpump, given_tag_chamber_sensor)
	. = ..()
	if(given_id_tag)
		id_tag = given_id_tag
	if(given_frequency)
		set_frequency(given_frequency)
	if(given_tag_exterior_door)
		tag_exterior_door = given_tag_exterior_door
	if(given_tag_interior_door)
		tag_interior_door = given_tag_interior_door
	if(given_tag_airpump)
		tag_airpump = given_tag_airpump
	if(given_tag_chamber_sensor)
		tag_chamber_sensor = given_tag_chamber_sensor
	program = new /datum/computer/file/embedded_program/airlock(src)

/obj/structure/machinery/embedded_controller/radio/airlock/attackby(obj/item/attacking_item, mob/user)
	//Swiping ID on the access button
	if (attacking_item.GetID())
		attack_hand(user)
		return TRUE
	return ..()

/obj/structure/machinery/embedded_controller/radio/airlock/attack_hand(mob/user)
	if(!allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return FALSE
	return ..()

//Advanced airlock controller for when you want a more versatile airlock controller - useful for turning simple access control rooms into airlocks
/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller
	name = "Advanced Airlock Controller"

/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockConsoleAdvanced", name, ui_x=470, ui_y=290)
		ui.open()

/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_data(mob/user)
	var/list/data = list()

	data["chamber_pressure"] = round(program.memory["chamber_sensor_pressure"])
	data["has_exterior_sensor"] = has_exterior_sensor
	data["external_pressure"] = round(program.memory["external_sensor_pressure"])
	data["has_interior_sensor"] = has_interior_sensor
	data["internal_pressure"] = round(program.memory["internal_sensor_pressure"])
	data["processing"] = program.memory["processing"]
	data["purge"] = program.memory["purge"]
	data["secure"] = program.memory["secure"]

	return data

/obj/structure/machinery/embedded_controller/radio/airlock/advanced_airlock_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "command")
		var/command_name = sanitize(params["command"])
		program.receive_user_command(command_name)

//Airlock controller for airlock control - most airlocks on the station use this
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller
	name = "Airlock Controller"
	tag_secure = TRUE

	/// 2 = complete/wired, 1 = circuit inserted but unwired, 0 = frame only.
	/// Player-built via /obj/item/frame/airlock_controller; mapped-in/preset
	/// controllers default to 2 (already finished).
	/// panel_open is inherited from base /obj/structure/machinery.
	var/buildstage = 2

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/Initialize(mapload, var/dir, var/building = 0)
	. = ..(mapload)
	if(building)
		if(dir)
			set_dir(dir)
		apply_wall_mount_offset()
		buildstage = 0
	update_icon()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/persistence_reapply_wall_offset()
	apply_wall_mount_offset()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/persistent_objects_get_content()
	. = ..()
	.["buildstage"] = buildstage
	.["panel_open"] = panel_open

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/persistent_objects_apply_content(list/content, x, y, z)
	..()
	if(!islist(content))
		return
	if("buildstage" in content)
		buildstage = text2num(content["buildstage"])
	if("panel_open" in content)
		panel_open = content["panel_open"]
	update_icon()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/update_icon()
	if(buildstage < 2)
		ClearOverlays()
		return
	return ..()

/// Auto-assigns a unique id_tag the first time this controller is linked to
/// a door/sensor/button -- there's no in-game tool to type in a custom tag,
/// and a blank/null id_tag would make every untagged controller match every
/// other untagged device's blank slot.
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_ensure_id_tag()
	if(!id_tag)
		id_tag = "cycler_[REF(src)]"
	return id_tag

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/attackby(obj/item/attacking_item, mob/user)
	if(_handle_construction(attacking_item, user))
		return TRUE
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		// Covers every link change initiated FROM the controller -- doors,
		// sensors, access buttons, pumps and the Reset Links wipe alike. The
		// opposite direction (buffer this controller, then multitool the
		// device) is gated separately inside each _link_to_controller()
		// (airlock_control.dm); gating only one side would leave the other
		// wide open.
		if(!can_modify_links(user))
			to_chat(user, SPAN_WARNING("\The [src] is tagged to [get_faction_name(persistent_network)] -- you are not employed there, so you cannot change its links."))
			return TRUE
		var/obj/structure/machinery/door/airlock/door = MT.get_buffer(/obj/structure/machinery/door/airlock)
		if(door)
			door._link_to_controller(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/airlock_sensor/sensor = MT.get_buffer(/obj/structure/machinery/airlock_sensor)
		if(sensor)
			sensor._link_to_controller(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/access_button/button = MT.get_buffer(/obj/structure/machinery/access_button)
		if(button)
			button._link_to_controller(src, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/atmospherics/unary/vent_pump/pump = MT.get_buffer(/obj/structure/machinery/atmospherics/unary/vent_pump)
		if(pump)
			_link_to_airpump(pump, user)
			MT.set_buffer(null)
			return TRUE
		// Empty multitool on the controller itself -- ambiguous between "I
		// want to buffer this controller to go link something to it" and "I
		// want to wipe this controller's links and start over," so ask
		// instead of always assuming the former.
		var/choice = tgui_alert(user, "What would you like to do with \the [src]?", "Airlock Cycler", list("Buffer", "Reset Links"))
		if(QDELETED(src) || QDELETED(user) || QDELETED(MT) || !user.Adjacent(src))
			return TRUE
		if(!choice)
			return TRUE
		if(choice == "Reset Links")
			_reset_links(user)
			return TRUE
		MT.set_buffer(src)
		to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
		return TRUE
	return ..()

/// Wipes every door/sensor/pump/button link this controller has in one
/// action -- the multitool-on-empty-buffer popup's "Reset Links" choice
/// (attackby() above). Doors and pumps are entirely controller-side (no
/// back-reference stored on the device itself), so clearing these fields
/// alone fully unlinks them. Sensors and buttons carry their own back-
/// reference (master_tag) to this controller for their manual cycle signal
/// -- clearing only the controller's own fields would leave those stale
/// (still believing they're linked here), so sweep and clear both
/// directions at once. World-scoped scan, same shape as
/// _sweep_stray_umbilicals() (drydock_ship.dm) -- a rare, deliberate player
/// action, not a hot path.
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_reset_links(mob/user)
	var/count = length(get_exterior_door_tags()) + length(get_interior_door_tags()) + length(get_airpump_tags())
	tag_exterior_door = null
	tag_exterior_doors = null
	tag_interior_door = null
	tag_interior_doors = null
	tag_airpump = null
	tag_airpumps = null
	// Only bother scanning for sensors if this controller actually has one
	// linked -- _link_to_controller() (airlock_control.dm) always sets a
	// sensor's master_tag together with one of these three fields in the
	// same operation, so if all three are already unset, no sensor can have
	// master_tag pointing here either.
	if(tag_chamber_sensor || tag_exterior_sensor || tag_interior_sensor)
		for(var/obj/structure/machinery/airlock_sensor/S in world)
			if(S.master_tag == id_tag)
				S.master_tag = null
				count++
		tag_chamber_sensor = null
		tag_exterior_sensor = null
		tag_interior_sensor = null
	// Buttons have no controller-side counterpart field at all to check
	// first -- always scan.
	for(var/obj/structure/machinery/access_button/B in world)
		if(B.master_tag == id_tag)
			B.master_tag = null
			count++
	to_chat(user, SPAN_NOTICE("You reset \the [src], clearing [count] link\s. Doors, sensors, pumps, and buttons are all unlinked -- relink them individually if needed."))

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_handle_construction(obj/item/attacking_item, mob/user)
	switch(buildstage)
		if(0)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				set_dir(turn(dir, -90))
				to_chat(user, SPAN_NOTICE("You rotate \the [src]."))
				return TRUE
			if(istype(attacking_item, /obj/item/airlock_cycler_electronics/airlock_controller))
				to_chat(user, SPAN_NOTICE("You insert the circuit board."))
				qdel(attacking_item)
				buildstage = 1
				update_icon()
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You remove \the [src] from the wall."))
				new /obj/item/frame/airlock_controller(get_turf(user))
				attacking_item.play_tool_sound(get_turf(src), 50)
				qdel(src)
				return TRUE
		if(1)
			if(attacking_item.tool_behaviour == TOOL_CABLECOIL)
				var/obj/item/stack/cable_coil/C = attacking_item
				if(C.use(5))
					to_chat(user, SPAN_NOTICE("You wire \the [src]."))
					buildstage = 2
					update_icon()
					// Player-built cyclers were never registered for position/
					// existence tracking (objectsRegisterTrack()), unlike
					// cryopods/telepads -- so a saved worldstate row (tags,
					// frequency, buildstage) had nothing to apply itself to on
					// the next boot and the whole controller had to be rebuilt
					// and relinked from scratch. This is the only place a
					// player-built controller ever reaches buildstage 2 --
					// mapped-in ones start there directly and never hit this.
					if(GLOB.config.sql_enabled && GLOB.persistence_ready)
						SSpersistence.objectsRegisterTrack(src)
				else
					to_chat(user, SPAN_WARNING("You need 5 pieces of cable to wire \the [src]."))
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You pry out the circuit board."))
				new /obj/item/airlock_cycler_electronics/airlock_controller(get_turf(user))
				attacking_item.play_tool_sound(get_turf(src), 50)
				buildstage = 0
				update_icon()
				return TRUE
		if(2)
			if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
				panel_open = !panel_open
				to_chat(user, SPAN_NOTICE("You [panel_open ? "open" : "close"] \the [src]'s panel."))
				return TRUE
			if(panel_open && attacking_item.tool_behaviour == TOOL_WIRECUTTER)
				to_chat(user, SPAN_NOTICE("You cut \the [src]'s wires."))
				new /obj/item/stack/cable_coil(get_turf(src), 5)
				buildstage = 1
				update_icon()
				return TRUE
	return FALSE

/// Toggle-links (or unlinks) an air vent to this controller's chamber pump
/// slot (tag_airpump) -- the "pressurize/depressurize" pump the controller
/// commands during a cycle. Vents already have a guaranteed non-null id_tag
/// (auto-assigned on their own Initialize()), so no _ensure_id_tag() step
/// is needed here, unlike doors/sensors/buttons.
/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/proc/_link_to_airpump(obj/structure/machinery/atmospherics/unary/vent_pump/pump, mob/user)
	_ensure_id_tag()
	pump._ensure_id_tag()
	// Toggle off if this exact pump is already linked, in either slot.
	if(tag_airpump == pump.id_tag)
		// Promote an extra into the primary slot so removing the first pump
		// doesn't orphan the rest.
		tag_airpump = null
		if(LAZYLEN(tag_airpumps))
			tag_airpump = tag_airpumps[1]
			tag_airpumps -= tag_airpump
		to_chat(user, SPAN_NOTICE("You unlink \the [pump] from \the [src]. ([length(get_airpump_tags())] pump\s still linked.)"))
		return
	if(pump.id_tag in tag_airpumps)
		tag_airpumps -= pump.id_tag
		to_chat(user, SPAN_NOTICE("You unlink \the [pump] from \the [src]. ([length(get_airpump_tags())] pump\s still linked.)"))
		return

	if(!tag_airpump)
		tag_airpump = pump.id_tag
	else
		LAZYDISTINCTADD(tag_airpumps, pump.id_tag)
	pump.set_frequency(frequency)
	// Force the vent to re-scan for an adjacent pipe. atmos_init() bails
	// immediately on `if(node) return`, so a vent that initialized BEFORE its
	// pipes were laid keeps node == null permanently and reports "no pipe"
	// even when it's sitting against a fully pressurised run. Linking it to a
	// cycler is a deliberate player action and the natural point to retry.
	pump.node = null
	pump.atmos_init()
	pump.build_network()
	// Re-derive the pump's NOPOWER bit against its current area. Same reason
	// as the node re-scan: a machine whose turf was reassigned into another
	// area (blueprints) never recomputed it, so an otherwise-fine pump can sit
	// there insisting it has no power. Lets an already-broken cycler fix
	// itself on relink instead of needing the area rebuilt.
	pump.power_change()
	to_chat(user, SPAN_NOTICE("You link \the [pump] to \the [src] as a chamber vent pump and tune it to the controller's frequency. ([length(get_airpump_tags())] pump\s linked.)"))
	// atmos_init() (unary_base.dm) only ever looks ONE tile in the vent's OWN
	// dir for a pipe -- if node is still null after the re-scan above, this
	// pump will silently self-disable every tick forever
	// (vent_pump/process()'s `if(!node) update_use_power(POWER_USE_OFF)`),
	// commanded correctly by the controller or not. Without this, that only
	// ever shows up much later as "the cycle doesn't work", with nothing
	// pointing back at this specific pump or its facing. Surface it the
	// moment it happens instead.
	if(!pump.node)
		to_chat(user, SPAN_WARNING("\The [pump] has no pipe connected in the direction it's facing -- it will link, but won't actually pump air until it's rotated to face its pipe (or the pipe is run to that side)."))

/// Every chamber vent pump tag this controller drives -- the primary plus any
/// extras. Cycle commands go to all of them so a chamber with more than one
/// vent pressurises/depressurises as a unit.
/obj/structure/machinery/embedded_controller/radio/airlock/proc/get_airpump_tags()
	. = list()
	if(tag_airpump)
		. += tag_airpump
	for(var/extra_tag in tag_airpumps)
		if(extra_tag && !(extra_tag in .))
			. += extra_tag

/// Every linked exterior door tag (primary plus any extras) -- see
/// get_airpump_tags()'s own doc comment above, same shape.
/obj/structure/machinery/embedded_controller/radio/airlock/proc/get_exterior_door_tags()
	. = list()
	if(tag_exterior_door)
		. += tag_exterior_door
	for(var/extra_tag in tag_exterior_doors)
		if(extra_tag && !(extra_tag in .))
			. += extra_tag

/// Every linked interior door tag (primary plus any extras).
/obj/structure/machinery/embedded_controller/radio/airlock/proc/get_interior_door_tags()
	. = list()
	if(tag_interior_door)
		. += tag_interior_door
	for(var/extra_tag in tag_interior_doors)
		if(extra_tag && !(extra_tag in .))
			. += extra_tag

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/ui_interact(mob/user, datum/tgui/ui)
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockConsoleStandard", name, ui_x=470, ui_y=290)
		ui.open()

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/ui_data(mob/user)
	var/list/data = list()

	data["chamber_pressure"] = round(program.memory["chamber_sensor_pressure"])
	data["processing"] = program.memory["processing"]
#ifdef AIRLOCK_CYCLER_DIAGNOSTICS
	data["diagnostics"] = program.get_diagnostics()
#endif

	return data

/obj/structure/machinery/embedded_controller/radio/airlock/airlock_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "command")
		var/command_name = sanitize(params["command"])
		program.receive_user_command(command_name)

//Access controller for door control - used in virology and the like
/obj/structure/machinery/embedded_controller/radio/airlock/access_controller
	icon = 'icons/obj/airlock_machines.dmi'
	icon_state = "access_control_standby"

	name = "Access Controller"
	tag_secure = TRUE


/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/update_icon()
	if(on && program)
		if(program.memory["processing"])
			icon_state = "access_control_process"
		else
			icon_state = "access_control_standby"
	else
		icon_state = "access_control_off"

/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockConsoleAccess", name, ui_x=470, ui_y=290)
		ui.open()

/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/ui_data(mob/user)
	var/list/data = list()

	var/ext_door_status = (program.memory["exterior_status"]["state"] == "closed" && program.memory["exterior_status"]["lock"] == "locked")
	var/int_door_status = (program.memory["interior_status"]["state"] == "closed" && program.memory["interior_status"]["lock"] == "locked")

	data["exterior_secured"] = ext_door_status
	data["interior_secured"] = int_door_status
	data["processing"] = program.memory["processing"]

	return data

/obj/structure/machinery/embedded_controller/radio/airlock/access_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "command")
		var/command_name = sanitize(params["command"])
		program.receive_user_command(command_name)
