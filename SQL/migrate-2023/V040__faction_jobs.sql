CREATE TABLE IF NOT EXISTS `ss13_faction_jobs` (
  `id`          INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  `faction_uid` VARCHAR(32)      NOT NULL,
  `title`       VARCHAR(64)      NOT NULL,
  `access_json` JSON             DEFAULT NULL,
  `pay_rate`    INT              NOT NULL DEFAULT 500,
  `rank`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `faction_title` (`faction_uid`, `title`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
