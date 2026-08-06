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

/// Minimum `force` a stowed item needs before a disarmed soldier will bother
/// drawing it (draw_stowed_weapon()). Filters out pens/paperwork/spare mags
/// while still catching anything that genuinely beats a bare fist.
#define HOSTILE_NPC_MIN_DRAWN_WEAPON_FORCE 5

/// How long a temporarily-provoked NPC keeps fighting back before standing
/// down on its own -- "cut that out or I'll do some damage," not a
/// permanent hostility switch.
#define HOSTILE_NPC_PROVOKED_DURATION (6 SECONDS)

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
	/// Position/time MoveToTarget() last confirmed real progress towards
	/// last_found_target. A target visible through a window is never caught
	/// by last_target_seen_time alone (windows block movement but not
	/// sight), so this catches "physically can't get any closer" independent
	/// of whether the target is still visible.
	var/turf/last_progress_turf
	var/last_progress_time = 0
	/// world.time this soldier's shot was first continuously blocked by a
	/// friendly with no clear reposition tile available (AttackTarget()'s gun
	/// branch) -- 0 whenever not currently blocked. Blocked longer than
	/// HOSTILE_NPC_LOS_GIVEUP_TIME with no relief gives up on the current
	/// target entirely (LoseTarget()) rather than sitting stuck in
	/// HOSTILE_STANCE_ATTACKING forever, deaf to every idle-branch order
	/// (Follow/Hold/individual clicks) -- mirrors MoveToTarget()'s own
	/// LOS/unreachable-target giveup timer, which this scenario had no
	/// equivalent of (two soldiers following the same commander down a
	/// narrow corridor can permanently block each other's line of fire).
	var/friendly_fire_blocked_since = 0
	/// TRUE while last_found_target was assigned via an explicit
	/// commander_beacon.dm click-to-attack order rather than organic
	/// FindTarget() acquisition -- lets MoveToTarget()/AttackTarget() keep
	/// engaging even though is_friendly() would normally call it off, since
	/// overriding that is the whole point of the order. Reset automatically
	/// whenever the target changes (set_last_found_target()/
	/// unset_last_found_target()).
	var/target_is_ordered = FALSE
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
	/// TRUE while passive_mode was broken by _react_to_hostile_attack() (a
	/// temporary reaction), as opposed to a deliberate commander/beacon/
	/// barracks Hostile order -- only the former auto-reverts, see
	/// _calm_down_from_provocation().
	var/provoked_temporarily = FALSE
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
	/// Stuck detection for an outstanding ordered_destination -- the turf/time
	/// this soldier last actually CHANGED position while carrying out the
	/// order, plus whether the direct-step unstick has already been tried.
	/// See move_to_ordered_destination(); without these a soldier that can't
	/// path (blocked chokepoint, locked door, pathfinder range limit) holds a
	/// valid order it can never execute, silently, forever.
	var/turf/order_progress_turf
	var/order_progress_time = 0
	var/order_unstick_attempted = FALSE
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
	/// The weapon this soldier was equipped with at spawn. Tracked so a
	/// disarmed soldier recovers ITS OWN weapon (try_recover_weapon()) rather
	/// than hoovering up whatever happens to be lying nearby, which would be
	/// trivially baitable by dropping junk in front of it.
	var/obj/item/primary_weapon

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

/// Fellow soldiers (and this soldier's own commander) are not obstacles.
///
/// THE fix for "one of my two soldiers is permanently unresponsive to orders."
/// Every order path here -- follow_commander(), move_to_ordered_destination(),
/// patrol_guard_anchor(), hold_guard_post(), MoveToTarget() -- ultimately runs
/// through /datum/move_loop/has_target/dist_bound/move_to/move()
/// (movement_types.dm), which steps via BYOND's built-in get_step_to(). That
/// pathfinder routes around DENSE atoms, and /mob/living is dense -- so two
/// soldiers travelling together (a corridor, a doorway, both converging on the
/// same commander, or both freshly spawned on the beacon's single tile) are
/// solid walls to each other. The trailing one gets no legal step, Move(null)
/// does nothing, and it silently executes NOTHING while still holding a
/// perfectly valid order -- indistinguishable, from the player's side, from
/// ignoring orders entirely. It only ever "recovered" once the blocker
/// happened to wander off, which is why it looked random and self-healing.
/mob/living/carbon/human/npc/hostile/CanPass(atom/movable/mover, turf/target, height = 1.5, air_group = 0)
	if(mover && mover == commander)
		return TRUE
	if(istype(mover, /mob/living/carbon/human/npc/hostile))
		var/mob/living/carbon/human/npc/hostile/other = mover
		if(commander && other.commander == commander)
			return TRUE
		if(is_friendly(other))
			return TRUE
	return ..()

