--
-- Global ship identity for CENTRAL_SYNC_SHIPS -- shuttle_id is a bare
-- per-server AUTO_INCREMENT with no cross-server meaning (two independent
-- servers would routinely mint colliding shuttle_id=1,2,3...), so a real
-- cross-server identity is synthesized once, at purchase
-- (drydockBuy(), persistence_shuttles.dm), from this server's own
-- guaranteed-unique CENTRAL_SERVER_ID + its local shuttle_id:
-- "[CENTRAL_SERVER_ID]:[shuttle_id]". NULL for every ship bought before
-- this existed -- not backfilled, matching this session's existing
-- precedent (CENTRAL_SYNC_CHARACTERS/_FACTIONS/_MONEY only wire up new
-- writes/reads going forward, never retroactively).
--

ALTER TABLE `ss13_drydock_ships`
	ADD COLUMN `global_ship_id` VARCHAR(80) DEFAULT NULL,
	ADD UNIQUE KEY `idx_global_ship_id` (`global_ship_id`);
