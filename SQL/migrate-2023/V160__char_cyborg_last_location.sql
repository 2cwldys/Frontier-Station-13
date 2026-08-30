--
-- Last-used Synthetic Storage location for a stored cyborg.
--
-- Mirrors ss13_mob_position's last_pod_x/y/z for humans (persistence_set_last_pod()/
-- persistence_find_saved_cryopod(), persistence_cryo.dm) -- separate columns
-- from cyborg_json's own state blob, since this is spawn-routing bookkeeping,
-- not chassis state. Set by charCyborgSaveOne() from the storing unit's own
-- turf; read back by PersistentAutoSpawnCyborg()'s cascade
-- (persistence_cyborg.dm) to try the same unit first before falling through
-- to the tiered discovery prompt.
--

ALTER TABLE `ss13_char_cyborg`
	ADD COLUMN `last_x` SMALLINT NULL AFTER `cyborg_json`,
	ADD COLUMN `last_y` SMALLINT NULL AFTER `last_x`,
	ADD COLUMN `last_z` SMALLINT NULL AFTER `last_y`;
