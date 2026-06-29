-- Player-built shuttle registration.
-- hull_json stores JSON array of "x,y,z" position strings for all hull turfs.
-- Landmarks for destinations are stored in ss13_player_docking_beacons.

CREATE TABLE IF NOT EXISTS `ss13_player_shuttles` (
    `shuttle_name` VARCHAR(64) NOT NULL COMMENT 'Unique shuttle ID tag',
    `owner_ckey`   VARCHAR(32) DEFAULT NULL,
    `faction_uid`  VARCHAR(32) DEFAULT NULL,
    `home_x` INT NOT NULL,
    `home_y` INT NOT NULL,
    `home_z` INT NOT NULL COMMENT 'Position of the home landmark',
    `hull_json` TEXT NOT NULL COMMENT 'JSON array of "x,y,z" strings for hull tiles',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`shuttle_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_player_docking_beacons` (
    `landmark_tag` VARCHAR(128) NOT NULL COMMENT 'Unique landmark tag, e.g. dock_10_20_3',
    `x` INT NOT NULL,
    `y` INT NOT NULL,
    `z` INT NOT NULL,
    `label` VARCHAR(64) DEFAULT NULL COMMENT 'Player-given name shown in flight console',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`landmark_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
