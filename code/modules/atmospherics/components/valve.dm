/obj/structure/machinery/atmospherics/valve
	name = "manual valve"
	desc = "A pipe valve."
	icon = 'icons/atmos/valve.dmi'
	icon_state = "map_valve0"

	level = 1
	dir = SOUTH
	initialize_directions = SOUTH|NORTH

	var/open = 0
	var/openDuringInit = 0

	var/datum/pipe_network/network_node1
	var/datum/pipe_network/network_node2

/obj/structure/machinery/atmospherics/valve/feedback_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "It is [open ? "open" : "closed"]."

/obj/structure/machinery/atmospherics/valve/mechanics_hints(mob/user, distance, is_adjacent)
	. += ..()
	. += "Click this to turn the valve."
	. += "If red, the pipes on each end are seperated. Otherwise, they are connected."

/obj/structure/machinery/atmospherics/valve/open
	open = 1
	icon_state = "map_valve1"

/obj/structure/machinery/atmospherics/valve/update_icon(animation)
	if(animation)
		flick("valve[src.open][!src.open]",src)
	else
		icon_state = "valve[open]"

/obj/structure/machinery/atmospherics/valve/update_underlays()
	if(..())
		underlays.Cut()
		var/turf/T = get_turf(src)
		if(!istype(T))
			return
		add_underlay(T, node1, get_dir(src, node1))
		add_underlay(T, node2, get_dir(src, node2))

/obj/structure/machinery/atmospherics/valve/hide(var/i)
	update_underlays()

/obj/structure/machinery/atmospherics/valve/Initialize()
	switch(dir)
		if(NORTH, SOUTH)
			initialize_directions = NORTH|SOUTH
		if(EAST, WEST)
			initialize_directions = EAST|WEST
	. = ..()

/obj/structure/machinery/atmospherics/valve/network_expand(datum/pipe_network/new_network, obj/structure/machinery/atmospherics/pipe/reference)
	if(reference == node1)
		network_node1 = new_network
		if(open)
			network_node2 = new_network
	else if(reference == node2)
		network_node2 = new_network
		if(open)
			network_node1 = new_network

	if(new_network.normal_members.Find(src))
		return 0

	new_network.normal_members += src

	if(open)
		if(reference == node1)
			if(node2)
				return node2.network_expand(new_network, src)
		else if(reference == node2)
			if(node1)
				return node1.network_expand(new_network, src)

	return null

/obj/structure/machinery/atmospherics/valve/Destroy()
	loc = null

	if(node1)
		node1.disconnect(src)
		qdel(network_node1)
	if(node2)
		node2.disconnect(src)
		qdel(network_node2)

	node1 = null
	node2 = null

	return ..()

/obj/structure/machinery/atmospherics/valve/proc/open()
	if(open) return 0

	open = 1
	update_icon()

	if(network_node1&&network_node2)
		network_node1.merge(network_node2)
		network_node2 = network_node1

	if(network_node1)
		network_node1.update = 1
	else if(network_node2)
		network_node2.update = 1

	return 1

/obj/structure/machinery/atmospherics/valve/proc/close()
	if(!open)
		return 0

	open = 0
	update_icon()

	if(network_node1)
		qdel(network_node1)
	if(network_node2)
		qdel(network_node2)

	build_network()

	return 1

/obj/structure/machinery/atmospherics/valve/proc/normalize_dir()
	if(dir==3)
		set_dir(1)
	else if(dir==12)
		set_dir(4)

/obj/structure/machinery/atmospherics/valve/attack_ai(mob/user as mob)
	return

/obj/structure/machinery/atmospherics/valve/attack_hand(mob/user as mob)
	src.add_fingerprint(usr)
	update_icon(1)
	sleep(10)
	if (src.open)
		src.close()
	else
		src.open()

/obj/structure/machinery/atmospherics/valve/process()
	..()
	return PROCESS_KILL

