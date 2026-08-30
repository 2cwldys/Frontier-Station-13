/*
 * Player-facing skill verbs: Check Skills (see where you stand) and Teach
 * Skills (pass a tier on to somebody standing next to you).
 *
 * Both are ordinary mob verbs rather than admin verbs -- they sit under the
 * Persistence tab but are deliberately NOT gated behind check_rights(), since
 * the whole progression loop is a player activity. See skill_progression.dm for
 * the shared mutation helpers and the two traps they exist to avoid.
 */

/// How long a teaching session takes. Both parties are held in place for it.
#define SKILL_TEACH_TIME (30 SECONDS)

/mob/living/carbon/human/verb/check_skills()
	set name = "Check Skills"
	set category = "Persistence.Characters"
	set desc = "Review your current proficiency in every skill."

	if(!SSskills || !length(SSskills.all_skills))
		to_chat(src, SPAN_WARNING("Skill data is not available right now."))
		return

	// Bucketed by category so the readout matches how the skills are organised
	// everywhere else, rather than dumping 29 lines in singleton order.
	var/list/by_category = list()
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		var/singleton/skill_category/cat = sk.category ? GET_SINGLETON(sk.category) : null
		var/cat_name = istype(cat) ? cat.name : "Other"
		if(!by_category[cat_name])
			by_category[cat_name] = list()
		var/level = get_skill_progression_level(src, sk)
		var/cap = get_skill_progression_cap(src, sk)
		var/line = "[sk.name]: [SPAN_BOLD(get_skill_level_name(sk, level))]"
		// Flagging the ceiling matters here -- a few skills cannot reach
		// Professional at all, so without this their owner would reasonably
		// assume a manual or a teacher could still take them higher.
		if(level >= cap)
			line += " <i>(at maximum)</i>"
		else if(!sk.no_decay)
			// no_decay doubles as "no register_use() hook exists for this
			// skill at all" (skill_component.dm) -- skip the percentage for
			// those rather than show a permanently-stuck, meaningless 0%.
			var/datum/component/skill/comp = src.GetComponent(sk.component_type)
			var/needed = GLOB.config.skill_train_progress_needed
			var/progress_percent = (comp && needed > 0) ? round(100 * comp.training_progress / needed) : 0
			line += " <i>([SPAN_BOLD("[progress_percent]%")] to next tier)</i>"
		by_category[cat_name] += line

	var/list/out = list(SPAN_NOTICE(FONT_LARGE("Your skills:")))
	for(var/cat_name in by_category)
		out += SPAN_BOLD("[cat_name]")
		for(var/line in by_category[cat_name])
			out += "&nbsp;&nbsp;[line]"
	out += SPAN_NOTICE("Professional is reached by studying a skill manual, or by being taught it one tier at a time.")
	to_chat(src, jointext(out, "<br>"))

