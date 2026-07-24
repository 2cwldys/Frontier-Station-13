-- Docking beacon is reinstated: it's the only way a player can create a
-- landable destination somewhere with no pre-existing mapped landmark
-- (away sites and every landable ship's own visiting slots already cover
-- docking to those locations specifically). V096 dropped this table on the
-- mistaken assumption docking_beacon was fully superseded by sector-relative
-- drydock retrieve/stash -- it wasn't; those remain unrelated to this table.

CREATE TABLE IF NOT EXISTS `ss13_player_docking_beacons` (
    `landmark_tag` VARCHAR(128) NOT NULL COMMENT 'Unique landmark tag, e.g. dock_10_20_3',
    `x` INT NOT NULL,
    `y` INT NOT NULL,
    `z` INT NOT NULL,
    `label` VARCHAR(64) DEFAULT NULL COMMENT 'Player-given name shown in flight console',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`landmark_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
