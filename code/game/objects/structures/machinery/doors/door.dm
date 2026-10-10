//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31
#define DOOR_REPAIR_AMOUNT 50	//amount of health regained per stack amount used

/obj/structure/machinery/door
	name = "Door"
	desc = "It opens and closes."
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door_closed"
	anchored = TRUE
	opacity = TRUE
	density = TRUE
	layer = CLOSED_DOOR_LAYER
	dir = SOUTH
	hitsound = 'sound/weapons/smash.ogg' //sound door makes when hit with a weapon
	armor = list(
		MELEE = ARMOR_MELEE_RESISTANT,
		BULLET = ARMOR_BALLISTIC_SMALL,
		LASER = ARMOR_LASER_PISTOL
	)
	var/hitsound_light = 'sound/effects/glass_hit.ogg'//Sound door makes when hit very gently

	maxhealth = OBJECT_HEALTH_VERY_HIGH

	var/open_layer = OPEN_DOOR_LAYER
	var/closed_layer = CLOSED_DOOR_LAYER

	/// Boolean. Whether or not the door blocks vision.
	var/visible = TRUE
	/// Boolean. Whether or not the door's panel is open.
	var/p_open = FALSE
	/// Boolean. The door's operating state.
	var/operating = FALSE
	/// Boolean. Whether or not the door will automatically close.
	var/autoclose = FALSE
	/// Boolean. Whether or not the door is considered a glass door.
	var/glass = FALSE
	/// Boolean. Whether or not the door waits before closing. Generally tied to the timing wire.
	var/normalspeed = TRUE
	/// Boolean. Whether or not the door is heat proof. Affects turf thermal conductivity for non-opaque doors. Provided for mapping use.
	var/heat_proof = FALSE
	/// Instance of material stack that's been added to the door for repairs.
	var/obj/item/stack/material/repairing
	/// Integer. Width of the door in tiles.
	var/width = 1
	/// One /obj/effect/door_tile_blocker per EXTRA tile (width > 1 doors only,
	/// empty otherwise) -- see _sync_tile_blockers()'s own doc comment for why
	/// this exists at all.
	var/list/tile_blockers
	var/air_properties_vary_with_direction = 0
	/// Integer. Corresponds to dirs. If opened from this dir, no access is required.
	var/unres_dir = null
	/// Integer. How many strong hits it takes to destroy the door.
	var/destroy_hits = 10
	/// Integer. Minimum amount of force needed to damage the door with a melee weapon.
	var/min_force = 10
	var/block_air_zones = 1 //If set, air zones cannot merge across the door even when it is opened.
	var/open_duration = 150//How long it stays open

	var/hashatch = 0//If 1, this door has hatches, and certain small creatures can move through them without opening the door
	var/hatchstate = 0//0: closed, 1: open
	var/hatch_open_sound = 'sound/machines/hatch_open.ogg'
	var/hatch_close_sound = 'sound/machines/hatch_close.ogg'

	// Integer. Used for intercepting clicks on our turf. Set 0 to disable click interception. Passed directly to `/datum/component/turf_hand`.
	var/turf_hand_priority = 3

	// turf animation
	var/atom/movable/overlay/c_animation = null

	atmos_canpass = CANPASS_PROC

	can_astar_pass = CANASTARPASS_ALWAYS_PROC

