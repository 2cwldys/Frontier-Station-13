--
-- Set default 'On' for 'CRT_SCANLINES' in toggles_secondary (bit added
-- mid-development; no existing row could have deliberately disabled a flag
-- that didn't exist yet). Same shape as V072__vignette_default_on.sql.
-- CRT_SCANLINES = BITFLAG(14) = 16384.
--

UPDATE `ss13_player_preferences` SET `toggles_secondary` = `toggles_secondary` | 16384;
