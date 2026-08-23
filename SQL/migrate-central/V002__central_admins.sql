CREATE TABLE IF NOT EXISTS `ss13_central_admins` (
  `ckey`     VARCHAR(50) NOT NULL,
  `rank`     TEXT NOT NULL,
  `flags`    INT NOT NULL,
  `added_by` VARCHAR(50) NULL,
  `added_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
