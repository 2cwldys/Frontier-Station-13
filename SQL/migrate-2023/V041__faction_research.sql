CREATE TABLE IF NOT EXISTS `ss13_faction_research` (
  `faction_uid` VARCHAR(32) NOT NULL,
  `map_path`    VARCHAR(64) NOT NULL,
  `tech_data`   MEDIUMTEXT  NOT NULL,
  `saved_at`    DATETIME    NOT NULL,
  PRIMARY KEY (`faction_uid`, `map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
