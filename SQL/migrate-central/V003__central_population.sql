CREATE TABLE IF NOT EXISTS `ss13_central_population` (
  `server_id`   VARCHAR(100) NOT NULL,
  `playercount` INT NOT NULL,
  `admincount`  INT NOT NULL,
  `updated_at`  DATETIME NOT NULL,
  PRIMARY KEY (`server_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