/**
 * Keeps tile_blockers in sync with locs (every tile bound_x/bound_width make
 * this door visually span, computed by SetBounds()) -- called after every
 * SetBounds() call site (Initialize(), Move(), persistence_reapply_dir_state())
 * and from set_density() so an open door's extra tile(s) stop blocking too.
 *
 * This exists because bound_x/bound_width are NEVER consulted by movement/
 * collision anywhere in this codebase -- /turf/Enter() (turf.dm) only ever
 * scans turf.contents, populated purely by an atom's real .loc, and
 * /atom/movable/Move() (atoms_movable.dm) explicitly documents multitile-
 * aware movement as cut and never reimplemented ("we don't do multitile
 * movement (yet)"). So a width > 1 door's extra tile(s), covered only by the
 * bounding box, were always exactly as passable as open air, regardless of
 * whether bound_x held the right value -- fixing that value (the earlier
 * construction-path and persistence-restore-path fixes) could never have
 * fixed this, since nothing ever reads it for collision purposes.
 *
 * The only working pattern for real multi-tile collision anywhere in this
 * codebase is a genuine second object with its own real .loc per extra tile
 * -- see /obj/effect/piston_blocker (crusher_piston.dm) and
 * /datum/large_structure's per-tile /obj/structure/component (large.dm).
 * This mirrors that same approach, scoped to the base door class so any
 * width > 1 door (both airlock/multi_tile and firedoor/multi_tile, and any
 * future one) gets it automatically -- a no-op loop for every ordinary
 * width = 1 door, since locs - loc is empty for those.
 */
/obj/structure/machinery/door/proc/_sync_tile_blockers()
	if(width <= 1)
		if(length(tile_blockers))
			QDEL_LIST(tile_blockers)
		return
	var/list/wanted = locs - loc
	// Drop blockers no longer on a tile this door actually covers (dir/width
	// changed since they were placed).
	if(length(tile_blockers))
		for(var/obj/effect/door_tile_blocker/existing in tile_blockers)
			if(!(existing.loc in wanted))
				tile_blockers -= existing
				qdel(existing)
			else
				wanted -= existing.loc
	for(var/turf/T in wanted)
		var/obj/effect/door_tile_blocker/blocker = new(T)
		blocker.parent_door = src
		blocker.density = density
		LAZYADD(tile_blockers, blocker)

/obj/structure/machinery/door/set_density(new_value)
	. = ..()
	for(var/obj/effect/door_tile_blocker/blocker in tile_blockers)
		blocker.density = new_value

/obj/effect/door_tile_blocker
	name = ""
	anchored = TRUE
	invisibility = INVISIBILITY_MAXIMUM
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	/// The real door this tile's collision/interaction forwards to.
	var/obj/structure/machinery/door/parent_door

/obj/effect/door_tile_blocker/Destroy()
	parent_door = null
	return ..()

/obj/effect/door_tile_blocker/CollidedWith(atom/bumped_atom)
	. = ..()
	if(parent_door && !QDELETED(parent_door))
		parent_door.CollidedWith(bumped_atom)

/obj/effect/door_tile_blocker/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(parent_door && !QDELETED(parent_door))
		return parent_door.CanPass(mover, target, height, air_group)
	return ..()

/obj/effect/door_tile_blocker/attack_hand(mob/user)
	if(parent_door && !QDELETED(parent_door))
		return parent_door.attack_hand(user)
	return ..()

/obj/effect/door_tile_blocker/attackby(obj/item/I, mob/user, params)
	if(parent_door && !QDELETED(parent_door))
		return parent_door.attackby(I, user, params)
	return ..()

/obj/structure/machinery/door/mouse_drop_receive(atom/dropping, mob/user, params)
	//Adds the component only once. We do it here & not in Initialize() because there are tons of walls & we don't want to add to their init times
	LoadComponent(/datum/component/leanable, dropping)

/obj/structure/machinery/door/attack_generic(mob/user, damage, attack_message, environment_smash, armor_penetration, attack_flags, damage_type)
	if(damage >= 10)
		visible_message(SPAN_DANGER("\The [user] smashes into the [src]!"))
		playsound(src.loc, hitsound, 60, 1)
		add_damage(damage)
	else
		visible_message(SPAN_NOTICE("\The [user] bonks \the [src] harmlessly."))
		playsound(src.loc, hitsound_light, 8, TRUE, extrarange = SHORT_RANGE_SOUND_EXTRARANGE)
	user.do_attack_animation(src)