/mob/living/carbon/human/npc/hostile/Destroy()
	GLOB.move_manager.stop_looping(src)
	unset_last_found_target()
	targets.Cut()
	commander = null
	ordered_destination = null
	patrol_anchor_turf = null
	patrol_destination = null
	primary_weapon = null
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

	// Remember what they were issued so try_recover_weapon() can go pick up
	// THIS weapon specifically after a disarm.
	var/obj/item/issued_weapon = get_active_hand()
	if(istype(issued_weapon))
		primary_weapon = issued_weapon

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

	// A disarmed soldier retrieves its weapon rather than spending the rest of
	// the round throwing punches next to its own rifle. Only consumes the tick
	// while actively fetching -- an armed soldier falls straight through.
	if(try_recover_weapon())
		return

	// An explicit player order outranks the AI's own target pick, and must be
	// handled ABOVE the stance switch. Inside it, ordered_destination is only
	// ever read in the IDLE branch -- and FindTarget() runs first there and
	// kicks this mob straight out of that branch whenever any enemy is within
	// aggro_range -- so in any contested area a move order was silently
	// deferred until combat happened to end on its own, then executed late
	// (which read as "attacking also queued a move"). Normal combat
	// re-acquisition resumes by itself the tick after
	// move_to_ordered_destination() reaches the destination and clears it.
	if(ordered_destination)
		if(stance != HOSTILE_STANCE_IDLE)
			LoseTarget()
		move_to_ordered_destination()
		return

	switch(stance)
		if(HOSTILE_STANCE_IDLE)
			targets = get_targets(aggro_range)
			FindTarget()
			if(stance == HOSTILE_STANCE_IDLE)
				// Self-heals a dead/gone commander regardless of hold_position
				// -- follow_commander() below already does this same check,
				// but only ever runs when hold_position is FALSE, so a
				// soldier left on hold when its commander died/vanished
				// (release_followers() not reached, or reached but this
				// wasn't cleared) would otherwise never detect it and stay
				// stuck waiting for a "Follow" order that may never come.
				if(commander && (QDELETED(commander) || !isturf(commander.loc)))
					commander = null
					hold_position = FALSE
					GLOB.move_manager.stop_looping(src)
				// No ordered_destination check here -- it's handled above the
				// stance switch now, so reaching this point already means
				// there isn't one outstanding.
				if(commander && !hold_position)
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

		else
			// Any stance outside the three above (e.g. HOSTILE_STANCE_ALERT/
			// TIRED -- defined in the shared mob defines but never set by
			// this file) would otherwise match nothing and silently freeze
			// here forever, every tick, with no error logged.
			LOG_DEBUG("hostile_npc: [src] had unrecognized stance [stance], resetting to idle.")
			change_stance(HOSTILE_STANCE_IDLE)

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
			continue // someone else's patient -- irrelevant to us
		if(occ == src)
			return O.suppressing // ours: hold only while a cycle is running
		// Nobody registered on this table yet. Only hold if we were actually
		// PLACED here -- move_patient_to_table() sets resting TRUE, and the
		// table's own (much slower) process() tick needs us still lying when
		// it next runs or it can never claim us.
		//
		// A soldier merely STANDING on an empty table tile is not a patient.
		// This used to fall through to a bare "return TRUE" for any null
		// occupant, which froze think() before the stance switch on every
		// tick -- so walking onto an unoccupied operating table permanently
		// stopped a soldier following, fighting, and taking orders, while its
		// stance/commander/move loop all still looked perfectly healthy.
		if(resting || lying)
			return TRUE
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
/// Issues an explicit "go stand here" order (commander_beacon.dm's
/// "Command Soldier" click). Drops whatever this soldier was fighting --
/// an explicit player order outranks the AI's own target pick -- and
/// promotes it to fast thinking so the move visibly STARTS right away: an
/// idle soldier otherwise lives on SSmob_ai, which declares no wait (2s
/// default) and is SS_BACKGROUND, so it only runs on leftover tick time and
/// is deferred further under load. That delay is what made ordered soldiers
/// feel unresponsive even once the order itself landed correctly.
/mob/living/carbon/human/npc/hostile/proc/order_move_to(turf/T)
	ordered_destination = T
	hold_position = TRUE
	if(stance != HOSTILE_STANCE_IDLE)
		LoseTarget()
	// Fresh order -- restart the stuck detector (see
	// move_to_ordered_destination()) so a previous order's stall history
	// can't immediately abort this one.
	order_progress_turf = get_turf(src)
	order_progress_time = world.time
	order_unstick_attempted = FALSE
	// Force a genuinely new move loop rather than trusting the existing one:
	// add_loop() (move_manager.dm) silently refuses to replace a loop whose
	// args compare equal, so re-issuing an order to the same destination
	// would otherwise be a no-op against a loop that may already be stalled.
	GLOB.move_manager.stop_looping(src)
	MOB_SHIFT_TO_FAST_THINKING(src)

/mob/living/carbon/human/npc/hostile/proc/move_to_ordered_destination()
	if(!isturf(ordered_destination))
		_clear_ordered_destination()
		return
	if(get_dist(src, ordered_destination) <= 0)
		_clear_ordered_destination()
		return

	// Stuck detection. get_step_to() (the move loop's own stepper) routes
	// AROUND dense atoms, so any obstacle it can't path past -- a player in a
	// chokepoint, a locked door, a pathfinder range limit -- leaves this mob
	// holding a valid order it can never physically execute, silently, forever.
	// The CanPass() override above removes the common case (fellow soldiers),
	// but this guarantees "accepted the order, then never moved again" can
	// never be a permanent state whatever the obstacle turns out to be.
	if(get_turf(src) != order_progress_turf)
		order_progress_turf = get_turf(src)
		order_progress_time = world.time
		order_unstick_attempted = FALSE
	else if(world.time - order_progress_time > HOSTILE_NPC_LOS_GIVEUP_TIME)
		if(!order_unstick_attempted)
			// One direct step, bypassing get_step_to() entirely -- this Bumps
			// whatever is in the way (which is how mobs shove/swap past each
			// other) instead of politely trying to path around it.
			order_unstick_attempted = TRUE
			order_progress_time = world.time
			GLOB.move_manager.stop_looping(src)
			step_towards(src, ordered_destination)
			return
		// Still nothing after a second interval -- genuinely unreachable.
		// Give the order up and SAY so, rather than standing there mute.
		if(commander)
			to_chat(commander, SPAN_WARNING("[src] can't reach the marked position and has abandoned the order."))
		_clear_ordered_destination()
		return

	open_path_door_towards(ordered_destination)
	GLOB.move_manager.move_to(src, ordered_destination, 0, move_speed, INFINITY)

