--
-- Tracks WHICH faction currently holds a character imprisoned (cryogenic
-- prison storage, cryopod_prison.dm) -- imprisonment is exclusive: a
-- character already held by one faction cannot be silently re-imprisoned
-- (and their sentence/cell overwritten) by a different faction's pod. Same-
-- faction re-processing is still allowed. NULL whenever imprisoned = 0.
--

ALTER TABLE `ss13_mob_position`
	ADD COLUMN `imprisoned_by_faction_uid` VARCHAR(32) NULL DEFAULT NULL;
