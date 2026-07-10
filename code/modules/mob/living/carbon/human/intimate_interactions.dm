/*
	Intimate interaction menu scaffold.

	Drag your own mob onto another human mob to open a small interaction menu. Gated on a
	server config flag (ALLOW_INTIMATE_INTERACTIONS) and, for real players, on both
	participants individually opting in via the "Toggle Intimate Interactions" client
	preference.

	The dragger must always be a real connected player, conscious and unrestrained. The
	target may be a real player or a humanoid NPC/unpossessed body -- distinguished by
	`ckey`, not `client`, so a disconnected (SSD) player's body still requires their consent
	rather than being treated as a free-for-all NPC (see living.dm:888 for the existing
	`ckey || client` convention this follows). A real-player target must also be conscious
	and unrestrained -- a standing preference toggle is not moment-specific consent, so it
	does not waive that check. A genuinely unpossessed NPC (no ckey) has no consent to
	bypass and skips both the preference and state checks entirely.

	This is scaffolding only -- see docs/erp_interaction_port_notes.md for the follow-up
	work needed to add further actions at the EXTENSION POINT marked below.
*/

#define FUCK_CAP 40
#define MASTURBATE_CAP 30
#define FUCK_COOLDOWN (5 MINUTES)
#define EUPHORIC_RAINBOW_DURATION (25 SECONDS)

// Placeholder gendered pop sound pools -- 7 slots each, one picked at random whenever a
// male/female pop plays. All 7 currently point at the same generic pop.ogg; replace each
// slot below with its own distinct file when dedicated assets exist -- each is commented
// with its slot number so it's easy to find and swap individually.
GLOBAL_LIST_INIT(fuck_male_pops, list(
	'honk/sound/interactions/moan_m1.ogg', // male 1
	'honk/sound/interactions/moan_m2.ogg', // male 2
	'honk/sound/interactions/moan_m3.ogg', // male 3
	'honk/sound/interactions/moan_m4.ogg', // male 4
	'honk/sound/interactions/moan_m5.ogg', // male 5
	'honk/sound/interactions/moan_m6.ogg', // male 6
	'honk/sound/interactions/moan_m7.ogg', // male 7
	'sound/voice/male_moan1.ogg', // male 8
	'sound/voice/male_moan2.ogg', // male 9
	'sound/voice/male_moan3.ogg')) // male 10
GLOBAL_LIST_INIT(fuck_female_pops, list(
	'honk/sound/interactions/moan_f1.ogg', // female 1
	'honk/sound/interactions/moan_f2.ogg', // female 2
	'honk/sound/interactions/moan_f3.ogg', // female 3
	'honk/sound/interactions/moan_f4.ogg', // female 4
	'honk/sound/interactions/moan_f5.ogg', // female 5
	'honk/sound/interactions/moan_f6.ogg', // female 6
	'honk/sound/interactions/moan_f7.ogg', // female 7
	'sound/voice/female_moan1.ogg', // female 8
	'sound/voice/female_moan2.ogg', // female 9
	'sound/voice/female_moan3.ogg')) // female 10

// "Bang" pop sound pool for grab/hug beats -- picked at random per use so repeated
// grabs/hugs don't all sound identical.
GLOBAL_LIST_INIT(fuck_bang_pops, list(
	'honk/sound/interactions/bang1.ogg',
	'honk/sound/interactions/bang2.ogg',
	'honk/sound/interactions/bang3.ogg',
	'honk/sound/interactions/bang4.ogg',
	'honk/sound/interactions/bang5.ogg',
	'honk/sound/interactions/bang6.ogg'))

GLOBAL_LIST_INIT(throat_fuck_pops, list(
	'honk/sound/interactions/oral1.ogg',
	'honk/sound/interactions/oral2.ogg',
	'honk/sound/interactions/bj1.ogg',
	'honk/sound/interactions/bj2.ogg',
	'honk/sound/interactions/bj3.ogg',
	'honk/sound/interactions/bj4.ogg',
	'honk/sound/interactions/bj5.ogg',
	'honk/sound/interactions/bj6.ogg',
	'honk/sound/interactions/bj7.ogg',
	'honk/sound/interactions/bj8.ogg',
	'honk/sound/interactions/bj9.ogg',
	'honk/sound/interactions/bj10.ogg',
	'honk/sound/interactions/bj11.ogg'))