/// Shared teardown for a finished/abandoned move order -- also drops this mob
/// back off the fast subsystem it was promoted onto by order_move_to().
/mob/living/carbon/human/npc/hostile/proc/_clear_ordered_destination()
	ordered_destination = null
	order_progress_turf = null
	order_progress_time = 0
	order_unstick_attempted = FALSE
	GLOB.move_manager.stop_looping(src)
	MOB_SHIFT_TO_NORMAL_THINKING(src)

/mob/living/carbon/human/npc/hostile/proc/follow_commander()
	if(QDELETED(commander) || !isturf(commander.loc))
		commander = null
		GLOB.move_manager.stop_looping(src)
		return
	if(z != commander.z)
		catch_up_to_commander()
		return
	var/clear_path = has_clear_path_to(commander)
	if(get_dist(src, commander) <= 2 && clear_path)
		GLOB.move_manager.stop_looping(src)
		return
	open_path_door_towards(commander)
	// The move loop's own "close enough, stop" check (dist_bound/check_dist(),
	// movement_types.dm) only ever looks at raw tile distance -- it has no
	// concept of a window/wall sitting in between. Once raw distance is
	// already <=2, re-asking for that same min-distance-2 loop is a silent
	// no-op (compare_loops(), move_manager.dm, sees identical args and
	// leaves the existing, already-"arrived" loop untouched) -- which is
	// exactly how a soldier ends up frozen at a window forever: it's within
	// 2 tiles by the numbers, so the loop considers itself done, even though
	// there's no way through. Asking for distance 0 instead is a genuinely
	// different request, forcing get_step_to() to keep pathing all the way
	// around to an actual door rather than latching the moment raw distance
	// first happened to look close enough.
	var/requested_distance = (get_dist(src, commander) <= 2 && !clear_path) ? 0 : 2
	GLOB.move_manager.move_to(src, commander, requested_distance, move_speed, INFINITY)

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

/// Any forced relocation (a swap with another soldier mid-bump, an admin
/// teleport, whatever) moves this mob out-of-band from whatever
/// GLOB.move_manager's loop currently expects -- without an explicit reset,
/// the loop can keep computing from stale assumptions about where it
/// "should" be. Rather than chasing down the exact internal reason that
/// desyncs order-following after something like a swap, just force a clean
/// restart: the very next think() tick (moments away regardless)
/// recomputes everything fresh from wherever this mob actually now is.
/// catch_up_to_commander() already calls stop_looping() itself right before
/// its own forceMove(), so this is a harmless no-op there -- it only
/// actually matters for relocations nothing already anticipated.
/mob/living/carbon/human/npc/hostile/forceMove(atom/newloc)
	. = ..()
	if(.)
		GLOB.move_manager.stop_looping(src)

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
	if(is_same_hostile_npc_pack(L))
		return TRUE
	if(is_same_persistence_faction(L))
		// Same-faction (or allied-faction) hostile_npc soldiers stay
		// unconditionally friendly to each other -- they have no job/rank
		// concept, and this is what stops the faction's own troops from
		// fighting one another. Only a real player's job matters below:
		// Civilian (no job at all) isn't shielded from retaliation for
		// disarming/grabbing/attacking/stripping a same-faction NPC; holding
		// any actual job (including a custom faction-made one) still is.
		if(istype(L, /mob/living/carbon/human/npc/hostile))
			return TRUE
		return ishuman(L) && human_holds_any_job(L)
	return FALSE

/// ignore_friendliness lets an explicit click-to-attack order
/// (order_attack_target()/target_is_ordered) keep reusing this same
/// liveness/logged-out/bot gate without re-applying is_friendly()'s
/// exclusion -- overriding that exclusion is the whole point of an order.
/mob/living/carbon/human/npc/hostile/proc/is_valid_target(atom/candidate, ignore_friendliness = FALSE)
	if(!isliving(candidate) || candidate == src)
		return FALSE
	var/mob/living/L = candidate
	if(L.stat == DEAD)
		return FALSE
	if(L.key && !L.client) // logged-out mob, mirrors hostile.dm's FindTarget()
		return FALSE
	if(istype(L, /mob/living/bot)) // medbot/cleanbot/farmbot/etc -- not real threats (farmbot included -- it's a /mob/living/bot subtype like the rest, already covered by this one type check)
		return FALSE
	if(!ignore_friendliness && is_friendly(L))
		return FALSE
	return TRUE

/// TRUE if `candidate` is a legal target for an explicit click-to-attack
/// order (commander_beacon.dm's "Command Soldier" click) -- reuses
/// is_valid_target()'s baseline liveness checks (ignoring friendliness,
/// since overriding the AI's own pick is the whole point of an explicit
/// order) then layers on guards an order still has to respect: never your
/// own commander, never another of your own faction's/pack's hostile_npc
/// soldiers (no forced fratricide), and never a real (player) member of
/// your own or an allied faction who holds any actual job
/// (human_holds_any_job() -- a real station job or a custom
/// faction-assigned one, read off their ID card).
/mob/living/carbon/human/npc/hostile/proc/is_valid_ordered_attack_target(atom/candidate)
	if(!is_valid_target(candidate, TRUE))
		return FALSE
	var/mob/living/L = candidate
	if(L == commander)
		return FALSE
	if(is_same_hostile_npc_pack(L))
		return FALSE
	if(istype(L, /mob/living/carbon/human/npc/hostile) && is_same_persistence_faction(L))
		return FALSE
	if(is_same_persistence_faction(L))
		if(ishuman(L) && human_holds_any_job(L))
			return FALSE
	return TRUE

