--
-- Set default 'On' for 'ASFX_ANNOUNCER' in sfx_toggles (bit added
-- mid-development; no existing row could have deliberately disabled a flag
-- that didn't exist yet). Same shape as V072__vignette_default_on.sql /
-- V084__crt_scanlines_default_on.sql.
-- ASFX_ANNOUNCER = BITFLAG(12) = 4096.
--

UPDATE `ss13_player_preferences` SET `sfx_toggles` = `sfx_toggles` | 4096;
