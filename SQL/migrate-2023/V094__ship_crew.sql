--
-- Per-ship guest/crew list -- lets a drydock ship's owner (or a faction
-- officer, for a faction-owned ship) grant boarding access to specific
-- ckeys without giving them ownership, faction membership, or any
-- retrieve/stash/sell rights. Single ship kind (post corvette-retirement
-- merge), so no ship_kind discriminator column is needed.
--

CREATE TABLE IF NOT EXISTS `ss13_ship_crew` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    `shuttle_id` INT UNSIGNED NOT NULL,
    `ckey` VARCHAR(32) NOT NULL,
    `label` VARCHAR(64) DEFAULT NULL,
    `added_by` VARCHAR(32) DEFAULT NULL,
    `added_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uniq_shuttle_ckey` (`shuttle_id`, `ckey`)
);
