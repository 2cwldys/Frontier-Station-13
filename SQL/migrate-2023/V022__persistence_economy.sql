CREATE TABLE IF NOT EXISTS `ss13_money_accounts` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `ckey` VARCHAR(32) NOT NULL,
    `char_name` VARCHAR(64) NOT NULL,
    `account_number` INT NOT NULL DEFAULT 0,
    `money` INT NOT NULL DEFAULT 0,
    `remote_access_pin` VARCHAR(8) DEFAULT NULL,
    `public_account` TINYINT(1) NOT NULL DEFAULT 0,
    `suspended` TINYINT(1) NOT NULL DEFAULT 0,
    `security_level` INT NOT NULL DEFAULT 0,
    `transaction_log` MEDIUMTEXT DEFAULT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_ckey_name` (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
