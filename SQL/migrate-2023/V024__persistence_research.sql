CREATE TABLE IF NOT EXISTS `ss13_research_state` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `map_path` VARCHAR(128) NOT NULL,
    `tech_data` MEDIUMTEXT NOT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_map` (`map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
