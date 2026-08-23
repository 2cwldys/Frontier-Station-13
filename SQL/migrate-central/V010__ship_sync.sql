-- Central mirror for CENTRAL_SYNC_SHIPS -- see
-- docs/cross_server_persistence.md and persistence_shuttles.dm's
-- "CENTRAL SHIP SYNC" section.
--
-- Core ownership/existence fields ONLY, not full ship state -- interior
-- contents (persistence_ship_interiors.dm), crew ACLs (ss13_ship_crew),
-- schematic banking, and deployment position (z/overmap_x/overmap_y,
-- meaningless standalone on a different server's map) are explicitly out
-- of scope for this phase, same "core first" boundary Phase 1 drew around
-- ss13_mob_position's supplementary setters.
--
-- Keyed by `global_ship_id` (VARCHAR "[CENTRAL_SERVER_ID]:[shuttle_id]",
-- V154__drydock_global_ship_id.sql), not shuttle_id -- shuttle_id alone
-- has no cross-server meaning (bare per-server AUTO_INCREMENT, would
-- collide immediately between two servers).

CREATE TABLE IF NOT EXISTS `ss13_drydock_ships` (
  `global_ship_id`       VARCHAR(80)  NOT NULL,
  `origin_server_id`     VARCHAR(100) NOT NULL,
  `template_id`          VARCHAR(64)  NOT NULL,
  `owner_ckey`           VARCHAR(32)  DEFAULT NULL,
  `owner_char_name`      VARCHAR(64)  DEFAULT NULL,
  `owner_account_number` INT          DEFAULT NULL,
  `faction_uid`          VARCHAR(32)  DEFAULT NULL,
  `repossessed`          TINYINT(1)   NOT NULL DEFAULT 0,
  `prev_owner_ckey`      VARCHAR(64)  DEFAULT NULL,
  `prev_owner_char_name` VARCHAR(64)  DEFAULT NULL,
  `prev_faction_uid`     VARCHAR(32)  DEFAULT NULL,
  `stashed`              TINYINT(1)   NOT NULL DEFAULT 1,
  `custom_name`          VARCHAR(64)  DEFAULT NULL,
  `custom_class`         VARCHAR(32)  DEFAULT NULL,
  `title_ckey`           VARCHAR(32)  DEFAULT NULL,
  `title_char_name`      VARCHAR(64)  DEFAULT NULL,
  `title_faction_uid`    VARCHAR(32)  DEFAULT NULL,
  `reported_stolen`      TINYINT(1)   NOT NULL DEFAULT 0,
  `purchased_at`         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `saved_at`             TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`global_ship_id`),
  INDEX `idx_owner` (`owner_ckey`, `owner_char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
