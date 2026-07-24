--
-- Faction shareholders: percentage-of-company equity, distinct from the
-- per-share "stockholders" traded on the open exchange (ss13_stock_holdings).
-- Granted by redeeming a printed Share Certificate (Faction Management
-- program, code/modules/paperwork/share_certificate.dm) -- listing a faction
-- on the exchange seeds whoever listed it at 100%, and every certificate
-- redeemed after that proportionally dilutes the existing cap table, so
-- percent always sums to 100 for a listed faction. Dividends (pay_dividends,
-- faction_manage.dm) pay out against THIS table by raw percent.
--

CREATE TABLE IF NOT EXISTS `ss13_faction_shareholders` (
	`id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`faction_uid`    VARCHAR(32)  NOT NULL,
	`ckey`           VARCHAR(32)  NOT NULL,
	`char_name`      VARCHAR(64)  NOT NULL DEFAULT '',
	`percent`        DECIMAL(5,2) UNSIGNED NOT NULL,
	`granted_by`     VARCHAR(64)  DEFAULT NULL,
	`certificate_id` VARCHAR(16)  DEFAULT NULL,
	`created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uq_shareholder` (`faction_uid`, `ckey`, `char_name`),
	INDEX `idx_faction` (`faction_uid`),
	CONSTRAINT `fk_shareholder_faction` FOREIGN KEY (`faction_uid`) REFERENCES `ss13_factions` (`uid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