/// TRUE if this human actually holds a job -- a real station job or a
/// custom faction-assigned one, read straight off their ID card. Civilian
/// (no job at all) is the only thing this excludes. Deliberately NOT based
/// on DB faction-membership rank (get_effective_faction_rank()) -- that
/// requires a ss13_faction_members row a newly-assigned member may not have
/// yet, which was causing brand new faction members to read as unshielded
/// and get attacked by their own faction's hostile NPCs despite a
/// completely valid, correctly-stamped ID.
/proc/human_holds_any_job(mob/living/carbon/human/H)
	var/obj/item/card/id/ID = H.GetIdCard()
	return ID && ID.assignment && ID.assignment != "Civilian"

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
	if(!target_uid)
		return FALSE
#ifdef FACTION_ALLIANCES
	return target_uid == faction_uid || factions_are_allied(target_uid, faction_uid)
#else
	return target_uid == faction_uid
#endif //FACTION_ALLIANCES

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

/// Attacked while passive_mode is on by someone who isn't faction-friendly
/// -- passive mode means "hold fire", not "stand there and take it forever".
/// Breaks passive_mode TEMPORARILY (see _calm_down_from_provocation()) and
/// locks onto the attacker immediately instead of waiting for the next idle
/// target scan (which would otherwise never happen at all -- get_targets()
/// returns nothing while passive_mode is on). No-ops entirely once already
/// non-passive -- normal target scanning already handles that case.
/mob/living/carbon/human/npc/hostile/proc/_react_to_hostile_attack(mob/attacker)
	if(!passive_mode)
		return
	if(!isliving(attacker) || is_friendly(attacker))
		return
	passive_mode = FALSE
	provoked_temporarily = TRUE
	set_last_found_target(attacker)
	change_stance(HOSTILE_STANCE_ATTACK)
	addtimer(CALLBACK(src, PROC_REF(_calm_down_from_provocation)), HOSTILE_NPC_PROVOKED_DURATION)

/// Reverts a temporary provoked-retaliation back to passive -- "cut that out
/// or I'll do some damage," not a permanent hostility switch. No-ops if a
/// real commander/beacon/barracks order has since taken over
/// (provoked_temporarily already cleared), or the mob is gone.
/mob/living/carbon/human/npc/hostile/proc/_calm_down_from_provocation()
	if(QDELETED(src) || !provoked_temporarily)
		return
	provoked_temporarily = FALSE
	passive_mode = TRUE
	LoseTarget()
	visible_message(SPAN_NOTICE("[src] stands down."))

/// Melee weapon hit -- no reliable hit/miss signal on the human chain's
/// attackby() (its return only means "handled, skip afterattack"), so react
/// unconditionally after ..(), same as every other vector below.
/mob/living/carbon/human/npc/hostile/attackby(obj/item/attacking_item, mob/user, params)
	. = ..()
	_react_to_hostile_attack(user)

/// Ranged hit -- bullet_act has a real hit/miss convention (BULLET_ACT_HIT
/// vs BLOCK/FORCE_PIERCE/etc), unlike the other vectors, so only react on an
/// actual confirmed hit.
/mob/living/carbon/human/npc/hostile/bullet_act(obj/projectile/hitting_projectile, def_zone, piercing_hit)
	. = ..()
	if(. != BULLET_ACT_HIT)
		return .
	if(ismob(hitting_projectile.firer))
		_react_to_hostile_attack(hitting_projectile.firer)

/// Non-item/non-fist melee hits (simple_animal bites, cyborg claws, mecha
/// punches, etc). Human's attack_generic() returns the hit organ object (or
/// null on a miss/blocked hit) instead of a status code -- gate on that.
/mob/living/carbon/human/npc/hostile/attack_generic(mob/user, damage, attack_message, environment_smash, armor_penetration, attack_flags, damage_type)
	. = ..()
	if(!.)
		return
	_react_to_hostile_attack(user)

/// Unarmed punch -- no reliable hit/miss return on the human chain, react
/// unconditionally after ..() for anything other than helpful intent
/// (poking/helping a passive NPC shouldn't provoke it), mirroring
/// simple_animal/hostile's own attack_hand() override.
/mob/living/carbon/human/npc/hostile/attack_hand(mob/living/carbon/M as mob)
	. = ..()
	if(M.a_intent != I_HELP)
		_react_to_hostile_attack(M)

/// Trying to strip a passive faction NPC's equipment via the strip/equipment
/// menu is exactly as provoking as disarming/grabbing/hitting them.
/mob/living/carbon/human/npc/hostile/handle_strip(slot_to_strip, mob/living/user)
	_react_to_hostile_attack(user)
	return ..()

/// Thrown item hit -- mirrors simple_animal/hostile's own hitby() override
/// exactly: resolve the original thrower through the throwingdatum, not the
/// thrown object itself.
/mob/living/carbon/human/npc/hostile/hitby(atom/movable/hitting_atom, skipcatch, hitpush, blocked, datum/thrownthing/throwingdatum)
	. = ..()
	if(isobj(hitting_atom))
		var/atom/thrower = throwingdatum?.thrower?.resolve()
		if(!QDELETED(thrower))
			_react_to_hostile_attack(thrower)

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
	target_is_ordered = FALSE
	friendly_fire_blocked_since = 0
	if(target)
		last_target_seen_time = world.time
		last_progress_turf = get_turf(src)
		last_progress_time = world.time
		RegisterSignal(target, COMSIG_QDELETING, PROC_REF(on_last_found_target_deleted))
	return TRUE

