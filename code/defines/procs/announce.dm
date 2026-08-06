/var/datum/announcement/priority/priority_announcement
/var/datum/announcement/priority/command/command_announcement

/datum/announcement
	var/title = "Attention"
	var/announcer = ""
	var/log = FALSE
	var/sound
	var/newscast = FALSE
	var/print = FALSE
	var/channel_name = "Announcements"
	var/announcement_type = "Announcement"

/datum/announcement/New(var/do_log = TRUE, var/new_sound = null, var/do_newscast = FALSE, var/do_print = FALSE)
	sound = new_sound
	log = do_log
	newscast = do_newscast
	print = do_print

/datum/announcement/priority/New(var/do_log = TRUE, var/new_sound = 'sound/ai/announcements/notice.ogg', var/do_newscast = TRUE, var/do_print = FALSE)
	..(do_log, new_sound, do_newscast, do_print)
	title = "Priority Announcement"
	announcement_type = "Priority Announcement"

/datum/announcement/priority/command/New(var/do_log = TRUE, var/new_sound = 'sound/ai/announcements/notice.ogg', var/do_newscast = FALSE, var/do_print = FALSE)
	..(do_log, new_sound, do_newscast, do_print)
	title = "[SSatlas.current_map.boss_name] Update"
	announcement_type = "[SSatlas.current_map.boss_name] Update"

/datum/announcement/priority/security/New(var/do_log = TRUE, var/new_sound = 'sound/ai/announcements/notice.ogg', var/do_newscast = TRUE, var/do_print = FALSE)
	..(do_log, new_sound, do_newscast, do_print)
	title = "Security Announcement"
	announcement_type = "Security Announcement"

/datum/announcement/proc/Announce(var/message, var/new_title = "", var/new_sound = null, var/do_newscast = newscast, var/msg_sanitized = 0, var/do_print = FALSE, var/zlevels = SSatlas.current_map.contact_levels)
	if(!message)
		return
	var/message_title = length(new_title) ? new_title : title
	var/message_sound = new_sound ? new_sound : sound

	if(!msg_sanitized)
		message = sanitize(message, extra = 0)
		message_title = sanitizeSafe(message_title)

	var/msg = FormMessage(message, message_title)
	for(var/mob/M in GLOB.player_list)
		if(isnewplayer(M))
			continue

		// Due to spam, only print announcements if the ghost is in the matching z-level, OR if it's a Horizon message.
		if((isghost(M) && ((zlevels == SSatlas.current_map.contact_levels) || (GET_Z(M) in zlevels))) || (!isdeaf(M) && (GET_Z(M) in zlevels)))
			var/turf/T = get_turf(M)
			if(T)
				to_chat(M, msg)
				if(message_sound && !isdeaf(M) && (M.client?.prefs.sfx_toggles & ASFX_VOX))
					sound_to(M, message_sound)

	if(do_newscast && zlevels == SSatlas.current_map.contact_levels)
		NewsCast(message, message_title)
	if(do_print && zlevels == SSatlas.current_map.contact_levels)
		post_comm_message(message_title, message)
	Log(message, message_title)

/datum/announcement/proc/FormMessage(var/message, var/message_title)
	. = "<h2 class='alert'>[message_title]</h2>"
	. += "<br><span class='alert'>[message]</span>"
	if (announcer)
		. += "<br><span class='alert'> -[html_encode(announcer)]</span>"

/datum/announcement/minor/FormMessage(var/message, var/message_title)
	. = "<b>[message]</b>"

/datum/announcement/priority/command/FormMessage(var/message, var/message_title)
	. = "<h2 class='alert'>[SSatlas.current_map.boss_name] Update</h2>"
	if (message_title)
		. += "<h3 class='alert'>[message_title]</h3>"

	. += "<br><span class='alert'>[message]</span><br>"
	. += "<br>"

/datum/announcement/priority/security/FormMessage(var/message, var/message_title)
	. = "<font size=4 color='red'>[message_title]</font>"
	. += "<br><span class='warning'>[message]</span>"

