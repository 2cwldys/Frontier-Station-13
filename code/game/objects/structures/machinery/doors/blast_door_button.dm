/**
 * Buildable, multitool-linkable remote door button -- controls any mix of
 * blast doors/shutters AND plain airlocks from one button ("functional
 * checkpoints").
 *
 * Blast door linking uses /obj/structure/machinery/door/blast's own `id`
 * field (door_control.dm's existing button/remote/blast_door parent type
 * already matches on it). Airlock linking uses a dedicated
 * `door_button_tag` field (airlock_control.dm) -- deliberately NOT `id_tag`,
 * which is already shared by the legacy remote button and the airlock
 * cycler system; reusing it here would desync a cycler-managed door's link
 * the moment this button linked it too. Both fields are just set to this
 * button's own single `id` string -- one button, one tag, matched against
 * two different door-side fields depending on door type.
 *
 * A buildable frame lifecycle (mirroring /obj/structure/machinery/access_button,
 * airlock_control.dm), a multitool buffer-link step per door type
 * (deliberately NOT touching either door type's own attackby() -- linking
 * only happens on the button's side, from a multitool that already has a
 * door buffered via that door's own pre-existing, unmodified multitool
 * behavior), and a combined trigger()/picker (below) so the button's job
 * stays the same regardless of what's linked to it.
 */
/obj/structure/machinery/button/remote/blast_door/buildable
	name = "door button"
	desc = "A remote control switch for airlocks, blast doors, and shutters."

	/// 2 = complete/wired, 1 = circuit inserted but unwired, 0 = frame only.
	/// Mirrors access_button's own buildstage shape (airlock_control.dm).
	var/buildstage = 2

/obj/structure/machinery/button/remote/blast_door/buildable/Initialize(mapload, var/dir, var/building = 0)
	. = ..()
	if(building)
		if(dir)
			set_dir(dir)
		apply_wall_mount_offset()
		buildstage = 0
		update_icon()

/obj/structure/machinery/button/remote/blast_door/buildable/update_icon()
	if(buildstage < 2)
		icon_state = "doorctrl-p"
	else
		..()

