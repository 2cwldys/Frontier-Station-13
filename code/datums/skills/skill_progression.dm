/*
 * Runtime skill progression -- the shared plumbing behind skill manuals
 * (library/skill_manual.dm), peer teaching (Teach Skills verb), and skill loss
 * on resleeving (resleever_cloning.dm).
 *
 * Everyone starts Trained (the default fill, preference_setup/skills/skills.dm).
 * Professional is earned: taught one tier at a time by somebody who already
 * holds it, or in a single read from a very expensive cargo manual. Cloning
 * pushes you back down.
 *
 * WHY THESE HELPERS EXIST AT ALL -- two traps make hand-rolled skill mutation
 * wrong in ways that fail silently:
 *
 * 1. Never RemoveComponent() to lower a skill. on_spawn() (_skills.dm) skips
 *    component creation entirely for a non-required skill at Unfamiliar, and
 *    consumers treat a MISSING component as competent rather than unskilled --
 *    surgery.dm skips its penalty on a null skill_level, shuttle_console.dm
 *    allows use, ship.dm's UNFAMILIAR comparison is false for null. Deleting a
 *    component therefore makes a character BETTER. Loss must always be a
 *    skill_level write on a component that still exists, which is why
 *    set_skill_level() below loads the component before lowering it.
 *
 * 2. Never write skill_level past the skill's own maximum_level. That cap is
 *    otherwise only consulted by the chargen UI (dead code) and the BST admin
 *    spawn, so nothing else in the codebase would catch an overshoot.
 */

/// Current level of `skill` on `user`, or SKILL_LEVEL_UNFAMILIAR when they have
/// no component for it. Note the deliberate asymmetry with how the mechanics
/// read a missing component (see trap 1 above) -- this is the honest "what does
/// this character actually know" answer, for display and progression decisions.
/proc/get_skill_progression_level(mob/user, singleton/skill/skill)
	if(!user || !istype(skill) || !skill.component_type)
		return SKILL_LEVEL_UNFAMILIAR
	var/datum/component/skill/skill_comp = user.GetComponent(skill.component_type)
	if(!skill_comp)
		return SKILL_LEVEL_UNFAMILIAR
	return skill_comp.skill_level

/// The ceiling for `skill` on `user`, honouring their education where one can
/// be resolved. Falls back to the skill's own maximum_level rather than
/// runtiming, since get_maximum_level() crash_with()s on a non-instance and a
/// mob without a client (a fresh clone body, notably) has no prefs to read.
/proc/get_skill_progression_cap(mob/user, singleton/skill/skill)
	if(!istype(skill))
		return SKILL_LEVEL_UNFAMILIAR
	var/singleton/education/user_education
	if(user?.client?.prefs?.education && ispath(text2path(user.client.prefs.education), /singleton/education))
		user_education = GET_SINGLETON(text2path(user.client.prefs.education))
	if(istype(user_education))
		return skill.get_maximum_level(user_education)
	return skill.maximum_level

