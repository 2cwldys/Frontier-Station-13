/obj/structure/machinery/button/remote
	name = "remote object control"
	desc = "It controls objects, remotely."
	icon_state = "doorctrl0"
	power_channel = AREA_USAGE_ENVIRON
	var/desiredstate = 0
	var/exposedwires = 0
	var/wires = 3
	/*
	Bitflag,	1=checkID
				2=Network Access
	*/

	anchored = 1.0
	idle_power_usage = 2
	active_power_usage = 4

/obj/structure/machinery/button/remote/attack_ai(mob/user as mob)
	if(!ai_can_interact(user))
		return
	if(wires & 2)
		return src.attack_hand(user)
	else
		to_chat(user, "Error, no route to host.")

/obj/structure/machinery/button/remote/attackby(obj/item/attacking_item, mob/user)
	if(istype(attacking_item, /obj/item/forensics))
		return
	return src.attack_hand(user)

/obj/structure/machinery/button/remote/emag_act(var/remaining_charges, var/mob/user)
	if(req_access.len || req_one_access.len)
		req_access = list()
		req_one_access = list()
		playsound(src.loc, SFX_SPARKS, 100, 1)
		return 1

/obj/structure/machinery/button/remote/attack_hand(mob/user as mob)
	if(..())
		return

	src.add_fingerprint(user)
	if(stat & (NOPOWER|BROKEN))
		return

	if(!allowed(user) && (wires & 1))
		to_chat(user, SPAN_WARNING("Access denied"))
		flick("doorctrl-denied",src)
		return

	use_power_oneoff(5)
	icon_state = "doorctrl1"
	desiredstate = !desiredstate
	trigger(user)
	update_icon()

/obj/structure/machinery/button/remote/proc/trigger()
	return

/obj/structure/machinery/button/remote/power_change()
	..()
	update_icon()

/obj/structure/machinery/button/remote/update_icon()
	if(stat & NOPOWER)
		icon_state = "doorctrl-p"
	else
		icon_state = "doorctrl0"

/*
	Airlock remote control
*/

// Bitmasks for door switches.
#define OPEN   0x1
#define IDSCAN 0x2
#define BOLTS  0x4
#define SHOCK  0x8
#define SAFE   0x10

/obj/structure/machinery/button/remote/airlock
	name = "remote door-control"
	desc = "It controls doors, remotely."

	var/specialfunctions = 1
	/*
	Bitflag, 	1= open
				2= idscan,
				4= bolts
				8= shock
				16= door safties
	*/

/obj/structure/machinery/button/remote/airlock/trigger()
	for(var/obj/structure/machinery/door/airlock/D in SSmachinery.machinery)
		if(D.id_tag == src.id)
			if(specialfunctions & OPEN)
				if (D.density)
					D.open()
					return
				else
					D.close()
					return
			if(desiredstate == 1)
				if(specialfunctions & IDSCAN)
					D.set_idscan(0)
				if(specialfunctions & BOLTS)
					D.lock()
				if(specialfunctions & SHOCK)
					D.electrify(-1)
				if(specialfunctions & SAFE)
					D.set_safeties(0)
			else
				if(specialfunctions & IDSCAN)
					D.set_idscan(1)
				if(specialfunctions & BOLTS)
					D.unlock()
				if(specialfunctions & SHOCK)
					D.electrify(0)
				if(specialfunctions & SAFE)
					D.set_safeties(1)

/obj/structure/machinery/button/remote/airlock/screamer
	var/message = "REPLACE THIS!"
	var/channel = "Common"

/obj/structure/machinery/button/remote/airlock/screamer/trigger()
	. = ..()
	GLOB.global_announcer.autosay(message, capitalize_first_letters(name), channel)

#undef OPEN
#undef IDSCAN
#undef BOLTS
#undef SHOCK
#undef SAFE

/*
	Blast door remote control
*/
/obj/structure/machinery/button/remote/blast_door
	name = "remote blast door-control"
	desc = "It controls blast doors, remotely."

/// Combined toggle across every linked door/airlock -- the first one found
/// decides "open everything" vs "close everything." Widened from a
/// blast-door-only loop to also match airlocks by door_button_tag, so any
/// mapped button (not just the buildable/multitool-wired kind) can control
/// a mix of both once linked via _link_door()/_link_airlock() below.
/obj/structure/machinery/button/remote/blast_door/trigger()
	var/new_state
	for(var/obj/structure/machinery/door/D in _get_linked_doors())
		if(isnull(new_state))
			new_state = D.density
		if(new_state)
			D.open()
		else
			D.close()

/// Multitool linking -- lets a multitool that already has a blast door,
/// shutter, or airlock buffered (via that door's own attackby()) complete a
/// link to this button, or buffers this button itself so a door can be
/// buffered next instead. Moved here from the buildable subtype
/// (blast_door_button.dm) so every already-mapped button supports this, not
/// just a player-constructed one.
/obj/structure/machinery/button/remote/blast_door/attackby(obj/item/attacking_item, mob/user)
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

