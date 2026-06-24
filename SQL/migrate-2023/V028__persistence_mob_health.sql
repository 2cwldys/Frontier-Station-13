CREATE TABLE IF NOT EXISTS `ss13_char_health` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `ckey` VARCHAR(32) NOT NULL,
    `char_name` VARCHAR(64) NOT NULL,
    `organ_damage_json` MEDIUMTEXT DEFAULT NULL,
    `stamina` FLOAT NOT NULL DEFAULT 100,
    `bodytemperature` FLOAT NOT NULL DEFAULT 310,
    `on_fire` TINYINT(1) NOT NULL DEFAULT 0,
    `fire_stacks` FLOAT NOT NULL DEFAULT 0,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_ckey_name` (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