/// Sets `skill` on `user` to `new_level`, clamped to [UNFAMILIAR, cap]. Loads
/// the component first so a lowered skill still HAS one -- see trap 1 above.
/// Returns the level actually applied, or null if nothing could be done.
///
/// Also mirrors the applied level into user's currently-INSTALLED neural
/// lace, if they have one -- the lace is treated as the character's true,
/// continuously-current skill record, not just a snapshot taken at death.
/// Every caller (decay, train-by-use, manuals, Teach Skills, the admin
/// editor, and snapshot restore alike) funnels through here, so this one
/// spot keeps an installed lace live-synced for free. Harmless once a
/// consciousness is later actually captured (removed(), neural_lace.dm) --
/// that still takes its own fresh snapshot on top.
/proc/set_skill_progression_level(mob/user, singleton/skill/skill, new_level)
	if(!user || !istype(skill) || !skill.component_type)
		return null
	var/capped = clamp(new_level, SKILL_LEVEL_UNFAMILIAR, get_skill_progression_cap(user, skill))
	// LoadComponent is idempotent -- same raise-at-runtime shape used by
	// antagonist_create.dm, which is the only other place skills move mid-round.
	var/datum/component/skill/skill_comp = user.LoadComponent(skill.component_type, capped)
	if(!skill_comp)
		return null
	skill_comp.skill_level = capped
	if(istype(user, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = user
		var/obj/item/organ/internal/neural_lace/lace = H.internal_organs_by_name["neural_lace"]
		if(lace)
			LAZYINITLIST(lace.stored_skills)
			lace.stored_skills["[skill.type]"] = capped
	return capped

/// Human-readable tier name ("Trained"), for the messages every consumer shows.
/proc/get_skill_level_name(singleton/skill/skill, level)
	if(!istype(skill) || !islist(skill.skill_level_map))
		return "Unknown"
	if(level < 1 || level > length(skill.skill_level_map))
		return "Unknown"
	return skill.skill_level_map[level]

/**
 * Snapshots every skill `user` currently holds as an assoc list of
 * skill typepath -> level, suitable for stashing on a neural lace or
 * serializing to the database.
 *
 * This is what makes earned progression survive death. A clone body is built by
 * copy_to() from the character's saved chargen slot
 * (build_cloned_body_for_character(), resleever_cloning.dm), and that slot only
 * ever holds the Trained default fill -- nothing a character learns in-round
 * from a manual or a teacher is in it. Without carrying a snapshot across, a
 * resleeve would silently wipe ALL earned skill, not take the intended tier or
 * two.
 */
/proc/get_skill_snapshot(mob/user)
	var/list/snapshot = list()
	if(!user || !SSskills || !length(SSskills.all_skills))
		return snapshot
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		snapshot["[sk.type]"] = get_skill_progression_level(user, sk)
	return snapshot

/// Applies a snapshot from get_skill_snapshot() onto `user`. Levels are still
/// clamped per skill by set_skill_progression_level(), so a snapshot taken
/// under a different education or an older cap can't push anything past its
/// current ceiling. Silently ignores skill types that no longer exist.
/proc/apply_skill_snapshot(mob/user, list/snapshot)
	if(!user || !islist(snapshot) || !length(snapshot))
		return FALSE
	for(var/skill_key in snapshot)
		var/skill_path = text2path(skill_key)
		if(!skill_path)
			continue
		var/singleton/skill/sk = GET_SINGLETON(skill_path)
		if(!istype(sk))
			continue
		set_skill_progression_level(user, sk, snapshot[skill_key])
	return TRUE

/**
 * Snapshots the decay clock (decay_progress -- accumulated in-game/world.time
 * deciseconds of disuse, see its own doc comment on skill_component.dm) and
 * banked train-by-use progress (training_progress) of every skill component
 * `user` currently has, as skill typepath ->
 * {"decay_progress": N, "progress": N}. Companion to get_skill_snapshot() for
 * persistence_skills.dm's own DB round-trip -- deliberately NOT folded into
 * get_skill_snapshot()/apply_skill_snapshot() themselves, since those are
 * also used by the neural lace and widening their shape would ripple into
 * that working, unrelated path.
 */
/proc/get_skill_activity_snapshot(mob/user)
	var/list/snapshot = list()
	if(!user || !SSskills || !length(SSskills.all_skills))
		return snapshot
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		if(!sk.component_type)
			continue
		var/datum/component/skill/comp = user.GetComponent(sk.component_type)
		if(!comp)
			continue
		snapshot["[sk.type]"] = list("decay_progress" = comp.decay_progress, "progress" = comp.training_progress)
	return snapshot

/// Applies an activity snapshot from get_skill_activity_snapshot() onto
/// `user` -- run this AFTER apply_skill_snapshot() so the components it
/// writes to already exist. Skills with no component (still at the default,
/// never raised) are silently skipped -- nothing to track yet. Rows saved
/// before decay_progress existed (a bare number, or a {"last_used",
/// "progress"} list from the old REALTIMEOFDAY-based clock -- not
/// meaningfully convertible to an in-game-time duration) simply have no
/// "decay_progress" key here, so they fall back to each component's own
/// fresh-creation default of 0 -- not decay-eligible yet, same as any other
/// legacy row, rather than attempting a conversion that can't be correct.
/proc/apply_skill_activity_snapshot(mob/user, list/snapshot)
	if(!user || !islist(snapshot) || !length(snapshot))
		return FALSE
	for(var/skill_key in snapshot)
		var/skill_path = text2path(skill_key)
		if(!skill_path)
			continue
		var/singleton/skill/sk = GET_SINGLETON(skill_path)
		if(!istype(sk) || !sk.component_type)
			continue
		var/datum/component/skill/comp = user.GetComponent(sk.component_type)
		if(!comp)
			continue
		var/entry = snapshot[skill_key]
		if(islist(entry))
			comp.decay_progress = entry["decay_progress"] || 0
			comp.training_progress = entry["progress"] || 0
	return TRUE

/**
 * Degrades a resleeved character's skills: a random handful lose a tier each,
 * never more than GLOB.config.resleeve_max_tiers_lost in total, and only
 * skills sitting above GLOB.config.resleeve_skill_loss_floor are eligible --
 * so some skills come through untouched every time, and basic competence is
 * never taken away entirely. All three thresholds are config.txt-tunable
 * (controllers/configuration.dm) -- kept small/capped by default on purpose:
 * dying should sting and be visible, not gut a character.
 *
 * Returns a list of human-readable "Skill (Old -> New)" strings describing what
 * was actually lost, so the caller can tell the player exactly what they came
 * back missing. Empty list means nothing degraded.
 *
 * Lowering happens through set_skill_progression_level(), which keeps the
 * component alive -- removing it would make the character read as MORE capable,
 * not less. See the header of this file.
 */
/proc/apply_resleeve_skill_loss(mob/user)
	var/list/lost = list()
	if(!user || !SSskills || !length(SSskills.all_skills))
		return lost

	var/loss_floor = GLOB.config.resleeve_skill_loss_floor

	// Only skills with room to fall, so the random pick can't waste its budget
	// on something already at the floor and silently degrade nothing.
	var/list/eligible = list()
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		if(get_skill_progression_level(user, sk) > loss_floor)
			eligible += sk
	if(!length(eligible))
		return lost

	var/tiers_remaining = rand(1, GLOB.config.resleeve_max_tiers_lost)
	var/skills_remaining = GLOB.config.resleeve_max_skills_affected
	while(tiers_remaining > 0 && skills_remaining > 0 && length(eligible))
		var/singleton/skill/sk = pick(eligible)
		eligible -= sk
		var/old_level = get_skill_progression_level(user, sk)
		if(old_level <= loss_floor)
			continue
		var/applied = set_skill_progression_level(user, sk, old_level - 1)
		if(isnull(applied) || applied >= old_level)
			continue
		lost += "[sk.name] ([get_skill_level_name(sk, old_level)] -> [get_skill_level_name(sk, applied)])"
		tiers_remaining--
		skills_remaining--

	return lost

/// Every skill a manual can be written for -- i.e. those that can actually
/// reach Professional. Derived rather than hardcoded so it tracks any future
/// cap change: three combat skills cap at Trained and pilot_mechs at Familiar,
/// and a manual for those would either no-op or have to break the cap.
/proc/get_professional_capable_skills()
	var/list/result = list()
	if(!SSskills)
		return result
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		if(sk.maximum_level >= SKILL_LEVEL_PROFESSIONAL)
			result += sk
	return result