/obj/structure/machinery/button/remote/blast_door/buildable/attackby(obj/item/attacking_item, mob/user)
	if(_handle_construction(attacking_item, user))
		return TRUE
	if(buildstage < 2)
		to_chat(user, SPAN_WARNING("\The [src] isn't wired up yet."))
		return TRUE
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/door/blast/D = MT.get_buffer(/obj/structure/machinery/door/blast)
		if(D)
			_link_door(D, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/door/airlock/A = MT.get_buffer(/obj/structure/machinery/door/airlock)
		if(A)
			_link_airlock(A, user)
			MT.set_buffer(null)
			return TRUE
		// Empty multitool on the button itself -- ambiguous between "I want
		// to buffer this to go link a door to it" and "I want to wipe every
		// link and start over," so ask instead of always assuming the
		// former. Mirrors the airlock cycler controller's own multitool
		// popup exactly (airlock_controllers.dm).
		var/choice = tgui_alert(user, "What would you like to do with \the [src]?", "Door Button", list("Buffer", "Reset Links"))
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

/obj/structure/machinery/button/remote/blast_door/buildable/proc/_handle_construction(obj/item/attacking_item, mob/user)
	switch(buildstage)
		if(0)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				set_dir(turn(dir, -90))
				to_chat(user, SPAN_NOTICE("You rotate \the [src]."))
				return TRUE
			if(istype(attacking_item, /obj/item/blast_door_button_electronics))
				to_chat(user, SPAN_NOTICE("You insert the circuit board."))
				qdel(attacking_item)
				buildstage = 1
				update_icon()
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You remove \the [src] from the wall."))
				new /obj/item/frame/blast_door_button(get_turf(user))
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
					if(GLOB.config.sql_enabled && GLOB.persistence_ready)
						SSpersistence.objectsRegisterTrack(src)
				else
					to_chat(user, SPAN_WARNING("You need 5 pieces of cable to wire \the [src]."))
				return TRUE
			if(attacking_item.tool_behaviour == TOOL_CROWBAR)
				to_chat(user, SPAN_NOTICE("You pry out the circuit board."))
				new /obj/item/blast_door_button_electronics(get_turf(user))
				attacking_item.play_tool_sound(get_turf(src), 50)
				buildstage = 0
				update_icon()
				return TRUE
		if(2)
			if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
				to_chat(user, SPAN_NOTICE("You pry out the circuit board."))
				new /obj/item/blast_door_button_electronics(get_turf(user))
				buildstage = 1
				update_icon()
				return TRUE
	return FALSE

/// Toggle-links (or unlinks) a blast door/shutter to this button by
/// assigning (or clearing) the door's own `id` var -- trigger() (door_control.dm,
/// unchanged) already matches purely on `id` equality. Generates this
/// button's own id once, on first-ever link (not REF(), which isn't
/// restart-stable -- both ends persist their `id` via worldstate_vars).
/// Whether user may link/unlink a door carrying this faction tag.
///
/// Without this, buffer-linking is a clean access bypass: a faction-tagged door
/// could be linked to a button anyone owns and then opened from that button,
/// sidestepping the door's own access checks entirely. The same applies in
/// reverse -- unlinking, or resetting a button, would let an outsider cut a
/// faction's doors off from their own controls.
///
/// Untagged doors (persistent_network "") are unaffected: ordinary construction
/// stays ordinary. Rank 0, deliberately not officer -- the bar is MEMBERSHIP of
/// the owning faction, not seniority within it, since wiring a checkpoint is
/// routine work rather than a command decision. Admins bypass, as everywhere
/// else can_configure_faction_shackle() is used.
/obj/structure/machinery/button/remote/blast_door/buildable/proc/_can_link_faction_door(mob/user, obj/structure/machinery/door/D)
	if(!istype(D))
		return TRUE
	// An airlock marked PUBLIC opens for anybody already (req_access_faction,
	// set by the faction tagger's "Mark Public Airlock"). Wiring it to a button
	// therefore bypasses nothing -- there is no access left to circumvent -- so
	// it stays freely linkable even while it carries an ownership tag. Note
	// this is a DIFFERENT var from persistent_network: one is who may open the
	// door, the other is who owns it.
	if(istype(D, /obj/structure/machinery/door/airlock))
		var/obj/structure/machinery/door/airlock/AL = D
		if(AL.req_access_faction == "public")
			return TRUE
	return can_rewire_faction_device(user, D.faction_tagger_get_uid())

/obj/structure/machinery/button/remote/blast_door/buildable/proc/_link_door(obj/structure/machinery/door/blast/D, mob/user)
	if(!_can_link_faction_door(user, D))
		to_chat(user, SPAN_WARNING("\The [D] is tagged to [get_faction_name(D.persistent_network)] -- you have no standing there to wire it to anything."))
		return
	if(!id)
		id = "blastbtn_[rand(100000, 999999)]"
	if(D.id == id)
		D.id = null
		to_chat(user, SPAN_NOTICE("You unlink \the [D] from \the [src]."))
		return
	D.id = id
	to_chat(user, SPAN_NOTICE("You link \the [D] to \the [src]."))

/// Toggle-links (or unlinks) an airlock to this button by assigning (or
/// clearing) its dedicated door_button_tag var (airlock_control.dm) -- see
/// this file's own header comment for why that's a separate field from
/// id_tag, not a reuse of it.
/obj/structure/machinery/button/remote/blast_door/buildable/proc/_link_airlock(obj/structure/machinery/door/airlock/A, mob/user)
	if(!_can_link_faction_door(user, A))
		to_chat(user, SPAN_WARNING("\The [A] is tagged to [get_faction_name(A.persistent_network)] -- you have no standing there to wire it to anything."))
		return
	if(!id)
		id = "blastbtn_[rand(100000, 999999)]"
	if(A.door_button_tag == id)
		A.door_button_tag = null
		to_chat(user, SPAN_NOTICE("You unlink \the [A] from \the [src]."))
		return
	A.door_button_tag = id
	to_chat(user, SPAN_NOTICE("You link \the [A] to \the [src]."))

/// Every door (blast door/shutter or airlock) currently matching this
/// button's tag -- the shared source of truth for trigger(), the multi-door
/// picker, and the multitool checklist.
/obj/structure/machinery/button/remote/blast_door/buildable/proc/_get_linked_doors()
	. = list()
	if(!id)
		return
	for(var/obj/structure/machinery/door/blast/D in SSmachinery.machinery)
		if(D.id == id)
			. += D
	for(var/obj/structure/machinery/door/airlock/A in SSmachinery.machinery)
		if(A.door_button_tag == id)
			. += A

/// Wipes every door/airlock link this button has in one action -- the
/// multitool-on-empty-buffer popup's "Reset Links" choice (attackby()
/// above). Doors carry no back-reference to the button (just a shared
/// tag), so a world scan clearing any door matching this button's `id` is
/// sufficient, then the button's own `id` is cleared too so a future link
/// starts from a clean, freshly-generated tag instead of potentially
/// missing a door somehow left stale.
/obj/structure/machinery/button/remote/blast_door/buildable/proc/_reset_links(mob/user)
	// Checked BEFORE anything is cleared. A reset unlinks every door at once,
	// so without this an outsider could cut a faction's whole checkpoint off
	// from its own controls in one click -- the same bypass _link_door() closes,
	// just applied wholesale. Refuse the entire reset rather than partially
	// clearing it: leaving a button half-linked is worse than leaving it alone.
	var/list/blocked = list()
	for(var/obj/structure/machinery/door/D in _get_linked_doors())
		if(!_can_link_faction_door(user, D))
			blocked |= get_faction_name(D.faction_tagger_get_uid())
	if(length(blocked))
		to_chat(user, SPAN_WARNING("\The [src] controls doors tagged to [english_list(blocked)] -- you have no standing there, so it can't be reset."))
		return

	var/count = 0
	for(var/obj/structure/machinery/door/D in _get_linked_doors())
		if(istype(D, /obj/structure/machinery/door/blast))
			var/obj/structure/machinery/door/blast/BD = D
			BD.id = null
		else if(istype(D, /obj/structure/machinery/door/airlock))
			var/obj/structure/machinery/door/airlock/AL = D
			AL.door_button_tag = null
		count++
	id = null
	to_chat(user, SPAN_NOTICE("You reset \the [src], unlinking [count] door\s."))

/// Combined toggle across every linked door/airlock -- the first one found
/// decides "open everything" vs "close everything," same shared-state shape
/// the inherited blast-door-only trigger() (door_control.dm) already used,
/// just widened to both door types. Used only when exactly one door is
/// linked (attack_hand() below opens a picker instead once there's more
/// than one, since a blind toggle stops being obviously correct once
/// multiple doors -- especially a mix of types -- are involved).
/obj/structure/machinery/button/remote/blast_door/buildable/trigger()
	var/new_state
	for(var/obj/structure/machinery/door/D in _get_linked_doors())
		if(isnull(new_state))
			new_state = D.density
		if(new_state)
			D.open()
		else
			D.close()

/// More than one linked door -- a blind toggle-everything press stops being
/// obviously correct (especially for a mixed airlock/blast-door
/// checkpoint), so open a native picker instead: which door, then which
/// action for it. Mirrors commander_beacon.dm's own
/// _remote_door_control() picker shape exactly. Exactly one linked door
/// still falls through to the base class's immediate press-and-trigger()
/// behavior -- no extra friction for the common single-door case.
/obj/structure/machinery/button/remote/blast_door/buildable/attack_hand(mob/user as mob)
	if(buildstage < 2)
		return
	var/list/doors = _get_linked_doors()
	if(length(doors) <= 1)
		return ..()

	add_fingerprint(user)
	if(stat & (NOPOWER|BROKEN))
		return
	if(!allowed(user) && (wires & 1))
		to_chat(user, SPAN_WARNING("Access denied"))
		flick("doorctrl-denied", src)
		return

	var/list/door_options = list()
	for(var/obj/structure/machinery/door/D in doors)
		door_options["[D.name] @ ([D.x],[D.y])"] = D
	var/pick = tgui_input_list(user, "Select a door to control:", "Door Button", door_options)
	if(!pick)
		return
	var/obj/structure/machinery/door/D = door_options[pick]
	if(QDELETED(D))
		to_chat(user, SPAN_WARNING("That door is no longer there."))
		return

	var/is_airlock = istype(D, /obj/structure/machinery/door/airlock)
	var/list/action_options = is_airlock ? list("Open", "Close", "Bolt", "Unbolt") : list("Open", "Close")
	var/action = tgui_input_list(user, "Action for [D.name]:", "Door Button", action_options)
	if(!action)
		return
	if(QDELETED(D) || QDELETED(src) || QDELETED(user))
		return

	use_power_oneoff(5)
	switch(action)
		if("Open")
			D.open()
		if("Close")
			D.close()
		if("Bolt")
			var/obj/structure/machinery/door/airlock/AL = D
			AL.lock()
		if("Unbolt")
			var/obj/structure/machinery/door/airlock/AL = D
			AL.unlock()
	to_chat(user, SPAN_NOTICE("You remotely [lowertext(action)] \the [D]."))
	update_icon()

/**
 * Circuit board for the buildable blast door button, mirroring
 * airlock_cycler_electronics' own shape (airlock_control.dm).
 */
/obj/item/blast_door_button_electronics
	name = "blast door button electronics"
	desc = "A circuit board for a blast door button."
	icon = 'icons/obj/module.dmi'
	icon_state = "door_electronics"
	w_class = WEIGHT_CLASS_SMALL
	matter = list(DEFAULT_WALL_MATERIAL = 50, MATERIAL_GLASS = 50)
