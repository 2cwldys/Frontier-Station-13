--
-- Splits permanent "title" (who legitimately bought/was given a ship --
-- never changes except via a deliberate drydockGiveSchematic() transfer)
-- away from the existing owner_ckey/owner_char_name/faction_uid, which are
-- now genuinely mutable "current owner" fields: banking a schematic you
-- aren't titled to (drydockBankSchematic()) reassigns those to you and
-- flags reported_stolen. Dev-environment cutover -- existing ships have no
-- ownership history, so their current owner becomes their permanent title.
--

ALTER TABLE `ss13_drydock_ships`
	ADD COLUMN `title_ckey` VARCHAR(32) DEFAULT NULL,
	ADD COLUMN `title_char_name` VARCHAR(64) DEFAULT NULL,
	ADD COLUMN `title_faction_uid` VARCHAR(32) DEFAULT NULL,
	ADD COLUMN `reported_stolen` TINYINT(1) NOT NULL DEFAULT 0;

UPDATE `ss13_drydock_ships`
	SET title_ckey = owner_ckey, title_char_name = owner_char_name, title_faction_uid = faction_uid;
