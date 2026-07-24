--
-- Admin-managed cargo export price list, replacing the old hardcoded
-- per-material /datum/export price list. Loaded into an in-memory cache at
-- boot (cargoExportsInitialize()), managed live by the Manage Cargo Exports
-- admin verb. Anything not listed here still sells, at CARGO_EXPORT_BASE_PRICE.
--

CREATE TABLE IF NOT EXISTS `ss13_cargo_exports` (
  `id`         INT NOT NULL AUTO_INCREMENT,
  `map_path`   VARCHAR(64) NOT NULL,
  `type_path`  VARCHAR(255) NOT NULL,
  `price`      INT NOT NULL DEFAULT 10,
  `label`      VARCHAR(64) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `type_path_map` (`type_path`, `map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