/// Whether user may link/unlink a door carrying this faction tag.
///
/// Without this, buffer-linking is a clean access bypass: a faction-tagged door
/// could be linked to a button anyone owns and then opened from that button,
/// sidestepping the door's own access checks entirely. The same applies in
/// reverse -- unlinking, or resetting a button, would let an outsider cut a
/// faction's doors off from their own controls.
///
/// Untagged and "public" doors are unaffected: ordinary construction stays
/// ordinary. See can_rewire_faction_device() (persistence_factions.dm) for the
/// shared rule: the bar is EMPLOYMENT by the owning faction. Printing yourself
/// an ID does not count -- that registers as FACTION_RANK_CIVILIAN (card.dm).
/obj/structure/machinery/button/remote/blast_door/proc/_can_link_faction_door(mob/user, obj/structure/machinery/door/D)
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

/// Toggle-links (or unlinks) a blast door/shutter to this button by
/// assigning (or clearing) the door's own `id` var -- trigger() above
/// already matches purely on `id` equality. Generates this button's own id
/// once, on first-ever link (not REF(), which isn't restart-stable -- both
/// ends persist their `id` via worldstate_vars).
/obj/structure/machinery/button/remote/blast_door/proc/_link_door(obj/structure/machinery/door/blast/D, mob/user)
	if(!_can_link_faction_door(user, D))
		to_chat(user, SPAN_WARNING("\The [D] is tagged to [get_faction_name(D.persistent_network)] -- you are not employed there, so you cannot wire it to anything."))
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
/// clearing) its dedicated door_button_tag var (airlock_control.dm) --
/// deliberately NOT `id_tag`, which is already shared by the legacy remote
/// button and the airlock cycler system; reusing it here would desync a
/// cycler-managed door's link the moment this button linked it too.
/obj/structure/machinery/button/remote/blast_door/proc/_link_airlock(obj/structure/machinery/door/airlock/A, mob/user)
	if(!_can_link_faction_door(user, A))
		to_chat(user, SPAN_WARNING("\The [A] is tagged to [get_faction_name(A.persistent_network)] -- you are not employed there, so you cannot wire it to anything."))
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
/obj/structure/machinery/button/remote/blast_door/proc/_get_linked_doors()
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
/obj/structure/machinery/button/remote/blast_door/proc/_reset_links(mob/user)
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
		to_chat(user, SPAN_WARNING("\The [src] controls doors tagged to [english_list(blocked)] -- you are not employed there, so it can't be reset."))
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

/obj/structure/machinery/button/remote/blast_door/open_only/trigger()
	for(var/obj/structure/machinery/door/blast/M in SSmachinery.machinery)
		if(M.id == src.id)
			if(M.density)
				M.open()
				return

/obj/structure/machinery/button/remote/blast_door/hangar_lockdown
	var/on_message = "A hangar lockdown has been initiated."
	var/off_message = "The hangar lockdown has been lifted."
	var/on_title = "Hangar Lockdown In Effect!"
	var/off_title = "Hangar Lockdown Lifted!"
	var/channel = "Common"
	var/on = FALSE

/obj/structure/machinery/button/remote/blast_door/hangar_lockdown/trigger()
	. = ..()
	on = !on
	if(on)
		security_announcement.Announce(on_message, on_title)
	else
		security_announcement.Announce(off_message, off_title)
	for(var/obj/structure/machinery/button/remote/blast_door/hangar_lockdown/B in SSmachinery.machinery)
		if(B.id == src.id)
			B.on = src.on
/*
	Emitter remote control
*/
/obj/structure/machinery/button/remote/emitter
	name = "remote emitter control"
	desc = "It controls emitters, remotely."

/obj/structure/machinery/button/remote/emitter/trigger(mob/user as mob)
	for(var/obj/structure/machinery/power/emitter/E in SSmachinery.machinery)
		if(E.id == src.id)
			E.activate(user)
			return

/*
	Mass driver remote control
*/
/obj/structure/machinery/button/remote/driver
	name = "mass driver button"
	desc = "A remote control switch for a mass driver."
	icon_state = "launcherbtt"

/obj/structure/machinery/button/remote/driver/trigger(mob/user as mob)
	active = 1
	update_icon()

	var/list/same_id = list()

	for(var/obj/structure/machinery/door/blast/M in SSmachinery.machinery)
		if (M.id == src.id)
			same_id += M
			INVOKE_ASYNC(M, TYPE_PROC_REF(/obj/structure/machinery/door/blast, open))

	sleep(20)

	for(var/obj/structure/machinery/mass_driver/M in SSmachinery.machinery)
		if(M.id == src.id)
			M.drive()

	sleep(50)

	for(var/mm in same_id)
		INVOKE_ASYNC(mm, TYPE_PROC_REF(/obj/structure/machinery/door/blast, close))

	icon_state = "launcherbtt"
	active = 0
	update_icon()

	return

/obj/structure/machinery/button/remote/driver/update_icon()
	if(!active || (stat & NOPOWER))
		icon_state = "launcherbtt"
	else
		icon_state = "launcheract"
