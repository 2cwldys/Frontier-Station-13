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
 *
 * The existing per-area ambience system (game/area/areas.dm) overrides this
 * playlist while it is actively playing area-specific ambience, then hands
 * playback back once that circumstance ends -- see the duck/resume logic in
 * /area/Entered().
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
))

/// Crossfade length (deciseconds) when area ambience ducks/hands back the playlist.
#define AMBIENT_PLAYLIST_FADE_TIME 20
/// Fallback duration (deciseconds, ~3 minutes) used only if a track is
/// somehow missing from ambient_playlist_durations -- keeps the chain alive
/// rather than silently stalling forever.
#define AMBIENT_PLAYLIST_FALLBACK_DURATION 1800

/client/var/ambient_playlist_last_track
/client/var/ambient_playlist_ducked = FALSE
/client/var/ambient_playlist_running = FALSE
/client/var/ambient_playlist_next_track_timer_id
/client/var/ambient_playlist_resume_timer_id

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
/// pre-queuing a batch. If fade_in is set, the track starts silent and ramps
/// up to the target volume over AMBIENT_PLAYLIST_FADE_TIME -- used when
/// handing playback back from a ducked area-ambience circumstance.
/// A short real sleep separates the initial silent sound from the SOUND_UPDATE
/// fade-up: sending both back-to-back with no gap risks the update arriving
/// before the client's engine considers the sound "active" and silently
/// failing to attach, which left tracks stuck at volume 0 until a player
/// manually touched the volume verb (whose update landed well after the
/// sound was genuinely playing, so it always "fixed" it).
/client/proc/play_next_ambient_track(fade_in = FALSE)
	set waitfor = FALSE
	var/track = pick_next_ambient_track()
	ambient_playlist_last_track = track

	if(fade_in)
		SEND_SOUND(src, sound(track, repeat = 0, wait = TRUE, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST))
		sleep(3)
		// status is NOT a valid sound() constructor argument on this BYOND
		// version -- passing it that way threw "bad arg name 'status'" at
		// runtime every single time, silently aborting the rest of this proc
		// (including the addtimer below), which is why the playlist only
		// ever played one track and never advanced. Match the working
		// pattern already used elsewhere in this codebase
		// (set_sound_channel_volume(), sound_channels.dm): construct the
		// sound datum first, then assign .status as a property.
		var/sound/fade_update = sound(null, fade = AMBIENT_PLAYLIST_FADE_TIME, volume = prefs.ambient_playlist_vol, channel = CHANNEL_AMBIENT_PLAYLIST)
		fade_update.status = SOUND_UPDATE
		SEND_SOUND(src, fade_update)
	else
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

	var/duration = GLOB.ambient_playlist_durations[track] || AMBIENT_PLAYLIST_FALLBACK_DURATION
	ambient_playlist_next_track_timer_id = addtimer(CALLBACK(src, PROC_REF(play_next_ambient_track)), duration, TIMER_UNIQUE | TIMER_OVERRIDE | TIMER_STOPPABLE)

/client/proc/start_ambient_playlist(resuming = FALSE)
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
	if(ambient_playlist_ducked || ambient_playlist_running)
		return

	ambient_playlist_running = TRUE
	// Only fade in when genuinely resuming from a duck (audible gap to smooth
	// over). A cold start has nothing playing yet to fade from -- queue it
	// straight at the target volume so it isn't silently stuck at 0 waiting
	// on a fade that has nothing to visually improve anyway.
	play_next_ambient_track(fade_in = resuming)

/// Smoothly fades the currently playing track to silence and cancels the
/// scheduled next-track timer -- called when area ambience takes over, so
/// nothing tries to start a new ambient track while the area's own ambience
/// is active. resume_ambient_playlist() picks a fresh track and reschedules
/// once the area ambience circumstance ends.
/client/proc/duck_ambient_playlist()
	// status is not a valid sound() constructor arg on this BYOND version --
	// construct then assign it as a property (see play_next_ambient_track()).
	var/sound/duck_update = sound(null, fade = AMBIENT_PLAYLIST_FADE_TIME, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST)
	duck_update.status = SOUND_UPDATE
	SEND_SOUND(src, duck_update)
	if(ambient_playlist_next_track_timer_id)
		deltimer(ambient_playlist_next_track_timer_id)
		ambient_playlist_next_track_timer_id = null
	addtimer(CALLBACK(src, PROC_REF(flush_duck_fade)), AMBIENT_PLAYLIST_FADE_TIME * 0.1 SECONDS)

/// Cancels any pending next-track/resume timers -- called before a hard stop
/// so nothing scheduled earlier can fire later and restart playback.
/client/proc/cancel_ambient_playlist_timers()
	if(ambient_playlist_next_track_timer_id)
		deltimer(ambient_playlist_next_track_timer_id)
		ambient_playlist_next_track_timer_id = null
	if(ambient_playlist_resume_timer_id)
		deltimer(ambient_playlist_resume_timer_id)
		ambient_playlist_resume_timer_id = null

/// Mutes the channel once the duck fade completes. If the area circumstance
/// already ended and the playlist resumed before this fires, skip the mute
/// so the newly-resumed audio isn't cut off.
/client/proc/flush_duck_fade()
	if(!ambient_playlist_ducked)
		return
	ambient_playlist_running = FALSE
	src << sound(null, repeat = 0, wait = 0, volume = 0, channel = CHANNEL_AMBIENT_PLAYLIST)

/// Hard, unconditional stop -- mutes immediately, halts future playback, and
/// cancels any pending timers. Used when the player manually mutes the
/// playlist, and whenever a client leaves the round (cryo-store, disconnect)
/// so nothing can resume playback later over the lobby music.
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

#undef AMBIENT_PLAYLIST_FADE_TIME
#undef AMBIENT_PLAYLIST_FALLBACK_DURATION
