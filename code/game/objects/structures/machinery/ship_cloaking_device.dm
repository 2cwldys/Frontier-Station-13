/*
 * Ship Cloaking Device
 * A cargo-purchasable machine that, once wrenched to a ship's hull and
 * powered, makes that ship completely undetectable across every overmap
 * detection surface (contact_sensors.dm, sensors.dm, helm.dm,
 * overmap_shuttle.dm, personal_travel.dm, sector_view.dm -- see
 * overmap_object.dm's cloaked/is_detectable()/set_cloaked()). Burns phoron
 * crystals as fuel, deliberately fast (see time_per_sheet below) so
 * near-total stealth isn't a free, permanent state.
 *
 * Named distinctly from the unrelated wearable /obj/item/cloaking_device
 * (weapons/cloaking_device.dm) to avoid confusion in logs/admin tools.
 */

/obj/structure/machinery/ship_cloaking_device
	name = "cloaking device"
	desc = "A hulking device that bends light and subspace signals around the ship, rendering it undetectable to conventional sensors."
	icon = 'icons/obj/power.dmi'
	icon_state = "rtg"
	color = "#9b30ff"
	anchored = FALSE // spawns loose on purchase -- must be wrenched down before it can activate
	density = TRUE
	maxhealth = OBJECT_HEALTH_HIGH
	idle_power_usage = 0
	active_power_usage = 0

	var/active = FALSE
	/// Fuel efficiency -- how long 1 sheet lasts at power_output 1. Deliberately
	/// far below portgen/basic's baseline (576, portgen.dm) -- a cloak this
	/// total is meant to be hungry, not a free permanent state.
	var/time_per_sheet = 60
	var/max_sheets = 30
	var/sheets = 0
	var/sheet_left = 0
	var/power_output = 1
	var/sheet_path = /obj/item/stack/material/phoron
	var/sheet_name = "phoron crystals"
	/// world.time this device may next be (re)activated -- stamped whenever
	/// firing a weapon force-uncloaks the ship (_ship_gun.dm's fire()), so a
	/// cloaked ship can't fire and immediately vanish again.
	var/cloak_lockout_until = 0

/obj/structure/machinery/ship_cloaking_device/Initialize()
	. = ..()
	return INITIALIZE_HINT_LATELOAD

// Same reasoning as allinone.dm's ship subtype and faction_beacon's own
// hookup timing -- a freshly drydock-deployed ship's shuttle datum doesn't
// exist yet when LateInitialize() first runs here; SSshuttle's
// populate_sector_objects() links it moments later via a direct
// attempt_hook_up() call that bypasses LateInitialize() entirely, so
// hooking the link into attempt_hook_up() itself (via _hook_up_to_ship())
// means it fires exactly once, whichever call site actually succeeds.
/obj/structure/machinery/ship_cloaking_device/LateInitialize()
	. = ..()
	_hook_up_to_ship()

/obj/structure/machinery/ship_cloaking_device/proc/_hook_up_to_ship()
	if(linked)
		return TRUE
	if(!SSatlas.current_map.use_overmap)
		return FALSE
	var/my_sector = GLOB.map_sectors["[GET_Z(src)]"]
	if(istype(my_sector, /obj/effect/overmap/visitable))
		return attempt_hook_up(my_sector)
	return FALSE

/obj/structure/machinery/ship_cloaking_device/Destroy()
	if(active && istype(linked))
		linked.set_cloaked(FALSE)
	DropFuel()
	return ..()

/obj/structure/machinery/ship_cloaking_device/proc/HasFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(sheets >= needed_sheets - sheet_left)
		return TRUE
	return FALSE

/obj/structure/machinery/ship_cloaking_device/proc/UseFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(needed_sheets > sheet_left)
		sheets--
		sheet_left = (1 + sheet_left) - needed_sheets
	else
		sheet_left -= needed_sheets

