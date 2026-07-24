CREATE TABLE IF NOT EXISTS `ss13_faction_corvettes_backup` (
    `corvette_id`  INT UNSIGNED NOT NULL,
    `template_id`  VARCHAR(64) NOT NULL,
    `faction_uid`  VARCHAR(32) NOT NULL,
    `purchased_at` DATETIME DEFAULT NULL,
    `backed_up_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`corvette_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
