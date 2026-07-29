/*
 * Hostile Humanoid NPC
 * A real /mob/living/carbon/human that fights with real equipment (guns,
 * melee weapons, armor) via a purpose-built AI layer -- no combat AI exists
 * anywhere else in this codebase for human-type mobs (every existing
 * AI-driven "hostile" is a /mob/living/simple_animal/hostile, which has no
 * armor/inventory, just a flat damage number). Configured entirely via
 * admin-defined presets (persistence_hostile_npcs.dm) applied post-spawn --
 * this is a single concrete type, not one subtype per preset.
 *
 * AI scheduling reuses SSmob_ai/SSmob_fast_ai as-is (mob_ai.dm) -- already
 * mob-type-agnostic and already refuses to tick anything with a ckey, so an
 * admin possessing this mob safely halts its AI on the next tick for free.
 * The stance/state-machine shape is ported from
 * /mob/living/simple_animal/hostile (hostile.dm), but the attack leaf calls
 * the SAME item-level procs a player's click would reach (gun.afterattack(),
 * item.resolve_attackby(), UnarmedAttack()) instead of a flat damage roll,
 * so armor/wounds/ammo all apply exactly as they do for a player.
 */
/// How long a soldier will keep chasing a target it can no longer actually
/// see before giving up and returning to IDLE (follow/hold/patrol/individual
/// orders). Without this, a target that breaks LOS behind a wall/window
/// locks the mob out of ALL idle-branch behavior forever, since nothing else
/// ever calls LoseTarget() for a target that's merely out of sight rather
/// than dead/invalid.
#define HOSTILE_NPC_LOS_GIVEUP_TIME (10 SECONDS)

/mob/living/carbon/human/npc/hostile
	/// Persistence faction uid this NPC belongs to -- distinct from the
	/// pre-existing lore mob/var/faction string every mob has. null = no
	/// faction (attacks/is attacked by everyone except its commander, if any).
	var/faction_uid
	/// Which hostile_npc_presets row (if any) configured this instance.
	var/preset_id
	/// Optional admin-authored "pack" tag (hostile_npc_presets' own pack_id)
	/// -- lets multiple DIFFERENT factionless presets be grouped so they
	/// don't attack each other (e.g. several distinct "pirate" variants).
	/// Only consulted when this NPC has no real faction_uid -- see
	/// is_same_hostile_npc_pack().
	var/pack_id
	var/stance = HOSTILE_STANCE_IDLE
	var/atom/last_found_target
	/// world.time this NPC last actually had LOS on last_found_target --
	/// see HOSTILE_NPC_LOS_GIVEUP_TIME in MoveToTarget().
	var/last_target_seen_time = 0
	var/list/targets = list()
	var/aggro_range = 10
	var/ranged_attack_range = 6
	move_speed = 5
	var/is_fast_processing = FALSE
	var/hostile_time_between_attacks = 10
	var/hostile_last_attack = 0
	var/attacked_times = 0
	/// Off by default for humans -- a person smashing tables while pathing
	/// reads oddly compared to a claw-monster doing it. Preset-toggleable.
	var/destroy_surroundings = FALSE
	/// Never targeted by, and never targets, this NPC -- set for commander
	/// item followers (their summoning player), checked ahead of faction.
	var/mob/commander
	/// Toggled from the barracks/commander_beacon TGUI ("Hostile"/"Passive").
	/// When TRUE, this NPC never proactively acquires a target at all (see
	/// get_targets()) -- it still follows/holds/moves-to-order as normal,
	/// it simply never starts a fight. There is no "defend if attacked"
	/// middle ground -- this mob type has no retaliation hooks.
	var/passive_mode = FALSE
	/// Commander-item followers only. When TRUE, idle followers stay put
	/// instead of closing distance to their commander -- toggled from the
	/// commander_beacon's TGUI ("Follow"/"Hold Position" buttons). Does not
	/// affect combat -- a held-position follower still chases and fights
	/// any target it actually finds.
	var/hold_position = FALSE
	/// Commander-item followers only. A one-shot "go stand here" order
	/// (commander_beacon's point-to-move handling) -- takes priority over
	/// follow/hold while idle, cleared automatically once reached (see
	/// move_to_ordered_destination()). Combat targeting still overrides it.
	var/turf/ordered_destination
	/// Barracks soldiers only (set by faction_barracks.dm's spawn_soldier())
	/// -- the fixed point they guard. When idle (and not commander-following
	/// or hold_position), they wander a short distance around this instead
	/// of standing stacked on the barracks forever.
	var/turf/patrol_anchor_turf
	var/patrol_radius = 5
	var/turf/patrol_destination
	var/patrol_wait_until = 0
	/// Guard-beacon soldiers only -- a fixed direction to face while
	/// otherwise idle (not following/patrolling/point-ordered), so they read
	/// as a stationed guard instead of a mob standing still facing whatever
	/// direction combat last left it in. Unused (0) for every other spawner.
	var/guard_facing_dir = 0
	/// Guard-beacon soldiers only -- the exact tile they're posted at. Unlike
	/// patrol_anchor_turf (which wanders nearby), a guard walks straight back
	/// to this specific tile if bumped/pushed/thrown off it. Null for every
	/// other spawner.
	var/turf/guard_post_turf

