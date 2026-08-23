-- Central mirrors for CENTRAL_SYNC_FACTIONS -- see
-- docs/cross_server_persistence.md and persistence_factions.dm's
-- "CENTRAL FACTION SYNC" section. Same column shapes as their local
-- counterparts (ss13_factions/ss13_faction_accounts/ss13_faction_members,
-- SQL/migrate-2023) minus surrogate ids/foreign keys (mirror tables use
-- natural keys, no referential integrity enforcement needed here, same
-- convention V006__character_sync.sql already established).
--
-- ss13_faction_accounts is the one table in this migration that matters
-- for correctness, not just availability: every write into it from DM
-- (persistence_factions.dm's _faction_balance_credit_atomic()/
-- _faction_balance_debit_atomic()) is a SQL-side delta
-- (balance = balance +/- :amount), never an absolute overwrite, and every
-- debit is an atomic check-and-decrement (WHERE balance >= :amount) --
-- required precisely because this table, unlike character data, has no
-- presence-lock equivalent keeping concurrent writes from two servers
-- from being the routine case once faction members are spread across
-- more than one central-linked server.

CREATE TABLE IF NOT EXISTS `ss13_factions` (
  `uid`                       VARCHAR(32)  NOT NULL,
  `name`                      VARCHAR(64)  NOT NULL,
  `abbreviation`              VARCHAR(8)   DEFAULT NULL,
  `founder_ckey`              VARCHAR(32)  DEFAULT NULL,
  `is_company_tier`           TINYINT(1)   NOT NULL DEFAULT 0,
  `pirate_founded`            TINYINT(1)   NOT NULL DEFAULT 0,
  `leader_ckey`               VARCHAR(32)  DEFAULT NULL,
  `leader_char_name`          VARCHAR(64)  DEFAULT NULL,
  `color`                     VARCHAR(7)   DEFAULT NULL,
  `auto_payroll`              TINYINT(1)   NOT NULL DEFAULT 1,
  `allowed_cargo_category`    VARCHAR(64)  DEFAULT NULL,
  `cargo_category_changed_at` DATETIME     DEFAULT NULL,
  `last_payroll_at`           DATETIME     DEFAULT NULL,
  `created_at`                TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_faction_accounts` (
  `faction_uid`      VARCHAR(32) NOT NULL,
  `balance`          BIGINT      NOT NULL DEFAULT 0,
  `cards_epoch`      INT UNSIGNED NOT NULL DEFAULT 0,
  `master_card_lost` TINYINT(1)  NOT NULL DEFAULT 0,
  `saved_at`         TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`faction_uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_faction_members` (
  `ckey`        VARCHAR(32) NOT NULL,
  `real_name`   VARCHAR(64) NOT NULL,
  `faction_uid` VARCHAR(32) NOT NULL,
  `job_title`   VARCHAR(64) DEFAULT NULL,
  `rank`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `joined_at`   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `faction_uid`),
  INDEX `idx_faction` (`faction_uid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
