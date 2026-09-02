///Default override for echo
/sound
	echo = list(
		0, // Direct
		0, // DirectHF
		-10000, // Room, -10000 means no low frequency sound reverb
		-10000, // RoomHF, -10000 means no high frequency sound reverb
		0, // Obstruction
		0, // ObstructionLFRatio
		0, // Occlusion
		0.25, // OcclusionLFRatio
		1.5, // OcclusionRoomRatio
		1.0, // OcclusionDirectRatio
		0, // Exclusion
		1.0, // ExclusionLFRatio
		0, // OutsideVolumeHF
		0, // DopplerFactor
		0, // RolloffFactor
		0, // RoomRolloffFactor
		1.0, // AirAbsorptionFactor
		0, // Flags (1 = Auto Direct, 2 = Auto Room, 4 = Auto RoomHF)
	)
	environment = SOUND_ENVIRONMENT_NONE //Default to none so sounds without overrides dont get reverb

/**
 * playsound is a proc used to play a 3D sound in a specific range. This uses SOUND_RANGE + extra_range to determine that.
 *
 * * source - Origin of sound.
 * * soundin - Either a file, or a string that can be used to get an SFX.
 * * vol - The volume of the sound, excluding falloff and pressure affection.
 * * vary - bool that determines if the sound changes pitch every time it plays.
 * * extrarange - modifier for sound range. This gets added on top of SOUND_RANGE.
 * * falloff_exponent - Rate of falloff for the audio. Higher means quicker drop to low volume. Should generally be over 1 to indicate a quick dive to 0 rather than a slow dive.
 * * frequency - playback speed of audio.
 * * channel - The channel the sound is played at.
 * * pressure_affected - Whether or not difference in pressure affects the sound (E.g. if you can hear in space).
 * * ignore_walls - Whether or not the sound can pass through walls.
 * * falloff_distance - Distance at which falloff begins. Sound is at peak volume (in regards to falloff) aslong as it is in this range.
 *
 * Aurora snowflake parameters:
 *
 * * required_preferences - What preference is required to be on on the client, for the sound to play
 * * required_asfx_toggles - What toggles are required to be on on the client, for the sound to play
 */
/proc/playsound(atom/source, soundin, vol as num, vary, extrarange as num, falloff_exponent = SOUND_FALLOFF_EXPONENT, frequency = null, channel = 0, pressure_affected = TRUE, ignore_walls = TRUE, falloff_distance = SOUND_DEFAULT_FALLOFF_DISTANCE, use_reverb = TRUE, required_preferences, required_asfx_toggles)
	if(isarea(source))
		CRASH("playsound(): source is an area")

	var/turf/turf_source = get_turf(source)

	if (!turf_source || !soundin || !vol)
		return

	//allocate a channel if necessary now so its the same for everyone
	channel = channel || SSsounds.random_available_channel()

	var/sound/S = isdatum(soundin) ? soundin : sound(get_sfx(soundin))
	var/maxdistance = SOUND_RANGE + extrarange
	var/source_z = turf_source.z
	var/list/listeners = list()

	var/list/players_by_zlevel[world.maxz][1]
	var/list/dead_players_by_zlevel[world.maxz][1]

	for(var/mob/player as anything in GLOB.player_list)
		if(required_preferences && (player.client.prefs.toggles & required_preferences) != required_preferences)
			continue

		if(required_asfx_toggles && (player.client.prefs.sfx_toggles & required_asfx_toggles) != required_asfx_toggles)
			continue

		//This is because your Z is 0 if you are inside eg. a mech
		var/turf/player_turf = get_turf(player)
		if(!player_turf)
			continue

		if(player_turf.z == source_z)
			listeners += player

		if(player_turf.z)
			players_by_zlevel[player_turf.z] += player

		if(isobserver(player) && player_turf.z)
			dead_players_by_zlevel[player_turf.z] += player

	. = list()//output everything that successfully heard the sound

	var/turf/above_turf = GET_TURF_ABOVE(turf_source)
	var/turf/below_turf = GET_TURF_BELOW(turf_source)

	if(ignore_walls)

		if(above_turf && istype(above_turf, /turf/simulated/open))
			listeners += players_by_zlevel[above_turf.z]

		if(below_turf && istype(turf_source, /turf/simulated/open))
			listeners += players_by_zlevel[below_turf.z]

	else //these sounds don't carry through walls
		listeners = get_hearers_in_view(maxdistance, turf_source)

		if(above_turf && istype(above_turf, /turf/simulated/open))
			listeners += get_hearers_in_view(maxdistance, above_turf)

		if(below_turf && istype(turf_source, /turf/simulated/open))
			listeners += get_hearers_in_view(maxdistance, below_turf)

	for(var/mob/listening_mob in listeners | dead_players_by_zlevel[source_z])//observers always hear through walls
		if(get_dist(listening_mob, turf_source) <= maxdistance)
			//Aurora snowflake, if we don't ignore the walls, account for wall-like obstacles to dampen the sound
			if(ignore_walls)
				listening_mob.playsound_local(turf_source, soundin, vol, vary, frequency, falloff_exponent, channel, pressure_affected, S, maxdistance, falloff_distance, 1, use_reverb)
			else
				adjust_sound_based_on_path_obstacles(listening_mob, turf_source, soundin, vol, vary, frequency, falloff_exponent, channel, pressure_affected, S, maxdistance, falloff_distance, use_reverb)

			. += listening_mob

