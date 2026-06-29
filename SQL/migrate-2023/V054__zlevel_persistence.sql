-- Per-Z-level persistence toggle.
-- Empty table = all Z levels persist (safe default).
-- Only disabled Z levels have rows (enabled = 0).
-- Admins use the "Toggle Z-Level Persistence" verb to manage this.

CREATE TABLE IF NOT EXISTS `ss13_zlevel_persistence` (
    `z` TINYINT UNSIGNED NOT NULL COMMENT 'Z level number (1-indexed)',
    `enabled` TINYINT(1) NOT NULL DEFAULT 1
        COMMENT '1 = persist normally; 0 = skip this Z level on save/load (e.g. mining zones)',
    `notes` VARCHAR(128) DEFAULT NULL COMMENT 'Admin label, e.g. "Mining - regenerate each restart"',
    PRIMARY KEY (`z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