/mob/living/carbon/human/mouse_drop_receive(atom/dropped, mob/user, params)
	if(!GLOB.config.intimate_interactions_allowed)
		return

	if(!ishuman(dropped) || !ishuman(src))
		return

	if(dropped != user || src == user)
		return

	if(!user.client)
		return

	if(GLOB.config.require_consent && !(user.client.prefs.toggles_secondary & INTIMATE_INTERACTIONS_ENABLED))
		to_chat(user, SPAN_WARNING("You need to enable the 'Toggle Intimate Interactions' preference before you can do this."))
		return

	if(user.stat || user.restrained())
		return

	// A ckey means this body is or was a real player -- their consent (opt-in preference)
	// and their state (conscious, unrestrained) still apply even if they're currently SSD
	// (no client). An incapacitated real player can't withdraw or grant consent in the
	// moment, so a standing preference toggle does not waive that. Only a genuinely
	// unpossessed NPC (no ckey ever) skips both checks entirely.
	if(src.ckey)
		if(!src.client)
			return

		// Silent failure here on purpose: revealing whether a specific player has this
		// preference enabled would let people probe/out others' settings by dragging onto them.
		if(GLOB.config.require_consent && !(src.client.prefs.toggles_secondary & INTIMATE_INTERACTIONS_ENABLED))
			return

		if(src.stat || src.restrained())
			to_chat(user, SPAN_WARNING("[src] can't respond to that right now."))
			return

	open_intimate_menu(user)

/mob/living/carbon/human/proc/open_intimate_menu(mob/living/carbon/human/user)
	var/dat = "<b>Interact with [src]:</b><br/><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=supergrab;intimate_target=[REF(src)]'>Mount</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=superhug;intimate_target=[REF(src)]'>Fuck</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=throatfuck;intimate_target=[REF(src)]'>Throat fuck</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=suck;intimate_target=[REF(src)]'>Suck</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=slapass;intimate_target=[REF(src)]'>Slap ass</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=hug;intimate_target=[REF(src)]'>Hug</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=handshake;intimate_target=[REF(src)]'>Shake hands</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=wave;intimate_target=[REF(src)]'>Wave</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=bow;intimate_target=[REF(src)]'>Bow</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=pet;intimate_target=[REF(src)]'>Pat on the head</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=kiss;intimate_target=[REF(src)]'>Kiss on the cheek</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=cheer;intimate_target=[REF(src)]'>Cheer for</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=five;intimate_target=[REF(src)]'>High five</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=slap;intimate_target=[REF(src)]'>Slap</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=fuckyou;intimate_target=[REF(src)]'>Flip off</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=knock;intimate_target=[REF(src)]'>Knock on</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=spit;intimate_target=[REF(src)]'>Spit at</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=threaten;intimate_target=[REF(src)]'>Threaten</a><br/>"
	dat += "<a href='byond://?src=[REF(user)];intimate_action=tongue;intimate_target=[REF(src)]'>Stick tongue out at</a><br/>"

	// EXTENSION POINT: add further actions as additional
	// <a href='byond://?src=[REF(user)];intimate_action=xxx;intimate_target=[REF(src)]'>Label</a>
	// entries above, plus a matching case in /mob/living/carbon/human/Topic()'s "intimate_action"
	// branch (human.dm). See docs/erp_interaction_port_notes.md for the source procs and anatomy
	// checks this deliberately does not port.

	var/datum/browser/popup = new(user, "intimate_menu_[REF(src)]", "Interact with [src]", 300, 400, src)
	popup.set_content(dat)
	popup.open()

