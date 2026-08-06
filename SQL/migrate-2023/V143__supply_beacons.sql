--
-- Supply Beacon Terminal: overmap trade-crate economy. A beacon is a fixed
-- point on the overmap chart (no Z-level of its own) admins place with the
-- "Modify Cargo Beacons" verb; each one tracks its own price per commodity,
-- seeded in code (GLOB.supply_beacon_commodities, persistence_supply_beacons.dm)
-- the first time a given (beacon, commodity) pair is saved.
--

CREATE TABLE IF NOT EXISTS `ss13_supply_beacons` (
	`beacon_id`  INT UNSIGNED NOT NULL AUTO_INCREMENT,
	`x`          SMALLINT UNSIGNED NOT NULL,
	`y`          SMALLINT UNSIGNED NOT NULL,
	`notes`      VARCHAR(128) NOT NULL DEFAULT '',
	`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY (`beacon_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ss13_supply_beacon_commodities` (
	`beacon_id`      INT UNSIGNED NOT NULL,
	-- Matches a key in GLOB.supply_beacon_commodities (persistence_supply_
	-- beacons.dm), e.g. 'zenithium' -- not a foreign key to any table since
	-- commodities are code-defined, not database-defined.
	`commodity`      VARCHAR(16) NOT NULL,
	`current_price`  INT UNSIGNED NOT NULL DEFAULT 1000,
	`previous_price` INT UNSIGNED NOT NULL DEFAULT 1000,
	`price_high`     INT UNSIGNED NOT NULL DEFAULT 1000,
	`price_low`      INT UNSIGNED NOT NULL DEFAULT 1000,
	`updated_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	PRIMARY KEY (`beacon_id`, `commodity`),
	CONSTRAINT `fk_supply_beacon_commodity_beacon` FOREIGN KEY (`beacon_id`) REFERENCES `ss13_supply_beacons` (`beacon_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
