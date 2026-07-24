-- Audit trail for "Panic Purge IDs" (faction_manage.dm) -- one row per
-- whole-faction ID purge, visible to officers+ in the Faction Management
-- terminal (not just admins via log_game/message_admins).

CREATE TABLE IF NOT EXISTS `ss13_faction_id_purges` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `faction_uid`    VARCHAR(32)  NOT NULL,
  `issued_by_ckey` VARCHAR(32)  NOT NULL,
  `issued_by_name` VARCHAR(64)  NOT NULL,
  `revoked_count`  INT UNSIGNED NOT NULL DEFAULT 0,
  `member_count`   INT UNSIGNED NOT NULL DEFAULT 0,
  `created_at`     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_faction` (`faction_uid`),
  CONSTRAINT `fk_fip_faction` FOREIGN KEY (`faction_uid`) REFERENCES `ss13_factions` (`uid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