/mob/living/carbon/human/var/fuck_count = 0
/mob/living/carbon/human/var/masturbate_count = 0
/mob/living/carbon/human/var/fuck_cooldown_until = 0
/mob/living/carbon/human/var/recently_came_until = 0
/mob/living/carbon/human/var/list/fuck_recent_uses = list()
/mob/living/carbon/human/var/list/slapass_recent_uses = list()
/mob/living/carbon/human/var/mob/living/carbon/human/mounting = null // who I am currently Super Grabbing
/mob/living/carbon/human/var/mob/living/carbon/human/mounted_by = null // who is currently Super Grabbing me
/mob/living/carbon/human/var/list/recent_action_given = list() // REF(target) -> list(verb, time) of the last thing I did to them

/// TRUE if I did `verb` to `target` within the last 3 seconds -- used to pair up complementary
/// simultaneous acts (e.g. throat-fucking someone while they suck you) towards both participants'
/// counts instead of just the receiver's.
/mob/living/carbon/human/proc/gave_recently(mob/living/carbon/human/target, verb)
	var/list/entry = recent_action_given[REF(target)]
	return entry && entry[1] == verb && entry[2] >= world.time - 3 SECONDS

/mob/living/carbon/human/proc/receive_mount(mob/living/carbon/human/grabber)
	// Using Super Grab again on someone you're already Super Grabbing toggles it off.
	if(mounted_by == grabber)
		break_mount()
		visible_message(SPAN_NOTICE("[grabber] releases [src] from their mount."))
		return

	if(!grabber.Adjacent(src))
		return

	if(grabber.wear_suit || grabber.w_uniform || src.wear_suit || src.w_uniform)
		to_chat(grabber, SPAN_WARNING("You both need to be out of your suits and uniforms first."))
		return

	if(mounted_by)
		break_mount()
	mounted_by = grabber
	grabber.mounting = src
	RegisterSignal(grabber, COMSIG_MOVABLE_MOVED, PROC_REF(check_mount_adjacency))
	RegisterSignal(src, COMSIG_MOVABLE_MOVED, PROC_REF(check_mount_adjacency))
	visible_message(SPAN_NOTICE("[grabber] mounts [src]!"))
	// Placeholder pop -- swap for a dedicated "grab" sound when one exists
	playsound(src, pick(GLOB.fuck_bang_pops), rand(35, 45), TRUE)

	// Force both mobs prone -- always applied (idempotent if already resting), the "tackle"
	// flavor message only shows if they weren't already down.
	var/already_down = (grabber.resting || grabber.lying) && (src.resting || src.lying)

	grabber.resting = TRUE
	grabber.update_canmove()
	grabber.update_icon()
	SEND_SIGNAL(grabber, COMSIG_MOB_RESTED)

	src.resting = TRUE
	src.update_canmove()
	src.update_icon()
	SEND_SIGNAL(src, COMSIG_MOB_RESTED)

	if(!already_down)
		visible_message(SPAN_NOTICE("[grabber] pulls [src] tight towards them!"))

/mob/living/carbon/human/proc/check_mount_adjacency()
	if(mounted_by && !mounted_by.Adjacent(src))
		to_chat(mounted_by, SPAN_WARNING("Your mount on [src] breaks as you move apart."))
		to_chat(src, SPAN_WARNING("[mounted_by]'s mount on you breaks as you move apart."))
		break_mount()

/mob/living/carbon/human/proc/break_mount()
	if(!mounted_by)
		return
	UnregisterSignal(mounted_by, COMSIG_MOVABLE_MOVED)
	UnregisterSignal(src, COMSIG_MOVABLE_MOVED)
	mounted_by.mounting = null
	mounted_by = null

