/*
 * Ship Shield Generator
 * A cargo-purchasable machine that, once wrenched to a ship's hull, powered,
 * and activated, absorbs incoming ship weapon fire up to its shield_strength
 * pool instead of letting it hit the target Z-level at all -- see
 * check_entry_ship() (_overmap_projectiles.dm) for the actual interception,
 * and on_hit() (_ship_ammunition.dm) for a defense-in-depth recheck in case
 * shields drop mid-flight.
 *
 * Modeled directly on ship_cloaking_device.dm -- same hook-up-to-ship
 * pattern, same phoron-sheet hopper fuel model. The one deliberate
 * difference from that fuel model: fuel here is a PURE on/off gate. It only
 * decides whether the generator can be active and can regen/absorb at all --
 * it never scales shield_strength/regen_rate. Running dry takes the
 * generator offline (stops blocking AND stops regenerating) until refueled;
 * it does not make shields weaker while still "on."
 *
 * Only activatable aboard an actual ship (drydock-owned or otherwise) --
 * refuses on a station, same as a cloak wouldn't make sense there either.
 */

/// Coarse shield-capacity buckets, shared between this generator's own
/// tier-transition announcer (see _check_tier_transition()) and the
/// targeting console's continuous enemy-shield readout
/// (_targeting_console.dm) -- both read tiers through get_shield_tier()
/// below so the two can never disagree about where a boundary falls.
#define SHIELD_TIER_NONE "none" // no generator, or present but inactive -- ENEMY_SHIP_NO_SHIELDS when read externally
#define SHIELD_TIER_DOWN "down" // active, but fully depleted
#define SHIELD_TIER_TWENTY_FIVE "twenty_five" // active, actually near 25% of max
#define SHIELD_TIER_FIFTY "fifty" // active, actually near 50% of max
#define SHIELD_TIER_NORMAL "normal" // active, but not close to any callout below -- no line, see file header
#define SHIELD_TIER_MAX "max" // active, at 100% of max

/// How close (in percent of max) shield_strength has to be to 25/50 for
/// get_shield_tier() to actually call it out by that name -- e.g. 12.5 means
/// the 25% line only covers 12.5%-37.5% of the real value. Anything outside
/// every band below falls back to SHIELD_TIER_NORMAL (silent) rather than
/// naming a percentage nowhere close to the truth -- e.g. a big single hit
/// that drops 90% straight to 5% has no honest "X percent" line to say, so
/// it says nothing until shields either fully recover or fully collapse.
#define SHIELD_TIER_BAND_WIDTH 2

/// Announcer queue supersede key (see play_announcer_sound(), announce.dm)
/// for the enemy-ship tier readout (_targeting_console.dm's continuous
/// poll) -- that one's still a "current state" snapshot, unlike the own-
/// ship line's crossing-based announcements below, which need no supersede
/// key since every crossing they announce is a genuine distinct event.
#define SHIELD_TIER_ANNOUNCE_KEY_ENEMY "shield_tier_enemy"

/// See the SHIELD_TIER_* defines above for what each bucket means. Reads
/// off the ACTUAL current percentage (gen.shield_strength /
/// gen.max_shield_strength), not just a fraction of max_shield_strength in
/// isolation -- this is what makes it correct regardless of whether
/// max_shield_strength is 100, 300, or anything else.
/proc/get_shield_tier(obj/structure/machinery/ship_shield_generator/gen)
	if(!gen || !gen.active)
		return SHIELD_TIER_NONE
	if(gen.shield_strength <= 0)
		return SHIELD_TIER_DOWN
	if(gen.shield_strength >= gen.max_shield_strength)
		return SHIELD_TIER_MAX
	var/percent = (gen.shield_strength / gen.max_shield_strength) * 100
	if(abs(percent - 50) <= SHIELD_TIER_BAND_WIDTH)
		return SHIELD_TIER_FIFTY
	if(abs(percent - 25) <= SHIELD_TIER_BAND_WIDTH)
		return SHIELD_TIER_TWENTY_FIVE
	return SHIELD_TIER_NORMAL

