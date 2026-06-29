CREATE TABLE IF NOT EXISTS `ss13_faction_members` (
    `id`          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    `ckey`        VARCHAR(32)   NOT NULL,
    `real_name`   VARCHAR(64)   NOT NULL,
    `faction_uid` VARCHAR(32)   NOT NULL,
    `job_title`   VARCHAR(64)   DEFAULT NULL,
    `rank`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `joined_at`   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_member` (`ckey`, `faction_uid`),
    INDEX `idx_faction` (`faction_uid`),
    CONSTRAINT `fk_fm_faction` FOREIGN KEY (`faction_uid`) REFERENCES `ss13_factions` (`uid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
