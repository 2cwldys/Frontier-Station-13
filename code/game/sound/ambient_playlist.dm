/*
 * Ambient Music Playlist
 * A continuous, shuffled, no-immediate-repeat background music playlist that
 * plays while a player is in the round. Concept ported from a GMod/Helix
 * codebase (not portable code -- only the track files and playback concept
 * transferred). Plays one track at a time and schedules the next when the
 * current one is expected to finish -- the same shape /area/proc/play_ambience()
 * and /area/proc/play_music() (game/area/areas.dm) already use for their own
 * music/ambience sounds, which never freeze.
 *
 * An earlier version of this system pre-queued the whole ~20-track batch at
 * once via wait=TRUE chaining (BYOND auto-advance). That was the one
 * structural difference between this system and every other large-media
 * playback in the codebase, and the freeze it caused at first play could not
 * be fixed by any amount of server-side timing/pacing, preloading, or
 * file-format changes -- only dropping the batch entirely resolved it.
 */

GLOBAL_LIST_INIT(ambient_playlist_tracks, list(
	'sound/music/ambient_playlist/ager_sonus_through_the_desert.ogg',
	'sound/music/ambient_playlist/alien_isolation_derelict_approach.ogg',
	'sound/music/ambient_playlist/atrium_carceri_from_chasms_reborn.ogg',
	'sound/music/ambient_playlist/atrium_carceri_surfacing.ogg',
	'sound/music/ambient_playlist/atrium_carceri_third_from_the_centre.ogg',
	'sound/music/ambient_playlist/codecay.ogg',
	'sound/music/ambient_playlist/depeche_mode_introspectre.ogg',
	'sound/music/ambient_playlist/desiderii_marginis_beyond_retrieval.ogg',
	'sound/music/ambient_playlist/fear2_city_ambience.ogg',
	'sound/music/ambient_playlist/foundation_hope_troubled_herd_crawling.ogg',
	'sound/music/ambient_playlist/incantation.ogg',
	'sound/music/ambient_playlist/kammarheit_the_hierophant.ogg',
	'sound/music/ambient_playlist/resident_evil_remake_contaminated.ogg',
	'sound/music/ambient_playlist/solarhums.ogg',
	'sound/music/ambient_playlist/space_empires_iv_track1.ogg',
	'sound/music/ambient_playlist/space_empires_v_main13.ogg',
	'sound/music/ambient_playlist/spiritual_front_overture_for_castration.ogg',
	'sound/music/ambient_playlist/ss13_endless_space.ogg',
	'sound/music/ambient_playlist/thief_deadly_shadows_old_quarter.ogg',
	'sound/music/ambient_playlist/thomas_bangalter_rectum.ogg',
	'sound/music/ambient_playlist/spookyspace1.ogg',
	'sound/music/ambient_playlist/spookyspace2.ogg',
	'sound/music/ambient_playlist/ops1.ogg',
	'sound/music/ambient_playlist/orbital_deck1.ogg',
	'sound/music/ambient_playlist/NEambi.ogg',
	'sound/music/ambient_playlist/arrivals.ogg',
	'sound/music/ambient_playlist/eve_nouvelle_rouvenor_hero.ogg',
	'sound/music/ambient_playlist/amongst_allies.ogg',
	'sound/music/ambient_playlist/but_still_we_go_on.ogg',
	'sound/music/ambient_playlist/eve_my_other_residency.ogg',
	'sound/music/ambient_playlist/eve_lost_wormhole.ogg',
	'sound/music/ambient_playlist/eve_forsaken_ruins.ogg',
	'sound/music/ambient_playlist/eve_object_almost_accomplished.ogg',
	'sound/music/ambient_playlist/hellsirens.ogg',
))