/obj/structure/machinery/door/Initialize()
	. = ..()
	if(density)
		layer = closed_layer
		explosion_resistance = initial(explosion_resistance)
		update_heat_protection(get_turf(src))
	else
		layer = open_layer
		explosion_resistance = 0

	SetBounds()
	_sync_tile_blockers()
	update_nearby_tiles(need_rebuild=1)
	if(turf_hand_priority)
		AddComponent(/datum/component/turf_hand, turf_hand_priority)

/obj/structure/machinery/door/Move(new_loc, new_dir)
	. = ..()
	SetBounds()
	_sync_tile_blockers()
	update_nearby_tiles()
	update_icon()

// Matches upstream Aurora.3's SetBounds() exactly -- no bound_x/bound_y offset
// at all. This fork had grown a dir-conditional bound_x/bound_y sign flip on
// top of this that doesn't exist upstream and was never correct; a door's
// .loc is always the south/west-most tile of the pair, and the box only ever
// needs to extend toward positive X/Y (east/north) from there.
/obj/structure/machinery/door/proc/SetBounds()
	if(width > 1)
		if(dir in list(EAST, WEST))
			bound_width = width * world.icon_size
			bound_height = world.icon_size
		else
			bound_width = world.icon_size
			bound_height = width * world.icon_size

/// Persistence restores dir by raw assignment, long after Initialize() already
/// ran SetBounds() against the compile-time default dir -- and forceMove()
/// never routes through Move(), which is the only other place bounds are
/// recomputed. For a width > 1 door saved in any other orientation that left
/// bound_x/bound_y pointing at the wrong neighbouring tile, so the tile the
/// sprite covers was as passable as open air. Exactly the bug already fixed on
/// the construction path (see the SetBounds() call and its comment in
/// airlock.dm's Initialize()); this is the restore-path half of it.
/obj/structure/machinery/door/persistence_reapply_dir_state()
	SetBounds()
	_sync_tile_blockers()
	update_nearby_tiles()

/obj/structure/machinery/door/proc/open_hatch(var/atom/mover = null)
	if (!hatchstate)
		hatchstate = 1
		update_icon()
		playsound(src.loc, hatch_open_sound, 40, TRUE, extrarange = SILENCED_SOUND_EXTRARANGE)


	close_hatch_in(29)

	if (istype(mover, /mob/living))
		var/mob/living/S = mover
		S.under_door()


/obj/structure/machinery/door/proc/close_hatch()
	hatchstate = 0//hatch stays open for 3 seconds
	update_icon()
	playsound(src.loc, hatch_close_sound, 30, TRUE, extrarange = SILENCED_SOUND_EXTRARANGE)

/obj/structure/machinery/door/Destroy()
	set_density(FALSE)
	update_nearby_tiles()
	if(length(tile_blockers))
		QDEL_LIST(tile_blockers)

	return ..()

/obj/structure/machinery/door/proc/close_door_in(var/time = 5 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(close)), time, TIMER_UNIQUE | TIMER_OVERRIDE)

/obj/structure/machinery/door/proc/close_hatch_in(var/time = 3 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(close_hatch)), time, TIMER_UNIQUE | TIMER_OVERRIDE)

/obj/structure/machinery/door/proc/can_open()
	if(!density || operating || !ROUND_IS_STARTED)
		return 0
	return 1

/obj/structure/machinery/door/proc/can_close()
	if(density || operating || !ROUND_IS_STARTED)
		return 0
	return 1

