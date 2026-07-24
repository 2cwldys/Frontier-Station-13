--
-- Set default 'On' for 'ASFX_ENGINE_HUM' in sfx_toggles (bit added
-- mid-development; no existing row could have deliberately disabled a flag
-- that didn't exist yet). Same shape as V072__vignette_default_on.sql /
-- V084__crt_scanlines_default_on.sql / V107__announcer_voice_default_on.sql.
-- ASFX_ENGINE_HUM = BITFLAG(13) = 8192.
--

UPDATE `ss13_player_preferences` SET `sfx_toggles` = `sfx_toggles` | 8192;
