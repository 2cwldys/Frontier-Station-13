--
-- Hub repossession: lets Hub security seize ownership of a ship outright
-- (not just force-stash it), then either return it to the original owner
-- or keep it as a Hub asset. repossessed flags the seizure; the prev_*
-- columns snapshot whatever ownership existed at seizure time so
-- drydockReturnToOwner() can restore it exactly, mirroring the existing
-- owner_ckey/owner_char_name/faction_uid column shapes on this same table.
--

ALTER TABLE `ss13_drydock_ships`
    ADD COLUMN `repossessed` TINYINT(1) NOT NULL DEFAULT 0 AFTER `faction_uid`,
    ADD COLUMN `prev_owner_ckey` VARCHAR(64) DEFAULT NULL AFTER `repossessed`,
    ADD COLUMN `prev_owner_char_name` VARCHAR(64) DEFAULT NULL AFTER `prev_owner_ckey`,
    ADD COLUMN `prev_faction_uid` VARCHAR(32) DEFAULT NULL AFTER `prev_owner_char_name`;
