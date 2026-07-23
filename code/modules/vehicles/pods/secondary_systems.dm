/*
 * Phase 2 secondary systems: cargo hold, shielding. A starting handful --
 * Phase 3+ can add more variety. The hatch lock used to live here too, but
 * it competed with these two for the same POD_PART_SECONDARY slot -- see
 * lock.dm, which gives it its own dedicated POD_PART_LOCK slot instead.
 */

// ---------------------------------------------------------------------
// Cargo hold -- built on the same /obj/item/storage base bike.dm's own
// storage_compartment already uses, rather than a separate generic storage
// datum wrapper.
// ---------------------------------------------------------------------
/obj/item/podcomponent/secondary/cargo
	name = "cargo hold"
	desc = "A small cargo module for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "ore_hold"
	power_used = 0
	var/obj/item/storage/toolbox/hold

/obj/item/podcomponent/secondary/cargo/get_slot()
	return POD_PART_SECONDARY

/obj/item/podcomponent/secondary/cargo/ship_install()
	if(!hold)
		hold = new /obj/item/storage/toolbox(src)
		hold.name = "cargo hold contents"
		hold.max_w_class = WEIGHT_CLASS_BULKY
		hold.max_storage_space = 28

/obj/item/podcomponent/secondary/cargo/attack_hand(mob/user)
	if(hold && pod && (user in pod))
		hold.open(user)
		return
	return ..()

/obj/item/podcomponent/secondary/cargo/Destroy()
	QDEL_NULL(hold)
	return ..()

/// Delegates to the same serializePersistentItem()/deserializePersistentItem()
/// helpers closets already use for their own contents.
/obj/item/podcomponent/secondary/cargo/persistent_objects_get_content()
	var/list/content = ..()
	if(hold)
		var/list/items = list()
		for(var/obj/item/I in hold.contents)
			var/list/data = serializePersistentItem(I)
			if(data)
				items += list(data)
		if(length(items))
			content["hold_items"] = items
	return content

/obj/item/podcomponent/secondary/cargo/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content) || !islist(content["hold_items"]) || !hold)
		return
	for(var/list/data in content["hold_items"])
		deserializePersistentItem(data, hold)

// ---------------------------------------------------------------------
// Shielding -- a timed, activatable damage-reduction pool. One configurable
// tier for now (block_pct/shield_life/duration/recharge_time); a heavier
// second tier can be added later by subtyping this with higher values.
// ---------------------------------------------------------------------

/// The animated bubble shown on the pod's own hull while shielding is
/// active -- pod_ship.dmi's "shield" state (32x32, 7-frame looping shimmer)
/// was already sized for exactly this, previously only used as the
/// shielding component's own inventory icon. Attached to the pod via
/// vis_contents rather than being a real object in its contents.
/obj/effect/pod_shield_bubble
	name = "shield"
	desc = "A shimmering deflector field."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "shield"
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	alpha = 0
	layer = ABOVE_HUMAN_LAYER

/obj/item/podcomponent/secondary/shielding
	name = "light shielding system"
	desc = "A short-lived deflector shield for a space pod."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "shield"
	power_used = 60
	/// Fraction of incoming damage blocked while the shield has life left.
	var/block_pct = 0.25
	/// Total damage the shield can absorb before failing.
	var/shield_life = 100
	/// How long (deciseconds) the shield stays up once activated.
	var/duration = 10 SECONDS
	/// Cooldown (deciseconds) before it can be activated again after failing/expiring.
	var/recharge_time = 60 SECONDS
	var/current_life = 0
	var/ready = TRUE
	/// The visual bubble shown on the pod itself while the shield is up --
	/// see show_shield_bubble()/hide_shield_bubble() below.
	var/obj/effect/pod_shield_bubble/bubble
	/// world.time the shield will auto-expire, while active -- surfaced in
	/// cockpit.dm's ui_data() so the pilot can actually see the countdown
	/// instead of the shield just dropping with no visible explanation.
	var/shield_active_until = 0
	/// world.time the shield will be ready to reactivate, while recharging --
	/// same visibility purpose as shield_active_until above.
	var/shield_ready_at = 0

/obj/item/podcomponent/secondary/shielding/get_slot()
	return POD_PART_SECONDARY

/obj/item/podcomponent/secondary/shielding/Destroy()
	if(pod && bubble)
		pod.remove_vis_contents(bubble)
	QDEL_NULL(bubble)
	return ..()

/obj/item/podcomponent/secondary/shielding/activate(give_message = TRUE)
	if(!ready)
		if(pod)
			to_chat(usr, SPAN_WARNING("\The [src] is still recharging."))
		return FALSE
	. = ..()
	if(.)
		current_life = shield_life
		shield_active_until = world.time + duration
		addtimer(CALLBACK(src, PROC_REF(shield_expire)), duration)
		show_shield_bubble()

/obj/item/podcomponent/secondary/shielding/deactivate(give_message = TRUE)
	..()
	hide_shield_bubble()

/**
 * Fades the shield bubble in on the pod itself. Attached via
 * add_vis_contents() (not pod.dm's own AddOverlays()/ClearOverlays() hull-
 * sprite mechanism -- AddOverlays() freezes an image's appearance at add
 * time, so it can't be live-animated for a fade, and pod.dm's update_icon()
 * unconditionally clears all AddOverlays() overlays on every hull refresh,
 * e.g. toggling the engine, which would wipe the bubble along with it.
 * vis_contents is a separate list untouched by either of those, matching
 * how /obj/aura/mechshield (code/modules/heavy_vehicle/equipment/combat.dm)
 * already does the same thing for a mech's shield.
 */
/obj/item/podcomponent/secondary/shielding/proc/show_shield_bubble()
	if(!pod)
		return
	if(!bubble)
		bubble = new(pod)
		pod.add_vis_contents(bubble)
	animate(bubble, alpha = 255, time = 1 SECOND)

/// Fades the bubble back out rather than cutting it instantly. Left sitting
/// in vis_contents at alpha 0 between toggles instead of removed/re-added
/// each time.
/obj/item/podcomponent/secondary/shielding/proc/hide_shield_bubble()
	if(!bubble)
		return
	animate(bubble, alpha = 0, time = 1 SECOND)

/obj/item/podcomponent/secondary/shielding/proc/shield_expire()
	if(active)
		deactivate()
	ready = FALSE
	shield_ready_at = world.time + recharge_time
	addtimer(CALLBACK(src, PROC_REF(shield_recharge)), recharge_time)

/obj/item/podcomponent/secondary/shielding/proc/shield_recharge()
	ready = TRUE
	if(pod)
		pod.visible_message(SPAN_NOTICE("\The [pod]'s shield generator hums -- ready again."))

/// Called from the pod's damage-taking path (Phase 2 hook -- see
/// /obj/vehicle/bike/pod/add_damage() override in pod.dm) to reduce
/// incoming damage while the shield still has life left. Returns the
/// (possibly reduced) damage to actually apply.
/obj/item/podcomponent/secondary/shielding/proc/absorb(amount)
	if(!active || current_life <= 0)
		return amount
	var/blocked = amount * block_pct
	blocked = min(blocked, current_life)
	current_life -= blocked
	if(current_life <= 0)
		shield_expire()
	return amount - blocked

/obj/item/podcomponent/secondary/shielding/persistent_objects_get_content()
	var/list/content = ..()
	content["current_life"] = current_life
	content["ready"] = ready
	return content

/obj/item/podcomponent/secondary/shielding/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["current_life"]))
		current_life = text2num(content["current_life"])
	ready = content["ready"] ? TRUE : FALSE