/// Damage-per-simulated-rock when an asteroid wave is absorbed instead of
/// blocked outright -- see absorb_meteor_wave() and meteors.dm's send_wave().
/// First-pass tuning, same spirit as absorb_hit()'s devastation/heavy/light
/// weights -- rebalance here without touching anything else.
#define SHIELD_METEOR_DAMAGE_PER_ROCK 27

/// How long a generator refuses to reactivate after collapsing from combat
/// damage (shield_strength hitting 0 while it was actually up) -- see
/// _apply_shield_damage() and toggle_shield(). Does NOT apply to a fresh
/// unit activated for the first time at 0 charge; only to a genuine
/// mid-fight collapse.
#define SHIELD_RECOVERY_COOLDOWN 30 SECONDS

/// Blocks pod warp (warp.dm) and Personal Travel leaps (personal_travel.dm)
/// from targeting a ship whose shields are up, UNLESS the traveler is crew/
/// faction of that same ship -- reuses _drydock_full_access_check()
/// (telepad_drydock_boarding.dm), the same owner/faction/crew-list check
/// drydock boarding itself already gates interior access on, so "who counts
/// as this ship's own people" can never drift between the two systems. A
/// non-drydock ship (NPC/pirate) has no crew list to match against, so its
/// shields block everyone with no bypass -- correct, since there's no
/// player crew to exempt.
/proc/ship_shields_block_travel(obj/effect/overmap/visitable/target, mob/user)
	if(!istype(target, /obj/effect/overmap/visitable/ship))
		return FALSE
	var/obj/effect/overmap/visitable/ship/VS = target
	if(!VS.shield_generator || !VS.shield_generator.shields_up())
		return FALSE
	if(length(target.map_z) && _drydock_full_access_check(user, target.map_z[1]))
		return FALSE
	return TRUE

/// Mirrors /obj/effect/pod_shield_bubble (secondary_systems.dm) exactly --
/// same asset, same vis_contents technique (not AddOverlays(), which can't
/// be live-animated for a fade and gets wiped by the ship marker's own
/// update_icon() on every move -- see that file's own doc comment for the
/// full reasoning, which applies here unchanged).
/obj/effect/ship_shield_bubble
	name = "shield"
	desc = "A shimmering deflector field."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "shield"
	anchored = TRUE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	alpha = 0
	layer = ABOVE_HUMAN_LAYER

// vis_contents-attached to the ship's OVERMAP marker (OVERMAP_SHIP_LAYER,
// layers.dm) instead of the generator itself -- the base type's
// ABOVE_HUMAN_LAYER (copied from pod_shield_bubble, which really is on the
// normal plane) rendered this ~58 layers below the ship icon it's attached
// to, i.e. never seen.
/obj/effect/ship_shield_bubble/overmap
	layer = OVERMAP_SHIP_LAYER + 0.01

