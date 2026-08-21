CREATE TABLE IF NOT EXISTS `ss13_shards` (
  `shard_id`   VARCHAR(100) NOT NULL,
  `port`       INT NOT NULL,
  `status`     ENUM('running','stopped') NOT NULL DEFAULT 'running',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `started_at` DATETIME NULL,
  PRIMARY KEY (`shard_id`),
  UNIQUE KEY `idx_port` (`port`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
