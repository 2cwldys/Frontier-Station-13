CREATE TABLE IF NOT EXISTS `ss13_char_inventory` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `ckey` VARCHAR(32) NOT NULL,
    `char_name` VARCHAR(64) NOT NULL,
    `inventory_json` MEDIUMTEXT NOT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_ckey_name` (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