/mob/living/carbon/human/proc/receive_fuck(mob/living/carbon/human/hugger)
	// Either side of an existing mount can initiate -- they're already mounted
	// together, so a second/reverse mount isn't required for the other to fuck back.
	if(mounted_by != hugger && mounting != hugger)
		to_chat(hugger, SPAN_WARNING("You need to mount [src] before you can fuck them."))
		return

	if(hugger.wear_suit || hugger.w_uniform || src.wear_suit || src.w_uniform)
		to_chat(hugger, SPAN_WARNING("You both need to be out of your suits and uniforms first."))
		return

	if(!hugger.lying || !lying)
		to_chat(hugger, SPAN_WARNING("You both need to be lying down together to fuck."))
		return

	if(world.time < fuck_cooldown_until)
		to_chat(hugger, SPAN_WARNING("[src] has had enough fucking for now."))
		return

	for(var/i in fuck_recent_uses.len to 1 step -1)
		if(fuck_recent_uses[i] <= world.time - 3 SECONDS)
			fuck_recent_uses.Cut(i, i + 1)

	if(fuck_recent_uses.len >= 2)
		to_chat(hugger, SPAN_WARNING("[src] needs a moment to catch their breath."))
		return

	fuck_recent_uses += world.time

	visible_message(SPAN_NOTICE("[hugger] fucks [src]!"))
	// Placeholder pop #1 -- swap for a dedicated "hug squeeze" sound when one exists
	playsound(src, pick(GLOB.fuck_bang_pops), rand(35, 45), TRUE)
	// Placeholder pop #2, a tick behind the first, for a "double pop" cadence -- swap alongside pop #1
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(playsound), src, pick(GLOB.fuck_bang_pops), rand(35, 45), TRUE), 1)
	hugger.quick_jitter(3 SECONDS)

	fuck_count++
	// Already mounted together -- this is inherently mutual, so it counts towards both.
	hugger.fuck_count++

	// Every 4th hug, an extra pop plays based on the hugger's real gender. 25% of the time,
	// both the hugger's-gender and target's-gender pops play together instead, staggered --
	// if hugger and target share a gender this just plays that same placeholder twice.
	if(fuck_count % 4 == 0)
		var/hugger_pop = pick(hugger.gender == FEMALE ? GLOB.fuck_female_pops : GLOB.fuck_male_pops)
		if(prob(25))
			var/target_pop = pick(src.gender == FEMALE ? GLOB.fuck_female_pops : GLOB.fuck_male_pops)
			playsound(src, hugger_pop, 50, TRUE)
			addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(playsound), src, target_pop, 50, TRUE), 1)
		else
			playsound(src, hugger_pop, 50, TRUE)

	if(fuck_count >= FUCK_CAP)
		fuck_count = 0
		fuck_cooldown_until = world.time + FUCK_COOLDOWN
		if(hugger.gender == FEMALE && src.gender == FEMALE)
			src.recently_came_until = world.time + FUCK_COOLDOWN
			hugger.recently_came_until = world.time + FUCK_COOLDOWN
			visible_message(SPAN_DANGER("[hugger] cums together with [src]!"))
		else if(hugger.gender == FEMALE)
			src.recently_came_until = world.time + FUCK_COOLDOWN
			visible_message(SPAN_DANGER("[src] has came inside of [hugger]!"))
		else
			hugger.recently_came_until = world.time + FUCK_COOLDOWN
			visible_message(SPAN_DANGER("[hugger] has came inside of [src]!"))
		// Placeholder loud "cap reached" pop -- swap for a distinct climactic sound when one exists
		playsound(src, pick(GLOB.fuck_bang_pops), 100, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 10, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 20, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 30, TRUE)
		// Extra gendered pop on cap, based on the hugger's gender
		playsound(src, pick(hugger.gender == FEMALE ? GLOB.fuck_female_pops : GLOB.fuck_male_pops), 100, TRUE)
		var/turf/simulated/location = get_turf(src)
		if(istype(location, /turf/simulated))
			location.add_cum(src)
		hugger.apply_euphoric_rainbow()
		apply_euphoric_rainbow() // src (the target) gets it too now
		hugger.quick_jitter(10 SECONDS)
		quick_jitter(10 SECONDS)

	// Independent check for hugger's own count -- normally in lockstep with src's (since
	// mounted-together pairing above increments both every time), but kept separate in case
	// hugger had a head start from an unrelated earlier interaction.
	if(hugger.fuck_count >= FUCK_CAP)
		hugger.fuck_count = 0
		hugger.fuck_cooldown_until = world.time + FUCK_COOLDOWN
		if(src.gender == FEMALE && hugger.gender == FEMALE)
			hugger.recently_came_until = world.time + FUCK_COOLDOWN
			src.recently_came_until = world.time + FUCK_COOLDOWN
			visible_message(SPAN_DANGER("[src] cums together with [hugger]!"))
		else if(src.gender == FEMALE)
			hugger.recently_came_until = world.time + FUCK_COOLDOWN
			visible_message(SPAN_DANGER("[hugger] has came inside of [src]!"))
		else
			src.recently_came_until = world.time + FUCK_COOLDOWN
			visible_message(SPAN_DANGER("[src] has came inside of [hugger]!"))
		playsound(hugger, pick(GLOB.fuck_bang_pops), 100, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 10, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 20, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 30, TRUE)
		playsound(hugger, pick(src.gender == FEMALE ? GLOB.fuck_female_pops : GLOB.fuck_male_pops), 100, TRUE)
		var/turf/simulated/hugger_location = get_turf(hugger)
		if(istype(hugger_location, /turf/simulated))
			hugger_location.add_cum(hugger)
		src.apply_euphoric_rainbow()
		hugger.apply_euphoric_rainbow()
		quick_jitter(10 SECONDS)
		hugger.quick_jitter(10 SECONDS)

