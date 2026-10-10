-- Central mirror of ss13_factions.recruiting (SQL/migrate-2023/V164__faction_recruiting.sql)
-- -- set_faction_recruiting() (persistence_factions.dm) writes this via
-- _factionCentralPartialUpdate(), and _faction_hydrate_from_central() reads
-- it back for a faction first seen on a different central-linked server.

ALTER TABLE `ss13_factions` ADD COLUMN `recruiting` TINYINT(1) NOT NULL DEFAULT 0;
