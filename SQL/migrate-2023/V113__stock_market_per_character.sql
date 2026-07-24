--
-- Stock market: isolate holdings and trade history per-character (ckey +
-- char_name), matching how ss13_money_accounts itself is actually schema'd
-- (UNIQUE KEY idx_ckey_name (ckey, char_name)) -- a second character on the
-- same ckey now starts with a clean portfolio instead of sharing one.
--

ALTER TABLE `ss13_stock_holdings`
	ADD COLUMN `char_name` VARCHAR(64) NOT NULL DEFAULT '' AFTER `ckey`,
	DROP INDEX `uq_holding`,
	ADD UNIQUE KEY `uq_holding` (`ckey`, `char_name`, `company_id`);

ALTER TABLE `ss13_stock_trade_log`
	ADD COLUMN `char_name` VARCHAR(64) NOT NULL DEFAULT '' AFTER `ckey`,
	DROP INDEX `idx_ckey_traded`,
	ADD INDEX `idx_ckey_traded` (`ckey`, `char_name`, `traded_at`);
