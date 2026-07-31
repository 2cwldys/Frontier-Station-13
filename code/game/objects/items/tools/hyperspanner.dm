/*
 * Hyperspanner
 * Cell-powered multi-tool that fully repairs damaged walls, windows,
 * machinery (airlocks included -- they're a machinery subtype), and floors
 * over a few uses instead of instantly -- unlike the welder-based repair
 * paths those types already have (wall_attacks.dm, door.dm,
 * floor_attackby.dm), which this tool doesn't touch or replace. Ships
 * without a cell installed -- same convention as any other cell tool
 * (stunbaton.dm, cloaking_device.dm).
 */
/obj/item/hyperspanner
	name = "hyperspanner"
	desc = "A heavy-duty multi-tool for rapid structural repairs to walls, windows, machinery, and floors. Requires a power cell."
	// PLACEHOLDER sprite until dedicated art is done -- borrowing the wrench's.
	icon = 'icons/obj/tools.dmi'
	icon_state = "wrench"
	item_state = "wrench"
	w_class = WEIGHT_CLASS_NORMAL
	slot_flags = SLOT_BELT
	force = 5
	throwforce = 5
	// PLACEHOLDER -- swap for the custom loop once it's converted to .ogg.
	usesound = 'sound/items/Welder.ogg'

	/// Installed power cell, or null. Removed with a screwdriver, same as
	/// any other cell-in-tool device (stunbaton.dm, cloaking_device.dm).
	var/obj/item/cell/cell = null
	/// Charge consumed per repair pulse.
	var/charge_cost = 500
	/// Tool-wide cooldown between repair pulses (any target) -- gives the
	/// tool a deliberate, multi-step repair pace instead of instantly
	/// hammering a target back to full in one click.
	COOLDOWN_DECLARE(hyperspanner_cd)
	/// How many pulses each currently-damaged floor turf has received so
	/// far, keyed by the turf itself -- floors use boolean broken/burnt
	/// flags (floor_damage.dm), not a health pool, so they have no other
	/// way to track partial repair progress the way walls/windows/airlocks
	/// do via their own health/maxhealth (see _repair_health_target()).
	/// Cleared once a floor is fully repaired.
	var/list/floor_repair_progress = list()
	/// TRUE while a repair pulse's use_tool() channel is running -- lets
	/// _repair_loop_sound() know when to stop repeating its playsound.
	var/repairing_now = FALSE

/obj/item/hyperspanner/Destroy()
	QDEL_NULL(cell)
	floor_repair_progress = null
	return ..()

/obj/item/hyperspanner/get_examine_text(mob/user, distance, is_adjacent, infix = "", suffix = "", show_extended)
	. = ..()
	if(cell)
		. += "It has \a [cell] installed, with [cell.charge]/[cell.maxcharge] charge remaining."
	else
		. += "It has no power cell installed."

// Never let a repair target's own attackby() consume this click -- doors
// (door.dm) fall through to just opening/closing themselves for any
// unrecognized tool, and other machinery/turfs have their own generic
// fallbacks too. Bypassing attackby() entirely for a valid repair target
// guarantees afterattack() below always gets the click instead, regardless
// of what any given target type's own fallback happens to do. Mirrors
// commander_beacon.dm's faction tagger, which does the same thing for the
// same reason.
/obj/item/hyperspanner/resolve_attackby(atom/A, mob/user, click_parameters)
	if(_is_valid_repair_target(A))
		pre_attack(A, user)
		add_fingerprint(user)
		return FALSE
	return ..()

