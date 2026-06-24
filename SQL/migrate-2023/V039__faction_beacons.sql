CREATE TABLE IF NOT EXISTS `ss13_faction_beacons` (
  `faction_uid` VARCHAR(32)      NOT NULL,
  `x`           SMALLINT UNSIGNED NOT NULL,
  `y`           SMALLINT UNSIGNED NOT NULL,
  `z`           SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (`faction_uid`, `x`, `y`, `z`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