/// Forces this soldier to immediately engage `target`, bypassing the usual
/// aggro_range/hearing scan and (via target_is_ordered) the is_friendly()
/// exclusion is_valid_target() would otherwise apply -- called only after
/// commander_beacon.dm's is_valid_ordered_attack_target() has already
/// confirmed target isn't protected. Overrides passive_mode too, same as
/// any other already-in-progress engagement -- passive_mode only ever
/// blocks get_targets() from proactively finding a NEW target on its own,
/// it was never a "refuse to fight" flag.
/mob/living/carbon/human/npc/hostile/proc/order_attack_target(atom/target)
	// Without this, a soldier previously point-ordered to a location (which
	// sets ordered_destination + hold_position TRUE, commander_beacon.dm's
	// _on_destination_click()) that's LATER ordered to attack keeps that
	// stale destination the whole fight -- once the target dies/is lost and
	// this soldier reverts to HOSTILE_STANCE_IDLE, think()'s IDLE branch
	// checks ordered_destination first and immediately, automatically walks
	// there with zero further player input, which reads exactly like
	// "engaging the target also queued a move order." hold_position itself
	// is deliberately left untouched -- it's sticky by design (see
	// move_to_ordered_destination()'s own doc comment) until Follow/Hold is
	// pressed again.
	ordered_destination = null
	set_last_found_target(target)
	target_is_ordered = TRUE
	change_stance(HOSTILE_STANCE_ATTACK)

/mob/living/carbon/human/npc/hostile/proc/unset_last_found_target()
	if(!last_found_target)
		return FALSE
	UnregisterSignal(last_found_target, COMSIG_QDELETING)
	last_found_target = null
	target_is_ordered = FALSE
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

/// Re-grips a two-handed gun already in the active hand. toggle_wield()
/// (gun.dm) hard-requires the gun be in the ACTIVE hand with the inactive
/// hand EMPTY, so both are checked here rather than assumed.
/mob/living/carbon/human/npc/hostile/proc/_rewield_active_gun()
	var/obj/item/gun/G = get_active_hand()
	if(!istype(G) || !G.is_wieldable || G.wielded)
		return
	if(get_inactive_hand())
		return
	G.toggle_wield(src)

/// Recovers a dropped weapon after a disarm, and restores a two-handed grip.
///
/// Returns TRUE only when this tick was SPENT recovering (walking to the
/// weapon, or picking it up), so think() can hand the tick over. Returns
/// FALSE when already properly armed, or when there's nothing to recover --
/// an intentionally unarmed soldier still fights with fists exactly as before.
///
/// Without this a disarmed soldier degraded permanently to unarmed melee and
/// would keep closing to punching range while its own rifle lay on the floor
/// beside it -- toggle_wield() was only ever called once, at spawn, and
/// nothing anywhere picked a weapon back up.
/mob/living/carbon/human/npc/hostile/proc/try_recover_weapon()
	// Already holding something in the active hand -- just make sure a
	// two-hander is actually gripped with both hands. Also covers a grip lost
	// to anything else (e.g. a reload that shuffles hands).
	if(get_active_hand())
		_rewield_active_gun()
		return FALSE

	// Weapon ended up in the offhand -- swap it across, since toggle_wield()
	// refuses to work on anything but the active hand.
	if(get_inactive_hand())
		swap_hand()
		_rewield_active_gun()
		return FALSE

	// Both hands empty. Prefer the weapon this soldier was actually issued,
	// and only if it's genuinely lying loose -- isturf() rules out one that's
	// been picked up by someone else or stuffed in a bag.
	//
	// A gun that can't fire and can't be reloaded is skipped in both passes
	// below -- that's what stops a soldier from instantly retrieving the dry
	// weapon it just deliberately discarded (AttackTarget()) and looping on
	// it forever. It's a live check rather than a remembered blacklist, so it
	// needs no cleanup and self-corrects: if that gun is reloaded and dropped
	// again, it becomes worth picking up again.
	var/obj/item/recover_target
	if(primary_weapon && !QDELETED(primary_weapon) && isturf(primary_weapon.loc) \
		&& primary_weapon.z == z && get_dist(src, primary_weapon) <= 3 \
		&& (!istype(primary_weapon, /obj/item/gun) || _gun_has_shots(primary_weapon)))
		recover_target = primary_weapon
	else
		// Fallback for a disarm that flung the gun clear, or an issued weapon
		// that's been destroyed -- anything immediately underfoot/adjacent.
		for(var/obj/item/gun/G in range(1, src))
			if(!isturf(G.loc))
				continue
			if(!_gun_has_shots(G))
				continue
			recover_target = G
			break

	// Nothing of ours on the floor to go and get -- last resort, draw whatever
	// we're still carrying rather than fighting with fists.
	if(!recover_target)
		return draw_stowed_weapon()

	if(!Adjacent(recover_target))
		GLOB.move_manager.move_to(src, recover_target, 0, move_speed, INFINITY)
		return TRUE

	GLOB.move_manager.stop_looping(src)
	put_in_active_hand(recover_target)
	_rewield_active_gun()
	return TRUE