/obj/item/hyperspanner/attackby(obj/item/attacking_item, mob/user)
	if(istype(attacking_item, /obj/item/cell))
		var/obj/item/cell/new_cell = attacking_item
		if(new_cell.w_class != WEIGHT_CLASS_NORMAL)
			to_chat(user, SPAN_WARNING("\The [new_cell] is too [new_cell.w_class < WEIGHT_CLASS_NORMAL ? "small" : "large"] to fit here."))
			return
		if(cell)
			to_chat(user, SPAN_NOTICE("\The [src] already has a cell."))
			return
		if(!user.drop_from_inventory(attacking_item, src))
			return
		cell = new_cell
		to_chat(user, SPAN_NOTICE("You install a cell in \the [src]."))
		return
	if(attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
		if(!cell)
			to_chat(user, SPAN_WARNING("\The [src] has no cell installed."))
			return
		user.put_in_hands(cell)
		to_chat(user, SPAN_NOTICE("You remove the cell from \the [src]."))
		cell = null
		return
	return ..()

/obj/item/hyperspanner/afterattack(atom/target, mob/user, proximity_flag)
	. = ..()
	if(!proximity_flag)
		return
	// Say so rather than doing nothing at all. A click on a tile very often
	// resolves to an object sitting on it rather than the turf itself, and
	// unsimulated (shuttle/CentCom) plating isn't a repair target either --
	// both used to return here in total silence, which reads as the tool
	// being broken rather than the target being wrong.
	if(!_is_valid_repair_target(target))
		to_chat(user, SPAN_WARNING("\The [target] can't be repaired with \the [src]."))
		return
	if(!COOLDOWN_FINISHED(src, hyperspanner_cd))
		to_chat(user, SPAN_WARNING("\The [src] is still recharging -- [COOLDOWN_TIMELEFT(src, hyperspanner_cd)] second[COOLDOWN_TIMELEFT(src, hyperspanner_cd) > 10 ? "s" : ""] left."))
		return
	if(!cell)
		to_chat(user, SPAN_WARNING("\The [src] has no power source!"))
		return
	if(!cell.check_charge(charge_cost))
		to_chat(user, SPAN_WARNING("\The [src] is out of charge."))
		return
	if(istype(target, /turf/simulated/floor))
		_repair_floor_target(target, user)
	else
		_repair_health_target(target, user)

/obj/item/hyperspanner/proc/_is_valid_repair_target(atom/target)
	return istype(target, /turf/simulated/wall) || \
		istype(target, /obj/structure/window) || \
		istype(target, /obj/structure/machinery) || \
		istype(target, /turf/simulated/floor)

/// TRUE if `target` currently needs repair -- health-pool types (walls,
/// windows, machinery) check health/maxhealth directly; machinery also
/// counts as needing repair while flagged BROKEN even if health happens to
/// already read at maxhealth.
/obj/item/hyperspanner/proc/_needs_health_repair(atom/target)
	if(istype(target, /obj/structure/machinery))
		var/obj/structure/machinery/M = target
		if(M.stat & BROKEN)
			return TRUE
	return target.health < target.maxhealth

/obj/item/hyperspanner/proc/_repair_health_target(atom/target, mob/user)
	if(!_needs_health_repair(target))
		to_chat(user, SPAN_WARNING("\The [target] does not need repairs."))
		return
	repairing_now = TRUE
	_repair_loop_sound(target)
	var/success = use_tool(target, user, 3 SECONDS, volume = 50)
	repairing_now = FALSE
	if(!success)
		return
	cell.checked_use(charge_cost)
	target.add_health(round(target.maxhealth * 0.4))
	if(istype(target, /obj/structure/machinery))
		var/obj/structure/machinery/M = target
		if(M.health >= M.maxhealth)
			M.stat &= ~BROKEN
			M.update_icon()
	spark(target, 5)
	user.visible_message(SPAN_NOTICE("[user] works to repair the [target]."), SPAN_NOTICE("You work to repair the [target]."))
	COOLDOWN_START(src, hyperspanner_cd, 15 SECONDS)

/obj/item/hyperspanner/proc/_repair_floor_target(turf/simulated/floor/target, mob/user)
	if(isnull(target.broken) && isnull(target.burnt))
		to_chat(user, SPAN_WARNING("\The [target] does not need repairs."))
		return
	repairing_now = TRUE
	_repair_loop_sound(target)
	var/success = use_tool(target, user, 3 SECONDS, volume = 50)
	repairing_now = FALSE
	if(!success)
		return
	cell.checked_use(charge_cost)
	floor_repair_progress[target] = (floor_repair_progress[target] || 0) + 1
	if(floor_repair_progress[target] >= 2)
		target.broken = null
		target.burnt = null
		target.icon_state = "plating"
		floor_repair_progress -= target
	spark(target, 5)
	user.visible_message(SPAN_NOTICE("[user] works to repair the [target]."), SPAN_NOTICE("You work to repair the [target]."))
	COOLDOWN_START(src, hyperspanner_cd, 15 SECONDS)

/// Repeats usesound roughly every 1.5 seconds for as long as repairing_now
/// stays TRUE -- there's no existing "true loop" convention on hand tools
/// (use_tool() only plays usesound once at the start and once at the end
/// of its delay), so this is a small, self-contained stand-in until the
/// custom loop track is ready.
/obj/item/hyperspanner/proc/_repair_loop_sound(atom/target)
	set waitfor = FALSE
	while(repairing_now)
		playsound(target, usesound, 50, TRUE)
		sleep(15)
