--
-- Last-used Synthetic Storage location for an IPC character.
--
-- Deliberately separate columns from last_pod_x/y/z -- that trio is read by
-- persistence_find_saved_cryopod() specifically searching for a
-- /obj/structure/machinery/cryopod at those coordinates. An IPC no longer
-- uses cryopods at all (cryopod.dm's check_occupant_allowed() now refuses
-- them), so reusing the same columns for a different machine type would
-- risk corrupting the existing meaning those columns have for every other
-- human character. Same (ckey, char_name) row as everything else on this
-- table; written by persistence_set_last_synthetic_storage(), read by
-- persistence_find_saved_synthetic_storage_for_character()
-- (persistence_cyborg.dm).
--

ALTER TABLE `ss13_mob_position`
	ADD COLUMN `last_synth_x` SMALLINT NULL AFTER `last_pod_z`,
	ADD COLUMN `last_synth_y` SMALLINT NULL AFTER `last_synth_x`,
	ADD COLUMN `last_synth_z` SMALLINT NULL AFTER `last_synth_y`;
