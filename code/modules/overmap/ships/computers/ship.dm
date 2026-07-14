/*
While these computers can be placed anywhere, they will only function if placed on either a non-space, non-shuttle turf
with an /obj/effect/overmap/visitable/ship present elsewhere on that z level, or else placed in a shuttle area with an /obj/effect/overmap/visitable/ship
somewhere on that shuttle. Subtypes of these can be then used to perform ship overmap movement functions.
*/
/obj/structure/machinery/computer/ship
	/// Weakrefs to mobs in direct-view mode.
	var/list/viewers
	/// How much the view is increased by when the mob is in overmap mode.
	var/extra_view = 0
	/// The ship we're attached to. This is a typecheck for linked, to ensure we're linked to a ship and not a sector
	var/obj/effect/overmap/visitable/ship/connected
	/// Are we targeting anything right now?
	var/targeting = FALSE
	var/linked_type = /obj/effect/overmap/visitable/ship

	/// For hotwiring, how many cycles are needed. This decreases by 1 each cycle and triggers at 0
	var/hotwire_progress = 8

/obj/structure/machinery/computer/antagonist_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "Consoles like these are typically access-locked."
	. += "You can remove this lock with <b>wirecutters</b>, but it would take awhile! Alternatively, you can also use a cryptographic sequencer (emag) for instant removal."

/obj/structure/machinery/computer/ship/attackby(obj/item/attacking_item, mob/user)
	if(attacking_item.tool_behaviour == TOOL_CABLECOIL) // Repair from hotwire
		var/obj/item/stack/cable_coil/C = attacking_item
		if(hotwire_progress >= initial(hotwire_progress))
			to_chat(usr, SPAN_BOLD("\The [src] does not require repairs."))
		else
			to_chat(usr, SPAN_BOLD("You attempt to replace some cabling for \the [src]..."))
			while(C.can_use(2, user))
				if(do_after(user, 15 SECONDS, src, DO_UNIQUE))
					if(hotwire_progress < initial(hotwire_progress))
						C.use(2)
						hotwire_progress++
						if(hotwire_progress >= initial(hotwire_progress))
							restore_access(user)
							return
						to_chat(usr, SPAN_BOLD("You replace some broken cabling of \the [src] <b>([(hotwire_progress / initial(hotwire_progress)) * 100]%)</b>."))
						playsound(src.loc, 'sound/items/Deconstruct.ogg', 30, TRUE)
			return

	if(attacking_item.tool_behaviour == TOOL_WIRECUTTER) // Hotwiring
		if(!req_access && !req_one_access && !emagged) // Already hacked/no need to hack
			to_chat(user, SPAN_BOLD("[src] is not access-locked."))
			return
		// Begin hotwire
		user.visible_message("<b>[user]</b> opens a panel underneath \the [src] and starts snipping wires...", SPAN_BOLD("You open the maintenance panel and attempt to hotwire \the [src]..."))
		while(hotwire_progress > 0)
			if(do_after(user, 15 SECONDS, src, DO_UNIQUE))
				hotwire_progress--
				if(hotwire_progress <= 0)
					emag_act(user=user, hotwired=TRUE)
					return
				to_chat(user, SPAN_BOLD("You snip some cabling from \the [src] <b>([((initial(hotwire_progress)-hotwire_progress) / initial(hotwire_progress)) * 100]%)</b>."))
				playsound(src.loc, 'sound/items/Wirecutter.ogg', 30, TRUE)
			else
				return
	return ..()

