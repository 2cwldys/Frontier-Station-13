--
-- Lets a "kill" mission target an admin-authored hostile NPC preset
-- (ss13_hostile_npc_presets) instead of only a raw mob type path, so
-- kill-mission targets can be equipped/tuned real NPCs.
--

ALTER TABLE `ss13_missions`
	ADD COLUMN `kill_preset_id` INT NULL DEFAULT NULL;
