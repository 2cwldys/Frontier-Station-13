--
-- Stock market: add total_shares_outstanding so market cap / total investor
-- net wealth (current_price * total_shares_outstanding) is a real, tracked
-- quantity, not just a bare per-share price with no market structure behind
-- it. Players will only ever hold a sliver of a company's float -- this is
-- what represents "everyone else" (the simulated rest of the market).
--

ALTER TABLE `ss13_stock_companies`
	ADD COLUMN `total_shares_outstanding` BIGINT UNSIGNED NOT NULL DEFAULT 1000000 AFTER `base_price`;

-- Backfill the placeholder seed companies with a bit of blue-chip-vs-small-cap
-- variety instead of leaving every row at the flat default above. No-ops on a
-- fresh install (nothing to match yet) -- stockMarketInitialize()'s own seed
-- INSERT sets these directly for that case.
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 2000000 WHERE `ticker` = 'ZNTH';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 800000  WHERE `ticker` = 'ORBF';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 500000  WHERE `ticker` = 'VSPR';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 3000000 WHERE `ticker` = 'HLCY';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 1500000 WHERE `ticker` = 'PRAX';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 2500000 WHERE `ticker` = 'MRDN';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 400000  WHERE `ticker` = 'SLCE';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 600000  WHERE `ticker` = 'TNTL';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 1200000 WHERE `ticker` = 'AURL';
UPDATE `ss13_stock_companies` SET `total_shares_outstanding` = 300000  WHERE `ticker` = 'NGHT';