/mob/living/carbon/human/npc/hostile/Initialize(mapload)
	. = ..()
	// zone_sel is normally only ever built during client HUD setup
	// (_onclick/hud/human.dm) -- attack_hand() reads it UNGUARDED on every
	// unarmed attack (human_attackhand.dm) -- a clientless mob needs its own
	// or its first bare-handed punch hard-errors. Never added to any
	// client's screen list, so nothing ever renders it.
	zone_sel = new /atom/movable/screen/zone_sel(null)
	// Without this, handle_regular_status_updates() (life.dm) treats a
	// permanently keyless body as an SSD'd player and forces it into an
	// unwakeable sleep on its very first Life() tick (disconnect_time never
	// gets set since this mob never logs in/out, so the "disconnected for
	// 5+ minutes" check is always true). Set here, before this mob could
	// possibly receive its first Life() tick.
	deliberately_clientless = TRUE

/mob/living/carbon/human/npc/hostile/Destroy()
	GLOB.move_manager.stop_looping(src)
	unset_last_found_target()
	targets.Cut()
	commander = null
	ordered_destination = null
	patrol_anchor_turf = null
	patrol_destination = null
	return ..()

/// Applies a hostile NPC preset (persistence_hostile_npcs.dm's cached list
/// shape) to this already-spawned mob -- outfit, faction tag/coloring,
/// tuning -- then starts its AI. override_faction_uid (if given) wins over
/// the preset's own stored faction_uid, so the same preset can be reused by
/// different factions' barracks/commander items.
/mob/living/carbon/human/npc/hostile/proc/apply_hostile_preset(list/preset, override_faction_uid = null)
	if(!preset)
		return
	preset_id = preset["id"]
	pack_id = preset["pack_id"]
	if(preset["name"])
		// Overrides Initialize()'s already-run species.get_random_name()
		// roll -- mirrors industrial_xion_remote's exact established
		// pattern for renaming a human post-Initialize() (human_species.dm).
		real_name = preset["name"]
		name = real_name
		if(dna)
			dna.real_name = real_name
		if(mind)
			mind.name = real_name
	if(preset["move_speed"])
		move_speed = preset["move_speed"]
	if(preset["aggro_range"])
		aggro_range = preset["aggro_range"]
	if(preset["ranged_attack_range"])
		ranged_attack_range = preset["ranged_attack_range"]
	if(preset["attack_delay"])
		hostile_time_between_attacks = preset["attack_delay"]
	destroy_surroundings = !!preset["destroy_surroundings"]
	faction_uid = override_faction_uid ? normalize_faction_uid(override_faction_uid) : (preset["faction_uid"] ? normalize_faction_uid(preset["faction_uid"]) : null)

	if(preset["outfit_template_id"])
		var/list/template = get_outfit_template(preset["outfit_template_id"])
		if(template)
			var/obj/outfit/O = build_outfit_instance_from_template(template)
			preEquipOutfit(O)
			equipOutfit(O)
	else if(preset["outfit_path"])
		var/outfit_path = text2path(preset["outfit_path"])
		if(outfit_path)
			preEquipOutfit(outfit_path)
			equipOutfit(outfit_path)
	update_body()
	regenerate_icons()

	// A real player would always grip a two-handed weapon with both hands
	// in combat for the accuracy/recoil/delay bonus -- make sure a freshly
	// equipped NPC does too, rather than fighting gimped forever.
	var/obj/item/gun/held_gun = get_active_hand()
	if(istype(held_gun) && held_gun.is_wieldable && !held_gun.wielded)
		held_gun.toggle_wield(src)

	// Tint the equipped helmet/armor to the faction's color -- the exact
	// same mechanism the faction management program already uses for
	// player-worn faction clothing (persistence_faction_tagger.dm), reused
	// directly rather than reinventing a tint.
	if(faction_uid)
		if(istype(head, /obj/item/clothing))
			var/obj/item/clothing/C = head
			C.faction_tagger_set(faction_uid, null)
		if(istype(wear_suit, /obj/item/clothing))
			var/obj/item/clothing/C = wear_suit
			C.faction_tagger_set(faction_uid, null)

	MOB_START_THINKING(src)

