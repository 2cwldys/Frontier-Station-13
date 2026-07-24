--
-- Stock market: track each company's running price high/low so the UI can
-- show a visual range bar (current price's position between its low and
-- high), not just a bare number.
--

ALTER TABLE `ss13_stock_companies`
	ADD COLUMN `price_high` INT UNSIGNED NOT NULL DEFAULT 100 AFTER `previous_price`,
	ADD COLUMN `price_low`  INT UNSIGNED NOT NULL DEFAULT 100 AFTER `price_high`;

UPDATE `ss13_stock_companies` SET `price_high` = `current_price`, `price_low` = `current_price`;
