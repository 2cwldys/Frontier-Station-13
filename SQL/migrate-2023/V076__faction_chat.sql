CREATE TABLE IF NOT EXISTS `ss13_faction_chat` (
    `msg_id`      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_uid` VARCHAR(32) NOT NULL,
    `sender_name` VARCHAR(64) NOT NULL,
    `sender_ckey` VARCHAR(32) NOT NULL,
    `message`     VARCHAR(512) NOT NULL,
    `sent_at`     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`msg_id`),
    KEY `idx_faction_time` (`faction_uid`, `msg_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