/obj/structure/machinery/atmospherics/valve/atmos_init()
	normalize_dir()

	var/node1_dir
	var/node2_dir

	for(var/direction in GLOB.cardinals)
		if(direction&initialize_directions)
			if (!node1_dir)
				node1_dir = direction
			else if (!node2_dir)
				node2_dir = direction

	for(var/obj/structure/machinery/atmospherics/target in get_step(src,node1_dir))
		if(target.initialize_directions & get_dir(target,src))
			if (check_connect_types(target,src))
				node1 = target
				break
	for(var/obj/structure/machinery/atmospherics/target in get_step(src,node2_dir))
		if(target.initialize_directions & get_dir(target,src))
			if (check_connect_types(target,src))
				node2 = target
				break

	build_network()

	queue_icon_update()
	update_underlays()

	if(openDuringInit)
		close()
		open()
		openDuringInit = 0

/obj/structure/machinery/atmospherics/valve/build_network()
	if(!network_node1 && node1)
		network_node1 = new /datum/pipe_network()
		network_node1.normal_members += src
		network_node1.build_network(node1, src)

	if(!network_node2 && node2)
		network_node2 = new /datum/pipe_network()
		network_node2.normal_members += src
		network_node2.build_network(node2, src)

/obj/structure/machinery/atmospherics/valve/return_network(obj/structure/machinery/atmospherics/reference)
	build_network()

	if(reference==node1)
		return network_node1

	if(reference==node2)
		return network_node2

	return null

/obj/structure/machinery/atmospherics/valve/reassign_network(datum/pipe_network/old_network, datum/pipe_network/new_network)
	if(network_node1 == old_network)
		network_node1 = new_network
	if(network_node2 == old_network)
		network_node2 = new_network

	return 1

/obj/structure/machinery/atmospherics/valve/return_network_air(datum/pipe_network/reference)
	return null

/obj/structure/machinery/atmospherics/valve/disconnect(obj/structure/machinery/atmospherics/reference)
	if(reference==node1)
		qdel(network_node1)
		node1 = null

	else if(reference==node2)
		qdel(network_node2)
		node2 = null

	update_underlays()

	return null

/obj/structure/machinery/atmospherics/valve/digital		// can be controlled by AI
	name = "digital valve"
	desc = "A digitally controlled valve."
	icon = 'icons/atmos/digital_valve.dmi'

	var/frequency = 0
	var/id = null
	var/datum/radio_frequency/radio_connection
	/// Determines if this digital valve should provide an admin message. Set to false if the valve is not relevant to admins.
	var/admin_message = TRUE

/obj/structure/machinery/atmospherics/valve/digital/no_admin_message
	admin_message = FALSE

/obj/structure/machinery/atmospherics/valve/digital/open
	open = 1
	icon_state = "map_valve1"

/obj/structure/machinery/atmospherics/valve/digital/open/no_admin_message
	admin_message = FALSE

/obj/structure/machinery/atmospherics/valve/digital/attack_ai(mob/user as mob)
	if(!ai_can_interact(user))
		return
	return src.attack_hand(user)

/obj/structure/machinery/atmospherics/valve/digital/attack_hand(mob/user as mob)
	if(!powered())
		return
	if(!src.allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return
	..()

	if(admin_message)
		log_and_message_admins("has [open ? SPAN_WARNING("OPENED") : "closed"] [name].", user)

/obj/structure/machinery/atmospherics/valve/digital/AltClick(var/mob/abstract/ghost/observer/admin)
	if (istype(admin))
		if (admin.client && admin.client.holder && ((R_MOD|R_ADMIN) & admin.client.holder.rights))
			if (open)
				close()
			else
				if (alert(admin, "The valve is currently closed. Do you want to open it?", "Open the valve?", "Yes", "No") == "No")
					return
				open()

			log_and_message_admins("has [open ? "opened" : "closed"] [name].", admin)

/obj/structure/machinery/atmospherics/valve/digital/power_change()
	var/old_stat = stat
	..()
	if(old_stat != stat)
		queue_icon_update()

/obj/structure/machinery/atmospherics/valve/digital/update_icon()
	..()
	if(!powered())
		icon_state = "valve[open]nopower"

/obj/structure/machinery/atmospherics/valve/digital/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = SSradio.add_object(src, frequency, RADIO_ATMOSIA)

/obj/structure/machinery/atmospherics/valve/digital/atmos_init()
	..()
	if(frequency)
		set_frequency(frequency)

/obj/structure/machinery/atmospherics/valve/digital/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id))
		return 0

	switch(signal.data["command"])
		if("valve_open")
			if(!open)
				open()

		if("valve_close")
			if(open)
				close()

		if("valve_toggle")
			if(open)
				close()
			else
				open()

