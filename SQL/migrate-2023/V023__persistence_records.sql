CREATE TABLE IF NOT EXISTS `ss13_crew_records` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `ckey` VARCHAR(32) NOT NULL,
    `char_name` VARCHAR(64) NOT NULL,
    `rank` VARCHAR(64) DEFAULT NULL,
    `criminal_status` VARCHAR(32) NOT NULL DEFAULT 'None',
    `crimes` TEXT DEFAULT NULL,
    `ccia_notes` TEXT DEFAULT NULL,
    `medical_notes` TEXT DEFAULT NULL,
    `security_notes` TEXT DEFAULT NULL,
    `saved_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE INDEX `idx_ckey_name` (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