/mob/living/carbon/human/proc/receive_throat_fuck(mob/living/carbon/human/hugger)
	if(hugger.wear_suit || hugger.w_uniform || src.wear_suit || src.w_uniform)
		to_chat(hugger, SPAN_WARNING("You both need to be out of your suits and uniforms first."))
		return

	if(world.time < fuck_cooldown_until)
		to_chat(hugger, SPAN_WARNING("[src] has had enough fucking for now."))
		return

	for(var/i in fuck_recent_uses.len to 1 step -1)
		if(fuck_recent_uses[i] <= world.time - 3 SECONDS)
			fuck_recent_uses.Cut(i, i + 1)

	if(fuck_recent_uses.len >= 2)
		to_chat(hugger, SPAN_WARNING("[src] needs a moment to catch their breath."))
		return

	fuck_recent_uses += world.time

	visible_message(SPAN_NOTICE("[hugger] throat fucks [src]!"))
	playsound(src, pick(GLOB.throat_fuck_pops), rand(35, 45), TRUE)
	hugger.quick_jitter(3 SECONDS)

	// Paired with a recent "suck" the other way (69-style) -- counts towards both.
	var/mutual = src.gave_recently(hugger, "suck")
	hugger.recent_action_given[REF(src)] = list("throat_fuck", world.time)

	fuck_count++
	if(mutual)
		hugger.fuck_count++

	if(fuck_count % 4 == 0)
		playsound(src, pick(GLOB.throat_fuck_pops), 50, TRUE)

	if(fuck_count >= FUCK_CAP)
		fuck_count = 0
		fuck_cooldown_until = world.time + FUCK_COOLDOWN
		hugger.recently_came_until = world.time + FUCK_COOLDOWN
		visible_message(SPAN_DANGER("[hugger] has came down [src]'s throat!"))
		playsound(src, pick(GLOB.throat_fuck_pops), 100, TRUE)
		// Male orgasm moan on cap -- this act is specifically a male orgasm, always the male pool
		playsound(src, pick(GLOB.fuck_male_pops), 100, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 40, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 55, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 70, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 85, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 100, TRUE)
		var/turf/simulated/location = get_turf(src)
		if(istype(location, /turf/simulated))
			location.add_cum(src)
		hugger.apply_euphoric_rainbow()
		apply_euphoric_rainbow()
		hugger.quick_jitter(10 SECONDS)

	// Independent check for hugger's own count, paired here via the recent mutual "suck" --
	// hugger is on the receiving end of that, so the climax fires from src's throat-fuck.
	if(mutual && hugger.fuck_count >= FUCK_CAP)
		hugger.fuck_count = 0
		hugger.fuck_cooldown_until = world.time + FUCK_COOLDOWN
		src.recently_came_until = world.time + FUCK_COOLDOWN
		visible_message(SPAN_DANGER("[src] makes [hugger] cum!"))
		playsound(hugger, pick(GLOB.throat_fuck_pops), 100, TRUE)
		playsound(hugger, pick(GLOB.fuck_male_pops), 100, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 40, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 55, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 70, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 85, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 100, TRUE)
		var/turf/simulated/hugger_location = get_turf(hugger)
		if(istype(hugger_location, /turf/simulated))
			hugger_location.add_cum(hugger)
		src.apply_euphoric_rainbow()
		hugger.apply_euphoric_rainbow()
		src.quick_jitter(10 SECONDS)

