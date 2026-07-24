--
-- Stock market: per-transaction trade history (ticker, buy/sell, shares,
-- price paid/received per share, timestamp) so the "Portfolio" tab can show
-- a player their own trading history, including the price they bought at --
-- distinct from ss13_stock_price_history, which tracks the company's own
-- price over time regardless of who traded.
--

CREATE TABLE IF NOT EXISTS `ss13_stock_trade_log` (
	`id`              INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`ckey`            VARCHAR(32)  NOT NULL,
	`company_id`      INT UNSIGNED NOT NULL,
	`is_buy`          TINYINT(1)   NOT NULL,
	`shares`          INT UNSIGNED NOT NULL,
	`price_per_share` INT UNSIGNED NOT NULL,
	`total`           INT UNSIGNED NOT NULL,
	`traded_at`       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	INDEX `idx_ckey_traded` (`ckey`, `traded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
