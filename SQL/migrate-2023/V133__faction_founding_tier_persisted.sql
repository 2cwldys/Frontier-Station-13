--
-- is_company_tier: permanent record of whether uid was founded through the
-- cheaper Company path (25,000cr/5 supporters) rather than a Full Faction
-- (100,000cr/10 supporters) -- set once at tryFinalizeFounding()
-- (persistence_factions.dm) and never changed afterward. Distinct from the
-- founding petition's own is_company column (ss13_faction_founding_petitions,
-- V132) -- that row is deleted the moment a petition finalizes, so this is
-- what lets is_company_tier_faction() keep answering correctly indefinitely
-- (e.g. to refuse a Company faction claiming a faction beacon). Unrelated to
-- stock market listing/CEO status -- a Full Faction that later lists and
-- gets a CEO is still not "company tier". DEFAULT 0 correctly covers every
-- pre-existing and admin-made faction, which have no tier concept at all.
--

ALTER TABLE `ss13_factions` ADD COLUMN `is_company_tier` TINYINT(1) NOT NULL DEFAULT 0;
