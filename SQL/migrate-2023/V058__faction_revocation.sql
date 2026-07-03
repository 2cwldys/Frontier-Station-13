CREATE TABLE IF NOT EXISTS `ss13_faction_pending_revokes` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `faction_uid`    VARCHAR(32)  NOT NULL,
  `target_ckey`    VARCHAR(32)  NOT NULL,
  `target_name`    VARCHAR(64)  NOT NULL,
  `issued_by_ckey` VARCHAR(32)  NOT NULL,
  `issued_at`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processed`      TINYINT(1)   NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  INDEX `idx_pending_ckey` (`target_ckey`, `processed`),
  CONSTRAINT `fk_fpr_faction` FOREIGN KEY (`faction_uid`) REFERENCES `ss13_factions` (`uid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Monotonic per-faction counter instead of a wall-clock cutoff -- world.realtime
-- resets every server restart so it can't be compared against a wall-clock
-- DATETIME across rounds. Each charge card stores the epoch it was printed
-- under; "Invalidate All Charge Cards" bumps this by 1, instantly voiding
-- every card printed under an older epoch (online, offline, or on the floor).
ALTER TABLE `ss13_faction_accounts`
  ADD COLUMN `cards_epoch` INT UNSIGNED NOT NULL DEFAULT 0;
