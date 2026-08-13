--
-- pirate_founded: permanent record of whether uid was founded instantly
-- through a piracy beacon (piracyBeaconFoundFaction(), persistence_factions.dm)
-- rather than the normal petition process. Set once at founding, never
-- changed afterward. Gates two permanent restrictions: allowed_cargo_category
-- can never be self-service-set by the faction's own officers (cargo_order.dm
-- already treats a null category as "cannot order anything at all"), and
-- stockMarketListFaction() refuses to ever list the faction on the exchange.
-- DEFAULT 0 correctly covers every pre-existing and normally-founded faction.
--

ALTER TABLE `ss13_factions` ADD COLUMN `pirate_founded` TINYINT(1) NOT NULL DEFAULT 0;
