CREATE TABLE IF NOT EXISTS `ss13_worldstate_turfs` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `map_path` VARCHAR(128) NOT NULL,
    `x` INT NOT NULL,
    `y` INT NOT NULL,
    `z` INT NOT NULL,
    `turf_type` VARCHAR(128) NOT NULL,
    `base_type` VARCHAR(128) NOT NULL,
    `content` MEDIUMTEXT NOT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_pos` (`map_path`(64), `x`, `y`, `z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
