--
-- Faction color -- a hex string ("#rrggbb") officers can set via the faction
-- management console, used to tint clothing/equipment tagged to the faction
-- with the faction tagger (see persistence_faction_tagger.dm). Lives on the
-- identity table alongside name/abbreviation, not ss13_faction_accounts.
--

ALTER TABLE `ss13_factions` ADD COLUMN `color` VARCHAR(7) DEFAULT NULL;
