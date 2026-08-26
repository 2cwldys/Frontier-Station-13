SUBSYSTEM_DEF(skills)
	name = "Skills"
	wait = 10 MINUTES

	/// This is essentially the list we use to read skills in the character setup.
	var/list/skill_tree = list()

	/**
	 * The set of all known skill singletons.
	 * These are always typed as /singleton/skill and as such are safe to for(var/singleton/skill/skill as anything in SSskills.all_skills)
	 */
	var/list/all_skills = list()

	/**
	 * The set of all skills that are "forced" in order to guarantee necessary components are applied.
	 * These are always typed as /singleton/skill and as such are safe to for(var/singleton/skill/skill as anything in SSskills.required_skills)
	 */
	var/list/required_skills = list()

	/// component_type typepath -> the /singleton/skill that owns it. Lets a
	/// skill component (skill_component.dm's register_use()) resolve its own
	/// singleton without every component subtype needing to know it.
	var/list/skill_for_component_type = list()

	/// world.time at this subsystem's last fire() -- the decay sweep advances
	/// every skill component's decay_progress by the DELTA since this, not by
	/// comparing against an absolute saved timestamp. Reinitialized to the
	/// current (post-boot) world.time every startup, so the first delta after
	/// a restart is always small and correct -- never a stale cross-restart
	/// gap.
	var/last_decay_tick = 0

/datum/controller/subsystem/skills/Initialize()
	// Initialize the skill category lists first.
	// This creates linked lists as follows: "Science" -> empty list
	for(var/singleton/skill_category/skill_category as anything in GET_SINGLETON_SUBTYPE_LIST(/singleton/skill_category))
		skill_tree[skill_category] = list()

	// Now, initialize all the skills.
	// What actually goes on here: we want a tree that we can traverse programmatically.
	// To do that, we first of all make empty lists above with all the categories (they're singletons so we can easily iterate over them).
	// Next, we add the empty subcategory lists if they're not present. At this point, the tree would look like "Combat" -> "Melee" -> empty list
	// After that's done, if our skill is not present, add it to the empty list of the subcategory.
	for(var/singleton/skill/skill as anything in GET_SINGLETON_SUBTYPE_LIST(/singleton/skill))
		all_skills += skill
		if (skill.required && skill.component_type)
			required_skills += skill
		if(skill.component_type)
			skill_for_component_type[skill.component_type] = skill
		var/singleton/skill_category/skill_category = GET_SINGLETON(skill.category)
		if(!(skill.subcategory in skill_tree[skill_category]))
			skill_tree[skill_category] |= skill.subcategory
			skill_tree[skill_category][skill.subcategory] = list()

		if(!(skill in skill_tree[skill_category][skill.subcategory]))
			skill_tree[skill_category][skill.subcategory] |= skill
	last_decay_tick = world.time
	return SS_INIT_SUCCESS

/datum/controller/subsystem/skills/Destroy()
	all_skills.Cut()
	required_skills.Cut()
	skill_for_component_type.Cut()
	return ..()

/**
 * Decay sweep -- only ever looks at currently-spawned, alive human mobs, so
 * the decay clock only advances while a character is actually being played.
 * Measured in genuine in-game time (world.time), not wall-clock: each firing
 * computes how much world.time has passed since the last one and banks that
 * delta onto every tracked component's decay_progress, so time the server
 * spends offline between sessions never counts against anyone -- see
 * skill_decay_grace_period's comment, controllers/configuration.dm. A skill
 * with no component isn't tracked at all -- nothing to decay, it's already
 * at (or below) the floor. A skill flagged no_decay (a passive stat with no
 * discrete use, or one with no gameplay consumer implemented at all -- see
 * its own doc comment, _skills.dm) is skipped outright, regardless of
 * activity -- it shouldn't be able to rot away with no way for a player to
 * earn it back through play. Grace period, interval, and floor are all
 * config.txt-tunable.
 */
/datum/controller/subsystem/skills/fire()
	var/grace_period = GLOB.config.skill_decay_grace_period
	var/interval = GLOB.config.skill_decay_interval
	var/floor = GLOB.config.skill_decay_floor
	var/delta = world.time - last_decay_tick
	last_decay_tick = world.time
	if(delta <= 0)
		return
	for(var/mob/living/carbon/human/H as anything in GLOB.human_mob_list)
		if(QDELETED(H) || H.stat == DEAD || !H.ckey)
			continue
		for(var/singleton/skill/sk as anything in all_skills)
			if(!sk.component_type || sk.no_decay)
				continue
			var/datum/component/skill/comp = H.GetComponent(sk.component_type)
			if(!comp)
				continue
			comp.decay_progress += delta
			if(comp.decay_progress < grace_period)
				continue
			var/tiers_to_drop = 1 + round((comp.decay_progress - grace_period) / interval)
			var/new_level = max(floor, comp.skill_level - tiers_to_drop)
			if(new_level >= comp.skill_level)
				continue
			var/old_level = comp.skill_level
			var/applied = set_skill_progression_level(H, sk, new_level)
			if(isnull(applied) || applied >= old_level)
				continue
			comp.decay_progress = 0
			to_chat(H, SPAN_WARNING("Your [sk.name] feels rusty from disuse -- it's slipped to [get_skill_level_name(sk, applied)]."))
