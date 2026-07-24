--
-- Ship interior persistence -- player ships (faction corvettes and drydock
-- ships) now keep their interior state across stash/retrieve cycles and
-- server restarts. Interior content rows live in the existing 7 persistence
-- content tables under a ship-scoped map_path key ("ship:c:<corvette_id>" /
-- "ship:d:<shuttle_id>") -- no new content tables needed. This column just
-- records when a hull's interior was last captured; NULL = never saved
-- (pristine template).
--
-- Lifecycle change shipping with this migration (code-side): ledger rows are
-- no longer deleted while a ship is deployed -- the row persists with
-- stashed=0, making crash recovery automatic.
--

ALTER TABLE `ss13_faction_corvettes`
    ADD COLUMN `interior_saved_at` DATETIME DEFAULT NULL COMMENT 'last shipInteriorSave() for this hull; NULL = never saved (pristine template)';

ALTER TABLE `ss13_drydock_ships`
    ADD COLUMN `interior_saved_at` DATETIME DEFAULT NULL COMMENT 'last shipInteriorSave() for this hull; NULL = never saved (pristine template)';