// ============================================================
// AI -- ported shape from hostile.dm, driving real item attacks
// ============================================================

/mob/living/carbon/human/npc/hostile/think()
	. = ..()
	if(stat || !ai_enabled_check())
		return
	if(is_on_medical_table())
		return // being placed on / actively treated by a medical table -- hold still and don't fight resting, let it do its work in its own time
	if(resting)
		resting = FALSE
		update_canmove()
		update_icon()

	switch(stance)
		if(HOSTILE_STANCE_IDLE)
			targets = get_targets(aggro_range)
			FindTarget()
			if(stance == HOSTILE_STANCE_IDLE)
				if(ordered_destination)
					move_to_ordered_destination()
				else if(commander && !hold_position)
					follow_commander()
				else if(patrol_anchor_turf && !hold_position)
					patrol_guard_anchor()
				else if(guard_post_turf)
					hold_guard_post()

		if(HOSTILE_STANCE_ATTACK)
			MoveToTarget()

		if(HOSTILE_STANCE_ATTACKING)
			AttackTarget()
			if(attacked_times >= rand(0, 4))
				targets = get_targets(aggro_range)
				FindTarget()
				attacked_times = 0

/// Placeholder hook kept separate from the stat check so a future
/// admin/preset "AI paused" toggle has a single place to plug into.
/mob/living/carbon/human/npc/hostile/proc/ai_enabled_check()
	return TRUE

/// TRUE while this NPC should hold still and leave `resting` alone because
/// it's sitting on an optable/autodoc's tile -- checked every think() tick so
/// follow/patrol/combat all get skipped rather than dragging the NPC off
/// mid-treatment (the autodoc never buckles its patient, so nothing else
/// would stop movement). Broader than just "actively suppressing": the
/// table's own occupant registration (operating_table.dm's check_occupant())
/// only runs on its OWN process() tick, independent of and much slower than
/// ours -- if this only checked "already registered and suppressing," our
/// own think() would see `resting == TRUE` right after being placed (before
/// the table's next tick notices) and immediately stand the NPC back up,
/// permanently preventing the table from ever registering them at all. Only
/// returns FALSE (stop holding, time to get up and leave) once we're the
/// table's CONFIRMED occupant and its repair cycle has actually ended.
/mob/living/carbon/human/npc/hostile/proc/is_on_medical_table()
	var/turf/T = get_turf(src)
	if(!T)
		return FALSE
	for(var/obj/structure/machinery/optable/O in T)
		var/mob/living/carbon/human/occ = O.occupant?.resolve()
		if(occ && occ != src)
			continue // table's occupant is someone else -- irrelevant to us
		if(occ == src && !O.suppressing)
			return FALSE // confirmed done -- stand up and walk off
		return TRUE // not yet registered (hold so it CAN register), or actively suppressing
	return FALSE

/mob/living/carbon/human/npc/hostile/proc/get_targets(dist = 10)
	if(passive_mode)
		return list()
	return get_hearers_in_LOS(dist, src)