/obj/structure/machinery/door/CollidedWith(atom/bumped_atom)
	. = ..()
	if(p_open || operating) return
	if (!bumped_atom.simulated) return
	if(ismob(bumped_atom))
		var/mob/M = bumped_atom
		if(world.time - M.last_bumped <= 10) return	//Can bump-open one airlock per second. This is to prevent shock spam.
		M.last_bumped = world.time
		if(!M.restrained() && (!issmall(M) || ishuman(M) || istype(M, /mob/living/silicon/robot/drone/mining)))
			bumpopen(M)
		return

	if(istype(bumped_atom, /obj/structure/machinery/bot))
		var/obj/structure/machinery/bot/bot = bumped_atom
		if(src.check_access(bot.botcard))
			if(density)
				open()
		return

	if(istype(bumped_atom, /mob/living/bot))
		var/mob/living/bot/bot = bumped_atom
		if(src.check_access(bot.botcard))
			if(density)
				open()
		return

	if(istype(bumped_atom, /mob/living/simple_animal/spiderbot))
		var/mob/living/simple_animal/spiderbot/bot = bumped_atom
		if(src.check_access(bot.internal_id))
			if(density)
				open()
		return

	if(istype(bumped_atom, /obj/structure/bed/stool/chair/office/wheelchair))
		var/obj/structure/bed/stool/chair/office/wheelchair/wheel = bumped_atom
		if(density)
			if(wheel.pulling && (src.allowed(wheel.pulling)))
				open()
			else
				do_animate("deny")
		return
	if(istype(bumped_atom, /obj/structure/cart))
		var/obj/structure/cart/cart = bumped_atom
		if(density)
			if(cart.pulling && (src.allowed(cart.pulling)))
				open()
			else
				do_animate("deny")
		return

	if(istype(bumped_atom, /obj/vehicle))
		var/obj/vehicle/V = bumped_atom
		if(density)
			if(V.buckled && (src.allowed(V.buckled)))
				open()
			else
				do_animate("deny")
		return

	return


/obj/structure/machinery/door/CanPass(atom/movable/mover, turf/target, height=0, air_group=0)
	if(air_group)
		return !block_air_zones
	if (istype(mover))
		if(mover.movement_type & PHASING)
			return TRUE
		if(mover.pass_flags & PASSGLASS)
			return !opacity
		if(density && hashatch && mover.pass_flags & PASSDOORHATCH)
			if (istype(mover, /mob/living/silicon/pai))
				var/mob/living/silicon/pai/P = mover
				if (allowed(P))
					open_hatch(mover)
					return 1
			else
				open_hatch(mover)
				return 1//If this door is closed, but it has hatches, and this creature can go through hatches. Then we let it through without opening
	return !density

/obj/structure/machinery/door/CanAStarPass(to_dir, datum/can_pass_info/pass_info)
	return (check_access_list(pass_info.access) && can_open())


/obj/structure/machinery/door/proc/bumpopen(mob/user as mob)
	if(operating)	return
	if(user.last_airflow > world.time - GLOB.vsc.airflow_delay) //Fakkit
		return
	src.add_fingerprint(user)
	if(density)
		if(allowed(user))	open()
		else				do_animate("deny")
	return

/obj/structure/machinery/door/bullet_act(obj/projectile/hitting_projectile, def_zone, piercing_hit)
	. = ..()
	if(. != BULLET_ACT_HIT)
		return .

	var/damage = hitting_projectile.get_structure_damage()

	// Emitter Blasts - these will eventually completely destroy the door, given enough time.
	if (damage > 90)
		destroy_hits -= (1 * hitting_projectile.anti_materiel_potential)
		if (destroy_hits <= 0)
			visible_message(SPAN_DANGER("\The [src.name] disintegrates!"))
			switch (hitting_projectile.damage_type)
				if(DAMAGE_BRUTE)
					new /obj/item/stack/material/steel(src.loc, 2)
					new /obj/item/stack/rods(src.loc, 3)
				if(DAMAGE_BURN)
					new /obj/effect/decal/cleanable/ash(src.loc) // Turn it to ashes!
			qdel(src)

	if(damage)
		add_damage(damage)

/obj/structure/machinery/door/hitby(atom/movable/hitting_atom, skipcatch, hitpush, blocked, datum/thrownthing/throwingdatum)
	..()
	var/tforce = 0
	if(!throwingdatum)
		return

	if(ismob(hitting_atom))
		tforce = 15 * (throwingdatum.speed/5)
	else if(isobj(hitting_atom))
		var/obj/O = hitting_atom
		tforce = O.throwforce * (throwingdatum.speed/5)

	if (tforce > 0)
		var/volume = 100
		if (tforce < 20)//No more stupidly loud banging sound from throwing a piece of paper at a door
			volume *= (tforce / 20)
		playsound(src.loc, hitsound, volume, TRUE)
		add_damage(tforce)

