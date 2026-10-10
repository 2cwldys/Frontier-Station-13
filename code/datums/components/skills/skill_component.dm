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

	/// Set by register_use() on every qualifying use (even a throttled one
	/// that grants no progress -- same "still counts as kept up" semantics
	/// the old decay_progress reset had), cleared by SSskills' fire() after
	/// checking it. A component with this set skips decay entirely for that
	/// tick; a use in ANY tick fully pauses decay for that tick, same
	/// all-or-nothing philosophy the old flat-timer system used, just
	/// checked every tick instead of via a separate elapsed-time counter.
	/// Not persisted -- meaningless across a restart, same as the old
	/// decay_progress was for anything except its own accumulation.
	var/used_since_last_decay_tick = FALSE
	/// Per-instance cooldown gate for register_use()'s progress gain, so a
	/// burst of rapid actions (spam-clicking an attack, a mech's per-tile
	/// move signal) can't bank many ticks of progress in a second. Does not
	/// gate the used-this-tick flag above -- every qualifying use still
	/// counts as "kept up," only progress accrual is throttled. Real-world
	/// time on purpose -- an anti-spam throttle, not a decay measurement.
	var/next_train_roll = 0
	/// Accumulated practice toward the next tier (positive, out of
	/// GLOB.config.skill_train_progress_needed) or accumulated rust toward
	/// losing the current one (negative, out of
	/// GLOB.config.skill_decay_progress_needed) -- one signed counter,
	/// register_use() and SSskills' decay sweep push it in opposite
	/// directions. Builds up gradually, not a flat per-use/per-tick chance
	/// to instantly jump a tier. Persisted (persistence_skills.dm); carries
	/// its remainder across a tier change (up OR down) rather than
	/// resetting to zero.
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
	used_since_last_decay_tick = FALSE

/**
 * Called whenever the parent mob successfully does something this skill
 * governs. Always marks the skill as kept-up for this decay tick;
 * additionally banks GLOB.config.skill_train_progress_per_use points of
 * progress toward the next tier, throttled to once per
 * GLOB.config.skill_train_cooldown so a burst of rapid actions can't bank
 * many ticks of progress in a second. Once progress reaches
 * GLOB.config.skill_train_progress_needed the tier actually rises -- a
 * steady, deterministic build-up from practice, not a flat per-use chance
 * to instantly jump a tier. All three config.txt-tunable,
 * controllers/configuration.dm.
 */
/datum/component/skill/proc/register_use(mob/user)
	used_since_last_decay_tick = TRUE
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
	else
		// Couldn't actually apply (e.g. cap changed between the check above
		// and here) -- don't silently discard the practice that was banked.
		training_progress -= GLOB.config.skill_train_progress_per_use