// Removes whatever's left in the hopper as a fresh stack -- mirrors
// portgen/basic's DropFuel(), called on Destroy() so scrapping the device
// doesn't silently delete stored phoron.
/obj/structure/machinery/ship_cloaking_device/proc/DropFuel()
	if(sheets)
		var/obj/item/stack/material/S = new sheet_path(loc)
		var/amount = min(sheets, S.max_amount)
		S.amount = amount
		sheets -= amount

/obj/structure/machinery/ship_cloaking_device/process()
	if(active && anchored && istype(linked) && HasFuel())
		UseFuel()
	else if(active)
		// Ran out of phoron, got unanchored, or lost its ship link -- force off.
		_set_active(FALSE, silent = (!HasFuel())) // still announce unanchor/delink, but not routine fuel exhaustion spam beyond the one alert below
		if(!HasFuel())
			audible_message(SPAN_WARNING("\The [src] sputters and powers down -- out of phoron."))

/obj/structure/machinery/ship_cloaking_device/proc/toggle_cloak(mob/user)
	if(!active)
		if(world.time < cloak_lockout_until)
			to_chat(user, SPAN_WARNING("\The [src] is still recalibrating after firing -- [round((cloak_lockout_until - world.time) / 10)] second\s left."))
			return
		if(!anchored)
			to_chat(user, SPAN_WARNING("\The [src] must be anchored before it can be activated."))
			return
		if(!_hook_up_to_ship())
			to_chat(user, SPAN_WARNING("\The [src] cannot locate this ship on the overmap."))
			return
		if(!HasFuel())
			to_chat(user, SPAN_WARNING("\The [src] has no phoron left to burn."))
			return
	_set_active(!active)

/obj/structure/machinery/ship_cloaking_device/proc/_set_active(new_state, silent = FALSE)
	if(active == new_state)
		return
	active = new_state
	if(istype(linked))
		linked.set_cloaked(active)
	if(!silent)
		visible_message(active \
			? SPAN_NOTICE("\The [src] hums to life -- the air around the hull shimmers, then the ship seems to vanish.") \
			: SPAN_NOTICE("\The [src] powers down."))
	update_icon()

/obj/structure/machinery/ship_cloaking_device/update_icon()
	set_light(active ? 2 : 0, 1, l_color = color)

/obj/structure/machinery/ship_cloaking_device/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, sheet_path))
		var/obj/item/stack/addstack = attacking_item
		var/amount = min((max_sheets - sheets), addstack.amount)
		if(amount < 1)
			to_chat(user, SPAN_NOTICE("\The [src] is full!"))
			return
		to_chat(user, SPAN_NOTICE("You feed [amount] [sheet_name] into \the [src]."))
		sheets += amount
		addstack.use(amount)
		return
	if(attacking_item.tool_behaviour == TOOL_WRENCH)
		if(anchored && active)
			to_chat(user, SPAN_WARNING("Power down \the [src] before unwrenching it."))
			return TRUE
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		user.visible_message(SPAN_NOTICE("[user] [anchored ? "wrenches" : "unwrenches"] \the [src] [anchored ? "to" : "from"] the floor."), \
			SPAN_NOTICE("You [anchored ? "wrench \the [src] to" : "unwrench \the [src] from"] the floor."))
		return TRUE
	return ..()

/obj/structure/machinery/ship_cloaking_device/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/ship_cloaking_device/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ShipCloakingDevice", "Cloaking Device", 380, 320)
		ui.open()

/obj/structure/machinery/ship_cloaking_device/ui_data(mob/user)
	var/list/data = list()
	data["active"] = active
	data["anchored"] = anchored
	data["linked"] = istype(linked)
	data["sheets"] = sheets
	data["max_sheets"] = max_sheets
	data["sheet_name"] = sheet_name
	var/needed_sheets = power_output / time_per_sheet // fraction of a sheet burned per process() tick
	data["seconds_per_sheet"] = time_per_sheet
	data["seconds_remaining"] = (needed_sheets > 0) ? round((sheets + sheet_left) / needed_sheets) : null
	return data

/obj/structure/machinery/ship_cloaking_device/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("toggle")
			toggle_cloak(user)
			. = TRUE