/// Commander-item followers with no attack target close the distance to
/// whoever summoned them instead of standing still -- re-targeted every
/// idle tick since the commander is expected to keep moving.
/// Walks toward a point-issued destination order (commander_beacon.dm's
/// on_owner_point()) -- mirrors follow_commander()'s shape, but targets a
/// static turf instead of a moving mob, and clears itself on arrival
/// instead of stopping-and-resuming (hold_position is already set TRUE
/// by whoever issued the order, so arrival just leaves it holding there).
/mob/living/carbon/human/npc/hostile/proc/move_to_ordered_destination()
	if(!isturf(ordered_destination))
		ordered_destination = null
		GLOB.move_manager.stop_looping(src)
		return
	if(get_dist(src, ordered_destination) <= 0)
		ordered_destination = null
		GLOB.move_manager.stop_looping(src)
		return
	open_path_door_towards(ordered_destination)
	GLOB.move_manager.move_to(src, ordered_destination, 0, move_speed, INFINITY)

/mob/living/carbon/human/npc/hostile/proc/follow_commander()
	if(QDELETED(commander) || !isturf(commander.loc))
		commander = null
		GLOB.move_manager.stop_looping(src)
		return
	if(z != commander.z)
		catch_up_to_commander()
		return
	if(get_dist(src, commander) <= 2 && has_clear_path_to(commander))
		GLOB.move_manager.stop_looping(src)
		return
	open_path_door_towards(commander)
	GLOB.move_manager.move_to(src, commander, 2, move_speed, INFINITY)

/// Followers can't path across z-levels (get_dist()/move_manager are both
/// same-z only) -- if the commander changes z without the follower
/// physically riding along, teleport them to stay together instead of
/// leaving them stranded, with the same arrival VFX used at initial spawn
/// (persistence_hostile_npcs.dm) so it reads as an intentional "beam to
/// commander" effect rather than a silent teleport glitch.
/mob/living/carbon/human/npc/hostile/proc/catch_up_to_commander()
	GLOB.move_manager.stop_looping(src)
	var/turf/destination = get_turf(commander)
	if(!destination)
		return
	var/turf/origin = get_turf(src)
	if(origin)
		new /obj/effect/portal/decorative/fading(origin, null, null, 5 SECONDS, 0)
		spark(origin, 3, GLOB.alldirs)
	forceMove(destination)
	new /obj/effect/portal/decorative/fading(destination, null, null, 5 SECONDS, 0)
	spark(destination, 3, GLOB.alldirs)

/// Proactively opens a closed, unrestricted door directly in the next step
/// toward target -- get_step_to() (used by the move loops themselves, see
/// GLOB.move_manager.move_to()) treats dense obstacles as something to
/// route around rather than deliberately walk into and bump, unlike a
/// player's direct keypress, so a soldier can otherwise stall in front of a
/// door forever rather than ever attempting the same Bump()-triggered
/// bumpopen() a player gets for free. Still respects real access
/// restrictions -- bumpopen()'s own allowed() check denies a soldier with
/// no matching ID exactly as it would a player.
/mob/living/carbon/human/npc/hostile/proc/open_path_door_towards(atom/target)
	var/turf/target_turf = get_turf(target)
	var/turf/my_turf = get_turf(src)
	if(!target_turf || !my_turf || my_turf == target_turf)
		return
	var/turf/next = get_step_to(src, target_turf)
	if(!next)
		// get_step_to() gives up entirely (returns 0) when a dense door is
		// the ONLY route -- it can't tell a closed-but-openable door apart
		// from a solid wall, so it never hands back the door's tile to try.
		// Fall back to a plain directional step, which is exactly where a
		// blocking door is most likely to be.
		next = get_step(my_turf, get_dir(my_turf, target_turf))
	if(!next)
		return
	for(var/obj/structure/machinery/door/D in next)
		if(D.density && !D.operating && D.allowed(src))
			D.open()

/// Barracks soldiers only -- wanders to a random nearby non-dense turf
/// around patrol_anchor_turf, pauses there a while, then picks a new one.
/// Naturally drifts back toward the guarded point over time even after
/// being pulled away by combat, since the next waypoint is always chosen
/// relative to the fixed anchor, not wherever the soldier currently is.
/mob/living/carbon/human/npc/hostile/proc/patrol_guard_anchor()
	if(!patrol_anchor_turf)
		return
	if(patrol_destination)
		if(get_dist(src, patrol_destination) <= 0)
			patrol_destination = null
			patrol_wait_until = world.time + rand(50, 150)
			GLOB.move_manager.stop_looping(src)
			return
		open_path_door_towards(patrol_destination)
		GLOB.move_manager.move_to(src, patrol_destination, 0, move_speed, INFINITY)
		return
	if(world.time < patrol_wait_until)
		return
	var/list/candidates = list()
	for(var/turf/T in orange(patrol_radius, patrol_anchor_turf))
		if(!T.density)
			candidates += T
	if(length(candidates))
		patrol_destination = pick(candidates)

