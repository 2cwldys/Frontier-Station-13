/**
 * The base type for Componentized skills, containing only the information extracted from Skill preferences that would be required to function.
 * Children of this component can be added to a character from skill singletons by overriding that singleton's on_spawn() proc.
 */
ABSTRACT_TYPE(/datum/component/skill)
	/**
	 * How many ranks a player has purchased in a given skill.
	 * How this is actually used is entirely up to the implementation of individual components.
	 */
	var/skill_level = SKILL_LEVEL_UNFAMILIAR

	/**
	 * Reference value used for checking "Skill Diff"
	 * "Skill Diff" is the distance from the actual skill level to the reference.
	 *
	 * This can essentially be thought of as the "baseline competence" for how a vanilla character would function prior to the introduction of Skill Components.
	 * Any datum that is *missing* a given skill component can be logically assumed to be at this skill level.
	 * Therefore, characters who both have the component, and are at a level lower than this can be assumed to be "less competent".
	 * While characters at a level above this can be assumed to be "more competent".
	 */
	var/skill_diff_reference = SKILL_LEVEL_TRAINED

	/// REALTIMEOFDAY of the last time this skill was used or deliberately
	/// raised (teaching, a manual, or an admin edit) -- NOT touched by
	/// restoring a snapshot (DB load, resleeve), only by something that
	/// actually happened. Drives decay: see SSskills' fire() and the
	/// SKILL_DECAY_* defines (skill_progression.dm). Set to "now" on every
	/// component creation so a brand-new component never starts already
	/// decay-eligible; persistence restore (persistence_skills.dm) overwrites
	/// it with the real saved value when there is one.
	var/last_used_time = 0
	/// Per-instance cooldown gate for register_use()'s progress gain, so a
	/// burst of rapid actions (spam-clicking an attack, a mech's per-tile
	/// move signal) can't bank many ticks of progress in a second. Does not
	/// gate the last_used_time refresh itself -- every qualifying use still
	/// counts as "kept up," only progress accrual is throttled.
	var/next_train_roll = 0
	/// Accumulated practice toward the next tier, out of
	/// GLOB.config.skill_train_progress_needed -- builds up gradually from
	/// register_use(), not a flat per-use chance to instantly jump a tier.
	/// Persisted alongside last_used_time (persistence_skills.dm); carries
	/// its remainder across a tier-up rather than resetting to zero.
	var/training_progress = 0

/**
 * Always use . = ..() at the start of a NameSkillComponent's Initialize() proc.
 * Skills MUST have their skill_level set first during initialization.
 * Do this by setting var/level to the 2nd arg of AddComponent()
 */
/datum/component/skill/Initialize(var/level = SKILL_LEVEL_UNFAMILIAR)
	SHOULD_CALL_PARENT(TRUE)
	. = ..()
	skill_level = level
	last_used_time = REALTIMEOFDAY

/**
 * Called whenever the parent mob successfully does something this skill
 * governs. Always refreshes the decay clock; additionally banks
 * GLOB.config.skill_train_progress_per_use points of progress toward the
 * next tier, throttled to once per GLOB.config.skill_train_cooldown so a
 * burst of rapid actions can't bank many ticks in a second. Once progress
 * reaches GLOB.config.skill_train_progress_needed the tier actually rises --
 * a steady, deterministic build-up from practice, not a flat per-use chance
 * to instantly jump a tier. All three config.txt-tunable,
 * controllers/configuration.dm.
 */
/datum/component/skill/proc/register_use(mob/user)
	last_used_time = REALTIMEOFDAY
	if(REALTIMEOFDAY < next_train_roll)
		return
	next_train_roll = REALTIMEOFDAY + GLOB.config.skill_train_cooldown
	var/singleton/skill/sk = SSskills.skill_for_component_type[type]
	if(!istype(sk))
		return
	if(skill_level >= get_skill_progression_cap(user, sk))
		return
	training_progress += GLOB.config.skill_train_progress_per_use
	if(training_progress < GLOB.config.skill_train_progress_needed)
		return
	var/applied = set_skill_progression_level(user, sk, skill_level + 1)
	if(!isnull(applied) && applied > skill_level)
		training_progress -= GLOB.config.skill_train_progress_needed
		to_chat(user, SPAN_GOOD("You feel yourself getting better at [sk.name]. It's now [get_skill_level_name(sk, applied)]."))
		last_used_time = REALTIMEOFDAY
	else
		// Couldn't actually apply (e.g. cap changed between the check above
		// and here) -- don't silently discard the practice that was banked.
		training_progress -= GLOB.config.skill_train_progress_per_use
