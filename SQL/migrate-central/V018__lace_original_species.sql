--
-- Central mirror of ss13_char_lace_dna.original_species.
--
-- Same column, same table, same (ckey, char_name) key as the local
-- migration (V162__char_lace_original_species.sql) -- lets the pre-resleeve
-- species backup follow a character across servers sharing this database,
-- the same way species_override already does. Gated behind
-- CENTRAL_SYNC_CHARACTERS; inert with central sync off.
--

ALTER TABLE `ss13_char_lace_dna`
	ADD COLUMN `original_species` VARCHAR(64) NULL DEFAULT NULL AFTER `species_override`;
