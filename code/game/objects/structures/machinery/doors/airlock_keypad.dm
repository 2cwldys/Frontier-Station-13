/**
 * Keypad Entry Airlock -- ported from Persistent-Bay
 * (D:\Aurora-Persistence\Persistent-Bay\code\game\machinery\doors\airlock_subtypes\airlock_keypad.dm),
 * with several deliberate improvements over that source:
 *  - A real TGUI (this file's own "KeypadDoor" window) instead of a raw
 *    show_browser() HTML popup.
 *  - The code, and who set it, are persisted (persistent_objects_get/apply_content
 *    below) instead of being lost every restart.
 *  - Only the original setter (or an admin) can reset the code -- the
 *    source tracked no "who set this" identity at all.
 *  - An admin-only "Force Unlock" (one-time) and "Bolt Open" (holds the
 *    door open indefinitely until an admin restores normal operation)
 *    action.
 *  - Auto re-locks on every close (self-timer, remote, or someone else
 *    closing it) -- the source never re-locked automatically.
 *
 * Code-only access: no req_access/ID scanning at all (requiresID() below) --
 * this door's sole gate is the keypad code.
 */
/obj/structure/machinery/door/airlock/keypad
	name = "keypad entry airlock"
	desc = "A door with a keypad lock."
	req_access = list()
	req_one_access = list()
	// A dedicated keypad sprite sheet exists in the Persistent-Bay source
	// this was ported from, but its single-file states don't map onto this
	// codebase's multi-file overlay compositor (set_airlock_overlays()) --
	// a plain white-tinted stock airlock (no glass) instead, using the
	// same door_color tinting every other airlock subtype in this file
	// already uses.
	door_color = COLOR_WHITE

	/// The permanent stored code, null = not yet set.
	var/set_code = null
	/// (ckey, char_name) of whoever set the current code -- BOTH must match
	/// the acting user for a reset (same composite per-character identity
	/// pattern used elsewhere, e.g. persistence_personal_cargo_category.dm)
	/// -- switching to a different character on the same account doesn't
	/// grant reset rights, only admins bypass this.
	var/setter_ckey = null
	var/setter_name = null
	/// Transient, per-door, not persisted -- the digits typed so far on the
	/// TGUI keypad, cleared on every Enter/Clear press (mirrors the codebase's
	/// existing NuclearBomb.tsx keypad convention: server-side accumulation,
	/// one digit per act() call).
	var/entry_buffer = ""
	/// Admin-only "Bolt Open" -- holds the door open indefinitely, ignoring
	/// autoclose/remote-close/manual-close entirely (close() below refuses
	/// outright while this is set), until an admin explicitly restores
	/// normal operation. Persisted -- an admin propping a door open expects
	/// it to stay that way across a restart too.
	var/admin_forced_open = FALSE

/obj/structure/machinery/door/airlock/keypad/Initialize(mapload, dir, populate_components, obj/structure/door_assembly/assembly = null)
	. = ..()
	locked = TRUE // No code set yet -- closed and inaccessible until one is.
	update_icon()

/// Code-only door -- ID cards/access lists never factor in at all.
/obj/structure/machinery/door/airlock/keypad/requiresID()
	return FALSE

/obj/structure/machinery/door/airlock/keypad/allowed(mob/M)
	return !locked

/// Re-locks unconditionally on every close -- self-timer autoclose, a
/// remote signal, or another player closing it all count. The code has to
/// be re-entered to get back in every time, per design. Refuses to close at
/// all while admin_forced_open is set -- "Bolt Open" below.
/obj/structure/machinery/door/airlock/keypad/close(var/forced = 0)
	if(admin_forced_open)
		return FALSE
	. = ..()
	if(set_code)
		lock(TRUE)

/// Alt-click closes the door without opening the TGUI first -- the same
/// action as its own "Close Door" button (close_door, ui_act() below).
/// close() above already refuses outright while admin_forced_open is set,
/// so "unless it's admin bolt opened" is already handled there for free;
/// this only needs to gate on actually being open and physically at the door.
/obj/structure/machinery/door/airlock/keypad/AltClick(mob/user)
	if(!Adjacent(user))
		return ..()
	if(density)
		return ..()
	close()
	return TRUE

/obj/structure/machinery/door/airlock/keypad/attack_hand(mob/user as mob)
	if(!istype(user, /mob/living/silicon))
		if(isElectrified())
			if(shock(user, 100))
				return
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.a_intent == I_HURT)
			return ..()
	ui_interact(user)

/obj/structure/machinery/door/airlock/keypad/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "KeypadDoor", "Keypad Door", 380, 650)
		ui.open()

/obj/structure/machinery/door/airlock/keypad/ui_data(mob/user)
	var/list/data = list()
	data["doorName"] = name
	data["codeSet"] = !!set_code
	data["locked"] = locked
	data["doorOpen"] = !density
	data["setterName"] = setter_name
	// NOT isobserver(user) -- that's specific to the base airlock's own
	// "boltsOverride" ghost-debugging feature (airlock.dm), which only
	// matters for an admin actively ghosted/observing. An admin playing
	// embodied (the normal case) is never an observer, so gating on it here
	// hid every admin action from any admin actually walking around as a
	// character -- the actual root cause of "admin options don't show."
	var/isAdmin = check_rights(R_ADMIN, FALSE, user)
	var/isSetter = _is_setter(user)
	data["canReset"] = set_code && isSetter
	data["isAdmin"] = isAdmin
	data["canHoldOpen"] = isAdmin || isSetter
	data["entry"] = entry_buffer
	data["adminForcedOpen"] = admin_forced_open
	return data

