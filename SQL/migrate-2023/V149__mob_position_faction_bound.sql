--
-- IPC/cyborg faction shackle -- a per-character "faction_bound" flag,
-- persisted alongside every other cryo/position-state field on
-- ss13_mob_position (char_state, imprisoned, etc.), same shape as the
-- imprisonment columns (V119/V120). faction_bound_uid records WHICH
-- faction currently holds the shackle -- independent of whatever ID card
-- the character currently holds, since the shackle must survive an ID
-- swap/removal. See persistence_set_faction_bound()/
-- persistence_character_faction_bound() (persistence_mobs.dm).
--

ALTER TABLE `ss13_mob_position`
	ADD COLUMN `faction_bound` TINYINT(1) NOT NULL DEFAULT 0,
	ADD COLUMN `faction_bound_uid` VARCHAR(32) NULL DEFAULT NULL;