/obj/structure/machinery/computer/ship/attack_hand(mob/user)
	if(stat & (NOPOWER|BROKEN))
		return FALSE
	// Snowflake case for checking player characters for a Pilot Spacecraft Skill.
	// Only player characters will have the component. Which will both always be present on them, and will only enable its own return logic if it exists.
	// NPCs, Ghostroles, and Offship Antags that don't generate skills are unaffected by this check by intentional design so that we don't have to account for them.
	if (user.GetComponent(PILOT_SPACECRAFT_SKILL_COMPONENT)?.skill_level == SKILL_LEVEL_UNFAMILIAR)
		to_chat(user, SPAN_WARNING("There's just so many buttons... You have no idea where to even begin."))
		return FALSE

	if(use_check_and_message(user))
		return
	if(!emagged && !allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return FALSE
	user.set_machine(src)
	ui_interact(user)

/obj/structure/machinery/computer/ship/attack_ai(mob/user)
	if(!ai_can_interact(user))
		return
	src.add_hiddenprint(user)
	ui_interact(user)

/obj/structure/machinery/computer/ship/get_examine_text(mob/user, distance, is_adjacent, infix, suffix)
	. = ..()
	if(initial(hotwire_progress) != hotwire_progress)
		if(hotwire_progress != 0)
			. += SPAN_ITALIC("The bottom panel appears open with wires hanging out. It can be repaired with additional cabling. <i>Current progress: [(hotwire_progress / initial(hotwire_progress)) * 100]%</i>")
		else
			. += SPAN_ITALIC("The bottom panel appears open with wires hanging out. It can be repaired with additional cabling.")

/obj/structure/machinery/computer/ship/emag_act(var/remaining_charges, var/mob/user, var/emag_source, var/hotwired = FALSE)
	if(emagged)
		to_chat(user, SPAN_WARNING("\The [src] has already been subverted."))
		return FALSE
	emagged = TRUE
	if(hotwired)
		user.visible_message(SPAN_WARNING("\The [src] sparks as a panel suddenly opens and burnt cabling spills out!"),SPAN_BOLD("You short out the console's ID checking system. It's now available to everyone!"))
	else
		user.visible_message(SPAN_WARNING("\The [src] sparks!"),SPAN_BOLD("You short out the console's ID checking system. It's now available to everyone!"))
	spark(src, 2, 0)
	hotwire_progress = 0
	return TRUE

/// Used to restore access removed from emag_act() by setting access from req_access_old and req_one_access_old
/obj/structure/machinery/computer/ship/proc/restore_access(var/mob/user)
	if(!emagged)
		to_chat(user, SPAN_WARNING("There is no access to restore for \the [src]!"))
		return FALSE
	emagged = FALSE
	to_chat(user, "You repair out the console's ID checking system. It's access restrictions have been restored.")
	playsound(loc, 'sound/machines/ping.ogg', 50, FALSE)
	hotwire_progress = initial(hotwire_progress)
	return TRUE

/obj/structure/machinery/computer/ship/Topic(href, href_list)
	if(..())
		return TOPIC_HANDLED
	if(href_list["sync"])
		sync_linked()
		return TOPIC_REFRESH
	if(href_list["close"])
		unlook(usr)
		usr.unset_machine()
		return TOPIC_HANDLED
	return TOPIC_NOACTION

/obj/structure/machinery/computer/ship/sync_linked()
	. = ..()
	if(istype(linked, linked_type))
		connected = linked

// Management of mob view displacement. look to shift view to the ship on the overmap; unlook to shift back.

/obj/structure/machinery/computer/ship/proc/look(var/mob/user)
	// Always resolve fresh from this console's OWN current Z instead of
	// trusting the cached `linked` var. `linked` is only ever (re)computed
	// at Initialize() (racy against the ship's own overmap marker
	// registering, see sectors.dm's lonely_ship_computers retry) or via a
	// manual Topic(href_list["sync"]) click (line ~122 below) -- nothing
	// calls that automatically on stash/unstash/retrieval/redelivery, so
	// `linked` can point at a stale or wrong sector indefinitely after any
	// relocation. GLOB.map_sectors is authoritative and always current --
	// the same lookup Personal Travel already uses safely from anywhere.
	// `linked` is kept only as a last-resort fallback (still used for its
	// other jobs: ownership/weapon-linking/navigation_viewers bookkeeping).
	var/obj/effect/overmap/visitable/target_sector = GLOB.map_sectors["[GET_Z(src)]"]
	if(!target_sector)
		target_sector = linked
	if(target_sector)
		// Self-heal markers stranded off the overmap (failed/raced
		// placement) before pointing the camera at them -- see
		// repair_stray_overmap_marker (sectors.dm).
		repair_stray_overmap_marker(target_sector)
		user.reset_view(target_sector)
	if(user.client)
		// Cache the real dynamic view so unlook() can restore it directly
		// instead of asking refit_dynamic_view() to re-derive it live --
		// that recompute is only reliable right after a genuine window
		// resize event, not this transition (Sector View Bug D).
		user.client.saved_dynamic_view = user.client.view
		// world.view is a "WxH" string in this fork (world.dm) -- naive
		// `world.view + extra_view` string-concatenates instead of adding
		// numerically (e.g. "15x15" + 4 -> "15x154", a malformed viewport).
		// expanded_client_view() (personal_travel.dm) parses out the numeric
		// base and returns a proper int.
		user.client.view = expanded_client_view(extra_view)
		// update_skybox() only fires off real /mob/Move() -- looking at the
		// overmap never moves the mob, just the eye/view, so the skybox is
		// otherwise left frozen at the player's last real-world offset and
		// bleeds across the whole sector map view. The overmap plane has no
		// meaningful skybox of its own (a strategic grid, not a starfield),
		// so just hide it instead of trying to reposition it for there.
		if(user.client.skybox)
			user.client.screen -= user.client.skybox
		user.reload_fullscreen()
		// apply_gameui_border()'s scale math assumes client.view tracks the
		// real map-window pixel size (true for the normal dynamic viewport,
		// computed FROM that size by refit_dynamic_view()) -- but the flat
		// world.view + extra_view set above has no relationship to the
		// actual window size, so scaling the border to it lands the frame
		// in the middle of the screen instead of at the edges, covering the
		// sector view instead of framing it. Same reasoning as the skybox
		// hide above: hide it here rather than rescale it to a view size
		// it was never designed for. unlook()'s refit_dynamic_view() call
		// already restores it correctly on the way back out.
		user.clear_fullscreen("gameui_border", FALSE)
	RegisterSignal(user, COMSIG_MOVABLE_MOVED, PROC_REF(unlook))
	if(user.eyeobj)
		RegisterSignal(user, COMSIG_MOVABLE_MOVED, PROC_REF(unlook))
	LAZYDISTINCTADD(viewers, WEAKREF(user))
	if(linked)
		LAZYDISTINCTADD(linked.navigation_viewers, WEAKREF(user))
	ADD_TRAIT(user, TRAIT_COMPUTER_VIEW, REF(src))

/// Handles disabling the user's overmap view when a signal comes in, primarily used when the TGUI is closed, see helm.dm and sensors.dm
/obj/structure/machinery/computer/ship/proc/handle_unlook_signal(var/datum/source, var/mob/user)
	SIGNAL_HANDLER

	unlook(user)

/obj/structure/machinery/computer/ship/proc/unlook(var/mob/user)
	user.reset_view()
	var/client/c = user.client

	if(isEye(user))
		var/mob/abstract/eye/E = user
		E.reset_view()
		c = E.owner?.client

	if(c)
		c.pixel_x = 0
		c.pixel_y = 0
		// Restore the exact dynamic view cached by look() rather than
		// asking refit_dynamic_view() to re-derive it live -- that recompute
		// is only reliable right after a genuine window resize event, not
		// this transition (Sector View Bug D). Falls back to the live
		// recompute only if nothing was cached (e.g. relog mid-view).
		if(c.saved_dynamic_view)
			c.view = c.saved_dynamic_view
			c.saved_dynamic_view = null
		else
			c.refit_dynamic_view()
		// Restore the skybox now that the eye/view are back on the player's
		// real position -- forced rebuild, same as a genuine /mob/Move()
		// would trigger, since look() hid it outright rather than letting
		// it go stale (see look() above).
		c.update_skybox(TRUE)
		// gameui_border still needs re-fitting to the (now correctly
		// restored) view -- refit_dynamic_view() normally does this itself
		// (via c.mob, not necessarily user -- matters for the AI eye case
		// above), so mirror that here rather than assuming user is right.
		if(c.mob)
			c.mob.reload_fullscreen()
			c.mob.apply_gameui_border()

	UnregisterSignal(user, COMSIG_MOVABLE_MOVED)

	if(isEye(user)) // If we're an AI eye, the computer has our AI mob in its viewers list not the eye mob
		var/mob/abstract/eye/E = user
		UnregisterSignal(E.owner, COMSIG_MOVABLE_MOVED)
		LAZYREMOVE(viewers, WEAKREF(E.owner))
	LAZYREMOVE(viewers, WEAKREF(user))
	if(linked)
		LAZYREMOVE(linked.navigation_viewers, WEAKREF(user))

	if(linked)
		for(var/obj/structure/machinery/computer/ship/sensors/sensor in linked.consoles)
			sensor.hide_contacts(user)

	REMOVE_TRAIT(user, TRAIT_COMPUTER_VIEW, REF(src))

/obj/structure/machinery/computer/ship/proc/viewing_overmap(mob/user)
	return (WEAKREF(user) in viewers) || (linked && (WEAKREF(user) in linked.navigation_viewers))

/obj/structure/machinery/computer/ship/CouldNotUseTopic(mob/user)
	. = ..()
	unlook(user)

/obj/structure/machinery/computer/ship/CouldUseTopic(mob/user)
	. = ..()
	if(viewing_overmap(user))
		look(user)

/obj/structure/machinery/computer/ship/check_eye(var/mob/user)
	if(!viewing_overmap(user))
		return FALSE

	var/flags = issilicon(user) ? USE_ALLOW_NON_ADJACENT : 0
	// No `!linked` here -- look() resolves the sector live from this
	// console's own Z and works with linked null/stale, but this proc is
	// polled every tick by handle_vision() (life.dm) and any negative
	// return snaps the camera back to the mob, silently closing the
	// overmap whenever linked lost its Initialize() race or went stale
	// across a save/stash cycle.
	if (use_check_and_message(user, flags) || user.blinded || !operable())
		return -1
	else
		return SEE_THRU

/obj/structure/machinery/computer/ship/Destroy()
	SSshuttle.lonely_ship_computers -= src
	if(linked)
		linked = null
	if(connected)
		LAZYREMOVE(connected.consoles, src)
	. = ..()

/obj/structure/machinery/computer/ship/sensors/Destroy()
	sensor_ref = null
	identification = null
	QDEL_NULL(sound_token)
	if(LAZYLEN(viewers))
		// Snapshot copy: unlook() LAZYREMOVEs from viewers itself, and
		// mutating the list mid-iteration silently skips entries -- leaving
		// some viewers stuck in overmap view after the console is gone.
		for(var/datum/weakref/W as anything in viewers.Copy())
			var/mob/M = W.resolve()
			if(M)
				unlook(M)
				if(linked)
					LAZYREMOVE(linked.navigation_viewers, W)
	. = ..()

/obj/structure/machinery/computer/ship/on_user_login(mob/M)
	unlook(M)

/obj/structure/machinery/computer/ship/attempt_hook_up(var/obj/effect/overmap/visitable/sector)
	. = ..()

	if(.)
		if(istype(linked, linked_type))
			connected = linked
			if(istype(connected)) // we do a little type abuse
				LAZYSET(connected.consoles, src, TRUE)

/obj/structure/machinery/computer/ship/Initialize()
	. = ..()
	if(SSatlas.current_map.use_overmap && !linked)
		var/my_sector = GLOB.map_sectors["[z]"]
		if(istype(my_sector, linked_type))
			attempt_hook_up(my_sector)
		// Both this console and its ship's own overmap marker initialize in
		// the same init_atoms() batch, before init_shuttles() -- whichever
		// happens to process first wins, so this one attempt can lose purely
		// on map-tile order. Queue for a retry once the marker actually
		// registers (see /obj/effect/overmap/visitable/Initialize(), sectors.dm)
		// instead of staying permanently unlinked if it does.
		if(!linked)
			SSshuttle.lonely_ship_computers += src