/**
 * This proc takes into account walls, windows and similar when deciding the received sound for a mob,
 *
 * this is *NOT* meant to be called directly, use `playsound()`
 *
 * Use this to tweak what happens with the sound along the path from the emitter to the receiver of said sound
 */
/proc/adjust_sound_based_on_path_obstacles(mob/listening_mob, turf/turf_source, soundin, vol, vary, frequency, falloff_exponent, channel, pressure_affected, S, maxdistance, falloff_distance, use_reverb)
	var/turf/inbetween_turf = get_turf(listening_mob)

	for(var/step_counter in 1 to get_dist(listening_mob, turf_source))
		inbetween_turf = get_step_towards(inbetween_turf, turf_source)

		if(istype(inbetween_turf, /turf/simulated/wall))
			vol *= 0.6

		if(locate(/obj/structure/machinery/door) in inbetween_turf)
			vol *= 0.7

		if(locate(/obj/structure/window) in inbetween_turf)
			vol *= 0.75

		//If we're at or below zero, no point continuing, no sound
		if(vol <= 0)
			return

	listening_mob.playsound_local(turf_source, soundin, vol, vary, frequency, falloff_exponent, channel, pressure_affected, S, maxdistance, falloff_distance, 1, use_reverb)


/mob/proc/playsound_local(turf/turf_source, soundin, vol as num, vary, frequency, falloff_exponent = SOUND_FALLOFF_EXPONENT, channel = 0, pressure_affected = TRUE, sound/sound_to_use, max_distance, falloff_distance = SOUND_DEFAULT_FALLOFF_DISTANCE, distance_multiplier = 1, use_reverb = TRUE)
	if(!client || !can_hear())
		return

	if(!sound_to_use)
		sound_to_use = sound(get_sfx(soundin))

	sound_to_use.wait = 0 //No queue
	sound_to_use.channel = channel || SSsounds.random_available_channel()
	sound_to_use.volume = vol

	if(vary)
		if(frequency)
			sound_to_use.frequency = frequency
		else
			sound_to_use.frequency = get_rand_frequency()

	if(audio_lag_until && world.time < audio_lag_until)
		sound_to_use.frequency = AUDIO_LAG_FREQUENCY

	if(isturf(turf_source))
		var/turf/turf_loc = get_turf(src)

		//sound volume falloff with distance
		var/distance = get_dist(turf_loc, turf_source) * distance_multiplier

		if(max_distance) //If theres no max_distance we're not a 3D sound, so no falloff.
			sound_to_use.volume -= (max(distance - falloff_distance, 0) ** (1 / falloff_exponent)) / ((max(max_distance, distance) - falloff_distance) ** (1 / falloff_exponent)) * sound_to_use.volume
			//https://www.desmos.com/calculator/sqdfl8ipgf

		if(pressure_affected)
			//Atmosphere affects sound
			var/pressure_factor = 1
			var/datum/gas_mixture/hearer_env = turf_loc.return_air()
			var/datum/gas_mixture/source_env = turf_source.return_air()

			if(hearer_env && source_env)
				var/pressure = min(XGM_PRESSURE(hearer_env), XGM_PRESSURE(source_env))
				if(pressure < ONE_ATMOSPHERE)
					pressure_factor = max((pressure - SOUND_MINIMUM_PRESSURE)/(ONE_ATMOSPHERE - SOUND_MINIMUM_PRESSURE), 0)
			else //space
				pressure_factor = 0

			if(distance <= 1)
				pressure_factor = max(pressure_factor, 0.15) //touching the source of the sound

			sound_to_use.volume *= pressure_factor
			//End Atmosphere affecting sound

		if(sound_to_use.volume <= 0)
			return //No sound

		var/dx = turf_source.x - turf_loc.x // Hearing from the right/left
		sound_to_use.x = dx * distance_multiplier
		var/dz = turf_source.y - turf_loc.y // Hearing from infront/behind
		sound_to_use.z = dz * distance_multiplier
		var/dy = (turf_source.z - turf_loc.z) * 5 * distance_multiplier // Hearing from  above / below, multiplied by 5 because we assume height is further along coords.
		sound_to_use.y = dy

		sound_to_use.falloff = max_distance || 1 //use max_distance, else just use 1 as we are a direct sound so falloff isnt relevant.

		// Sounds can't have their own environment. A sound's environment will be:
		// 1. the mob's
		// 2. the area's (defaults to SOUND_ENVRIONMENT_NONE)
		if(sound_environment_override != SOUND_ENVIRONMENT_NONE)
			sound_to_use.environment = sound_environment_override
		else
			var/area/A = get_area(src)
			sound_to_use.environment = A.sound_environment

		if(use_reverb && sound_to_use.environment != SOUND_ENVIRONMENT_NONE) //We have reverb, reset our echo setting
			sound_to_use.echo[3] = 0 //Room setting, 0 means normal reverb
			sound_to_use.echo[4] = 0 //RoomHF setting, 0 means normal reverb.

	SEND_SOUND(src, sound_to_use)