/datum/announcement/proc/NewsCast(message as text, message_title as text)
	if(!newscast)
		return

	var/datum/news_announcement/news = new
	news.channel_name = channel_name
	news.author = announcer
	news.message = message
	news.message_type = announcement_type
	news.can_be_redacted = 0
	announce_newscaster_news(news)

/datum/announcement/proc/Log(message as text, message_title as text)
	if(log)
		log_say("[key_name(usr)] has made \a [announcement_type]: [message_title] - [message] - [announcer]")
		message_admins("[key_name_admin(usr)] has made \a [announcement_type].", 1)

/// Plays sound to every non-deaf client with the announcer voice preference
/// enabled -- mirrors the exact gating Announce() uses above, for to_world()
/// broadcasts (e.g. persistence save notices) that have no sound support of
/// their own.
/proc/play_announcer_voice_to_all(sound_path)
	for(var/mob/M in GLOB.player_list)
		if(isnewplayer(M) || isdeaf(M))
			continue
		if(M.client?.prefs.sfx_toggles & ASFX_ANNOUNCER)
			play_announcer_sound(M, sound_path)

/client/var/list/announcer_queue = list()
/client/var/announcer_free_at = 0
/// Bumped on every dispatch (immediate or queued) onto CHANNEL_ANNOUNCER --
/// each scheduled _dispatch_next_announcer_sound() callback is stamped with
/// the value at the time it was scheduled, and no-ops if it no longer
/// matches by the time it fires. Needed because
/// play_announcer_sound_priority() can jump the channel ahead of whatever
/// was already playing/scheduled; without this, that earlier sound's own
/// still-pending dispatch timer would fire on schedule and cut the priority
/// sound off early.
/client/var/announcer_seq = 0

/// Single entry point for every ASFX_ANNOUNCER-gated voice line. Plays
/// immediately on the shared CHANNEL_ANNOUNCER if free, otherwise queues --
/// prevents two announcer lines from overlapping for the same listener.
/// Callers keep doing their own ASFX_ANNOUNCER/ear_deaf gating beforehand;
/// this only owns delivery + queuing. Durations come from
/// announcer_sound_durations (_announcer_sound_durations.dm, auto-generated
/// by scripts/voicegen/build_bookended_lines.py) -- falls back to a safe
/// default if a sound was added to a call site before the manifest was
/// regenerated for it.
///
/// supersede_key: when non-null, any OTHER not-yet-played queue entry
/// sharing this key is dropped before this one is added/played -- for
/// readouts where only the latest state is ever worth hearing (shield tier
/// crossings, ship_shield_generator.dm), so a fast run of crossings can't
/// leave several stale announcements queued back to back. Leave null for
/// anything where order/completeness matters (e.g. personal confirmations).
/proc/play_announcer_sound(mob/M, sound_path, volume = 50, supersede_key = null)
	if(!M.client)
		return
	if(supersede_key)
		for(var/i in 1 to LAZYLEN(M.client.announcer_queue))
			var/list/queued = M.client.announcer_queue[i]
			if(length(queued) >= 3 && queued[3] == supersede_key)
				M.client.announcer_queue.Cut(i, i + 1)
				break
	var/duration = GLOB.announcer_sound_durations["[sound_path]"] || 3 SECONDS
	if(M.client.announcer_free_at <= world.time)
		M << sound(sound_path, volume = volume, channel = CHANNEL_ANNOUNCER)
		M.client.announcer_free_at = world.time + duration
		M.client.announcer_seq++
		addtimer(CALLBACK(M.client, TYPE_PROC_REF(/client, _dispatch_next_announcer_sound), M.client.announcer_seq), duration)
	else
		LAZYADD(M.client.announcer_queue, list(list(sound_path, volume, supersede_key)))