/obj/structure/machinery/door/attack_ai(mob/user)
	if(!ai_can_interact(user))
		return
	return attack_hand(user)

/obj/structure/machinery/door/attack_hand(mob/user as mob)
	if(src.operating > 0 || isrobot(user))	return //borgs can't attack doors open because it conflicts with their AI-like interaction with them.

	if(src.operating) return

	if(src.allowed(user) && operable())
		if(src.density)
			open()
		else
			close()
		return

	if(src.density)
		do_animate("deny")
		return

/obj/structure/machinery/door/attackby(obj/item/attacking_item, mob/user)
	if(!istype(attacking_item, /obj/item/forensics))
		src.add_fingerprint(user)

	if(attacking_item.tool_behaviour == TOOL_HAMMER && user.a_intent != I_HURT)
		var/obj/item/stack/stack = usr.get_inactive_hand()
		if(istype(stack) && stack.get_material_name() == get_material_name())
			// Gated only once the repair attempt is real (stack in hand) --
			// a broken hammer in hand must not block plain door use.
			if(!attacking_item.tool_use_check(user, 0))
				return TRUE
			if(stat & BROKEN)
				to_chat(user, SPAN_NOTICE("It looks like \the [src] is pretty busted. It's going to need more than just patching up now."))
				return TRUE
			if(health >= maxhealth)
				to_chat(user, SPAN_NOTICE("Nothing to fix!"))
				return TRUE
			if(!density)
				to_chat(user, SPAN_WARNING("\The [src] must be closed before you can repair it."))
				return TRUE

			//figure out how much metal we need
			var/amount_needed = (maxhealth - health) / DOOR_REPAIR_AMOUNT
			amount_needed = (round(amount_needed) == amount_needed)? amount_needed : round(amount_needed) + 1 //Why does BYOND not have a ceiling proc?

			var/transfer
			if (repairing)
				transfer = stack.transfer_to(repairing, amount_needed - repairing.amount)
				if (!transfer)
					to_chat(user, SPAN_WARNING("You must weld or remove \the [repairing] from \the [src] before you can add anything else."))
			else
				repairing = stack.split(amount_needed)
				if (repairing)
					repairing.forceMove(src)
					transfer = repairing.amount

			if (transfer)
				to_chat(user, SPAN_NOTICE("You fit [transfer] [stack.singular_name]\s to damaged and broken parts on \the [src]."))
				attacking_item.degrade_durability(attacking_item.durability_per_use)

			return TRUE

	if(repairing && attacking_item.tool_behaviour == TOOL_WELDER)
		if(!density)
			to_chat(user, SPAN_WARNING("\The [src] must be closed before you can repair it."))
			return TRUE

		var/obj/item/weldingtool/welder = attacking_item
		if(welder.use(0,user))
			to_chat(user, SPAN_NOTICE("You start to fix dents and weld \the [repairing] into place."))
			if(welder.use_tool(src, user, 5 * repairing.amount, volume = 50) && welder && welder.isOn())
				to_chat(user, SPAN_NOTICE("You finish repairing the damage to \the [src]."))
				health = between(health, health + repairing.amount*DOOR_REPAIR_AMOUNT, maxhealth)
				update_icon()
				qdel(repairing)
				repairing = null
		return TRUE

	if(repairing && attacking_item.tool_behaviour == TOOL_CROWBAR)
		if(!attacking_item.tool_use_check(user, 0))
			return TRUE
		to_chat(user, SPAN_NOTICE("You remove \the [repairing]."))
		attacking_item.play_tool_sound(get_turf(src), 50)
		repairing.forceMove(user.loc)
		repairing = null
		attacking_item.degrade_durability(attacking_item.durability_per_use)
		return TRUE

	//psa to whoever coded this, there are plenty of objects that need to call attack() on doors without bludgeoning them.
	if(src.density && istype(attacking_item, /obj/item) && user.a_intent == I_HURT && !istype(attacking_item, /obj/item/card))
		var/obj/item/W = attacking_item
		// This melee path never chains to the gated /atom/movable/attackby --
		// gate and wear it here directly.
		if(W.wear_broken)
			to_chat(user, SPAN_WARNING("\The [W] is broken and can't be used to attack."))
			return TRUE
		user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
		if(W.damtype == DAMAGE_BRUTE || W.damtype == DAMAGE_BURN)
			user.do_attack_animation(src)
			if(W.force < min_force)
				user.visible_message(SPAN_DANGER("\The [user] hits \the [src] with \the [W] with no visible effect."))
			else
				user.visible_message(SPAN_DANGER("\The [user] forcefully strikes \the [src] with \the [W]!"))
				playsound(src.loc, hitsound, W.get_clamped_volume(), TRUE, extrarange = MEDIUM_RANGE_SOUND_EXTRARANGE)
				add_damage(W.force, W.damage_flags(), W.damtype, W.armor_penetration, W)
				SEND_SIGNAL(W, COMSIG_ITEM_MELEE_HIT)
		return TRUE

	if(src.operating > 0 || isrobot(user))
		return TRUE //borgs can't attack doors open because it conflicts with their AI-like interaction with them.

	if(src.allowed(user) && operable())
		if(src.density)
			open()
		else
			close()
		return TRUE

	if(src.density)
		do_animate("deny")