/proc/sound_to_playing_players(soundin, volume = 100, vary = FALSE, frequency = 0, channel = 0, pressure_affected = FALSE, sound/S)
	if(!S)
		S = sound(get_sfx(soundin))
	for(var/m in GLOB.player_list)
		if(ismob(m) && !isnewplayer(m))
			var/mob/M = m
			M.playsound_local(M, null, volume, vary, frequency, null, channel, pressure_affected, S)

/// How long the playlist is held before its first track starts. Every step of
/// the playlist is cancellable (see below), so a further playtitlemusic() call
/// landing inside this window cancels the pending start and replaces it --
/// which is what collapses a burst of calls down to one playlist and one
/// announcement, instead of one of each per call.
#define LOBBY_ANNOUNCE_DEBOUNCE (1 SECOND)

/// Pending _advance_lobby_track() timer IDs from the most recent
/// playtitlemusic() call -- cancelled at the top of every call so a repeat
/// invocation (cryo/store-character return, toggling the lobby music
/// preference, etc. -- all explicitly expected, see playtitlemusic()'s own
/// comment) can't leave a superseded playlist still stepping forward in the
/// background.
/client/var/list/lobby_music_announce_timer_ids

/// Bumped by every playtitlemusic() call so a superseded playlist's own
/// pending step can tell it has been taken over and stop.
/client/var/lobby_music_generation = 0

/// The shuffled playlist currently being stepped through, and how far into it
/// we are. Held on the client because the playlist is driven ONE TRACK AT A
/// TIME from the server (see _advance_lobby_track()) rather than queued onto
/// the sound channel all at once.
/client/var/list/lobby_playlist
/client/var/lobby_playlist_index = 0

