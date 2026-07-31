--
-- clocked_in: whether a faction member is currently "on shift" -- gates
-- factionPayroll() (persistence_factions.dm) on top of the existing
-- online/actively-played-character requirement. DEFAULT 0 is deliberate:
-- every existing member starts clocked OUT and must explicitly clock in
-- (ID Card Modification program) before payroll resumes for them. Cleared
-- automatically whenever a member is stored via the persistence cryo
-- system, normal or prison (persistStoreCharacter(), persistence_cryo.dm).
--

ALTER TABLE `ss13_faction_members` ADD COLUMN `clocked_in` TINYINT(1) NOT NULL DEFAULT 0;