/// TRUE if user is the (ckey, char_name) that set the current code -- the
/// same composite identity "Reset Code" gates on, also used for "Bolt
/// Open"/"Return to Default" (the setter is trusted with the same
/// hold-open power as an admin, just for their own door).
/obj/structure/machinery/door/airlock/keypad/proc/_is_setter(mob/user)
	return set_code && (user.ckey == setter_ckey) && (user.real_name == setter_name)

/// Keypad actions are handled BEFORE delegating upward, deliberately.
///
/// The usual `. = ..()` / `if(.) return TRUE` opener does not work here: the
/// parent airlock's own ui_act() (airlock.dm) ends with an unconditional
/// `return TRUE` after its switch, so it claims EVERY action -- including ones
/// it has no case for. Opening with it meant this proc returned before its own
/// switch ever ran, and not one keypad button did anything: no digits, no
/// clear, no enter, no reset. Handle what belongs to this door first, and only
/// fall through to the parent for everything else.
/obj/structure/machinery/door/airlock/keypad/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	var/mob/user = usr
	var/isAdmin = check_rights(R_ADMIN, FALSE, user) // see the matching comment in ui_data() above

	switch(action)
		if("type")
			var/digit = params["value"]
			// Membership test rather than text2num(): in DM `null == 0` is
			// TRUE, so `text2num("0") != null` is FALSE and the digit 0 was
			// rejected while 1-9 passed. A five-digit code containing a zero
			// could never be entered at all.
			if(istext(digit) && length(digit) == 1 && findtext("0123456789", digit) && length(entry_buffer) < 5)
				entry_buffer += digit
			. = TRUE
		if("clear")
			entry_buffer = ""
			. = TRUE
		if("close_door")
			// Anyone can voluntarily close/re-lock it behind themselves --
			// same as bumping through and letting it swing shut, just
			// without waiting on the autoclose timer. close() (above)
			// re-locks automatically, refuses outright if admin_forced_open.
			if(!density)
				close()
			. = TRUE
		if("enter")
			var/entered = entry_buffer
			entry_buffer = ""
			if(length(entered) != 5)
				. = TRUE
				return
			if(!set_code)
				set_code = entered
				setter_ckey = user.ckey
				setter_name = user.real_name
				lock(TRUE)
				to_chat(user, SPAN_NOTICE("You set \the [src]'s passcode."))
				log_game("[key_name(user)] set a passcode on keypad door [src] at [COORD(src)].")
			else if(entered == set_code)
				unlock(TRUE)
				open()
			else
				to_chat(user, SPAN_WARNING("Incorrect code."))
				do_animate("deny")
			. = TRUE
		if("reset_code")
			if(!set_code || (!_is_setter(user) && !isAdmin))
				return TRUE
			set_code = null
			setter_ckey = null
			setter_name = null
			unlock(TRUE)
			to_chat(user, SPAN_NOTICE("You reset \the [src]'s passcode."))
			log_game("[key_name(user)] reset the passcode on keypad door [src] at [COORD(src)].")
			. = TRUE
		if("force_unlock")
			if(!isAdmin)
				return TRUE
			unlock(TRUE)
			open()
			message_admins("[key_name_admin(user)] force-unlocked keypad door [src] at [COORD(src)].")
			log_admin("[key_name(user)] force-unlocked keypad door [src] at [COORD(src)].")
			. = TRUE
		if("bolt_open")
			if(!isAdmin && !_is_setter(user))
				return TRUE
			admin_forced_open = TRUE
			unlock(TRUE)
			open()
			to_chat(user, SPAN_NOTICE("You bolt \the [src] open."))
			log_game("[key_name(user)] bolted keypad door [src] open at [COORD(src)].")
			if(isAdmin)
				message_admins("[key_name_admin(user)] bolted keypad door [src] open at [COORD(src)].")
			. = TRUE
		if("restore_default")
			if(!isAdmin && !_is_setter(user))
				return TRUE
			admin_forced_open = FALSE
			close()
			to_chat(user, SPAN_NOTICE("You restore \the [src] to normal operation."))
			log_game("[key_name(user)] restored keypad door [src] to normal operation at [COORD(src)].")
			if(isAdmin)
				message_admins("[key_name_admin(user)] restored keypad door [src] to normal operation at [COORD(src)].")
			. = TRUE

	if(.)
		SStgui.update_uis(src)
		return TRUE
	// Not ours -- let the ordinary airlock controls (bolts, power, idscan, the
	// wire panel) work as they do on any other airlock.
	return ..()

/**
 * Persists the code/setter/lock state across a restart -- same generic
 * per-object content hook proven this session on ion_engine.dm (on/thrust_limit).
 */
/obj/structure/machinery/door/airlock/keypad/persistent_objects_get_content()
	var/list/content = ..()
	content["set_code"] = set_code
	content["setter_ckey"] = setter_ckey
	content["setter_name"] = setter_name
	content["locked"] = locked
	content["admin_forced_open"] = admin_forced_open
	return content

/obj/structure/machinery/door/airlock/keypad/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	set_code = content["set_code"]
	setter_ckey = content["setter_ckey"]
	setter_name = content["setter_name"]
	locked = content["locked"] || FALSE
	admin_forced_open = content["admin_forced_open"] || FALSE
	update_icon()
