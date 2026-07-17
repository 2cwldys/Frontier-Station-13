-- Drydock ship slots are meant to be reused once a ship is permanently
-- removed (scuttled or sold) -- both removal paths already fully purge
-- every table keyed by shuttle_id (ss13_drydock_ships_backup, ss13_ship_crew,
-- purgeShipScopeRows()) before the row is gone, so reusing the freed number
-- is safe. AUTO_INCREMENT never reuses a value after a DELETE, so drop it;
-- drydockBuy() (persistence_shuttles.dm) now assigns shuttle_id itself via
-- an app-level "lowest free slot" allocator instead of last_insert_id.

ALTER TABLE `ss13_drydock_ships` MODIFY COLUMN `shuttle_id` INT(10) UNSIGNED NOT NULL;
