-- Per-faction access whitelist -- specific (ckey, character_name) pairs
-- granted entry to that faction's claimed territory, and exempted from the
-- auto-eviction sweep, regardless of the faction raiding toggle or faction
-- membership/alliances.
--
-- Deliberately scoped to ONE named character per ckey, not "this player, any
-- character" -- matches ss13_faction_members' own ckey keying but adds
-- character_name so a whitelist grant doesn't silently cover every alt a
-- ckey ever plays.
--
-- Local to this shard only (no central-DB mirror, unlike ss13_faction_members)
-- -- territory access is a single-shard concept, Zs don't exist cross-shard.
CREATE TABLE IF NOT EXISTS `ss13_faction_access_whitelist` (
  `id`             INT          NOT NULL AUTO_INCREMENT,
  `faction_uid`    VARCHAR(64)  NOT NULL,
  `ckey`           VARCHAR(32)  NOT NULL,
  `character_name` VARCHAR(64)  NOT NULL,
  `added_by_ckey`  VARCHAR(32)  DEFAULT NULL,
  `added_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `faction_ckey_name` (`faction_uid`, `ckey`, `character_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
