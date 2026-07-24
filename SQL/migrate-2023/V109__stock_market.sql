--
-- Stock market: fluctuating fake-company share prices, tied to a player's
-- personal money_account (ss13_money_accounts). Companies are seeded in code
-- (stockMarketInitialize(), persistence_stock_market.dm) the first time this
-- table is empty -- see that proc's doc comment for how to rename/replace
-- the placeholder companies later.
--

CREATE TABLE IF NOT EXISTS `ss13_stock_companies` (
	`company_id`    INT UNSIGNED  NOT NULL AUTO_INCREMENT,
	`ticker`        VARCHAR(8)    NOT NULL,
	`name`          VARCHAR(64)   NOT NULL,
	`current_price` INT UNSIGNED  NOT NULL DEFAULT 100,
	`previous_price` INT UNSIGNED NOT NULL DEFAULT 100,
	-- "Fair value" anchor current_price gently mean-reverts toward (see
	-- /datum/stock_company/proc/tick_price(), stock_market.dm) -- keeps a
	-- long-running server's prices from drifting to absurd extremes over
	-- weeks of continuous ticking. Fixed at seed time.
	`base_price`    INT UNSIGNED  NOT NULL DEFAULT 100,
	-- Max ordinary percent move per 5-minute tick, e.g. 1.50 = 1.5%. Kept
	-- small on purpose -- real single-stock moves over a few minutes are a
	-- fraction of a percent, not a whole day's volatility.
	`volatility`    DECIMAL(4,2) UNSIGNED NOT NULL DEFAULT 1.50,
	`updated_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`company_id`),
	UNIQUE KEY `uq_ticker` (`ticker`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_stock_holdings` (
	`id`            INT UNSIGNED  NOT NULL AUTO_INCREMENT,
	`ckey`          VARCHAR(32)   NOT NULL,
	`company_id`    INT UNSIGNED  NOT NULL,
	`shares_owned`  INT UNSIGNED  NOT NULL DEFAULT 0,
	`avg_cost_basis` INT UNSIGNED NOT NULL DEFAULT 0,
	`updated_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	UNIQUE KEY `uq_holding` (`ckey`, `company_id`),
	INDEX `idx_company` (`company_id`),
	CONSTRAINT `fk_holding_company` FOREIGN KEY (`company_id`) REFERENCES `ss13_stock_companies` (`company_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_stock_price_history` (
	`id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`company_id`  INT UNSIGNED NOT NULL,
	`price`       INT UNSIGNED NOT NULL,
	`recorded_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`id`),
	INDEX `idx_company` (`company_id`),
	INDEX `idx_recorded` (`recorded_at`),
	CONSTRAINT `fk_history_company` FOREIGN KEY (`company_id`) REFERENCES `ss13_stock_companies` (`company_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
