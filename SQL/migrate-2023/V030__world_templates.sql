CREATE TABLE IF NOT EXISTS `ss13_world_templates` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `description` TEXT DEFAULT NULL,
    `map_path` VARCHAR(128) NOT NULL,
    `created_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_name_map` (`name`, `map_path`(64))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_template_pending` (
    `id` INT NOT NULL DEFAULT 1,
    `template_id` INT NOT NULL,
    `map_path` VARCHAR(128) NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
