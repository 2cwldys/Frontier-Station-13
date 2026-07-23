/*
 * Space Pod -- base vehicle framework (Phase 1)
 *
 * Subtypes /obj/vehicle/bike rather than raw /obj/vehicle -- bike.dm already
 * provides everything a small pilotable space vehicle needs: buckle-based
 * piloting (relaymove() -> Move(), see bike.dm:194-199), space-vs-land speed
 * (check_destination()/space_speed), an ion trail effect, and the whole
 * damage/collision/EMP pipeline inherited from /obj/vehicle. wasp_torpedo.dm
 * ("a manned torpedo used by... space forces") is proof this exact base
 * already supports a small manned space vehicle -- pods are the same idea,
 * generalized with a slot-based part system instead of one fixed loadout.
 *
 * What's genuinely new here (no existing analog): the part/slot dictionary
 * (install_part()/eject_part()/delete_part()/get_part(), POD_PART_* slots
 * from code/__DEFINES/vehicle_pods.dm) and gating the engine key's ignition
 * on an installed engine part instead of (or in addition to) a physical key.
 */
/obj/vehicle/bike/pod
	name = "space pod"
	desc = "A small pressurized pod for short-range space travel."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "pod"

	health = 140
	maxhealth = 140

	land_speed = 1.4
	land_speed_careful = 2.2
	space_speed = 1
	space_speed_careful = 2

	can_hover = TRUE
	storage_type = null

	// Pods gate their engine on an installed engine part, not a physical
	// ignition key -- see toggle_engine()/turn_on() overrides below.
	spawns_with_key = FALSE
	key_type = null

	/// Slot name (POD_PART_*) -> installed /obj/item/podcomponent, or null if
	/// that slot is empty. Every slot key always exists (even when empty) so
	/// get_part() never has to distinguish "never populated" from "ejected."
	var/list/installed_parts

	/// icon_state in pod_ship.dmi for this variant's hull. Overridden per
	/// ship variant (see ships.dm). Pod art is one static state per variant
	/// rather than bike.dm's [bike_icon]_on/_off pairs, so update_icon()/
	/// setup_vehicle() are overridden below to use this directly instead.
	var/ship_sprite = "pod"

/// bike.dm's setup_vehicle() unconditionally sets icon_state to
/// "[bike_icon]_off" and adds an "_off_overlay" -- neither exists in
/// pod_ship.dmi, so undo that and pin the real static sprite instead.
/obj/vehicle/bike/pod/setup_vehicle()
	. = ..()
	ClearOverlays()
	icon_state = ship_sprite

/// Pod hulls are one static sprite per variant, not on/off pairs -- skip
/// bike.dm's [bike_icon]_on/_off overlay logic entirely.
/obj/vehicle/bike/pod/update_icon()
	ClearOverlays()
	icon_state = ship_sprite

/obj/vehicle/bike/pod/Initialize(mapload)
	. = ..()
	installed_parts = list(
		POD_PART_ENGINE = null,
		POD_PART_MAIN_WEAPON = null,
		POD_PART_SECONDARY = null,
		POD_PART_COMMS = null,
		POD_PART_SENSORS = null,
		POD_PART_LIGHTS = null,
		POD_PART_LOCK = null,
	)
	// See persistence.dm -- the same opt-in guard every other persistent
	// type in the codebase uses (e.g. code/game/objects/structures.dm).
	if(!mapload && GLOB.config.sql_enabled && GLOB.persistence_ready)
		SSpersistence.objectsRegisterTrack(src)

/obj/vehicle/bike/pod/Destroy()
	for(var/slot in installed_parts)
		var/obj/item/podcomponent/part = installed_parts[slot]
		if(part)
			qdel(part)
	installed_parts = null
	return ..()

/// Returns the part currently installed in slot, or null if empty/invalid.
/obj/vehicle/bike/pod/proc/get_part(slot)
	if(!installed_parts)
		return null
	return installed_parts[slot]

/**
 * Installs part into whichever slot part.get_slot() reports. Refuses if the
 * pod is locked, the part doesn't claim a valid slot, or the slot's already
 * occupied and eject_existing is FALSE (the occupant is ejected to user's
 * hand -- or the floor if user is null -- first when eject_existing is
 * TRUE, the default).
 */
/obj/vehicle/bike/pod/proc/install_part(mob/user, obj/item/podcomponent/part, eject_existing = TRUE)
	if(!istype(part))
		return FALSE
	var/slot = part.get_slot()
	if(!(slot in installed_parts))
		return FALSE
	if(locked)
		if(user)
			to_chat(user, SPAN_WARNING("\The [src] is locked."))
		return FALSE
	if(installed_parts[slot])
		if(!eject_existing)
			if(user)
				to_chat(user, SPAN_WARNING("\The [src]'s [slot] slot is already occupied."))
			return FALSE
		eject_part(user, slot)

	if(user)
		user.drop_from_inventory(part, src)
	part.forceMove(src)
	part.pod = src
	installed_parts[slot] = part
	part.ship_install()
	if(user)
		to_chat(user, SPAN_NOTICE("You install \the [part] into \the [src]'s [slot] slot."))
	return TRUE

