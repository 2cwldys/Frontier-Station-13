/*
 * Ambient Music Playlist
 * A continuous, shuffled, no-immediate-repeat background music playlist that
 * plays while a player is in the round. Concept ported from a GMod/Helix
 * codebase (not portable code -- only the track files and playback concept
 * transferred); implemented here using the same chained-sound trick already
 * used by playtitlemusic() (game/sound/sound.dm): sending sounds with
 * wait = TRUE on one channel makes BYOND auto-advance them back to back.
 *
 * The existing per-area ambience system (game/area/areas.dm) overrides this
 * playlist while it is actively playing area-specific ambience, then hands
 * playback back once that circumstance ends -- see the duck/resume logic in
 * /area/Entered().
 */

GLOBAL_LIST_INIT(ambient_playlist_tracks, list(
	'sound/music/ambient_playlist/ager_sonus_through_the_desert.mp3',
	'sound/music/ambient_playlist/alien_isolation_derelict_approach.mp3',
	'sound/music/ambient_playlist/atrium_carceri_from_chasms_reborn.mp3',
	'sound/music/ambient_playlist/atrium_carceri_surfacing.mp3',
	'sound/music/ambient_playlist/atrium_carceri_third_from_the_centre.mp3',
	'sound/music/ambient_playlist/codecay.mp3',
	'sound/music/ambient_playlist/depeche_mode_introspectre.mp3',
	'sound/music/ambient_playlist/desiderii_marginis_beyond_retrieval.mp3',
	'sound/music/ambient_playlist/fear2_city_ambience.mp3',
	'sound/music/ambient_playlist/foundation_hope_troubled_herd_crawling.mp3',
	'sound/music/ambient_playlist/incantation.mp3',
	'sound/music/ambient_playlist/kammarheit_the_hierophant.mp3',
	'sound/music/ambient_playlist/resident_evil_remake_contaminated.mp3',
	'sound/music/ambient_playlist/solarhums.mp3',
	'sound/music/ambient_playlist/space_empires_iv_track1.mp3',
	'sound/music/ambient_playlist/space_empires_v_main13.mp3',
	'sound/music/ambient_playlist/spiritual_front_overture_for_castration.mp3',
	'sound/music/ambient_playlist/ss13_endless_space.mp3',
	'sound/music/ambient_playlist/thief_deadly_shadows_old_quarter.mp3',
	'sound/music/ambient_playlist/thomas_bangalter_rectum.mp3',
))

/// How often start_ambient_playlist() re-queues a fresh shuffled batch.
/// Because tracks are chained with wait=TRUE, refilling early just appends
/// more music after whatever is still playing -- no gap, no overlap, and no
/// need to track exact per-file durations.
#define AMBIENT_PLAYLIST_REFILL_INTERVAL (40 MINUTES)
/// Crossfade length (deciseconds) when area ambience ducks/hands back the playlist.
#define AMBIENT_PLAYLIST_FADE_TIME 20

/client/var/ambient_playlist_last_track
/client/var/ambient_playlist_ducked = FALSE
/client/var/ambient_playlist_running = FALSE
/client/var/ambient_playlist_refill_timer_id
/client/var/ambient_playlist_resume_timer_id

/// Shuffle the track list so the same track never plays twice in a row
/// (including across the boundary between refills).
/client/proc/shuffled_ambient_batch()
	var/list/batch = shuffle(GLOB.ambient_playlist_tracks.Copy())
	if(ambient_playlist_last_track && batch[1] == ambient_playlist_last_track && length(batch) > 1)
		// Swap the repeat off the front of the batch
		var/tmp_track = batch[1]
		batch[1] = batch[2]
		batch[2] = tmp_track
	return batch

/// Queues a freshly shuffled batch. If fade_in is set, the first track starts
/// silent and ramps up to the target volume over AMBIENT_PLAYLIST_FADE_TIME --
/// used when handing playback back from a ducked area-ambience circumstance.
/// A short real sleep separates the initial silent sound from the SOUND_UPDATE
/// fade-up: sending both back-to-back with no gap risks the update arriving
/// before the client's engine considers the sound "active" and silently
/// failing to attach, which left tracks stuck at volume 0 until a player
/// manually touched the volume verb (whose update landed well after the
/// sound was genuinely playing, so it always "fixed" it).
/client/proc/queue_ambient_batch(fade_in = FALSE)
	var/list/batch = shuffled_ambient_batch()
	var/first = TRUE
	for(var/track in batch)
		if(first)
			if(fade_in)
				SEND_SOUND(src, sound(track, repeat = 0, wait = TRUE, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST))
				sleep(3)
				SEND_SOUND(src, sound(null, status = SOUND_UPDATE, fade = AMBIENT_PLAYLIST_FADE_TIME, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST))
			else
				// The volume= on this initial play isn't reliably honored by
				// itself (matches every other case in this system where only
				// an explicit SOUND_UPDATE actually stuck) -- reinforce it once
				// the sound is confirmed active rather than trusting the play
				// call alone, which was landing at BYOND's default (100) instead.
				SEND_SOUND(src, sound(track, repeat = 0, wait = TRUE, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST))
				sleep(3)
				SEND_SOUND(src, sound(null, status = SOUND_UPDATE, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST))
		else
			SEND_SOUND(src, sound(track, repeat = 0, wait = TRUE, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST))
		first = FALSE
	ambient_playlist_last_track = batch[length(batch)]

