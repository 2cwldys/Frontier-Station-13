CREATE TABLE IF NOT EXISTS `ss13_removed_structures` (
    `id`         INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    `map_path`   VARCHAR(64)     NOT NULL,
    `type`       VARCHAR(128)    NOT NULL,
    `x`          SMALLINT UNSIGNED NOT NULL,
    `y`          SMALLINT UNSIGNED NOT NULL,
    `z`          SMALLINT UNSIGNED NOT NULL,
    `removed_at` DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_position` (`map_path`, `type`, `x`, `y`, `z`),
    INDEX `idx_map_path` (`map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
