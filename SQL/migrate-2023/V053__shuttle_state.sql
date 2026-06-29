-- Persistent shuttle location tracking.
-- Stores where each shuttle was docked when the server shut down.
-- On restart, SSshuttle restores positions before SSpersistence loads objects,
-- preventing turf/object duplication at wrong locations.

CREATE TABLE IF NOT EXISTS `ss13_persistent_shuttles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `shuttle_name` VARCHAR(64) NOT NULL COMMENT 'datum/shuttle.name — unique shuttle identifier',
    `location_tag` VARCHAR(128) NOT NULL COMMENT 'shuttle_landmark.landmark_tag of last docked location',
    `saved_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_shuttle` (`shuttle_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
