/// Real playback duration of each lobby music track, in deciseconds --
/// measured offline via ffprobe against the actual .ogg files
/// (sound/music/lobby/), not computed at runtime. BYOND has no native way to
/// query a sound file's length, and playtitlemusic() (game/sound/sound.dm)
/// gets no "track ended" callback once a track is queued on a client's sound
/// channel -- so this is what lets a sequential "now playing" chat
/// announcement fire at roughly the real moment each track actually starts,
/// instead of when its SEND_SOUND resource dispatch merely happens (which,
/// for the whole queue, is within seconds due to the network-buffering
/// stagger, not real playback timing). Same pattern as
/// announcer_sound_durations (_announcer_sound_durations.dm), just for the
/// lobby music folder instead of announcer voice lines. Re-measure and
/// update this if a lobby track is ever replaced/re-encoded.
GLOBAL_LIST_INIT(lobby_track_durations, list(
	'sound/music/lobby/anotherstory.ogg' = 2784,
	'sound/music/lobby/astrogenesis.ogg' = 2492,
	'sound/music/lobby/duneorange_nang.ogg' = 2470,
	'sound/music/lobby/interkosmos_persistence.ogg' = 4391,
	'sound/music/lobby/jrb_naked_reality.ogg' = 6880,
	'sound/music/lobby/kaaistoep.ogg' = 2810,
	'sound/music/lobby/mainmenu.ogg' = 11545,
	'sound/music/lobby/radix_lluvia_leveld_colours.ogg' = 3199,
	'sound/music/lobby/saturn.ogg' = 2658,
	'sound/music/lobby/snow.ogg' = 2631,
	'sound/music/lobby/stellardrone_comet_halley.ogg' = 2255,
	'sound/music/lobby/stem_4_6.ogg' = 2561,
	'sound/music/lobby/zircon_ladder_to_the_sky.ogg' = 3062,
	'sound/music/lobby/system_shock_executive_cover.ogg' = 4260,
	'sound/music/lobby/zone_of_the_enders_2_zakat_extended.ogg' = 7024,
	'sound/music/lobby/sysdoom_shock_medical.ogg' = 3111,
))
