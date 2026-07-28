--
-- Admin-authored pool of hostile NPC presets (ss13_hostile_npc_presets)
-- eligible to auto-populate a freshly generated, unclaimed away site.
-- Mirrors ss13_hostile_npc_presets' own shape.
--

CREATE TABLE IF NOT EXISTS `ss13_away_site_mob_presets` (
	`id`         INT NOT NULL AUTO_INCREMENT,
	`map_path`   VARCHAR(64) NOT NULL,
	`preset_id`  INT NOT NULL,
	PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