/// Installing a podcomponent takes priority over everything else. An ID
/// (or wallet/PDA holding one) is next offered to swipe_id() (access.dm).
/// Anything else unrecognized is offered to the installed engine part (so
/// e.g. inserting a fuel tank still works once the engine is bolted in, not
/// just while it's a loose item in-hand -- see engine.dm's own attackby())
/// before finally falling through to the inherited key/maintenance/repair/
/// generic-damage handling (bike.dm/vehicle.dm).
/obj/vehicle/bike/pod/attackby(obj/item/attacking_item, mob/user)
	if(istype(attacking_item, /obj/item/podcomponent))
		install_part(user, attacking_item)
		return
	if(istype(attacking_item, /obj/item/faction_tagger))
		rename_via_tagger(user)
		return
	if(attacking_item.GetID())
		swipe_id(user, attacking_item)
		return
	var/obj/item/podcomponent/engine/E = get_part(POD_PART_ENGINE)
	if(istype(E) && E.attackby(attacking_item, user))
		return
	return ..()

/**
 * Trail visual while flying with the engine on -- copies
 * /obj/item/tank/jetpack's own allow_thrust() effect directly
 * (code/game/objects/items/weapons/tanks/jetpack.dm:135-139) rather than
 * relying on the inherited bike.dm ion/ion_type system, which only ever
 * fires while crossing actual space/openspace tiles (is_hole). Jetpack
 * thrust has no such gating -- it just always shows the trail -- which is
 * what actually flying a pod around visibly needs.
 */
/obj/vehicle/bike/pod/Move(turf/destination)
	var/turf/old_turf = get_turf(src)
	. = ..()
	if(. && on && old_turf && old_turf != get_turf(src))
		var/obj/effect/effect/ion_trails/I = new(old_turf)
		I.set_dir(dir)
		flick("ion_fade", I)
		I.icon_state = "blank"
		animate(I, alpha = 0, time = 18, easing = SINE_EASING | EASE_IN)
		QDEL_IN(I, 20)

/// Ejects whatever's in slot into user's hands (or the floor if no user/
/// full hands), returning the ejected part (or null if the slot was empty).
/// Routes incoming damage through an installed, active shielding secondary
/// (if any) before applying it, per that part's absorb().
/obj/vehicle/bike/pod/add_damage(damage, damage_flags, damage_type, armor_penetration, obj/weapon)
	var/obj/item/podcomponent/secondary/shielding/S = get_part(POD_PART_SECONDARY)
	if(istype(S))
		damage = S.absorb(damage)
	return ..(damage, damage_flags, damage_type, armor_penetration, weapon)

/// Ejects whatever's in slot into user's hands (or the floor if no user/
/// full hands), returning the ejected part (or null if the slot was empty).
/obj/vehicle/bike/pod/proc/eject_part(mob/user, slot)
	var/obj/item/podcomponent/part = installed_parts[slot]
	if(!part)
		return null
	if(part.active)
		part.deactivate(FALSE)
	part.ship_uninstall()
	part.pod = null
	installed_parts[slot] = null
	part.forceMove(get_turf(src))
	if(user)
		user.put_in_hands(part)
		to_chat(user, SPAN_NOTICE("You remove \the [part] from \the [src]."))
	return part

/// Permanently destroys whatever's in slot (used when a part is destroyed
/// outright rather than cleanly removed -- e.g. a future engine-critical hit).
/obj/vehicle/bike/pod/proc/delete_part(slot)
	var/obj/item/podcomponent/part = eject_part(null, slot)
	if(part)
		qdel(part)

/// Engine ignition now checks for an installed, undisrupted engine part
/// instead of (or alongside, if a key's ever added later) a physical key.
/obj/vehicle/bike/pod/toggle_engine(mob/user)
	if(use_check_and_message(user))
		return
	if(!on)
		var/obj/item/podcomponent/engine/E = get_part(POD_PART_ENGINE)
		if(!istype(E))
			to_chat(user, SPAN_WARNING("\The [src] has no engine installed."))
			return
		if(!E.activate())
			return
		turn_on()
		src.visible_message(SPAN_NOTICE("\The [src] hums to life."), SPAN_NOTICE("You hear a soft hum."))
		playsound(src, 'sound/machines/vehicles/bike_start.ogg', 100, 1)
	else
		var/obj/item/podcomponent/engine/E = get_part(POD_PART_ENGINE)
		if(istype(E))
			E.deactivate()
		turn_off()
		src.visible_message(SPAN_NOTICE("\The [src] powers down."), SPAN_NOTICE("You hear a soft whine fade out."))
