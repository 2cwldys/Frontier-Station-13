CREATE TABLE IF NOT EXISTS `ss13_atmos_zones` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `map_path` VARCHAR(128) NOT NULL,
    `rep_x` INT NOT NULL,
    `rep_y` INT NOT NULL,
    `rep_z` INT NOT NULL,
    `gas_json` MEDIUMTEXT NOT NULL,
    `temperature` FLOAT NOT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_pos` (`map_path`(64), `rep_x`, `rep_y`, `rep_z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
