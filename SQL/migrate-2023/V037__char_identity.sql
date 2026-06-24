CREATE TABLE IF NOT EXISTS `ss13_char_identity` (
  `ckey`           VARCHAR(32)  NOT NULL,
  `char_name`      VARCHAR(64)  NOT NULL,
  `citizenship`    VARCHAR(64)  DEFAULT NULL,
  `special_voice`  VARCHAR(64)  DEFAULT NULL,
  `flavor_texts`   JSON         DEFAULT NULL,
  `saved_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
