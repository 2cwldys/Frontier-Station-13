--
-- Central mirror of ss13_char_lace_dna.species_override.
--
-- Same column, same table, same (ckey, char_name) key as the local
-- migration (V157__char_lace_species_override.sql) -- lets the "Modify
-- Neural Lace" admin panel's clone-species override follow a character
-- across servers sharing this database, the same way ss13_char_lace_dna's
-- dna_json already does. Gated behind CENTRAL_SYNC_CHARACTERS; inert with
-- central sync off.
--

ALTER TABLE `ss13_char_lace_dna`
	ADD COLUMN `species_override` VARCHAR(64) NULL DEFAULT NULL AFTER `dna_json`;
