-- Central mirror for CENTRAL_SYNC_FACTIONS -- see
-- docs/cross_server_persistence.md and SQL/migrate-2023/V171__faction_access_whitelist.sql
-- for the local table this mirrors. Natural composite key, no surrogate
-- `id`/AUTO_INCREMENT -- same convention V008__faction_sync.sql already
-- established for ss13_faction_members (mirror tables use natural keys,
-- no referential integrity enforcement needed here).
CREATE TABLE IF NOT EXISTS `ss13_faction_access_whitelist` (
  `faction_uid`    VARCHAR(64) NOT NULL,
  `ckey`           VARCHAR(32) NOT NULL,
  `character_name` VARCHAR(64) NOT NULL,
  `added_by_ckey`  VARCHAR(32) DEFAULT NULL,
  `added_at`       TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`faction_uid`, `ckey`, `character_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
