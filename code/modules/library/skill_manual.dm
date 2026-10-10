/*
 * Skill Manuals
 *
 * A cargo-orderable book that raises its one skill by exactly ONE tier --
 * the same amount a qualified teacher gives in one session (Teach Skills
 * verb, skill_verbs.dm's min(their_level + 1, my_level)) -- then is
 * consumed. Refuses (and is NOT consumed) if the reader is already at that
 * skill's own ceiling. Ordering is per-skill (see
 * code/modules/cargo/items/skill_books.dm), so a crate contains exactly the
 * discipline that was paid for.
 *
 * Everyone starts Trained (the default fill, preference_setup/skills/skills.dm).
 * There are three ways up from there: this, being taught one tier at a time by
 * somebody who already holds a higher tier (Teach Skills verb), or slow
 * practice (register_use(), skill_component.dm -- doing the thing the skill
 * governs). Manuals and teaching are both instant but consumable/dependent on
 * another player; practice is free but slow. None are redundant.
 *
 * Every skill has one, even pilot_spacecraft (capped at Familiar, the same as
 * the default fill -- reading it does nothing today, but it's harmless and
 * keeps the catalogue uniform). Losing a skill to a resleeve is recoverable by
 * teaching or practice, which are the only ways it can drop in the first place
 * (that, and decay from prolonged disuse -- skills.dm's fire()).
 *
 * Unlike the language primer this is modelled on, studying takes real time --
 * the primer is instant and infinitely reusable, which is fine for a tongue but
 * far too cheap for even one tier of a discipline.
 */

/// How long studying a manual takes.
#define SKILL_MANUAL_STUDY_TIME (30 SECONDS)

/obj/item/book/skill_manual
	name = "skill manual"
	desc = "A dense professional-certification manual. Hard going, but it covers everything."
	icon_state = "book"
	item_state = "book"
	/// The /singleton/skill typepath this manual teaches. Set on each subtype.
	var/taught_skill

/obj/item/book/skill_manual/Initialize()
	. = ..()
	if(!taught_skill)
		return
	var/singleton/skill/skill = GET_SINGLETON(taught_skill)
	if(istype(skill))
		name = "[initial(name)] ([skill.name])"
		desc = "A professional-certification manual in [skill.name]. Hard going, but it covers everything."

/obj/item/book/skill_manual/attack_self(mob/user)
	if(!taught_skill)
		return ..()
	if(!ishuman(user))
		to_chat(user, SPAN_WARNING("You can't make sense of \the [src]."))
		return TRUE

	var/singleton/skill/skill = GET_SINGLETON(taught_skill)
	if(!istype(skill))
		return ..()

	var/current = get_skill_progression_level(user, skill)
	var/cap = get_skill_progression_cap(user, skill)
	var/target = min(current + 1, cap)

	// Already at the ceiling -- refuse outright, don't burn the book or the
	// reader's time for a raise that can't happen.
	if(current >= cap)
		to_chat(user, SPAN_NOTICE("You already know everything \the [src] has to teach about [skill.name]."))
		return TRUE

	user.visible_message(
		SPAN_NOTICE("\The [user] settles down to study \the [src]."),
		SPAN_NOTICE("You begin studying \the [src]. This will take a while.")
	)
	if(!do_after(user, SKILL_MANUAL_STUDY_TIME, src))
		to_chat(user, SPAN_WARNING("You lose your place in \the [src]."))
		return TRUE

	// Re-check: the study window is long enough that something else could have
	// raised this skill in the meantime.
	current = get_skill_progression_level(user, skill)
	cap = get_skill_progression_cap(user, skill)
	if(current >= cap)
		to_chat(user, SPAN_NOTICE("You already know everything \the [src] has to teach about [skill.name]."))
		return TRUE
	target = min(current + 1, cap)

	var/applied = set_skill_progression_level(user, skill, target)
	if(isnull(applied) || applied <= current)
		to_chat(user, SPAN_WARNING("You can't seem to make \the [src] stick."))
		return TRUE

	// Resets progress to exactly 0 (skill_component.dm) -- no carryover
	// either direction, same reasoning Teach Skills uses (skill_verbs.dm).
	var/datum/component/skill/comp = user.GetComponent(skill.component_type)
	if(comp)
		comp.training_progress = 0
		comp.used_since_last_decay_tick = TRUE

	user.visible_message(
		SPAN_NOTICE("\The [user] closes \the [src] with the air of someone who has just understood something."),
		SPAN_GOOD("You finish \the [src]. Your [skill.name] is now [get_skill_level_name(skill, applied)].")
	)
	log_game("[key_name(user)] raised [skill.name] to [get_skill_level_name(skill, applied)] from \a [src].")
	qdel(src)
	return TRUE

// ---- Everyday ----

/obj/item/book/skill_manual/bartending
	taught_skill = /singleton/skill/bartending

/obj/item/book/skill_manual/cooking
	taught_skill = /singleton/skill/cooking

/obj/item/book/skill_manual/gardening
	taught_skill = /singleton/skill/gardening

/obj/item/book/skill_manual/carousing
	taught_skill = /singleton/skill/carousing

/obj/item/book/skill_manual/ministry
	taught_skill = /singleton/skill/ministry

// ---- Combat ----

/obj/item/book/skill_manual/unarmed_combat
	taught_skill = /singleton/skill/unarmed_combat

/obj/item/book/skill_manual/armed_combat
	taught_skill = /singleton/skill/armed_combat

/obj/item/book/skill_manual/firearms
	taught_skill = /singleton/skill/firearms

/obj/item/book/skill_manual/leadership
	taught_skill = /singleton/skill/leadership

/obj/item/book/skill_manual/tenacity
	taught_skill = /singleton/skill/tenacity

// ---- Engineering ----

/obj/item/book/skill_manual/electrical_engineering
	taught_skill = /singleton/skill/electrical_engineering

/obj/item/book/skill_manual/mechanical_engineering
	taught_skill = /singleton/skill/mechanical_engineering

/obj/item/book/skill_manual/atmospherics_systems
	taught_skill = /singleton/skill/atmospherics_systems

/obj/item/book/skill_manual/reactor_systems
	taught_skill = /singleton/skill/reactor_systems

// ---- Medical ----

/obj/item/book/skill_manual/medicine
	taught_skill = /singleton/skill/medicine

/obj/item/book/skill_manual/surgery
	taught_skill = /singleton/skill/surgery

/obj/item/book/skill_manual/pharmacology
	taught_skill = /singleton/skill/pharmacology

/obj/item/book/skill_manual/anatomy
	taught_skill = /singleton/skill/anatomy

/obj/item/book/skill_manual/forensics
	taught_skill = /singleton/skill/forensics

// ---- Operations ----

/obj/item/book/skill_manual/robotics
	taught_skill = /singleton/skill/robotics

/obj/item/book/skill_manual/pilot_spacecraft
	taught_skill = /singleton/skill/pilot_spacecraft

/obj/item/book/skill_manual/pilot_mechs
	taught_skill = /singleton/skill/pilot_mechs

// ---- Science ----

/obj/item/book/skill_manual/research
	taught_skill = /singleton/skill/research

/obj/item/book/skill_manual/xenobotany
	taught_skill = /singleton/skill/xenobotany

/obj/item/book/skill_manual/archaeology
	taught_skill = /singleton/skill/archaeology

/obj/item/book/skill_manual/xenobiology
	taught_skill = /singleton/skill/xenobiology

#undef SKILL_MANUAL_STUDY_TIME
