--
-- One-time backup of a character's chargen species, captured automatically
-- the first time persistence_sync_character_species() changes it (a lace
-- resleeve/robotic transfer into a different-species body). NULL means no
-- backup is pending -- either the character has never been resleeved into a
-- different species, or an admin already consumed the backup via the
-- "Modify Neural Lace" panel's Restore Original Species action, which
-- writes the species back and clears this column in the same operation.
--

ALTER TABLE `ss13_char_lace_dna`
	ADD COLUMN `original_species` VARCHAR(64) NULL DEFAULT NULL AFTER `species_override`;
