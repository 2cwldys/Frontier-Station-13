CREATE TABLE IF NOT EXISTS `ss13_template_turfs` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `template_id` INT NOT NULL,
    `x` INT NOT NULL,
    `y` INT NOT NULL,
    `z` INT NOT NULL,
    `turf_type` VARCHAR(128) NOT NULL,
    `base_type` VARCHAR(128) NOT NULL,
    `content` MEDIUMTEXT NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_template_pos` (`template_id`, `x`, `y`, `z`),
    CONSTRAINT `fk_tmpl_turfs_template` FOREIGN KEY (`template_id`) REFERENCES `ss13_world_templates`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