/mob/living/carbon/human/proc/receive_suck(mob/living/carbon/human/hugger)
	if(src.gender != MALE)
		to_chat(hugger, SPAN_WARNING("[src] doesn't have anything for you to suck."))
		return

	if(hugger.wear_suit || hugger.w_uniform || src.wear_suit || src.w_uniform)
		to_chat(hugger, SPAN_WARNING("You both need to be out of your suits and uniforms first."))
		return

	if(world.time < fuck_cooldown_until)
		to_chat(hugger, SPAN_WARNING("[src] has had enough fucking for now."))
		return

	for(var/i in fuck_recent_uses.len to 1 step -1)
		if(fuck_recent_uses[i] <= world.time - 3 SECONDS)
			fuck_recent_uses.Cut(i, i + 1)

	if(fuck_recent_uses.len >= 2)
		to_chat(hugger, SPAN_WARNING("[src] needs a moment to catch their breath."))
		return

	fuck_recent_uses += world.time

	visible_message(SPAN_NOTICE("[hugger] sucks [src] off!"))
	playsound(src, pick(GLOB.throat_fuck_pops), rand(35, 45), TRUE)
	hugger.quick_jitter(3 SECONDS)

	// Paired with a recent "throat_fuck" the other way (69-style) -- counts towards both.
	var/mutual = src.gave_recently(hugger, "throat_fuck")
	hugger.recent_action_given[REF(src)] = list("suck", world.time)

	fuck_count++
	if(mutual)
		hugger.fuck_count++

	if(fuck_count % 4 == 0)
		playsound(src, pick(GLOB.throat_fuck_pops), 50, TRUE)

	if(fuck_count >= FUCK_CAP)
		fuck_count = 0
		fuck_cooldown_until = world.time + FUCK_COOLDOWN
		src.recently_came_until = world.time + FUCK_COOLDOWN
		visible_message(SPAN_DANGER("[hugger] makes [src] cum!"))
		playsound(src, pick(GLOB.throat_fuck_pops), 100, TRUE)
		// Male orgasm moan on cap -- this act is specifically a male orgasm, always the male pool
		playsound(src, pick(GLOB.fuck_male_pops), 100, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 40, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 55, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 70, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 85, TRUE)
		playsound(src, 'honk/sound/interactions/swallow.ogg', 100, TRUE)
		var/turf/simulated/location = get_turf(src)
		if(istype(location, /turf/simulated))
			location.add_cum(src)
		hugger.apply_euphoric_rainbow()
		apply_euphoric_rainbow()
		quick_jitter(10 SECONDS)

	// Independent check for hugger's own count, paired here via the recent mutual
	// "throat_fuck" -- hugger is on the receiving end of that, so the climax fires
	// from src's suck.
	if(mutual && hugger.fuck_count >= FUCK_CAP)
		hugger.fuck_count = 0
		hugger.fuck_cooldown_until = world.time + FUCK_COOLDOWN
		hugger.recently_came_until = world.time + FUCK_COOLDOWN
		visible_message(SPAN_DANGER("[src] has came down [hugger]'s throat!"))
		playsound(hugger, pick(GLOB.throat_fuck_pops), 100, TRUE)
		playsound(hugger, pick(GLOB.fuck_male_pops), 100, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 40, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 55, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 70, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 85, TRUE)
		playsound(hugger, 'honk/sound/interactions/swallow.ogg', 100, TRUE)
		var/turf/simulated/hugger_location = get_turf(hugger)
		if(istype(hugger_location, /turf/simulated))
			hugger_location.add_cum(hugger)
		src.apply_euphoric_rainbow()
		hugger.apply_euphoric_rainbow()
		hugger.quick_jitter(10 SECONDS)