/**
 * Buildable variant of the digital valve that gates manual opening
 * behind a keypad code instead of ID access. Deliberately doesn't touch
 * set_frequency()/atmos_init() -- a paired atmos control button (or AI)
 * still WORKS over RADIO_ATMOSIA exactly as any other digital valve, but
 * receive_signal() is overridden below so its open direction is gated by
 * the same lock the keypad enforces -- a button alone, without the code
 * ever having been entered, is not enough to open this valve. The admin
 * AltClick() bypass is untouched (still a full, unconditional override).
 */
/obj/structure/machinery/atmospherics/valve/digital/keypad
	name = "keypad valve"
	desc = "A digitally controlled valve gated by a keypad lock."

	/// The permanent stored code, null = not yet set.
	var/set_code = null
	/// (ckey, char_name) of whoever set the current code -- same composite
	/// per-character identity pattern airlock_keypad.dm uses.
	var/setter_ckey = null
	var/setter_name = null
	/// Transient, not persisted -- digits typed so far, mirrors
	/// airlock_keypad.dm's own entry_buffer.
	var/entry_buffer = ""
	/// TRUE until the correct code is entered via the keypad -- gates the
	/// OPEN direction of receive_signal() below (a paired remote atmos
	/// button/AI can't open this valve on frequency knowledge alone; it can
	/// only act once the keypad has already authorized it). Re-armed
	/// unconditionally by close() below regardless of what closed it --
	/// closing is always free (close_valve, ui_act()) and always re-locks.
	var/locked = TRUE

/obj/structure/machinery/atmospherics/valve/digital/keypad/attack_hand(mob/user as mob)
	if(!powered())
		return
	ui_interact(user)

/obj/structure/machinery/atmospherics/valve/digital/keypad/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "KeypadValve", "[name]", 380, 520)
		ui.open()

/obj/structure/machinery/atmospherics/valve/digital/keypad/ui_data(mob/user)
	var/list/data = list()
	data["valveName"] = name
	data["codeSet"] = !!set_code
	data["open"] = open
	data["setterName"] = setter_name
	// Matches ui_act()'s own "reset_code" gate exactly (setter OR admin) --
	// without the admin half here, an admin who isn't the setter would
	// never see the button to trigger the reset they're already allowed to do.
	data["canReset"] = set_code && (_is_setter(user) || check_rights(R_ADMIN, FALSE, user))
	data["entry"] = entry_buffer
	return data

/// TRUE if user is the (ckey, char_name) that set the current code.
/obj/structure/machinery/atmospherics/valve/digital/keypad/proc/_is_setter(mob/user)
	return set_code && (user.ckey == setter_ckey) && (user.real_name == setter_name)

/// Every close path (the TGUI's free close_valve, a remote valve_close/
/// valve_toggle signal, or an admin's AltClick) funnels through here, so
/// re-locking once, in this single override, covers all of them uniformly.
/obj/structure/machinery/atmospherics/valve/digital/keypad/close()
	. = ..()
	locked = TRUE

/// Same signal handling as the base digital valve, except the open
/// direction additionally requires !locked -- a paired remote button
/// knowing the frequency/id is not, on its own, sufficient authorization;
/// it can only act once the keypad has unlocked this valve. The close
/// direction is intentionally left unconditional, matching the keypad's
/// own free close_valve action.
/obj/structure/machinery/atmospherics/valve/digital/keypad/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id))
		return 0

	switch(signal.data["command"])
		if("valve_open")
			if(!open && !locked)
				open()
		if("valve_close")
			if(open)
				close()
		if("valve_toggle")
			if(open)
				close()
			else if(!locked)
				open()

