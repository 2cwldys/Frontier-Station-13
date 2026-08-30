--
-- Central mirror of ss13_mob_position's last_synth_x/y/z columns -- see
-- V161__mob_position_last_synthetic_storage.sql (local) for the full
-- rationale.
--

ALTER TABLE `ss13_mob_position`
	ADD COLUMN `last_synth_x` SMALLINT NULL AFTER `last_pod_z`,
	ADD COLUMN `last_synth_y` SMALLINT NULL AFTER `last_synth_x`,
	ADD COLUMN `last_synth_z` SMALLINT NULL AFTER `last_synth_y`;
