-- Mirrors ss13_faction_corvettes_backup -- single row per shuttle_id,
-- always overwritten on each Retrieve, no explicit expiry.
CREATE TABLE IF NOT EXISTS `ss13_drydock_ships_backup` (
    `shuttle_id`   INT UNSIGNED NOT NULL,
    `template_id`  VARCHAR(64) NOT NULL,
    `owner_ckey`   VARCHAR(32) DEFAULT NULL,
    `faction_uid`  VARCHAR(32) DEFAULT NULL,
    `purchased_at` DATETIME DEFAULT NULL,
    `backed_up_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`shuttle_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