/// Guard-beacon soldiers only -- walks straight back to its assigned post if
/// bumped/pushed/thrown off it (no wandering, unlike patrol_guard_anchor()),
/// and holds guard_facing_dir once actually there.
/mob/living/carbon/human/npc/hostile/proc/hold_guard_post()
	if(get_dist(src, guard_post_turf) > 0)
		open_path_door_towards(guard_post_turf)
		GLOB.move_manager.move_to(src, guard_post_turf, 0, move_speed, INFINITY)
		return
	GLOB.move_manager.stop_looping(src)
	if(guard_facing_dir && dir != guard_facing_dir)
		dir = guard_facing_dir

/// Shared friend-check used both for targeting exclusion (is_valid_target())
/// and for the friendly-fire path scan (is_friendly_fire_blocked()).
/mob/living/carbon/human/npc/hostile/proc/is_friendly(mob/living/L)
	if(L == commander)
		return TRUE
	if(is_same_persistence_faction(L))
		return TRUE
	if(is_same_hostile_npc_pack(L))
		return TRUE
	return FALSE

/mob/living/carbon/human/npc/hostile/proc/is_valid_target(atom/candidate)
	if(!isliving(candidate) || candidate == src)
		return FALSE
	var/mob/living/L = candidate
	if(L.stat == DEAD)
		return FALSE
	if(L.key && !L.client) // logged-out mob, mirrors hostile.dm's FindTarget()
		return FALSE
	if(istype(L, /mob/living/bot)) // cleanbot/medbot/etc -- not real threats
		return FALSE
	if(is_friendly(L))
		return FALSE
	return TRUE

/// Mirrors portable_turret.dm's already-shipped employer_faction/
/// normalize_faction_uid() bridge -- the only place in this codebase that
/// already connects real player-founded factions to AI/machine targeting.
/// Extended to also recognize ANOTHER hostile_npc's own faction_uid var
/// directly (get_living_persistence_faction_uid()) -- NPCs don't carry a
/// faction ID card the way a real player does, so without this, two
/// soldiers spawned by the SAME faction's barracks/beacon would never
/// recognize each other as friendly and would fight on sight.
/mob/living/carbon/human/npc/hostile/proc/is_same_persistence_faction(mob/living/L)
	if(!faction_uid)
		return FALSE
	var/target_uid = get_living_persistence_faction_uid(L)
	return target_uid && target_uid == faction_uid

/// Resolves whatever real persistence faction_uid a living mob "belongs
/// to" -- another hostile_npc's own faction_uid var, or a real player's
/// employer_faction ID card. Returns null for anyone with no real faction at
/// all (a factionless player, or a factionless NPC -- see
/// is_same_hostile_npc_pack() for how those are grouped instead). A global
/// proc (not scoped to hostile_npc) since it doesn't reference src at all --
/// shared with portable_turret.dm's own same-faction exemption check so a
/// same-faction hostile_npc soldier is recognized the same way a real
/// player's ID card already is.
/proc/get_living_persistence_faction_uid(mob/living/L)
	if(istype(L, /mob/living/carbon/human/npc/hostile))
		var/mob/living/carbon/human/npc/hostile/H = L
		return H.faction_uid
	if(!ishuman(L))
		return null
	var/mob/living/carbon/human/H2 = L
	var/obj/item/card/id/ID = H2.GetIdCard()
	return (ID && ID.employer_faction) ? normalize_faction_uid(ID.employer_faction) : null

