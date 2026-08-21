-- Central mirrors for CENTRAL_SYNC_CHARACTERS -- see
-- docs/cross_server_persistence.md and persistence_mobs.dm's write-through/
-- read-through-on-miss helpers. Same column shapes as their local
-- counterparts (ss13_char_identity/ss13_char_health/ss13_char_inventory/
-- ss13_mob_position, SQL/migrate-2023) so existing query text ports over
-- almost unchanged, just pointed at SScentraldb instead of SSdbcore.
--
-- ss13_mob_position's local table has grown extra columns over many
-- migrations (last_pod_x/y/z, imprisoned/imprisoned_until/
-- imprisoned_by_faction_uid, faction_bound/faction_bound_uid) written by
-- separate UPDATE-in-place procs (persistence_set_last_pod/_imprisoned/
-- _faction_bound) rather than mobPositionSave() itself -- all mirrored
-- here too, same shape as local, so imprisonment/faction-shackle/
-- last-used-pod state follows a character across servers along with
-- their core position.

CREATE TABLE IF NOT EXISTS `ss13_char_identity` (
  `ckey`           VARCHAR(32)  NOT NULL,
  `char_name`      VARCHAR(64)  NOT NULL,
  `citizenship`    VARCHAR(64)  DEFAULT NULL,
  `special_voice`  VARCHAR(64)  DEFAULT NULL,
  `flavor_texts`   MEDIUMTEXT   DEFAULT NULL,
  `languages_json` TEXT         DEFAULT NULL,
  `saved_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_char_health` (
  `ckey`              VARCHAR(32) NOT NULL,
  `char_name`         VARCHAR(64) NOT NULL,
  `organ_damage_json` MEDIUMTEXT  DEFAULT NULL,
  `stamina`           FLOAT       NOT NULL DEFAULT 100,
  `bodytemperature`   FLOAT       NOT NULL DEFAULT 310,
  `on_fire`           TINYINT(1)  NOT NULL DEFAULT 0,
  `fire_stacks`       FLOAT       NOT NULL DEFAULT 0,
  `nutrition`         FLOAT       NOT NULL DEFAULT 400,
  `hydration`         FLOAT       NOT NULL DEFAULT 400,
  `saved_at`          TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_char_inventory` (
  `ckey`           VARCHAR(32) NOT NULL,
  `char_name`      VARCHAR(64) NOT NULL,
  `inventory_json` MEDIUMTEXT  NOT NULL,
  `saved_at`       TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_mob_position` (
  `ckey`        VARCHAR(32)       NOT NULL,
  `char_name`   VARCHAR(64)       NOT NULL,
  `x`           SMALLINT UNSIGNED NOT NULL,
  `y`           SMALLINT UNSIGNED NOT NULL,
  `z`           SMALLINT UNSIGNED NOT NULL,
  `char_state`  VARCHAR(16)       NOT NULL DEFAULT 'alive',
  `in_lace`     TINYINT(1)        NOT NULL DEFAULT 0,
  `lace_pod_x`  SMALLINT UNSIGNED DEFAULT NULL,
  `lace_pod_y`  SMALLINT UNSIGNED DEFAULT NULL,
  `lace_pod_z`  SMALLINT UNSIGNED DEFAULT NULL,
  `last_pod_x`  SMALLINT UNSIGNED DEFAULT NULL,
  `last_pod_y`  SMALLINT UNSIGNED DEFAULT NULL,
  `last_pod_z`  SMALLINT UNSIGNED DEFAULT NULL,
  `imprisoned`  TINYINT(1)        NOT NULL DEFAULT 0,
  `imprisoned_until`          DATETIME    NULL DEFAULT NULL,
  `imprisoned_by_faction_uid` VARCHAR(32) NULL DEFAULT NULL,
  `faction_bound`     TINYINT(1)  NOT NULL DEFAULT 0,
  `faction_bound_uid` VARCHAR(32) NULL DEFAULT NULL,
  `saved_at`    TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
