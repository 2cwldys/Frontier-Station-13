--
-- Stock market: a second listing category alongside the AI-simulated
-- companies -- a real faction's own stock, backed by (and moving money
-- into/out of) that faction's actual treasury. NULL = today's AI company;
-- set = a faction-listed one. Only one listing per faction.
--

ALTER TABLE `ss13_stock_companies`
	ADD COLUMN `faction_uid` VARCHAR(32) NULL DEFAULT NULL AFTER `company_id`,
	ADD UNIQUE KEY `uq_faction_listing` (`faction_uid`);
