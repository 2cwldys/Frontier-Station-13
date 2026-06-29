-- Add account_number to faction members for offline payroll
-- The player's personal Idris account number is stored here so payroll
-- can credit their account without them being online.

ALTER TABLE `ss13_faction_members`
    ADD COLUMN `account_number` INT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN `last_paid_at` DATETIME DEFAULT NULL;

-- Track when each faction last ran payroll and what interval to use
ALTER TABLE `ss13_factions`
    ADD COLUMN `payroll_interval` INT UNSIGNED NOT NULL DEFAULT 3600
        COMMENT 'Payroll interval in seconds (default 1 hour)',
    ADD COLUMN `last_payroll_at` DATETIME DEFAULT NULL;