/obj/structure/machinery/ship_shield_generator
	name = "shield generator"
	desc = "A reinforced generator that projects a deflector field around the ship's hull, absorbing incoming weapons fire until its capacity is exhausted."
	icon = 'icons/obj/power.dmi'
	icon_state = "rtg"
	color = "#3daaff"
	anchored = FALSE // spawns loose on purchase -- must be wrenched down before it can activate
	density = TRUE
	maxhealth = OBJECT_HEALTH_HIGH
	idle_power_usage = 0
	active_power_usage = 0

	var/active = FALSE
	var/shield_strength = 0
	var/max_shield_strength = 300
	/// Points regenerated per process() tick while active and fueled --
	/// entirely independent of how much fuel is left, see file header.
	var/regen_rate = 2

	/// Same hopper shape as ship_cloaking_device.dm -- see that file's own
	/// doc comment for why these numbers are deliberately stingy (shields
	/// aren't meant to be a free permanent state).
	var/time_per_sheet = 60
	var/max_sheets = 30
	var/sheets = 0
	var/sheet_left = 0
	var/power_output = 1
	var/sheet_path = /obj/item/stack/material/phoron
	var/sheet_name = "phoron crystals"

	/// shield_strength as of the last _check_tier_transition() call --
	/// compared against the CURRENT value so a percentage threshold
	/// (25%/50%/0%/max) is caught even when a single change (a big hit, or
	/// several regen ticks at once) jumps clean past it without the current
	/// value ever landing near it.
	var/prev_shield_strength = 0
	/// Flips every absorb_hit() so shields_struck_1/_2 alternate instead of
	/// playing the same one back-to-back.
	var/next_struck_alternate = FALSE
	/// world.time toggle_shield() refuses reactivation until, set by
	/// _apply_shield_damage() when a hit collapses shield_strength to 0 --
	/// 0 (the default) means no cooldown is in effect. Never set by simply
	/// activating a fresh, uncharged generator.
	var/shield_recovery_at = 0
	/// The shimmer shown on the generator itself while shields are up -- see
	/// show_bubble()/hide_bubble().
	var/obj/effect/ship_shield_bubble/bubble
	/// The same shimmer, mirrored onto the linked ship's overmap marker --
	/// see show_bubble()/hide_bubble().
	var/obj/effect/ship_shield_bubble/overmap/overmap_bubble

	/// Whether the ambient hum loop is currently considered "on" -- diffed
	/// each _update_hum() sweep, same shape as ship.dm's own
	/// engine_hum_active/engine_hum_listeners/next_engine_hum_check.
	var/hum_active = FALSE
	/// Mobs currently hearing this generator's hum loop -- reconciled every
	/// sweep against who's actually on the linked ship's Z(s).
	var/list/hum_listeners = list()
	/// world.time of the next _update_hum() sweep -- throttled the same way
	/// process()'s own regen tick doesn't need to run every single tick.
	var/next_hum_check = 0

/obj/structure/machinery/ship_shield_generator/Initialize()
	. = ..()
	return INITIALIZE_HINT_LATELOAD

// Same reasoning/timing as ship_cloaking_device.dm's own LateInitialize()/
// _hook_up_to_ship() -- see its doc comment.
/obj/structure/machinery/ship_shield_generator/LateInitialize()
	. = ..()
	_hook_up_to_ship()

/// As well as linking this machine to its ship (attempt_hook_up(), the
/// generic /obj/structure/machinery proc), also registers back onto the
/// ship's own overmap marker (shield_generator var, ship.dm) so incoming-
/// fire code can find this generator from the TARGET side (check_entry_ship(),
/// on_hit()) without walking every machine aboard the ship.
/obj/structure/machinery/ship_shield_generator/proc/_hook_up_to_ship()
	if(linked)
		return TRUE
	if(!SSatlas.current_map.use_overmap)
		return FALSE
	var/my_sector = GLOB.map_sectors["[GET_Z(src)]"]
	if(!istype(my_sector, /obj/effect/overmap/visitable))
		return FALSE
	if(!attempt_hook_up(my_sector))
		return FALSE
	if(istype(linked, /obj/effect/overmap/visitable/ship))
		var/obj/effect/overmap/visitable/ship/VS = linked
		VS.shield_generator = src
	// Re-syncs the bubble to whatever shield_strength persistence just
	// restored, now that linked (and thus the ship marker to attach it to)
	// actually exists -- persistent_objects_apply_content() runs before this
	// in the restore sequence and already set prev_shield_strength to match,
	// so this is a no-op for the voice line, but still correctly shows/hides
	// the bubble for the restored charge.
	_check_tier_transition()
	return TRUE

