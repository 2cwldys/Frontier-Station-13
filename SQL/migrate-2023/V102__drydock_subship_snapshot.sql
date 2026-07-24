-- Self-contained "turf saving" for a sub-ship mapped into a drydock hull's
-- own hangar bay -- separate from the existing whole-Z ship-scale
-- persistence (ss13_drydock_ships / turfsFinalizeZ / objectsFinalizeZ etc).
-- One row per sub-ship instance: a JSON snapshot of every turf in its own
-- area (type + any loose items on it), captured at stash time and
-- re-applied at retrieve time so the sub-ship is always replenished to its
-- last good state, even if its compartment was damaged/destroyed or its
-- contents scattered in a previous session.

CREATE TABLE IF NOT EXISTS `ss13_drydock_subship_snapshot` (
    `shuttle_id` INT UNSIGNED NOT NULL,
    `shuttle_tag` VARCHAR(64) NOT NULL,
    `turf_data` LONGTEXT NOT NULL,
    PRIMARY KEY (`shuttle_id`, `shuttle_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
