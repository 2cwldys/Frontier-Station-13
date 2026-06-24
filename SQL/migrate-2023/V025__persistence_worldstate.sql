-- Worldstate persistence: saves station machinery state (airlocks, APCs, SMES, atmos equipment)
-- across rounds. Each row is keyed by (type, x, y, z) — one row per machine per position.
-- The UNIQUE INDEX enables ON DUPLICATE KEY UPDATE upserts.

CREATE TABLE IF NOT EXISTS `ss13_worldstate_objects` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `type` VARCHAR(128) NOT NULL,
    `x` INT NOT NULL,
    `y` INT NOT NULL,
    `z` INT NOT NULL,
    `content` MEDIUMTEXT NOT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_type_pos` (`type`(64), `x`, `y`, `z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