/obj/structure/machinery/ship_shield_generator/Destroy()
	if(istype(linked, /obj/effect/overmap/visitable/ship))
		var/obj/effect/overmap/visitable/ship/VS = linked
		if(VS.shield_generator == src)
			VS.shield_generator = null
		if(overmap_bubble)
			VS.remove_vis_contents(overmap_bubble)
	if(bubble)
		remove_vis_contents(bubble)
	QDEL_NULL(bubble)
	QDEL_NULL(overmap_bubble)
	for(var/mob/M in hum_listeners)
		M << sound(null, channel = CHANNEL_SHIP_SHIELD_HUM)
	hum_listeners = list()
	DropFuel()
	return ..()

/obj/structure/machinery/ship_shield_generator/proc/HasFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(sheets >= needed_sheets - sheet_left)
		return TRUE
	return FALSE

/obj/structure/machinery/ship_shield_generator/proc/UseFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(needed_sheets > sheet_left)
		sheets--
		sheet_left = (1 + sheet_left) - needed_sheets
	else
		sheet_left -= needed_sheets

// Removes whatever's left in the hopper as a fresh stack -- mirrors
// ship_cloaking_device.dm's own DropFuel(), called on Destroy() so
// scrapping the generator doesn't silently delete stored phoron.
/obj/structure/machinery/ship_shield_generator/proc/DropFuel()
	if(sheets)
		var/obj/item/stack/material/S = new sheet_path(loc)
		var/amount = min(sheets, S.max_amount)
		S.amount = amount
		sheets -= amount

/obj/structure/machinery/ship_shield_generator/process()
	_update_hum()
	if(active && anchored && istype(linked) && HasFuel())
		UseFuel()
		if(shield_strength < max_shield_strength)
			shield_strength = min(max_shield_strength, shield_strength + regen_rate)
			_check_tier_transition()
	else if(active)
		// Ran out of phoron, got unanchored, or lost its ship link -- force off.
		_set_active(FALSE, silent = (!HasFuel()))
		if(!HasFuel())
			audible_message(SPAN_WARNING("\The [src] sputters and powers down -- out of phoron."))

/obj/structure/machinery/ship_shield_generator/proc/toggle_shield(mob/user)
	if(!active)
		if(world.time < shield_recovery_at)
			to_chat(user, SPAN_WARNING("\The [src] is still recalibrating after its shields collapsed -- ready in [round((shield_recovery_at - world.time) / 10)] second\s."))
			return
		if(!anchored)
			to_chat(user, SPAN_WARNING("\The [src] must be anchored before it can be activated."))
			return
		if(!_hook_up_to_ship())
			to_chat(user, SPAN_WARNING("\The [src] cannot locate this ship on the overmap."))
			return
		// Scoped to ship/landable specifically, not the whole ship hierarchy --
		// the same istype() pitfall faction_beacon.dm already hit and fixed
		// (see its own doc comment): ship/stationary (sensor relays and other
		// away-site installations that just use a ship-shaped overmap icon)
		// is non-flyable scenery, not a real drydock ship or shuttle, and was
		// wrongly passing a bare /ship check.
		if(!istype(linked, /obj/effect/overmap/visitable/ship/landable))
			to_chat(user, SPAN_WARNING("\The [src] can only be activated aboard a drydock ship or shuttle, not a station."))
			return
		if(!HasFuel())
			to_chat(user, SPAN_WARNING("\The [src] has no phoron left to burn."))
			return
	_set_active(!active)

