--
-- Admin-authored, DB-backed, runtime-editable named equipment/stat/faction
-- presets for /mob/living/carbon/human/npc/hostile (a real human-based
-- hostile NPC with real combat AI). Mirrors ss13_missions' own shape.
--

CREATE TABLE IF NOT EXISTS `ss13_hostile_npc_presets` (
	`id`                    INT NOT NULL AUTO_INCREMENT,
	`map_path`              VARCHAR(64) NOT NULL,
	`name`                  VARCHAR(128) NOT NULL,
	`outfit_path`           VARCHAR(255) NOT NULL,
	`faction_uid`           VARCHAR(64) NULL DEFAULT NULL,
	`aggro_range`           INT NOT NULL DEFAULT 10,
	`ranged_attack_range`   INT NOT NULL DEFAULT 6,
	`attack_delay`          INT NOT NULL DEFAULT 10,
	`destroy_surroundings`  TINYINT(1) NOT NULL DEFAULT 0,
	`move_speed`            INT NOT NULL DEFAULT 5,
	`description`           VARCHAR(512) NULL DEFAULT NULL,
	`enabled`               TINYINT(1) NOT NULL DEFAULT 1,
	PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