/obj/structure/machinery/door/emag_act(var/remaining_charges)
	if(density && operable())
		do_animate("emag")
		emagged = 1
		sleep(6)
		stat |= BROKEN
		open(1)
		return 1

/obj/structure/machinery/door/add_damage(damage, damage_flags, damage_type, armor_penetration, obj/weapon, message = TRUE)
	var/initialhealth = health
	. = ..()
	if(message)
		if(src.health < src.maxhealth / 4 && initialhealth >= src.maxhealth / 4)
			visible_message(SPAN_WARNING("\The [src] looks like it's about to break!"))
		else if(src.health < src.maxhealth / 2 && initialhealth >= src.maxhealth / 2)
			visible_message(SPAN_WARNING("\The [src] looks seriously damaged!"))
		else if(src.health < src.maxhealth * 3/4 && initialhealth >= src.maxhealth * 3/4)
			visible_message(SPAN_WARNING("\The [src] shows signs of damage!"))
	update_icon()

/obj/structure/machinery/door/on_death(damage, damage_flags, damage_type, armor_penetration, obj/weapon)
	set_broken()

/obj/structure/machinery/door/proc/set_broken()
	stat |= BROKEN
	visible_message(SPAN_WARNING("[src] breaks!"))
	update_icon()

/obj/structure/machinery/door/emp_act(severity)
	. = ..()

	if(prob(20/severity) && (istype(src,/obj/structure/machinery/door/airlock) || istype(src,/obj/structure/machinery/door/window)) )
		open()

/obj/structure/machinery/door/ex_act(severity)
	var/bolted = 0
	if (istype(src, /obj/structure/machinery/door/airlock))
		var/obj/structure/machinery/door/airlock/A = src
		bolted = A.locked
	switch(severity)
		if(1.0)
			if((!bolted) || prob(80))
				qdel(src)
			else
				var/damage = rand(300,600)
				if (bolted)
					damage *= 0.8 //Bolted doors are a bit tougher
				add_damage(damage, message = FALSE)
		if(2.0)
			if((!bolted && prob(25)) || prob(20))
				qdel(src)
			else
				var/damage = rand(150,300)
				if (bolted)
					damage *= 0.8 //Bolted doors are a bit tougher
				add_damage(damage, message = FALSE)
		if(3.0)
			if(prob(80))
				spark(src, 2, GLOB.alldirs)
			var/damage = rand(100,150)
			if (bolted)
				damage *= 0.8
			add_damage(damage, message = FALSE)

	if (health <= 0)
		qdel(src)
	return