/// Factionless hostile NPCs (no real persistence faction_uid) still need
/// SOME notion of "friendly" -- otherwise a "pirates" preset with no
/// faction attached would fight itself. Two factionless NPCs are treated
/// as one pack if either: they share an explicit, admin-authored pack_id
/// (lets several DIFFERENT presets -- e.g. "Pirate Grunt"/"Pirate Captain"
/// -- be grouped together on purpose), or, failing that, they were spawned
/// from the exact same preset (the implicit default -- a kill mission
/// spawning several copies of one preset, or a single "Pirate" preset used
/// alone, still won't fight itself even with no pack_id ever set). Either
/// way they still attack players as normal. Only applies when NEITHER side
/// has a real faction -- a real faction_uid always takes priority via
/// is_same_persistence_faction() above.
/mob/living/carbon/human/npc/hostile/proc/is_same_hostile_npc_pack(mob/living/L)
	if(faction_uid)
		return FALSE
	if(!istype(L, /mob/living/carbon/human/npc/hostile))
		return FALSE
	var/mob/living/carbon/human/npc/hostile/H = L
	if(H.faction_uid)
		return FALSE
	if(pack_id && H.pack_id)
		return pack_id == H.pack_id
	return preset_id && H.preset_id == preset_id

/mob/living/carbon/human/npc/hostile/proc/FindTarget()
	var/atom/T = null
	var/target_range = INFINITY
	for(var/atom/A in targets)
		if(!is_valid_target(A))
			continue
		var/range_to_atom = get_dist(src, A)
		if(range_to_atom < target_range)
			T = A
			target_range = range_to_atom

	if(T != last_found_target)
		set_last_found_target(T)
	if(!isnull(T))
		change_stance(HOSTILE_STANCE_ATTACK)
	return T

/mob/living/carbon/human/npc/hostile/proc/set_last_found_target(atom/target)
	if(QDELETED(target))
		return FALSE
	if(target == last_found_target)
		return FALSE
	if(last_found_target)
		unset_last_found_target()
	last_found_target = target
	if(target)
		last_target_seen_time = world.time
		RegisterSignal(target, COMSIG_QDELETING, PROC_REF(on_last_found_target_deleted))
	return TRUE

/mob/living/carbon/human/npc/hostile/proc/unset_last_found_target()
	if(!last_found_target)
		return FALSE
	UnregisterSignal(last_found_target, COMSIG_QDELETING)
	last_found_target = null
	return TRUE

/mob/living/carbon/human/npc/hostile/proc/on_last_found_target_deleted()
	SIGNAL_HANDLER
	last_found_target = null

/mob/living/carbon/human/npc/hostile/proc/LoseTarget()
	change_stance(HOSTILE_STANCE_IDLE)
	unset_last_found_target()
	GLOB.move_manager.stop_looping(src)

/// Also flips the mob's own attack intent -- I_HURT while actively
/// pursuing/fighting a target, back to I_HELP once idle, since UnarmedAttack()/
/// resolve_attackby() resolve as non-harmful interactions under I_HELP.
/// The explicit stop_looping() on the IDLE branch guarantees no stale
/// combat/patrol/follow movement loop survives the transition -- a target
/// found mid-follow/mid-patrol is engaged immediately, not after finishing
/// whatever movement was already in progress.
/mob/living/carbon/human/npc/hostile/proc/change_stance(new_stance)
	if(new_stance == stance)
		return FALSE
	stance = new_stance
	switch(stance)
		if(HOSTILE_STANCE_IDLE)
			MOB_SHIFT_TO_NORMAL_THINKING(src)
			a_intent = I_HELP
			GLOB.move_manager.stop_looping(src)
		else
			MOB_SHIFT_TO_FAST_THINKING(src)
			a_intent = I_HURT
	return TRUE

/// Whatever's in the active hand (falling back to the inactive hand)
/// determines ranged-vs-melee-vs-unarmed dynamically, every tick -- the
/// entire point of building this on a real human with a real outfit rather
/// than a fixed ranged/melee flag.
/mob/living/carbon/human/npc/hostile/proc/get_wielded_weapon()
	var/obj/item/W = get_active_hand()
	if(!istype(W))
		W = get_inactive_hand()
	return istype(W) ? W : null