/obj/structure/machinery/ship_shield_generator/proc/_set_active(new_state, silent = FALSE)
	if(active == new_state)
		return
	active = new_state
	if(!silent)
		visible_message(active \
			? SPAN_NOTICE("\The [src] hums to life -- a faint shimmer spreads across the hull.") \
			: SPAN_NOTICE("\The [src] powers down."))
		// Suppressed alongside the text above on the routine "ran out of
		// fuel" auto-shutoff -- that path already has its own, more specific
		// "sputters and powers down" line (process()), so SHIELDS_ARE_OFFLINE
		// would just be redundant noise on top of it.
		if(active)
			_announce_to_ship('sound/AI/announcements/shields_online.ogg', 50, TRUE)
			_announce_to_ship('sound/effects/ship_weapons/shields_powered_on_vfx.ogg', 50, FALSE)
		else
			_announce_to_ship('sound/AI/announcements/shields_are_offline.ogg', 50, TRUE)
			_announce_to_ship('sound/effects/ship_weapons/shields_powered_off_vfx.ogg', 50, FALSE)
	update_icon()
	if(active)
		// Restores bubble visibility for whatever charge was already there --
		// see _check_tier_transition()'s own doc comment for why this alone
		// (with no strength actually changing) doesn't also re-announce a
		// percentage line.
		_check_tier_transition()
	else
		hide_bubble()

/obj/structure/machinery/ship_shield_generator/update_icon()
	set_light(active ? 2 : 0, 1, l_color = color)

/// Z-wide broadcast to every mob on the given ship's Z-level(s) -- Z-wide,
/// not console-range-limited like the engine announcer
/// (_announce_engine_power(), ship.dm), per explicit design: shield/combat
/// status is whole-ship information, not console-local ambiance. Shared by
/// the shield generator (its own status/tier lines), target()/detarget()
/// (lock-on confirmation), and the targeting console (fire confirmation,
/// enemy shield readout) -- one broadcast shape, several call sites.
/// use_announcer_queue routes voice lines through play_announcer_sound()
/// (the existing per-client announcer_queue/announcer_free_at system,
/// ASFX_ANNOUNCER-gated, so two lines never overlap for the same
/// listener); plain VFX/struck effects just play directly, gated only on
/// ear_deaf. supersede_key is passed straight through to
/// play_announcer_sound() -- see its own doc comment (announce.dm) for why
/// tier readouts need it and one-shot lines (fire confirmation, lock-on)
/// should leave it null.
/proc/announce_to_ship_z(list/map_z, sound_path, volume, use_announcer_queue, supersede_key = null)
	if(!length(map_z))
		return
	for(var/mob/M in GLOB.player_list)
		if(!M.client || M.ear_deaf || !(GET_Z(M) in map_z))
			continue
		if(use_announcer_queue)
			if(M.client.prefs.sfx_toggles & ASFX_ANNOUNCER)
				play_announcer_sound(M, sound_path, volume, supersede_key)
		else
			M << sound(sound_path, volume = volume)

/// Thin per-instance wrapper around announce_to_ship_z() for this
/// generator's own linked ship -- see that proc's doc comment.
/obj/structure/machinery/ship_shield_generator/proc/_announce_to_ship(sound_path, volume, use_announcer_queue, supersede_key = null)
	if(!istype(linked))
		return
	announce_to_ship_z(linked.map_z, sound_path, volume, use_announcer_queue, supersede_key)

/**
 * Checked after every regen tick (process()) and every absorbed hit
 * (absorb_hit()/absorb_meteor_wave()) -- shows/hides the shield bubble for
 * the current charge, then announces a percentage line for every 25%/50%/
 * max/down THRESHOLD actually crossed between the last check and now.
 *
 * Compares raw points (prev_shield_strength vs shield_strength), not a
 * "current tier" snapshot -- a single big hit or a multi-tick regen jump
 * can cross straight past 25% or 50% without shield_strength ever landing
 * near it, and a threshold that got skipped over still genuinely happened,
 * so it still gets announced. Checkpoints are announced in the order they
 * were actually passed through (high-to-low while declining, low-to-high
 * while recovering) -- e.g. a hit that drops 90% straight to 10% announces
 * "fifty percent" then "twenty-five percent", in that order, not just
 * whichever one the final value happens to be closest to.
 */
