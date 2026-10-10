-- Tracked objects no longer age out. expires_at becomes nullable so NULL can
-- mean "this row has no deadline", and only an explicit tombstone
-- (expires_at = NOW(), objectsDatabaseExpireEntry()) retires a row.
ALTER TABLE `ss13_persistent_objects` MODIFY `expires_at` DATETIME NULL;

-- Everything the world is still using loses its deadline. Rows already past
-- their deadline are tombstones marking destroyed objects -- clearing those
-- would resurrect deconstructed objects on the next boot, so they are left as
-- they are for the grace-period reaper to collect.
UPDATE `ss13_persistent_objects`
SET `expires_at` = NULL
WHERE `expires_at` > NOW()
  AND `type` NOT LIKE '/obj/effect/decal/cleanable%';

-- Cleanable decals are the one kind that still carries a deadline, matching
-- DECAL_PERSISTENCE_EXPIRY_HOURS (persistence_decals.dm).
UPDATE `ss13_persistent_objects`
SET `expires_at` = DATE_ADD(NOW(), INTERVAL 1 HOUR)
WHERE `expires_at` > NOW()
  AND `type` LIKE '/obj/effect/decal/cleanable%';
