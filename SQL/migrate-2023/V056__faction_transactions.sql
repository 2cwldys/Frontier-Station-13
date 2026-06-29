-- Faction transaction log — records every debit and credit so command can
-- see order history, payroll payments, transfers, and exports.
-- Populated by faction_debit() and faction_credit() in persistence_factions.dm.

CREATE TABLE IF NOT EXISTS `ss13_faction_transactions` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `faction_uid` VARCHAR(32) NOT NULL,
    `amount` INT NOT NULL COMMENT 'positive = credit, negative = debit',
    `reason` VARCHAR(255) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_faction` (`faction_uid`),
    INDEX `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