/obj/structure/machinery/ship_shield_generator/proc/_check_tier_transition()
	var/old_strength = prev_shield_strength
	var/new_strength = shield_strength
	prev_shield_strength = new_strength

	if(new_strength <= 0)
		hide_bubble()
	else
		show_bubble()

	if(old_strength == new_strength)
		return

	var/lo = min(old_strength, new_strength)
	var/hi = max(old_strength, new_strength)
	var/declining = (new_strength < old_strength)

	// High-to-low order -- reversed below when recovering, so each
	// checkpoint is announced in the order it was actually passed through.
	var/list/checkpoints = list(
		list(max_shield_strength, 'sound/AI/announcements/shields_maximum.ogg'),
		list(max_shield_strength * 0.5, 'sound/AI/announcements/shields_fifty_percent.ogg'),
		list(max_shield_strength * 0.25, 'sound/AI/announcements/shields_twenty_five_percent.ogg'),
		list(0, 'sound/AI/announcements/shields_are_down.ogg'),
	)
	if(!declining)
		checkpoints = reverselist(checkpoints)

	for(var/list/checkpoint in checkpoints)
		var/point = checkpoint[1]
		if(point >= lo && point <= hi)
			_announce_to_ship(checkpoint[2], 50, TRUE)

/// Fades the shield bubble in on the generator itself, and mirrors the same
/// fade onto the linked ship's overmap marker.
/obj/structure/machinery/ship_shield_generator/proc/show_bubble()
	if(!bubble)
		bubble = new(src)
		add_vis_contents(bubble)
	animate(bubble, alpha = 255, time = 1 SECOND)
	if(istype(linked))
		if(!overmap_bubble)
			overmap_bubble = new /obj/effect/ship_shield_bubble/overmap(linked)
			linked.add_vis_contents(overmap_bubble)
		// Match the marker's own invisibility exactly -- ship markers are
		// INVISIBILITY_OVERMAP (requires_contact), not 0, so whoever can
		// already see the ship icon (its owner, or anyone with sensor
		// contact) sees the bubble too, same as the icon itself, instead of
		// the bubble being gated by a different threshold than the ship it's
		// attached to.
		overmap_bubble.invisibility = linked.invisibility
		animate(overmap_bubble, alpha = 255, time = 1 SECOND)

/// Fades the bubble back out rather than cutting it instantly -- left
/// sitting in vis_contents at alpha 0 between toggles instead of removed/
/// re-added each time, same as pod_shield_bubble's own hide_shield_bubble().
/obj/structure/machinery/ship_shield_generator/proc/hide_bubble()
	if(bubble)
		animate(bubble, alpha = 0, time = 1 SECOND)
	if(overmap_bubble)
		animate(overmap_bubble, alpha = 0, time = 1 SECOND)

/// Reconciles the ambient hum loop against who's currently on the linked
/// ship's Z(s), same shape as _update_engine_hum() (ship.dm) -- deliberately
/// on its own CHANNEL_SHIP_SHIELD_HUM rather than sharing CHANNEL_MACHINERY,
/// since a ship can have both its engine and its shields active at once and
/// two loops on one channel would keep cutting each other off per listener.
/// Gated by the same ASFX_ENGINE_HUM toggle as the engine hum -- both are
/// "ship mechanical ambient loop" preferences from the player's perspective.
/// Called every process() tick; self-throttles.
/obj/structure/machinery/ship_shield_generator/proc/_update_hum()
	if(world.time < next_hum_check)
		return
	next_hum_check = world.time + 3 SECONDS

	var/should_hum = active && istype(linked)

	var/list/current_listeners = list()
	if(should_hum)
		for(var/mob/M in GLOB.player_list)
			if(!M.client || M.ear_deaf || !(GET_Z(M) in linked.map_z))
				continue
			if(!(M.client.prefs.sfx_toggles & ASFX_ENGINE_HUM))
				continue
			current_listeners += M
	hum_active = should_hum

	for(var/mob/M in current_listeners)
		if(!(M in hum_listeners))
			M << sound('sound/machines/electrical_hum1.ogg', repeat = 1, volume = 10, channel = CHANNEL_SHIP_SHIELD_HUM)
	for(var/mob/M in hum_listeners)
		if(!(M in current_listeners))
			M << sound(null, channel = CHANNEL_SHIP_SHIELD_HUM)
	hum_listeners = current_listeners