/// Real line-of-sight check between src and target -- walks getline()'s
/// (__HELPERS/unsorted.dm) proper Bresenham straight line between the two
/// turfs rather than manually stepping via get_step_towards() (which can
/// drift off the true line at non-45/90-degree angles). Acquisition
/// (get_targets()) already filters by LOS, but nothing previously re-checked
/// it once a target was locked in -- a target that ducked behind a
/// wall/corner after acquisition would otherwise keep getting shot at
/// through the obstruction.
/mob/living/carbon/human/npc/hostile/proc/can_see_target(atom/target)
	var/turf/source_turf = get_turf(src)
	var/turf/target_turf = get_turf(target)
	if(!source_turf || !target_turf)
		return FALSE
	for(var/turf/T in getline(source_turf, target_turf))
		if(T == source_turf || T == target_turf)
			continue
		if(IS_OPAQUE_TURF(T))
			return FALSE
	return TRUE

/// TRUE if nothing dense sits between src and target -- used to make sure
/// "close enough, stop following" (follow_commander()) means actually
/// reachable, not just within raw coordinate distance despite a wall or
/// closed door (including a transparent one, which wouldn't trip
/// can_see_target()) sitting directly between them.
/mob/living/carbon/human/npc/hostile/proc/has_clear_path_to(atom/target)
	var/turf/source_turf = get_turf(src)
	var/turf/target_turf = get_turf(target)
	if(!source_turf || !target_turf)
		return FALSE
	for(var/turf/T in getline(source_turf, target_turf))
		if(T == source_turf || T == target_turf)
			continue
		if(T.density)
			return FALSE
		for(var/obj/O in T)
			if(O.density)
				return FALSE
	return TRUE

/// TRUE if a living friendly (commander, same faction, or same pack) is
/// standing on any turf between src (or from, if given) and target -- checked
/// before firing so this NPC doesn't shoot through an ally's back to hit an
/// enemy beyond. turf/from lets find_clear_firing_position() test a
/// candidate position without actually moving there first. Same getline()
/// straight-line walk as can_see_target() -- a teammate standing almost but
/// not exactly on a get_step_towards()-stepped path was otherwise missed.
/mob/living/carbon/human/npc/hostile/proc/is_friendly_fire_blocked(atom/target, turf/from = null)
	var/turf/source_turf = from || get_turf(src)
	var/turf/target_turf = get_turf(target)
	if(!source_turf || !target_turf)
		return FALSE
	for(var/turf/T in getline(source_turf, target_turf))
		if(T == source_turf || T == target_turf)
			continue
		for(var/mob/living/L in T)
			if(L == src || L.stat == DEAD)
				continue
			if(is_friendly(L))
				return TRUE
	return FALSE

/// When fire is blocked by a friendly directly in the way, try each adjacent
/// open tile for a clear line to the target -- a real soldier would sidestep
/// for an open shot rather than just stand there. Returns the first clear
/// candidate turf found, or null if none of the eight neighbors work either.
/mob/living/carbon/human/npc/hostile/proc/find_clear_firing_position(atom/target)
	var/turf/my_turf = get_turf(src)
	if(!my_turf)
		return null
	for(var/turf/candidate in orange(1, my_turf))
		if(candidate.density)
			continue
		if(!is_friendly_fire_blocked(target, candidate))
			return candidate
	return null

/// TRUE if G is a compatible, non-empty magazine for AM's own gun -- mirrors
/// the exact same validation load_ammo() (projectile.dm) itself performs,
/// so a spare found this way is never rejected on actual reload.
/mob/living/carbon/human/npc/hostile/proc/_magazine_fits(obj/item/gun/projectile/G, obj/item/ammo_magazine/AM)
	if(!(G.load_method & AM.mag_type) || G.caliber != AM.caliber)
		return FALSE
	if(G.allowed_magazines && !is_type_in_list(AM, G.allowed_magazines))
		return FALSE
	return AM.stored_ammo.len > 0

/// Searches this NPC's own gear (backpack, belt, pockets, suit storage) for
/// a compatible, loaded spare magazine for G -- either sitting directly in
/// one of those slots, or inside a storage item occupying one of them.
/mob/living/carbon/human/npc/hostile/proc/find_spare_magazine(obj/item/gun/projectile/G)
	for(var/obj/item/holder in list(back, belt, s_store, l_store, r_store))
		if(!holder)
			continue
		if(istype(holder, /obj/item/ammo_magazine) && _magazine_fits(G, holder))
			return holder
		if(istype(holder, /obj/item/storage))
			var/obj/item/storage/S = holder
			for(var/obj/item/ammo_magazine/AM in S.contents)
				if(_magazine_fits(G, AM))
					return AM
	return null