/// Simple spam throttle, not tied to the climax/counter mechanic fuck/throat_fuck/suck
/// share -- slap-ass has no equivalent of that, it just needs its own rate limit.
/// Tracked on the target/receiver ("how often has this person been slapped recently"),
/// matching fuck_recent_uses' own convention.
/mob/living/carbon/human/proc/receive_slapass(mob/living/carbon/human/slapper)
	for(var/i in slapass_recent_uses.len to 1 step -1)
		if(slapass_recent_uses[i] <= world.time - 3 SECONDS)
			slapass_recent_uses.Cut(i, i + 1)

	if(slapass_recent_uses.len >= 2)
		to_chat(slapper, SPAN_WARNING("[src] needs a moment before you can do that again."))
		return

	slapass_recent_uses += world.time

	visible_message(SPAN_NOTICE("[slapper] has slapped [src]'s ass!"))
	playsound(src, 'sound/effects/interactions/slap.ogg', 25, TRUE)
	shake_animation()

/mob/living/carbon/human/verb/masturbate()
	set name = "Masturbate"
	set category = "IC"
	set hidden = TRUE

	if(!GLOB.config.intimate_interactions_allowed)
		return
	if(!client || !(client.prefs.toggles_secondary & INTIMATE_INTERACTIONS_ENABLED))
		to_chat(src, SPAN_WARNING("You need to enable the 'Toggle Intimate Interactions' preference before you can do this."))
		return
	if(stat || restrained())
		return
	if(wear_suit || w_uniform)
		to_chat(src, SPAN_WARNING("You need to be out of your suit and uniform first."))
		return
	if(world.time < fuck_cooldown_until)
		to_chat(src, SPAN_WARNING("You've had enough for now."))
		return

	visible_message(SPAN_NOTICE("[src] masturbates."), SPAN_NOTICE("You masturbate."))
	playsound(src, pick(GLOB.fuck_bang_pops), rand(35, 45), TRUE)
	quick_jitter(3 SECONDS)

	masturbate_count++

	if(masturbate_count % 4 == 0)
		playsound(src, pick(gender == FEMALE ? GLOB.fuck_female_pops : GLOB.fuck_male_pops), 50, TRUE)

	if(masturbate_count >= MASTURBATE_CAP)
		masturbate_count = 0
		fuck_cooldown_until = world.time + FUCK_COOLDOWN
		recently_came_until = world.time + FUCK_COOLDOWN
		visible_message(SPAN_DANGER("[src] cums!"))
		playsound(src, pick(GLOB.fuck_bang_pops), 100, TRUE)
		playsound(src, pick(gender == FEMALE ? GLOB.fuck_female_pops : GLOB.fuck_male_pops), 100, TRUE)
		var/turf/simulated/location = get_turf(src)
		if(istype(location, /turf/simulated))
			location.add_cum(src)
		apply_euphoric_rainbow()
		quick_jitter(10 SECONDS)

/mob/living/carbon/human/proc/apply_euphoric_rainbow()
	overlay_fullscreen("euphoric_rainbow", /atom/movable/screen/fullscreen/euphoric_rainbow, null, 0)
	var/atom/movable/screen/fullscreen/euphoric_rainbow/screen = screens["euphoric_rainbow"]
	if(screen)
		animate(screen, color = "#FF7F00", time = 7 SECONDS, loop = -1)
		animate(color = "#FFFF00", time = 7 SECONDS)
		animate(color = "#00FF00", time = 7 SECONDS)
		animate(color = "#00FFFF", time = 7 SECONDS)
		animate(color = "#0000FF", time = 7 SECONDS)
		animate(color = "#8F00FF", time = 7 SECONDS)
		animate(color = "#FF0000", time = 7 SECONDS)
	audio_lag_until = world.time + EUPHORIC_RAINBOW_DURATION
	addtimer(CALLBACK(src, PROC_REF(clear_euphoric_rainbow)), EUPHORIC_RAINBOW_DURATION, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_DELETE_ME)

/mob/living/carbon/human/proc/clear_euphoric_rainbow()
	clear_fullscreen("euphoric_rainbow", 1.5 SECONDS)
	audio_lag_until = 0
