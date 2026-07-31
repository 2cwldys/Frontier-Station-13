--
-- Cryogenic prison storage: a per-character "imprisoned" flag, persisted
-- alongside every other cryo-state field on ss13_mob_position (char_state,
-- last_pod_x/y/z, etc). NULL imprisoned_until while imprisoned=1 means an
-- indefinite sentence; a past imprisoned_until means an expired one (cleared
-- lazily on next check, not swept eagerly). See
-- persistence_character_imprisonment_status() (persistence_mobs.dm).
--

ALTER TABLE `ss13_mob_position`
	ADD COLUMN `imprisoned` TINYINT(1) NOT NULL DEFAULT 0,
	ADD COLUMN `imprisoned_until` DATETIME NULL DEFAULT NULL;