/// TRUE if I is worth drawing as a stopgap weapon. The offhand placeholder is
/// bookkeeping, not gear (see gun.dm's toggle_wield()), so it's excluded.
/mob/living/carbon/human/npc/hostile/proc/_is_drawable_weapon(obj/item/I)
	if(!istype(I) || istype(I, /obj/item/offhand))
		return FALSE
	return I.force >= HOSTILE_NPC_MIN_DRAWN_WEAPON_FORCE

/// TRUE if G can actually put rounds downrange -- either it's loaded right
/// now, or it can genuinely be brought back by this soldier on its own.
///
/// "Dry" doesn't mean the same thing for every weapon, so each type is asked
/// its own question:
///
///  - Projectile: is there a compatible loaded magazine anywhere in its gear?
///    Uses find_spare_magazine(), the same lookup the reload path itself
///    uses, so "can't shoot" here means exactly "can't reload" there.
///  - Energy: can it actually recharge WHERE IT IS? A self-recharging gun is
///    only temporarily dry and worth waiting on, but one that can't recharge
///    is dead for good to an NPC -- nothing in the AI swaps power cells or
///    goes looking for a recharger.
/mob/living/carbon/human/npc/hostile/proc/_gun_has_shots(obj/item/gun/G)
	if(!istype(G))
		return FALSE
	if(G.get_ammo() > 0)
		return TRUE
	if(istype(G, /obj/item/gun/projectile))
		return !!find_spare_magazine(G)
	if(istype(G, /obj/item/gun/energy))
		return _energy_gun_can_recharge(G)
	return TRUE // unknown gun type -- assume it's still good rather than bin it

/// Mirrors try_recharge()'s own gating (projectiles/guns/energy.dm) rather
/// than reinventing it, so this can't drift from what the gun will actually
/// do: it needs a cell, needs self_recharge, and when use_external_power is
/// set it needs an external supply that actually resolves.
///
/// That last one matters for NPCs specifically --
/// get_external_power_supply() only ever resolves for a borg, a rig module
/// or a recharger, never a weapon held in a human's hand. So an
/// external-power gun carried by a soldier can never come back, and is
/// correctly treated as spent.
/mob/living/carbon/human/npc/hostile/proc/_energy_gun_can_recharge(obj/item/gun/energy/EG)
	if(!istype(EG))
		return FALSE
	if(!EG.power_supply || !EG.self_recharge)
		return FALSE
	if(EG.use_external_power && !EG.get_external_power_supply())
		return FALSE
	return TRUE

/// Last-resort re-arm: pulls the best weapon this soldier is STILL CARRYING
/// out of its own gear once its issued weapon is gone for good (taken by
/// whoever disarmed it, destroyed, or thrown out of reach). Sweeps the same
/// slots -- and the same "also look inside storage items" rule --
/// find_spare_magazine() already uses for reloads.
///
/// A stowed sidearm always beats a knife regardless of `force` (guns do their
/// damage by shooting, not by being swung), so guns win outright; melee is
/// picked by highest force among the rest. Without this a disarmed soldier
/// throws punches with a perfectly good knife still on its belt.
/// Selection half of draw_stowed_weapon(), split out so callers can ask
/// "is there anything better than what I'm holding?" without committing to
/// the swap (see AttackTarget()'s dry-gun branch).
///
/// Ranking: a gun that can actually fire beats melee, melee beats a gun with
/// no shots left. That last part matters -- a dry stowed pistol used to win
/// outright over a perfectly good knife purely for being a gun, so a soldier
/// would "re-arm" into something it couldn't shoot.
/mob/living/carbon/human/npc/hostile/proc/_find_stowed_weapon()
	var/obj/item/best_gun
	var/obj/item/best_dry_gun
	var/obj/item/best_melee
	for(var/obj/item/holder in list(back, belt, s_store, l_store, r_store))
		if(!holder)
			continue
		var/list/candidates = list(holder)
		if(istype(holder, /obj/item/storage))
			var/obj/item/storage/S = holder
			candidates += S.contents
		for(var/obj/item/I in candidates)
			if(istype(I, /obj/item/gun))
				if(_gun_has_shots(I))
					if(!best_gun)
						best_gun = I
				else if(!best_dry_gun)
					best_dry_gun = I
				continue
			if(!_is_drawable_weapon(I))
				continue
			if(!best_melee || I.force > best_melee.force)
				best_melee = I

	return best_gun || best_melee || best_dry_gun

/mob/living/carbon/human/npc/hostile/proc/draw_stowed_weapon()
	var/obj/item/drawing = _find_stowed_weapon()
	if(!drawing)
		return FALSE
	// Drop-then-take rather than a raw slot move: if put_in_active_hand()
	// refuses for any reason the item ends up on the floor (recoverable next
	// tick) instead of stranded in limbo mid-transfer.
	if(!drop_from_inventory(drawing, get_turf(src)))
		return FALSE
	put_in_active_hand(drawing)
	_rewield_active_gun()
	visible_message(SPAN_WARNING("[src] draws \a [drawing]!"))
	return TRUE

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
	// Plate carrier pouches (and any other accessory-based pouch/webbing/
	// holster) attach to the worn suit or uniform's own accessories list,
	// not one of the fixed slots above -- and store their contents in a
	// separate internal storage sub-object (accessory/storage's own `hold`
	// var), not the accessory's own .contents.
	for(var/obj/item/clothing/worn in list(wear_suit, w_uniform))
		if(!worn || !LAZYLEN(worn.accessories))
			continue
		for(var/obj/item/clothing/accessory/storage/pouch in worn.accessories)
			if(!pouch.hold)
				continue
			for(var/obj/item/ammo_magazine/AM in pouch.hold.contents)
				if(_magazine_fits(G, AM))
					return AM
	// Storage suits (plate carriers, webbing vests -- /obj/item/clothing/suit/
	// storage and friends) keep their contents in an /obj/item/storage/internal
	// living in the garment's own contents (`pockets`, armor.dm), which is
	// neither one of the fixed slots above nor an accessory -- so neither loop
	// above ever reached it. That's why a soldier reloaded from its belt but
	// discarded its gun while carrying spare mags in a plate carrier. Same
	// locate() pattern serializePersistentItem() already uses for these suits.
	for(var/obj/item/clothing/worn_suit in list(wear_suit, w_uniform))
		if(!worn_suit)
			continue
		var/obj/item/storage/internal/IS = locate() in worn_suit
		if(!IS)
			continue
		for(var/obj/item/ammo_magazine/AM in IS.contents)
			if(_magazine_fits(G, AM))
				return AM
	return null