/client/proc/start_ambient_playlist(resuming = FALSE)
	set waitfor = FALSE
	// This is called inline/synchronously from /area/Entered() (a movement
	// signal handler, itself invoked mid-forceMove during e.g. cryopod exit)
	// as well as from addtimer callbacks. queue_ambient_batch() below can
	// sleep() -- without waitfor=FALSE that sleep suspends whatever called
	// us, and a movement signal handler is not expected to tolerate a
	// suspended coroutine mid-transition. This guarantees callers always get
	// control back immediately regardless of context.
	// Gate on volume, not the ASFX bit -- saved sfx_toggles bitmasks from
	// before this system existed lack the new bit, so it can't be the gate
	if(!prefs || !prefs.ambient_playlist_vol)
		return
	if(ambient_playlist_ducked || ambient_playlist_running)
		return

	ambient_playlist_running = TRUE
	// Only fade in when genuinely resuming from a duck (audible gap to smooth
	// over). A cold start has nothing playing yet to fade from -- queue it
	// straight at the target volume so it isn't silently stuck at 0 waiting
	// on a fade that has nothing to visually improve anyway.
	queue_ambient_batch(fade_in = resuming)
	ambient_playlist_refill_timer_id = addtimer(CALLBACK(src, PROC_REF(refill_ambient_playlist)), AMBIENT_PLAYLIST_REFILL_INTERVAL, TIMER_UNIQUE | TIMER_OVERRIDE | TIMER_STOPPABLE)

/client/proc/refill_ambient_playlist()
	set waitfor = FALSE
	if(ambient_playlist_ducked || !prefs || !prefs.ambient_playlist_vol)
		ambient_playlist_running = FALSE
		return

	queue_ambient_batch(fade_in = FALSE)
	ambient_playlist_refill_timer_id = addtimer(CALLBACK(src, PROC_REF(refill_ambient_playlist)), AMBIENT_PLAYLIST_REFILL_INTERVAL, TIMER_UNIQUE | TIMER_OVERRIDE | TIMER_STOPPABLE)

/// Smoothly fades the currently playing track to silence, then flushes the
/// rest of the queued batch once the fade completes -- called when area
/// ambience takes over. An immediate flush would pop the next queued track
/// back to full volume, so the fade needs its own short delay before that.
/client/proc/duck_ambient_playlist()
	SEND_SOUND(src, sound(null, status = SOUND_UPDATE, fade = AMBIENT_PLAYLIST_FADE_TIME, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST))
	addtimer(CALLBACK(src, PROC_REF(flush_duck_fade)), AMBIENT_PLAYLIST_FADE_TIME * 0.1 SECONDS)

/// Cancels any pending refill/resume timers -- called before a hard stop so
/// nothing scheduled earlier can fire later and restart playback.
/client/proc/cancel_ambient_playlist_timers()
	if(ambient_playlist_refill_timer_id)
		deltimer(ambient_playlist_refill_timer_id)
		ambient_playlist_refill_timer_id = null
	if(ambient_playlist_resume_timer_id)
		deltimer(ambient_playlist_resume_timer_id)
		ambient_playlist_resume_timer_id = null

/// Flushes the queued batch after a duck fade completes. If the area
/// circumstance already ended and the playlist resumed before this fires,
/// skip the flush so the newly-resumed audio isn't cut off.
/client/proc/flush_duck_fade()
	if(!ambient_playlist_ducked)
		return
	ambient_playlist_running = FALSE
	src << sound(null, repeat = 0, wait = 0, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST)

/// Hard, unconditional stop -- mutes immediately, halts future refills, and
/// cancels any pending refill/resume timers. Used when the player manually
/// mutes the playlist, and whenever a client leaves the round (cryo-store,
/// disconnect) so nothing can resume playback later over the lobby music.
/client/proc/stop_ambient_playlist()
	ambient_playlist_running = FALSE
	cancel_ambient_playlist_timers()
	src << sound(null, repeat = 0, wait = 0, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST)

/// Clears an area-ambience duck and fades the playlist back in.
/// Scheduled by play_ambience() a short while after a stinger fires.
/client/proc/resume_ambient_playlist()
	ambient_playlist_resume_timer_id = null
	ambient_playlist_ducked = FALSE
	start_ambient_playlist(resuming = TRUE)

#undef AMBIENT_PLAYLIST_REFILL_INTERVAL
#undef AMBIENT_PLAYLIST_FADE_TIME
