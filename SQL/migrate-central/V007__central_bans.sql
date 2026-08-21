-- Central ban list -- see docs/cross_server_persistence.md and
-- code/modules/admin/DB ban/central_ban.dm. A ban applied on any
-- central_sql_enabled server refuses a connection on every other server
-- sharing this central database, layered on top of (never replacing) each
-- server's own local ban system.

CREATE TABLE IF NOT EXISTS `ss13_central_bans` (
  `id`                INT          NOT NULL AUTO_INCREMENT,
  `ckey`              VARCHAR(32)  NOT NULL,
  `reason`            TEXT         NOT NULL,
  `banning_admin`     VARCHAR(32)  NOT NULL,
  `banned_at`         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at`        DATETIME     NULL DEFAULT NULL,
  `active`            TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  INDEX `idx_ckey_active` (`ckey`, `active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
