CREATE TABLE IF NOT EXISTS `ss13_faction_founding_petitions` (
  `faction_uid`   VARCHAR(64) NOT NULL,
  `founder_ckey`  VARCHAR(32) NOT NULL,
  `founder_name`  VARCHAR(64) NOT NULL,
  `faction_name`  VARCHAR(64) NOT NULL,
  `abbreviation`  VARCHAR(8)  NOT NULL,
  `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`faction_uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_faction_founding_supporters` (
  `faction_uid`    VARCHAR(64) NOT NULL,
  `supporter_ckey` VARCHAR(32) NOT NULL,
  `supported_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`faction_uid`, `supporter_ckey`),
  FOREIGN KEY (`faction_uid`) REFERENCES `ss13_faction_founding_petitions`(`faction_uid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_faction_creation_toggle` (
  `id`      TINYINT NOT NULL DEFAULT 1,
  `enabled` BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
