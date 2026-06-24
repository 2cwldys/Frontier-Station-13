CREATE TABLE IF NOT EXISTS `ss13_factions` (
  `uid`          VARCHAR(32)  NOT NULL,
  `name`         VARCHAR(64)  NOT NULL,
  `abbreviation` VARCHAR(8)   DEFAULT NULL,
  `description`  TEXT         DEFAULT NULL,
  `is_lore`      TINYINT(1)   NOT NULL DEFAULT 0,
  `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_faction_accounts` (
  `faction_uid`  VARCHAR(32)  NOT NULL,
  `balance`      BIGINT       NOT NULL DEFAULT 0,
  `saved_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`faction_uid`),
  FOREIGN KEY (`faction_uid`) REFERENCES `ss13_factions`(`uid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- No factions are pre-seeded. Admins add factions in-game via "Manage Faction Account".
