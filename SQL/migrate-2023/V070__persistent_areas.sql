--
-- Blueprint-created areas (finalize_area(), is_blueprint_area = TRUE): name,
-- turf membership, and faction ownership survive a restart. Never used for
-- mapped-in station areas -- those load from the map itself.
--
CREATE TABLE IF NOT EXISTS `ss13_persistent_areas` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `map_path` VARCHAR(64) NOT NULL,
    `z` INT NOT NULL,
    `name` VARCHAR(128) NOT NULL,
    `area_type` VARCHAR(128) NOT NULL,
    `turfs` MEDIUMTEXT NOT NULL,
    `persistent_network` VARCHAR(64) NULL,
    `saved_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_zone` (`map_path`(64), `z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
