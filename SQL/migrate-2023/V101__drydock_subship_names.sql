-- Persisted custom names for sub-ships mapped into a drydock hull's own
-- hangar bay (e.g. the COC Surveyor's inner "COC Survey Shuttle"). Bound
-- entirely to the parent ship -- no independent ownership/ledger, just a
-- per-instance display name keyed off the parent's shuttle_id plus the
-- sub-ship's own fixed shuttle_tag (disambiguates hulls with more than one
-- sub-ship, e.g. Xanu Frigate's "Xanu Fighter"/"Xanu Boarder").

CREATE TABLE IF NOT EXISTS `ss13_drydock_subship_names` (
    `shuttle_id` INT UNSIGNED NOT NULL,
    `shuttle_tag` VARCHAR(64) NOT NULL,
    `custom_name` VARCHAR(64) NOT NULL,
    PRIMARY KEY (`shuttle_id`, `shuttle_tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