/obj/structure/machinery/door/update_icon()
	if(density)
		icon_state = "door_closed"
	else
		icon_state = "door_open"
	return


/obj/structure/machinery/door/proc/do_animate(animation)
	switch(animation)
		if("opening")
			if(p_open)
				flick("o_doorc0", src)
			else
				flick("doorc0", src)
		if("closing")
			if(p_open)
				flick("o_doorc1", src)
			else
				flick("doorc1", src)
		if("spark")
			if(density)
				flick("door_spark", src)
		if("deny")
			if(density && !(stat & (NOPOWER|BROKEN)))
				flick("door_deny", src)
				playsound(src.loc, 'sound/machines/buzz-two.ogg', 50, FALSE, extrarange = SILENCED_SOUND_EXTRARANGE)
	return

/obj/structure/machinery/door/proc/open(var/forced = 0)
	set waitfor = FALSE

	if(!can_open(forced))
		return
	operating = TRUE

	intent_message(MACHINE_SOUND)

	do_animate("opening")
	icon_state = "door_open"
	set_opacity(0)
	sleep(3)
	set_density(FALSE)
	update_nearby_tiles()
	sleep(2)
	src.layer = open_layer
	explosion_resistance = 0
	update_icon()
	set_opacity(0)
	operating = FALSE

	if(autoclose && !QDELETED(src))
		close_door_in(next_close_time())

	return 1

/obj/structure/machinery/door/proc/next_close_time()
	return (normalspeed ? open_duration : 5)

/obj/structure/machinery/door/proc/autoclose()
	if (!QDELETED(src) && can_close(FALSE) && autoclose)
		close()

/obj/structure/machinery/door/proc/close(var/forced = 0)
	set waitfor = FALSE

	if(!can_close(forced))
		if (autoclose)
			for (var/atom/movable/M in get_turf(src))
				if (M.density && M != src)
					addtimer(CALLBACK(src, PROC_REF(autoclose)), 60, TIMER_UNIQUE)
					break
	operating = TRUE

	intent_message(MACHINE_SOUND)

	do_animate("closing")
	sleep(3)
	set_density(TRUE)
	explosion_resistance = initial(explosion_resistance)
	src.layer = closed_layer
	update_nearby_tiles()
	sleep(2)
	update_icon()
	if(visible && !glass)
		set_opacity(1)	//caaaaarn!
	operating = FALSE

	//I shall not add a check every x ticks if a door has closed over some fire.
	var/obj/hotspot/fire = locate() in loc
	if(fire)
		qdel(fire)
	return

/obj/structure/machinery/door/proc/requiresID()
	return 1

/obj/structure/machinery/door/allowed(mob/M)
	if(!requiresID())
		return TRUE // Door doesn't require an ID. So obviously they're allowed.
	if(unrestricted_side(M))
		return TRUE
	return ..(M)

/obj/structure/machinery/door/proc/unrestricted_side(mob/M) //Allows for specific side of airlocks to be unrestrected (IE, can exit maint freely, but need access to enter)
	if(!unres_dir)
		return FALSE
	return get_dir(src, M) & unres_dir

/obj/structure/machinery/door/update_nearby_tiles(need_rebuild)
	for(var/turf/T in locs)
		if (istype(T, /turf/simulated))
			var/turf/simulated/turf = T
			update_heat_protection(turf)
			SSair.mark_for_update(turf)

	return 1

/obj/structure/machinery/door/proc/update_heat_protection(var/turf/simulated/source)
	if(istype(source))
		if(src.density && (src.opacity || src.heat_proof))
			source.thermal_conductivity = DOOR_HEAT_TRANSFER_COEFFICIENT
		else
			source.thermal_conductivity = initial(source.thermal_conductivity)

/obj/structure/machinery/door/proc/is_open(var/invert=0)
	if(invert)
		return src.density
	return !src.density