/**
 * Called from check_entry_ship() (_overmap_projectiles.dm) before an
 * incoming shot is allowed to actually reach this ship's Z-level, and again
 * (defense-in-depth) from /obj/projectile/ship_ammo/on_hit()
 * (_ship_ammunition.dm) in case shields dropped mid-flight. Returns TRUE if
 * the hit was absorbed (caller must qdel the projectile and never let it
 * deal real damage) or FALSE if it should proceed normally.
 */
/// The exact "are shields actually up" gate absorb_hit() has always used --
/// pulled out so ship_shields_block_travel() (external callers, pod/
/// personal-travel boarding lockout) and absorb_hit()/absorb_meteor_wave()
/// (internal, weapon/hazard damage) can never disagree about what "up"
/// means.
/obj/structure/machinery/ship_shield_generator/proc/shields_up()
	return active && HasFuel() && shield_strength > 0

/// Shared damage/sound/shake/struck-alternate/tier-check tail for anything
/// that hits the shield -- weapon fire (absorb_hit()) and, now, an asteroid
/// wave redirected here instead of hitting the hull (absorb_meteor_wave()).
/// Both need to look and sound identical, so both funnel through this one
/// proc instead of duplicating the tail.
/obj/structure/machinery/ship_shield_generator/proc/_apply_shield_damage(damage)
	shield_strength = max(0, shield_strength - damage)

	var/turf/hit_turf = get_turf(src)
	if(hit_turf)
		playsound(hit_turf, 'sound/effects/shieldbash.ogg', 70, TRUE)
	for(var/z_level in GetConnectedZlevels(GET_Z(src)))
		for(var/mob/living/carbon/human/H in GLOB.human_mob_list)
			if(H.z == z_level)
				shake_camera(H, 6, 3)

	// Alternates so repeated hits don't sound identical back-to-back --
	// layered on top of the impact sound/shake above, not a replacement.
	var/struck_sound = next_struck_alternate ? 'sound/effects/ship_weapons/shields_struck_2.ogg' : 'sound/effects/ship_weapons/shields_struck_1.ogg'
	next_struck_alternate = !next_struck_alternate
	_announce_to_ship(struck_sound, 60, FALSE)

	_check_tier_transition()

	// A genuine mid-fight collapse, not just an already-off/never-charged
	// generator being irrelevant here -- shields_up() already gated entry
	// to this proc on active being TRUE, so reaching 0 here always means it
	// just got knocked out by damage. Deactivate outright and lock out
	// toggle_shield() for SHIELD_RECOVERY_COOLDOWN -- silent = TRUE since
	// _check_tier_transition() just announced shields_are_down.ogg for this
	// exact moment; a second "offline" line back to back would be noise.
	if(shield_strength <= 0)
		shield_recovery_at = world.time + SHIELD_RECOVERY_COOLDOWN
		_set_active(FALSE, silent = TRUE)
		visible_message(SPAN_WARNING("\The [src] overloads and shuts down!"))

/obj/structure/machinery/ship_shield_generator/proc/absorb_hit(obj/projectile/ship_ammo/incoming)
	if(!shields_up())
		return FALSE

	// Weighted composite of the shot's devastation/heavy/light explosion
	// radii (explosion_strength, _ship_ammunition.dm -- stored there for
	// exactly this) into a single "shield damage" number. Tuned as a first
	// pass; rebalance via these weights or max_shield_strength/regen_rate
	// without touching anything else.
	var/list/strength = incoming?.explosion_strength
	var/damage = 0
	if(islist(strength) && length(strength) >= 3)
		damage = (strength[1] * 15) + (strength[2] * 8) + (strength[3] * 4)
	_apply_shield_damage(damage)
	return TRUE

