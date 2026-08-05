--
-- Admin-managed drydock ship purchase price overrides (Modify Ship Prices
-- admin verb, persistence_drydock_ship_prices.dm). Sparse by design: a row
-- exists only for a ship an admin has actually repriced, and its absence
-- means "use the compile-time default", i.e. initial(/datum/map_template/
-- drydock_ship/price). Deleting a row IS the restore-to-code-default
-- operation.
--
-- Loaded into GLOB.drydock_ship_price_overrides at boot by
-- drydockShipPricesInitialize() and applied straight onto the live
-- SSmapping.drydock_ship_templates instances.
--

CREATE TABLE IF NOT EXISTS `ss13_drydock_ship_prices` (
  `id`        INT NOT NULL AUTO_INCREMENT,
  `map_path`  VARCHAR(64) NOT NULL,
  `ship_id`   VARCHAR(64) NOT NULL,
  `price`     INT NOT NULL,
  `ship_name` VARCHAR(128) NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `ship_id_map` (`ship_id`, `map_path`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
