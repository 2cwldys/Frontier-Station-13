--
-- Reverses V099__drydock_shuttle_id_reuse.sql. shuttle_id reuse (an app-level
-- "lowest free slot" allocator, _drydockNextFreeShuttleId(), persistence_shuttles.dm)
-- turned out to be pure downside: it's the reason ship_schematic.dm's
-- resolve_ship() needs a bound_purchased_at staleness guard at all (to detect
-- a reused id belonging to a different ship now), and it's the reason an
-- abandoned-but-not-deleted row permanently "eats" a low id instead of being
-- an unremarkable gap. shuttle_id is never shown to players (only in
-- admin-facing logs and the admin Restore Ship Backup verb), and the
-- deployed-ship cap already counts live rows rather than depending on id
-- density -- so there's no cost to letting it grow unboundedly.
--
-- Restoring AUTO_INCREMENT on a PK column that already has data is safe:
-- MariaDB/MySQL automatically sets the next auto-increment value to
-- MAX(existing shuttle_id) + 1 at ALTER time. No existing row's id changes.
--

ALTER TABLE `ss13_drydock_ships` MODIFY COLUMN `shuttle_id` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT;
