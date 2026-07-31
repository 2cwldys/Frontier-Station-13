--
-- Tracks whether a given map has ever had its cargo export price list seeded
-- from the legacy hardcoded /datum/export subtypes (persistence_cargo_exports.dm's
-- _cargoExportsSeedDefaults()), independent of ss13_cargo_exports' current row
-- count -- previously a row-count check alone couldn't tell "never configured"
-- from "admin wiped it clean", so a full "Wipe All Exports" was silently
-- undone by the very next boot's seed step.
--

CREATE TABLE IF NOT EXISTS `ss13_cargo_exports_seeded` (
  `map_path` VARCHAR(64) NOT NULL,
  PRIMARY KEY (`map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
