/*
 * Skill Manuals
 *
 * A cargo-orderable book that takes its one skill straight to Professional --
 * the top tier -- regardless of where the reader started, including back up
 * from the losses a resleeve inflicts. Ordering is per-skill (see
 * code/modules/cargo/items/skill_books.dm), so a crate contains exactly the
 * discipline that was paid for.
 *
 * Everyone starts Trained (the default fill, preference_setup/skills/skills.dm).
 * There are exactly two ways up from there: this, or being taught one tier at a
 * time by somebody who already holds the higher tier (Teach Skills verb). The
 * two are not redundant -- teaching needs a qualified teacher to already exist
 * on the server, so manuals are the bootstrap that seeds a discipline into the
 * population at all. That is what the price is for.
 *
 * Deliberately NOT offered for skills that cannot reach Professional (three
 * combat skills cap at Trained, pilot_mechs at Familiar) -- everyone is already
 * at those ceilings from the default fill, so a manual would either do nothing
 * or have to violate the cap. Losing one of those to a resleeve is recoverable
 * by teaching, which is the only way they can drop in the first place.
 *
 * Unlike the language primer this is modelled on, studying takes real time --
 * the primer is instant and infinitely reusable, which is fine for a tongue but
 * far too cheap for the top tier of a discipline.
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
	var/target = min(SKILL_LEVEL_PROFESSIONAL, get_skill_progression_cap(user, skill))

	// Already there -- say so rather than burning half a minute to no effect.
	if(current >= target)
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
	if(current >= target)
		to_chat(user, SPAN_NOTICE("You already know everything \the [src] has to teach about [skill.name]."))
		return TRUE

	var/applied = set_skill_progression_level(user, skill, target)
	if(isnull(applied))
		to_chat(user, SPAN_WARNING("You can't seem to make \the [src] stick."))
		return TRUE

	user.visible_message(
		SPAN_NOTICE("\The [user] closes \the [src] with the air of someone who has just understood something."),
		SPAN_GOOD("You finish \the [src]. Your [skill.name] is now [get_skill_level_name(skill, applied)].")
	)
	log_game("[key_name(user)] raised [skill.name] to [get_skill_level_name(skill, applied)] from \a [src].")
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
