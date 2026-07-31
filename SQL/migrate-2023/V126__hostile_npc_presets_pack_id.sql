--
-- Optional "pack" tag for hostile NPC presets -- lets multiple DIFFERENT
-- factionless presets (e.g. several distinct "pirate" variants) be grouped
-- so they don't attack each other, while still attacking players and any
-- real persistence-faction NPC. Only meaningful when faction_uid is null;
-- a real faction always takes priority over pack grouping.
--

ALTER TABLE `ss13_hostile_npc_presets`
	ADD COLUMN `pack_id` VARCHAR(64) NULL DEFAULT NULL;