/mob/living/carbon/human/npc/hostile/proc/MoveToTarget()
	if(QDELETED(last_found_target) || !isturf(last_found_target?.loc) && !isturf(last_found_target))
		LoseTarget()
		return
	if(!(last_found_target in targets) && !is_valid_target(last_found_target))
		LoseTarget()
		return

	// A target that's merely out of sight (behind a wall/window) is never
	// caught by the check above -- targets/is_valid_target() don't care
	// about LOS at all, and this branch (HOSTILE_STANCE_ATTACK) is the only
	// place a lost-LOS gun target would otherwise loop forever without ever
	// reaching AttackTarget()'s own LOS check. A melee target flips straight
	// to ATTACKING regardless of LOS/range, but bounces right back here via
	// AttackTarget()'s "dist > 1" branch, so this still catches it within
	// HOSTILE_NPC_LOS_GIVEUP_TIME either way.
	if(can_see_target(last_found_target))
		last_target_seen_time = world.time
	else if(world.time - last_target_seen_time > HOSTILE_NPC_LOS_GIVEUP_TIME)
		LoseTarget()
		return

	var/obj/item/W = get_wielded_weapon()
	if(istype(W, /obj/item/gun))
		if(get_dist(src, last_found_target) <= ranged_attack_range && can_see_target(last_found_target))
			GLOB.move_manager.stop_looping(src)
			change_stance(HOSTILE_STANCE_ATTACKING)
		else
			open_path_door_towards(last_found_target)
			GLOB.move_manager.move_to(src, last_found_target, ranged_attack_range - 1, move_speed, INFINITY)
	else
		change_stance(HOSTILE_STANCE_ATTACKING)
		open_path_door_towards(last_found_target)
		GLOB.move_manager.move_to(src, last_found_target, 1, move_speed, INFINITY)

/mob/living/carbon/human/npc/hostile/proc/AttackTarget()
	if(QDELETED(last_found_target) || !is_valid_target(last_found_target))
		LoseTarget()
		return FALSE

	if(ON_ATTACK_COOLDOWN(src))
		return FALSE

	var/obj/item/W = get_wielded_weapon()
	var/dist = get_dist(src, last_found_target)

	if(istype(W, /obj/item/gun))
		if(dist > ranged_attack_range || !can_see_target(last_found_target))
			change_stance(HOSTILE_STANCE_ATTACK)
			return FALSE
		var/obj/item/gun/G = W
		if(istype(G, /obj/item/gun/projectile) && G.get_ammo() <= 0)
			var/obj/item/gun/projectile/GP = G
			var/obj/item/ammo_magazine/spare = find_spare_magazine(GP)
			if(spare)
				if(GP.ammo_magazine)
					GP.unload_ammo(src, TRUE, TRUE)
				GP.load_ammo(spare, src)
			hostile_last_attack = world.time
			return TRUE
		if(is_friendly_fire_blocked(last_found_target))
			var/turf/better_spot = find_clear_firing_position(last_found_target)
			if(better_spot)
				GLOB.move_manager.move_to(src, better_spot, 0, move_speed)
			return FALSE
		face_atom(last_found_target)
		G.afterattack(last_found_target, src, FALSE, null)
		hostile_last_attack = world.time
		attacked_times++
		return TRUE

	if(dist > 1)
		change_stance(HOSTILE_STANCE_ATTACK)
		return FALSE

	face_atom(last_found_target)
	if(istype(W))
		W.resolve_attackby(last_found_target, src, null)
	else
		UnarmedAttack(last_found_target, TRUE)
	hostile_last_attack = world.time
	attacked_times++
	return TRUE

#ifdef FACTION_AI_CLONE_SOLDIERS
/// Faction-owned soldiers are lore-flavored as cloned combat drones --
/// factionless hostile_npc spawns (pirates/away-site presets) never get a
/// faction_uid at all, so this naturally excludes them without needing a
/// separate check.
/mob/living/carbon/human/npc/hostile/assemble_height_string(mob/examiner)
	. = ..()
	if(!faction_uid)
		return .
	. += "\n<b>They have a neurogenic suppressant device blinking on their head, indicating them as a cloned combat drone.</b>"
#endif //FACTION_AI_CLONE_SOLDIERS
