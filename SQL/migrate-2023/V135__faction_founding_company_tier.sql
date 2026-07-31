--
-- is_company: which founding tier this petition was started as. TRUE =
-- "Company" (25,000cr, 5 supporters, stays limited to a single cargo
-- category, auto-listed on the stock exchange at 100% to the founder on
-- success). FALSE (default) = the original full faction tier (100,000cr,
-- 10 supporters, unrestricted cargo access across every category once
-- founded -- see FACTION_CARGO_CATEGORY_ALL, persistence_factions.dm).
--

ALTER TABLE `ss13_faction_founding_petitions` ADD COLUMN `is_company` TINYINT(1) NOT NULL DEFAULT 0;