/obj/structure/machinery/atmospherics/valve/digital/keypad/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("type")
			var/digit = params["value"]
			// Membership test, not text2num() -- see airlock_keypad.dm's
			// identical comment: null == 0 is TRUE in DM, so text2num("0")
			// would be indistinguishable from a rejected digit.
			if(istext(digit) && length(digit) == 1 && findtext("0123456789", digit) && length(entry_buffer) < 5)
				entry_buffer += digit
			. = TRUE
		if("clear")
			entry_buffer = ""
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
				to_chat(user, SPAN_NOTICE("You set \the [src]'s passcode."))
			else if(entered == set_code)
				locked = FALSE
				if(!open)
					open()
					if(admin_message)
						log_and_message_admins("[SPAN_WARNING("OPENED")] [name] via keypad.", user)
				else
					to_chat(user, SPAN_NOTICE("\The [src] is already open."))
			else
				to_chat(user, SPAN_WARNING("Incorrect code."))
			. = TRUE
		// Closing is always free, no code needed -- mirrors
		// airlock_keypad.dm's own "Close Door" action. close() (overridden
		// below) re-locks unconditionally, so re-opening -- by keypad OR by
		// a paired remote button -- always needs the code again afterward.
		if("close_valve")
			if(open)
				close()
				if(admin_message)
					log_and_message_admins("closed [name] via keypad.", user)
			. = TRUE
		if("reset_code")
			if(!_is_setter(user) && !check_rights(R_ADMIN, FALSE, user))
				return TRUE
			set_code = null
			setter_ckey = null
			setter_name = null
			to_chat(user, SPAN_NOTICE("You reset \the [src]'s passcode."))
			. = TRUE
	if(.)
		SStgui.update_uis(src)

/// Persists the code/setter across a restart -- same generic per-object
/// content hook this session's other player-built machinery already uses.
/obj/structure/machinery/atmospherics/valve/digital/keypad/persistent_objects_get_content()
	var/list/content = ..()
	content["set_code"] = set_code
	content["setter_ckey"] = setter_ckey
	content["setter_name"] = setter_name
	return content

/obj/structure/machinery/atmospherics/valve/digital/keypad/persistent_objects_apply_content(list/content, x, y, z)
	..()
	if(!islist(content))
		return
	set_code = content["set_code"]
	setter_ckey = content["setter_ckey"]
	setter_name = content["setter_name"]

/obj/structure/machinery/atmospherics/valve/attackby(obj/item/attacking_item, mob/user)
	if (attacking_item.tool_behaviour != TOOL_WRENCH)
		return ..()
	if (istype(src, /obj/structure/machinery/atmospherics/valve/digital))
		to_chat(user, SPAN_WARNING("You cannot unwrench \the [src], it's too complicated."))
		return TRUE
	var/datum/gas_mixture/int_air = return_air()
	if (!loc) return FALSE
	var/datum/gas_mixture/env_air = loc.return_air()
	if ((XGM_PRESSURE(int_air)-XGM_PRESSURE(env_air)) > PRESSURE_EXERTED)
		to_chat(user, SPAN_WARNING("You cannot unwrench \the [src], it is too exerted due to internal pressure."))
		add_fingerprint(user)
		return TRUE
	to_chat(user, SPAN_NOTICE("You begin to unfasten \the [src]..."))
	if(attacking_item.use_tool(src, user, istype(attacking_item, /obj/item/pipewrench) ? 80 : 40, volume = 50))
		user.visible_message( \
			SPAN_NOTICE("\The [user] unfastens \the [src]."), \
			SPAN_NOTICE("You have unfastened \the [src]."), \
			"You hear a ratchet.")
		new /obj/item/pipe(loc, make_from=src)
		qdel(src)
		return TRUE