/mob/living/carbon/human/verb/teach_skills()
	set name = "Teach Skills"
	set category = "Persistence.Characters"
	set desc = "Teach one of your skills to somebody standing next to you."

	if(!SSskills || !length(SSskills.all_skills))
		to_chat(src, SPAN_WARNING("Skill data is not available right now."))
		return
	if(incapacitated())
		to_chat(src, SPAN_WARNING("You're in no state to teach anyone anything."))
		return

	// Adjacency, not a global picker -- teaching is meant to be a physical,
	// in-person act, and the session below holds both parties still anyway.
	var/list/candidates = list()
	for(var/mob/living/carbon/human/H in range(1, src))
		if(H == src || !H.client || H.stat != CONSCIOUS)
			continue
		candidates[H.name] = H
	if(!length(candidates))
		to_chat(src, SPAN_WARNING("There's nobody beside you to teach."))
		return

	var/mob/living/carbon/human/student
	if(length(candidates) == 1)
		student = candidates[candidates[1]]
	else
		var/pick = tgui_input_list(src, "Teach who?", "Teach Skills", candidates)
		if(!pick)
			return
		student = candidates[pick]
	if(!istype(student) || !Adjacent(student))
		return

	// Only offer skills where there is genuinely a gap to close: the teacher
	// must be strictly above the student, and the student must not already be
	// at their own ceiling for it.
	var/list/teachable = list()
	for(var/singleton/skill/sk as anything in SSskills.all_skills)
		var/my_level = get_skill_progression_level(src, sk)
		var/their_level = get_skill_progression_level(student, sk)
		if(my_level <= their_level)
			continue
		if(their_level >= get_skill_progression_cap(student, sk))
			continue
		teachable["[sk.name] ([get_skill_level_name(sk, their_level)] -> [get_skill_level_name(sk, their_level + 1)])"] = sk

	// Nothing to pass on -- tell BOTH of them, so the student isn't left
	// wondering whether the teacher simply never started.
	if(!length(teachable))
		to_chat(src, SPAN_WARNING("You have nothing left to teach [student]."))
		to_chat(student, SPAN_WARNING("[src] has nothing left to teach you."))
		return

	var/skill_pick = tgui_input_list(src, "Teach which skill?", "Teach Skills", teachable)
	if(!skill_pick)
		return
	var/singleton/skill/skill = teachable[skill_pick]
	if(!istype(skill) || !Adjacent(student))
		return

	if(tgui_alert(student, "[src] offers to teach you [skill.name]. This will take [SKILL_TEACH_TIME / 10] seconds, and neither of you may move.", "Teach Skills", list("Accept", "Decline")) != "Accept")
		to_chat(src, SPAN_WARNING("[student] declines your instruction."))
		to_chat(student, SPAN_NOTICE("You decline the lesson."))
		return
	if(!Adjacent(student))
		to_chat(src, SPAN_WARNING("[student] is no longer beside you."))
		return

	src.visible_message(
		SPAN_NOTICE("\The [src] begins instructing \the [student] in [skill.name]."),
		SPAN_NOTICE("You begin teaching \the [student] [skill.name]. Hold still.")
	)
	to_chat(student, SPAN_NOTICE("You begin learning [skill.name] from \the [src]. Hold still."))

	// DO_DEFAULT deliberately omits DO_USER_CAN_MOVE and DO_TARGET_CAN_MOVE --
	// those flags are permissive, so leaving them off is what pins BOTH the
	// teacher and the student for the whole session, per design.
	if(!do_after(src, SKILL_TEACH_TIME, student))
		to_chat(src, SPAN_WARNING("The lesson is interrupted."))
		to_chat(student, SPAN_WARNING("The lesson is interrupted."))
		return

	// Re-check everything after the session: half a minute is long enough for
	// either party's skills to have moved, or for a manual to have beaten us.
	var/my_level = get_skill_progression_level(src, skill)
	var/their_level = get_skill_progression_level(student, skill)
	if(my_level <= their_level || their_level >= get_skill_progression_cap(student, skill))
		to_chat(src, SPAN_WARNING("You have nothing left to teach [student] about [skill.name]."))
		to_chat(student, SPAN_WARNING("[src] has nothing left to teach you about [skill.name]."))
		return

	// One tier per session, and never past the teacher's own level -- so a
	// Professional can eventually bring somebody all the way up, but only one
	// session at a time.
	var/applied = set_skill_progression_level(student, skill, min(their_level + 1, my_level))
	if(isnull(applied))
		to_chat(src, SPAN_WARNING("The lesson doesn't seem to take."))
		return

	// Being taught counts as reinforcement, same as reading a manual --
	// resets the decay clock (skill_component.dm).
	var/datum/component/skill/comp = student.GetComponent(skill.component_type)
	if(comp)
		comp.decay_progress = 0

	to_chat(src, SPAN_GOOD("You finish teaching \the [student]. Their [skill.name] is now [get_skill_level_name(skill, applied)]."))
	to_chat(student, SPAN_GOOD("You finish learning from \the [src]. Your [skill.name] is now [get_skill_level_name(skill, applied)]."))
	log_game("[key_name(src)] taught [key_name(student)] [skill.name] to [get_skill_level_name(skill, applied)].")

#undef SKILL_TEACH_TIME
