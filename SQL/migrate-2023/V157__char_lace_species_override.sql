--
-- Admin-set species override for future clones of a character.
--
-- Separate from dna_json (ss13_char_lace_dna's existing column, which is an
-- auto-synced mirror of whatever body a lace was last surgically installed
-- into, written by organ replaced() and never touched by an admin). This
-- column is the opposite: only ever written by the "Modify Neural Lace"
-- admin panel, and consulted by build_cloned_body_for_character()
-- (resleever_cloning.dm) to decide what species a fresh clone grows as.
-- NULL means no override -- clone growth uses the character's own chargen
-- species (copy_to()) untouched, same as before this feature existed.
--

ALTER TABLE `ss13_char_lace_dna`
	ADD COLUMN `species_override` VARCHAR(64) NULL DEFAULT NULL AFTER `dna_json`;