/mob/living/carbon/human/npc/hostile/proc/MoveToTarget()
	if(QDELETED(last_found_target) || !isturf(last_found_target?.loc) && !isturf(last_found_target))
		LoseTarget()
		return
	if(!(last_found_target in targets) && !is_valid_target(last_found_target, target_is_ordered))
		LoseTarget()
		return

	// A target that's merely out of sight (behind a wall) is never caught by
	// the check above -- targets/is_valid_target() don't care about LOS at
	// all, and this branch (HOSTILE_STANCE_ATTACK) is the only place a
	// lost-LOS gun target would otherwise loop forever without ever reaching
	// AttackTarget()'s own LOS check. A melee target flips straight to
	// ATTACKING regardless of LOS/range, but bounces right back here via
	// AttackTarget()'s "dist > 1" branch, so this still catches it within
	// HOSTILE_NPC_LOS_GIVEUP_TIME either way.
	//
	// A target visible THROUGH A WINDOW is a separate case the LOS check
	// alone can never catch -- windows block movement but not sight, so
	// can_see_target() stays TRUE forever even though this mob can never
	// actually get any closer. last_progress_turf/_time tracks real physical
	// progress independent of visibility -- only giving up once BOTH the
	// target hasn't been seen recently AND no progress has been made
	// recently means truly stuck, not just a target that ducked out of
	// sight for a moment while still being closed in on.
	if(get_turf(src) != last_progress_turf)
		last_progress_turf = get_turf(src)
		last_progress_time = world.time

	if(can_see_target(last_found_target))
		last_target_seen_time = world.time

	if(world.time - last_target_seen_time > HOSTILE_NPC_LOS_GIVEUP_TIME && world.time - last_progress_time > HOSTILE_NPC_LOS_GIVEUP_TIME)
		LoseTarget()
		return

	var/obj/item/W = get_wielded_weapon()
	if(istype(W, /obj/item/gun))
		if(get_dist(src, last_found_target) <= ranged_attack_range && can_see_target(last_found_target))
			GLOB.move_manager.stop_looping(src)
			change_stance(HOSTILE_STANCE_ATTACKING)
		else
			open_path_door_towards(last_found_target)
			// Same raw-distance-vs-actual-reachability mismatch as
			// follow_commander() -- if we're already within naive gun range
			// but still here because can_see_target() failed (a window),
			// re-asking for that same distance is a no-op against the
			// already-"arrived" loop. Ask for distance 0 so it keeps pathing
			// around to an actual door instead of freezing at the glass.
			var/close_but_blocked = get_dist(src, last_found_target) <= ranged_attack_range - 1 && !can_see_target(last_found_target)
			GLOB.move_manager.move_to(src, last_found_target, close_but_blocked ? 0 : ranged_attack_range - 1, move_speed, INFINITY)
	else
		change_stance(HOSTILE_STANCE_ATTACKING)
		open_path_door_towards(last_found_target)
		GLOB.move_manager.move_to(src, last_found_target, 1, move_speed, INFINITY)

/mob/living/carbon/human/npc/hostile/proc/AttackTarget()
	if(QDELETED(last_found_target) || !is_valid_target(last_found_target, target_is_ordered))
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
		// Any dry gun, not just a projectile one -- this branch used to be
		// gated on /obj/item/gun/projectile, so an energy weapon at zero
		// charge never reached it and could never be dealt with at all.
		if(G.get_ammo() <= 0)
			var/reloaded = FALSE
			if(istype(G, /obj/item/gun/projectile))
				var/obj/item/gun/projectile/GP = G
				var/obj/item/ammo_magazine/spare = find_spare_magazine(GP)
				if(spare)
					if(GP.ammo_magazine)
						GP.unload_ammo(src, TRUE, TRUE)
					GP.load_ammo(spare, src)
					reloaded = TRUE

			// Ditch a weapon that genuinely can't come back, so the soldier
			// falls through to something that still works.
			//
			// Gated on !reloaded first so a successful reload always wins
			// outright -- it short-circuits before _gun_has_shots() is even
			// consulted, rather than depending on get_ammo() having already
			// updated from the load above.
			//
			// Only discards if there IS something better: a spent gun still
			// swings for its own `force`, which beats bare fists, so a soldier
			// carrying nothing else keeps it and pistol-whips instead.
			//
			// The drop is all that happens here -- think()'s existing
			// try_recover_weapon() re-arms on the next tick through the normal
			// path, and skips this gun now that _gun_has_shots() rejects it.
			if(!reloaded && !_gun_has_shots(G) && _find_stowed_weapon())
				visible_message(SPAN_WARNING("[src] discards \the [G]!"))
				drop_from_inventory(G, get_turf(src))
			hostile_last_attack = world.time
			return TRUE
		if(is_friendly_fire_blocked(last_found_target))
			var/turf/better_spot = find_clear_firing_position(last_found_target)
			if(better_spot)
				friendly_fire_blocked_since = 0
				GLOB.move_manager.move_to(src, better_spot, 0, move_speed)
				return FALSE
			// No clear tile among any of the 8 neighbors either -- possible
			// forever in a straight 1-wide corridor with an ally blocking the
			// only line. Give up on this target after the same grace period
			// MoveToTarget()'s own LOS/unreachable-target giveup uses, rather
			// than sitting stuck in HOSTILE_STANCE_ATTACKING indefinitely,
			// deaf to Follow/Hold/individual orders the whole time.
			if(!friendly_fire_blocked_since)
				friendly_fire_blocked_since = world.time
			else if(world.time - friendly_fire_blocked_since > HOSTILE_NPC_LOS_GIVEUP_TIME)
				LoseTarget()
			return FALSE
		friendly_fire_blocked_since = 0
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