/**
 * Called from meteor_wave/send_wave() (meteors.dm) instead of the real
 * spawn_meteors() call when the target ship's shields are up -- an asteroid
 * wave costs shield charge exactly like taking weapon fire (same sound/
 * shake/struck alternation/tier check via _apply_shield_damage()) rather
 * than ever reaching the hull. wave_size is the same get_wave_size() value
 * that would otherwise have decided how many real meteors to spawn.
 */
/obj/structure/machinery/ship_shield_generator/proc/absorb_meteor_wave(wave_size)
	if(!shields_up())
		return FALSE
	_apply_shield_damage(wave_size * SHIELD_METEOR_DAMAGE_PER_ROCK)
	return TRUE

/obj/structure/machinery/ship_shield_generator/attackby(obj/item/attacking_item, mob/user, params)
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

/obj/structure/machinery/ship_shield_generator/attack_hand(mob/user)
	if(..())
		return
	ui_interact(user)

/obj/structure/machinery/ship_shield_generator/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		// "ShipShieldGenerator", not "ShieldGenerator" -- that name is
		// already taken by the unrelated station-side forcefield generator
		// (code/modules/shieldgen/, ShieldGenerator.tsx).
		ui = new(user, src, "ShipShieldGenerator", "Shield Generator", 380, 340)
		ui.open()

/obj/structure/machinery/ship_shield_generator/ui_data(mob/user)
	var/list/data = list()
	data["active"] = active
	data["anchored"] = anchored
	data["linked"] = istype(linked)
	data["shield_strength"] = shield_strength
	data["max_shield_strength"] = max_shield_strength
	data["sheets"] = sheets
	data["max_sheets"] = max_sheets
	data["sheet_name"] = sheet_name
	var/needed_sheets = power_output / time_per_sheet // fraction of a sheet burned per process() tick
	data["seconds_per_sheet"] = time_per_sheet
	data["seconds_remaining"] = (needed_sheets > 0) ? round((sheets + sheet_left) / needed_sheets) : null
	data["recovery_seconds_left"] = (world.time < shield_recovery_at) ? round((shield_recovery_at - world.time) / 10) : 0
	return data

/obj/structure/machinery/ship_shield_generator/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("toggle")
			toggle_shield(user)
			. = TRUE

/**
 * Persists the fuel hopper, on/off state, and current charge across a
 * ship's stash/retrieve cycle -- same gap as ship_cloaking_device.dm's own
 * fix (see its doc comment): objectsRegisterTrack() already happens for
 * free, but with no content override every restore silently reset to the
 * mapped defaults. shield_recovery_at deliberately NOT persisted -- it's a
 * world.time-relative cooldown that would be meaningless (or permanently
 * stuck) after a real server restart.
 */
/obj/structure/machinery/ship_shield_generator/persistent_objects_get_content()
	var/list/content = ..()
	content["active"] = active
	content["sheets"] = sheets
	content["sheet_left"] = sheet_left
	content["shield_strength"] = shield_strength
	return content

/obj/structure/machinery/ship_shield_generator/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	sheets = content["sheets"] || 0
	sheet_left = content["sheet_left"] || 0
	shield_strength = content["shield_strength"] || 0
	// Matches shield_strength immediately -- without this, _check_tier_transition()
	// (fired later from _hook_up_to_ship(), once linked exists) would see a
	// fake "crossing" from 0 up to whatever was restored and misannounce it.
	prev_shield_strength = shield_strength
	// The raw flag only -- see _hook_up_to_ship() for why the bubble/tier
	// re-sync happens there instead of here (linked doesn't exist yet).
	active = content["active"] || FALSE