/client/proc/playtitlemusic()
	set waitfor = FALSE
	UNTIL(SSticker.login_music) //wait for SSticker init to set the login music

	// Supersede any playlist still stepping. Without this a repeat call leaves
	// the old one advancing in the background, and the two take turns
	// replacing each other's track on the same channel.
	lobby_music_generation++
	var/my_generation = lobby_music_generation

	if(lobby_music_announce_timer_ids)
		for(var/timer_id in lobby_music_announce_timer_ids)
			deltimer(timer_id)
	lobby_music_announce_timer_ids = list()

	SEND_SOUND(src, sound(null, repeat = 0, wait = 0, volume = prefs.lobby_music_vol, channel = CHANNEL_LOBBYMUSIC))

	lobby_playlist = null
	lobby_playlist_index = 0

	if(!prefs.lobby_music_vol)
		return

	// Shuffled per client, so which track you land on first is random.
	// shuffle() (__HELPERS/lists.dm) returns a shuffled COPY, so the shared
	// SSticker.login_music list is left untouched for everyone else.
	lobby_playlist = shuffle(SSticker.login_music)

	// Scheduled rather than started inline, deliberately: that is what lets a
	// burst of calls collapse to a single playlist, since the pending start is
	// cancellable above. See LOBBY_ANNOUNCE_DEBOUNCE.
	lobby_music_announce_timer_ids += addtimer(CALLBACK(src, PROC_REF(_advance_lobby_track), my_generation), LOBBY_ANNOUNCE_DEBOUNCE, TIMER_STOPPABLE)

/**
 * Starts the next track of this client's lobby playlist, announces it, and
 * schedules itself again for that track's own length.
 *
 * The playlist is driven one track at a time from the server rather than
 * queued onto the sound channel all at once with wait = TRUE. That queued
 * approach is what left the "Now playing" lines out of sync with the audio:
 * every track was dispatched within about two seconds, while the
 * announcements were scheduled against a predicted timeline spanning the
 * whole playlist (over an hour). Any real difference -- the client still
 * fetching a track's resource, a gap between tracks, anything at all --
 * accumulated with nothing to correct it, so the messages ran steadily
 * further ahead of the music.
 *
 * Here the announcement and the SEND_SOUND happen in the same step, so they
 * cannot disagree, and wait = 0 (replace, don't queue) keeps the server
 * authoritative about what is on the channel -- the message always names the
 * track that was just started. BYOND exposes no "track ended" callback, so
 * this is the closest to real sync available.
 */
/client/proc/_advance_lobby_track(generation)
	// Superseded by a newer playtitlemusic(), or this is no longer a
	// lobby-sitting client with music on -- spawning in, disconnecting, or
	// muting lobby music since this was scheduled all mean stop here.
	if(QDELETED(src) || generation != lobby_music_generation)
		return
	if(!mob || !isnewplayer(mob) || !prefs.lobby_music_vol)
		return
	if(!islist(lobby_playlist) || !length(lobby_playlist))
		return

	lobby_playlist_index++
	// Playlist exhausted -- stop, matching what the old all-at-once queue did
	// when it ran out, rather than silently looping.
	if(lobby_playlist_index > length(lobby_playlist))
		return

	var/track_path = lobby_playlist[lobby_playlist_index]
	SEND_SOUND(src, sound(track_path, repeat = 0, wait = 0, volume = prefs.lobby_music_vol, channel = CHANNEL_LOBBYMUSIC)) // MAD JAMS

	if(GLOB.config.githuburl)
		var/branch = GLOB.config.github_branch || "main"
		var/track_name = "[track_path]"
		to_chat(src, SPAN_NOTICE("Now playing lobby music: <a href='[GLOB.config.githuburl]/blob/[branch]/[track_name]'>[track_name]</a>"))

	// Real, offline-measured length (lobby_track_durations,
	// _lobby_track_durations.dm) -- BYOND has no native way to query a sound
	// file's length. Only ever one track ahead now, instead of a whole
	// playlist's worth of prediction.
	var/duration = GLOB.lobby_track_durations[track_path] || 5 MINUTES
	lobby_music_announce_timer_ids += addtimer(CALLBACK(src, PROC_REF(_advance_lobby_track), generation), duration, TIMER_STOPPABLE)

/proc/get_rand_frequency()
	return rand(32000, 55000) //Frequency stuff only works with 45kbps oggs.

/// Randomly return one of the SFX within the keyed list.
/proc/get_sfx(soundin)
	if(!istext(soundin))
		return soundin
	var/datum/sound_effect/sfx = SSsounds.sfx_datum_by_key[soundin]
	return sfx?.return_sfx() || soundin