/// Duration of each track in deciseconds, buffered a few deciseconds short so
/// the next track's timer always fires before the current one truly ends --
/// sending a new sound() to the same channel replaces whatever is playing on
/// it, so firing a touch early just means a clean cut, never a silent gap.
GLOBAL_LIST_INIT(ambient_playlist_durations, list(
	'sound/music/ambient_playlist/ager_sonus_through_the_desert.ogg' = 3901,
	'sound/music/ambient_playlist/alien_isolation_derelict_approach.ogg' = 1555,
	'sound/music/ambient_playlist/atrium_carceri_from_chasms_reborn.ogg' = 2561,
	'sound/music/ambient_playlist/atrium_carceri_surfacing.ogg' = 1646,
	'sound/music/ambient_playlist/atrium_carceri_third_from_the_centre.ogg' = 1696,
	'sound/music/ambient_playlist/codecay.ogg' = 1962,
	'sound/music/ambient_playlist/depeche_mode_introspectre.ogg' = 1031,
	'sound/music/ambient_playlist/desiderii_marginis_beyond_retrieval.ogg' = 5123,
	'sound/music/ambient_playlist/fear2_city_ambience.ogg' = 717,
	'sound/music/ambient_playlist/foundation_hope_troubled_herd_crawling.ogg' = 2907,
	'sound/music/ambient_playlist/incantation.ogg' = 655,
	'sound/music/ambient_playlist/kammarheit_the_hierophant.ogg' = 4421,
	'sound/music/ambient_playlist/resident_evil_remake_contaminated.ogg' = 3036,
	'sound/music/ambient_playlist/solarhums.ogg' = 344,
	'sound/music/ambient_playlist/space_empires_iv_track1.ogg' = 912,
	'sound/music/ambient_playlist/space_empires_v_main13.ogg' = 1803,
	'sound/music/ambient_playlist/spiritual_front_overture_for_castration.ogg' = 1996,
	'sound/music/ambient_playlist/ss13_endless_space.ogg' = 2135,
	'sound/music/ambient_playlist/thief_deadly_shadows_old_quarter.ogg' = 2588,
	'sound/music/ambient_playlist/thomas_bangalter_rectum.ogg' = 3829,
	'sound/music/ambient_playlist/spookyspace1.ogg' = 980,
	'sound/music/ambient_playlist/spookyspace2.ogg' = 990,
	'sound/music/ambient_playlist/ops1.ogg' = 2270,
	'sound/music/ambient_playlist/orbital_deck1.ogg' = 510,
	'sound/music/ambient_playlist/NEambi.ogg' = 2030,
	'sound/music/ambient_playlist/arrivals.ogg' = 210,
	'sound/music/ambient_playlist/eve_nouvelle_rouvenor_hero.ogg' = 2705,
	'sound/music/ambient_playlist/amongst_allies.ogg' = 3358,
	'sound/music/ambient_playlist/but_still_we_go_on.ogg' = 4895,
	'sound/music/ambient_playlist/eve_my_other_residency.ogg' = 2201,
	'sound/music/ambient_playlist/eve_lost_wormhole.ogg' = 3246,
	'sound/music/ambient_playlist/eve_forsaken_ruins.ogg' = 3665,
	'sound/music/ambient_playlist/eve_object_almost_accomplished.ogg' = 4615,
	'sound/music/ambient_playlist/hellsirens.ogg' = 4680,
))

/// Fallback duration (deciseconds, ~3 minutes) used only if a track is
/// somehow missing from ambient_playlist_durations -- keeps the chain alive
/// rather than silently stalling forever.
#define AMBIENT_PLAYLIST_FALLBACK_DURATION 1800

/client/var/ambient_playlist_last_track
/client/var/ambient_playlist_running = FALSE
/client/var/ambient_playlist_next_track_timer_id

/// Picks a track that isn't the same as the one that just played (when
/// there's more than one to choose from).
/client/proc/pick_next_ambient_track()
	var/list/choices = GLOB.ambient_playlist_tracks.Copy()
	if(ambient_playlist_last_track && length(choices) > 1)
		choices -= ambient_playlist_last_track
	return pick(choices)

