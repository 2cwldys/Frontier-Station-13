--
-- Faction automatic payroll toggle -- officers can flip this in the faction
-- management console. When TRUE, factionFinalize() runs payroll for the
-- faction unconditionally on every persistence autosave cycle (every 30
-- minutes, persistence.dm). When FALSE, only the manual "Pay Members Now"
-- action pays members. Defaults to automatic for every faction.
--

ALTER TABLE `ss13_factions`
    ADD COLUMN `auto_payroll` TINYINT(1) NOT NULL DEFAULT 1
        COMMENT 'If TRUE, payroll runs automatically every autosave cycle. If FALSE, only manual "Pay Members Now" pays members.';
