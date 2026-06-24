CREATE TABLE IF NOT EXISTS `ss13_character_slots` (
  `ckey`        VARCHAR(32)    NOT NULL,
  `slot_limit`  TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`ckey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