#ifdef NPC_AI_DEBUG_EXAMINE
/// Admin-only live AI state dump. This mob's failure modes are all "holds a
/// valid order but silently can't act on it," which look identical from the
/// outside -- this shows exactly which state it's actually in (stance, live
/// order, scheduling subsystem, and whether its move loop exists and what it's
/// chasing) instead of leaving it to be inferred from behaviour.
/mob/living/carbon/human/npc/hostile/get_examine_text(mob/user, distance, is_adjacent, infix, suffix)
	. = ..()
	if(!user || !check_rights(R_ADMIN, 0, user))
		return .
	var/datum/move_loop/active_loop = move_packet?.running_loop
	var/loop_desc = "none"
	if(active_loop)
		var/atom/loop_target
		if(istype(active_loop, /datum/move_loop/has_target))
			var/datum/move_loop/has_target/HT = active_loop
			loop_target = HT.target
		loop_desc = "[active_loop.type] -> [loop_target || "(no target)"]"
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> stance=[stance] | ordered_destination=[ordered_destination || "none"] | hold_position=[hold_position ? "YES" : "no"] | commander=[commander || "none"]")
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> target=[last_found_target || "none"] (ordered=[target_is_ordered ? "YES" : "no"]) | passive=[passive_mode ? "YES" : "no"] | ff_blocked_since=[friendly_fire_blocked_since]")
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> thinking=[thinking_enabled ? "YES" : "NO"] | fast=[is_fast_processing ? "YES" : "no"] | in_slow_list=[(src in SSmob_ai.processing) ? "YES" : "no"] | in_fast_list=[(src in SSmob_fast_ai.processing) ? "YES" : "no"]")
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> move_loop=[loop_desc] | order_stuck_for=[order_progress_time ? "[(world.time - order_progress_time) / 10]s" : "n/a"] | unstick_tried=[order_unstick_attempted ? "YES" : "no"]")
	// Movement capability. think() returns at its very first line on any
	// non-zero stat, and /mob/living/Move() hard-returns on buckled_to
	// (living.dm) -- either makes a mob that is being correctly TOLD to move
	// silently not move, with every AI field above still reading healthy.
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> stat=[stat] | canmove=[canmove ? "YES" : "NO"] | lying=[lying ? "YES" : "no"] | resting=[resting ? "YES" : "no"] | buckled_to=[buckled_to || "none"] | anchored=[anchored ? "YES" : "no"]")
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> weakened=[weakened] | stunned=[stunned] | paralysis=[paralysis] | on_medical_table=[is_on_medical_table() ? "YES" : "no"]")
	// Live pathing probe -- get_step_to() is the exact call the move loop
	// itself makes each tick (movement_types.dm). If it yields nothing while
	// a loop is active and distance is beyond min_dist, the loop is running
	// and simply cannot produce a step, which is the whole answer.
	if(commander && !QDELETED(commander))
		var/turf/probe_step = get_step_to(src, commander)
		. += SPAN_NOTICE("<b>\[NPC AI\]</b> dist_to_cmdr=[get_dist(src, commander)] | same_z=[(z == commander.z) ? "YES" : "NO"] | get_step_to=[probe_step ? "[probe_step.x],[probe_step.y]" : "NULL (no path!)"] | clear_path=[has_clear_path_to(commander) ? "YES" : "no"]")
	if(istype(active_loop, /datum/move_loop/has_target/dist_bound))
		var/datum/move_loop/has_target/dist_bound/DB = active_loop
		. += SPAN_NOTICE("<b>\[NPC AI\]</b> loop_min_dist=[DB.distance] | loop_wants_move=[DB.check_dist() ? "YES" : "NO (thinks it arrived)"] | loop_delay=[DB.delay] | loop_running=[(DB.status & MOVELOOP_STATUS_RUNNING) ? "YES" : "NO"]")
	// Beacon-side membership -- the AI state above can look perfect while an
	// order never reaches this mob at all, which is only visible from here.
	var/beacon_desc = "no commanding beacon found"
	for(var/obj/item/commander_beacon/B in world)
		if(!(src in B.active_mobs) && !(src in B.selected_soldiers))
			continue
		beacon_desc = "active=[(src in B.active_mobs) ? "YES" : "NO"] | selected=[(src in B.selected_soldiers) ? "YES" : "no"] | beacon_soldiers=[length(B.active_mobs)] | beacon_selected=[length(B.selected_soldiers)]"
		break
	. += SPAN_NOTICE("<b>\[NPC AI\]</b> [beacon_desc]")
#endif

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
