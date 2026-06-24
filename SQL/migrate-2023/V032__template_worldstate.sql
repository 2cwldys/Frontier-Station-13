CREATE TABLE IF NOT EXISTS `ss13_template_worldstate` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `template_id` INT NOT NULL,
    `type` VARCHAR(128) NOT NULL,
    `x` INT NOT NULL,
    `y` INT NOT NULL,
    `z` INT NOT NULL,
    `content` MEDIUMTEXT NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_template_type_pos` (`template_id`, `type`(64), `x`, `y`, `z`),
    CONSTRAINT `fk_tmpl_ws_template` FOREIGN KEY (`template_id`) REFERENCES `ss13_world_templates`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
