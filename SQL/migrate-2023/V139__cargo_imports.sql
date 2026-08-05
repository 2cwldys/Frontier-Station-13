--
-- Admin-managed cargo IMPORT price overrides (Modify Cargo Imports admin verb,
-- persistence_cargo_imports.dm). Sparse by design: a row exists only for an item
-- an admin has actually repriced, and its absence means "use the compile-time
-- default", i.e. initial(/singleton/cargo_item/price). Deleting a row IS the
-- restore-to-code-default operation, so no seed step or seeded-marker table is
-- needed here (unlike ss13_cargo_exports, which replaced a legacy system whole).
--
-- Loaded into GLOB.cargo_import_prices at boot by cargoImportsInitialize() and
-- applied straight onto the live /singleton/cargo_item instances.
--

CREATE TABLE IF NOT EXISTS `ss13_cargo_imports` (
  `id`        INT NOT NULL AUTO_INCREMENT,
  `map_path`  VARCHAR(64) NOT NULL,
  `type_path` VARCHAR(255) NOT NULL,
  `price`     INT NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `type_path_map` (`type_path`, `map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
