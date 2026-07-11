--
-- Set default 'On' for 'VIGNETTE' in toggles_secondary (bit added mid-development;
-- no existing row could have deliberately disabled a flag that didn't exist yet).
--

UPDATE `ss13_player_preferences` SET `toggles_secondary` = `toggles_secondary` | 8192;
