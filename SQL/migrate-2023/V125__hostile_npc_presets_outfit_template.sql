--
-- Lets a hostile NPC preset point at a custom outfit template
-- (ss13_outfit_templates) instead of only a compile-time /obj/outfit
-- typepath. outfit_path becomes nullable since a preset now uses EITHER
-- outfit_path OR outfit_template_id, never both.
--

ALTER TABLE `ss13_hostile_npc_presets`
	MODIFY COLUMN `outfit_path` VARCHAR(255) NULL DEFAULT NULL,
	ADD COLUMN `outfit_template_id` INT NULL DEFAULT NULL;
