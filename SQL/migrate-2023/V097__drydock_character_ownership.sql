--
-- Personal drydock ownership (and crew access) was keyed on ckey alone,
-- which in a multi-character codebase means EVERY character a player owns
-- shares ownership/boarding rights to a ship one of their characters
-- bought -- wrong, since a ship belongs to a character, not an account.
-- Pairs owner_ckey/crew ckey with the owning character's name (real_name),
-- matching the existing (ckey, char_name) composite-identity convention
-- already used by ss13_mob_position (persistence_mobs.dm). Dev environment
-- cutover -- no existing personal ownership/crew data is worth migrating,
-- so existing rows simply get NULL here (their owner_ckey no longer
-- matches any character until re-set, same low-stakes tradeoff as every
-- other dev-environment schema cutover this project has made). Faction
-- ownership (faction_uid) is untouched -- factions were never a
-- character-identity concept in the first place.
--

ALTER TABLE `ss13_drydock_ships`
    ADD COLUMN `owner_char_name` VARCHAR(64) DEFAULT NULL AFTER `owner_ckey`;

ALTER TABLE `ss13_drydock_ships_backup`
    ADD COLUMN `owner_char_name` VARCHAR(64) DEFAULT NULL AFTER `owner_ckey`;

ALTER TABLE `ss13_ship_crew`
    ADD COLUMN `char_name` VARCHAR(64) DEFAULT NULL AFTER `ckey`,
    DROP INDEX `uniq_shuttle_ckey`,
    ADD UNIQUE KEY `uniq_shuttle_ckey_char` (`shuttle_id`, `ckey`, `char_name`);