/// Plays a single track and schedules the next one via a timer set to the
/// track's known duration -- matches play_ambience()/play_music()'s call
/// shape (one sound() per call, no wait=TRUE chaining) rather than
/// pre-queuing a batch.
/client/proc/play_next_ambient_track()
	set waitfor = FALSE
	var/track = pick_next_ambient_track()
	ambient_playlist_last_track = track

	// Everything sound-related below is wrapped so a thrown exception can
	// never skip the addtimer() reschedule at the end of this proc -- without
	// this, any hiccup (not just the "status" one below, already fixed, but
	// any future/unknown one) would silently kill the chain forever, since
	// nothing else ever calls this proc again once ambient_playlist_running
	// is stuck TRUE (see start_ambient_playlist()'s own guard). Mirrors
	// SSmob_ai's identical per-entity guard (controllers/subsystems/mob_ai.dm)
	// around its own recurring think() call.
	try
		// The volume= on this play isn't reliably honored by itself (matches
		// every other case in this system where only an explicit SOUND_UPDATE
		// actually stuck) -- reinforce it once the sound is confirmed active
		// rather than trusting the play call alone, which was landing at
		// BYOND's default (100) instead.
		// wait = TRUE matches the old (known-working) code's first-track call --
		// omitting it broke playback entirely on CHANNEL_AMBIENT_PLAYLIST's very
		// first-ever use for a client. Harmless now that only one sound is ever
		// in flight per channel at a time (no batch to accidentally re-chain).
		SEND_SOUND(src, sound(track, repeat = 0, wait = TRUE, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST))
		sleep(3)
		var/sound/reinforce_update = sound(null, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST)
		reinforce_update.status = SOUND_UPDATE
		SEND_SOUND(src, reinforce_update)
	catch(var/exception/e)
		LOG_DEBUG("Ambient playlist: play_next_ambient_track threw for [key_name(src)]: [e]")

	var/duration = GLOB.ambient_playlist_durations[track] || AMBIENT_PLAYLIST_FALLBACK_DURATION
	ambient_playlist_next_track_timer_id = addtimer(CALLBACK(src, PROC_REF(play_next_ambient_track)), duration, TIMER_UNIQUE | TIMER_OVERRIDE | TIMER_STOPPABLE)

/client/proc/start_ambient_playlist()
	set waitfor = FALSE
	// This is called inline/synchronously from /area/Entered() (a movement
	// signal handler, itself invoked mid-forceMove during e.g. cryopod exit)
	// as well as from addtimer callbacks. play_next_ambient_track() below can
	// sleep() -- without waitfor=FALSE that sleep suspends whatever called
	// us, and a movement signal handler is not expected to tolerate a
	// suspended coroutine mid-transition. This guarantees callers always get
	// control back immediately regardless of context.
	// Gate on volume, not the ASFX bit -- saved sfx_toggles bitmasks from
	// before this system existed lack the new bit, so it can't be the gate
	if(!prefs || !prefs.ambient_playlist_vol)
		return
	if(ambient_playlist_running)
		return

	ambient_playlist_running = TRUE
	play_next_ambient_track()

/// Cancels the pending next-track timer -- called before a hard stop so
/// nothing scheduled earlier can fire later and restart playback.
/client/proc/cancel_ambient_playlist_timers()
	if(ambient_playlist_next_track_timer_id)
		deltimer(ambient_playlist_next_track_timer_id)
		ambient_playlist_next_track_timer_id = null

/// Hard, unconditional stop -- mutes immediately, halts future playback, and
/// cancels any pending timer. Used when the player manually mutes the
/// playlist, and whenever a client leaves the round (cryo-store, disconnect)
/// so nothing can resume playback later over the lobby music.
/client/proc/stop_ambient_playlist()
	ambient_playlist_running = FALSE
	cancel_ambient_playlist_timers()
	src << sound(null, repeat = 0, wait = 0, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST)

#undef AMBIENT_PLAYLIST_FALLBACK_DURATION
