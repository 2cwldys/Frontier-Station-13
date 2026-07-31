--
-- Admin-captured "outfit templates" -- an equipment loadout snapshotted from
-- a human mob's currently worn/held gear (persistence_outfit_templates.dm),
-- usable by hostile NPC presets as an alternative to a compile-time
-- /obj/outfit subtype. slots_json is a JSON object mapping /obj/outfit slot
-- var names (uniform, suit, head, l_hand, ...) to item typepath strings.
--

CREATE TABLE IF NOT EXISTS `ss13_outfit_templates` (
	`id`          INT NOT NULL AUTO_INCREMENT,
	`map_path`    VARCHAR(64) NOT NULL,
	`name`        VARCHAR(128) NOT NULL,
	`slots_json`  TEXT NOT NULL,
	`description` VARCHAR(512) NULL DEFAULT NULL,
	PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
