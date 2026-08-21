-- Central mirror for CENTRAL_SYNC_MONEY -- see
-- docs/cross_server_persistence.md and persistence_economy.dm's
-- "CENTRAL MONEY SYNC" section. Same column shape as the local
-- ss13_money_accounts (SQL/migrate-2023), natural (ckey, char_name) key
-- instead of a surrogate id, same convention every other central mirror
-- this session already established.
--
-- `money` is the one column that matters for correctness here, same
-- reasoning as ss13_faction_accounts.balance (V008__faction_sync.sql):
-- it is NEVER written as an absolute value from DM -- only ever a SQL-side
-- delta (economyApplyMoneyDeltaCentral(), persistence_economy.dm), so two
-- servers crediting/debiting the same account concurrently can never lose
-- an update. Every other column (account_number, remote_access_pin,
-- public_account, suspended, security_level, transaction_log,
-- intro_shown) is low-stakes account metadata, synced periodically
-- (piggybacked on the existing economyFinalize() cycle) as a plain
-- last-write-wins upsert that deliberately never touches `money`.
--
-- Known, disclosed gap: `account_number` is assigned by each server
-- independently (SSeconomy.next_account_number, a randomized per-boot
-- counter) with no cross-server uniqueness guarantee -- unlike ckey+
-- char_name (this table's real identity) or shard ports/ship ids, nothing
-- here yet prevents two different central-linked servers from
-- independently assigning the SAME account_number to two DIFFERENT
-- characters. Low-probability (an ~888,888-value random space), not
-- fixed in this pass.

CREATE TABLE IF NOT EXISTS `ss13_money_accounts` (
  `ckey`              VARCHAR(32)  NOT NULL,
  `char_name`         VARCHAR(64)  NOT NULL,
  `account_number`    INT          NOT NULL DEFAULT 0,
  `money`             INT          NOT NULL DEFAULT 0,
  `remote_access_pin` VARCHAR(8)   DEFAULT NULL,
  `public_account`    TINYINT(1)   NOT NULL DEFAULT 0,
  `suspended`         TINYINT(1)   NOT NULL DEFAULT 0,
  `security_level`    INT          NOT NULL DEFAULT 0,
  `transaction_log`   MEDIUMTEXT   DEFAULT NULL,
  `intro_shown`       TINYINT(1)   NOT NULL DEFAULT 0,
  `saved_at`          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