/**
 * For personal confirmations that are a direct response to something the
 * player just did (boarding, disembarking, drydock retrieve/stash) and
 * must be heard right at that moment -- this ignores the polite FIFO
 * queue entirely and plays immediately on
 * CHANNEL_ANNOUNCER, replacing whatever's currently playing there for this
 * client. This exists because forceMove()-triggered automatic cues (e.g.
 * the zone-security tier announcement, persistence_zone_security.dm) can
 * otherwise win the channel a split second earlier and push a boarding/
 * exiting confirmation into the queue for several more seconds -- long
 * after the portal/spool-up moment it's meant to mark.
 *
 * Bumps announcer_seq so the now-superseded dispatch timer from whatever
 * was previously playing/queued no-ops instead of firing later and cutting
 * this off early -- see that var's own doc comment above.
 */
/proc/play_announcer_sound_priority(mob/M, sound_path, volume = 50)
	if(!M?.client || M.ear_deaf)
		return
	if(!(M.client.prefs.sfx_toggles & ASFX_ANNOUNCER))
		return
	var/duration = GLOB.announcer_sound_durations["[sound_path]"] || 3 SECONDS
	M << sound(sound_path, volume = volume, channel = CHANNEL_ANNOUNCER)
	M.client.announcer_free_at = world.time + duration
	M.client.announcer_seq++
	addtimer(CALLBACK(M.client, TYPE_PROC_REF(/client, _dispatch_next_announcer_sound), M.client.announcer_seq), duration)

/// Pops and plays the next queued announcer sound for this client, if any --
/// scheduled by play_announcer_sound()/play_announcer_sound_priority() to
/// fire exactly when the previously playing line's duration elapses. No-op
/// if seq no longer matches announcer_seq -- a later priority dispatch
/// superseded this one before it got the chance to fire.
/client/proc/_dispatch_next_announcer_sound(seq)
	if(seq != announcer_seq)
		return
	if(!LAZYLEN(announcer_queue))
		return
	var/list/next = announcer_queue[1]
	announcer_queue.Cut(1, 2)
	var/duration = GLOB.announcer_sound_durations["[next[1]]"] || 3 SECONDS
	mob << sound(next[1], volume = next[2], channel = CHANNEL_ANNOUNCER)
	announcer_free_at = world.time + duration
	announcer_seq++
	addtimer(CALLBACK(src, TYPE_PROC_REF(/client, _dispatch_next_announcer_sound), announcer_seq), duration)

/proc/GetNameAndAssignmentFromId(var/obj/item/card/id/I)
	if(!I)
		return "Unknown"
	// Format currently matches that of newscaster feeds: Registered Name (Assigned Rank)
	return I.assignment ? "[I.registered_name], [I.assignment]" : I.registered_name

/proc/level_seven_announcement(var/list/affecting_z = list())
	if(!length(affecting_z))
		affecting_z += SSmapping.levels_by_trait(ZTRAIT_STATION)

	command_announcement.Announce("Confirmed outbreak of level 7 biohazard aboard [station_name()]. All personnel must contain the outbreak.", "Biohazard Alert", new_sound = 'sound/AI/level_7_biohazard.ogg', zlevels = affecting_z)

/proc/ion_storm_announcement(var/list/affecting_z = list())
	if(!length(affecting_z))
		affecting_z += SSmapping.levels_by_trait(ZTRAIT_STATION)

	command_announcement.Announce("It has come to our attention that the ship has passed through an ion storm.  Please monitor all electronic equipment for malfunctions.", "Anomaly Alert", zlevels = affecting_z)

/proc/AnnounceArrival(var/mob/living/carbon/human/character, var/rank, var/join_message)
	if(SSticker.current_state == GAME_STATE_PLAYING)
		if(character.mind.role_alt_title)
			rank = character.mind.role_alt_title
		AnnounceArrivalSimple(character.real_name, rank, join_message)

/proc/AnnounceArrivalSimple(var/name, var/rank = "visitor", var/join_message = "has arrived on the [SSatlas.current_map.station_type]", var/new_sound = 'sound/ai/announcements/notice.ogg')
	GLOB.global_announcer.autosay("[name], [rank], [join_message].", "Arrivals Announcer")
