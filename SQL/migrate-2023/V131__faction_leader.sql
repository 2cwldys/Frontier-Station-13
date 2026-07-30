--
-- leader_ckey / leader_char_name: an admin-designated faction leader, for
-- factions created via the admin "Create New Faction" verb rather than the
-- organic self-founding petition flow (which sets founder_ckey instead --
-- see V089). Distinct from founder_ckey: this is a specific character (not
-- just any character played by that ckey), and can be reassigned or cleared
-- by an admin at any time via "Manage Faction Account" -> "Set Faction
-- Leader" (persistence_factions.dm), whereas founder_ckey is set once at
-- founding and never reassigned. Checked by the "Print Master Card" action
-- (faction_manage.dm) alongside founder_ckey and is_faction_ceo().
--

ALTER TABLE `ss13_factions` ADD COLUMN `leader_ckey` VARCHAR(32) NULL;
ALTER TABLE `ss13_factions` ADD COLUMN `leader_char_name` VARCHAR(64) NULL;
