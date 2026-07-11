--
-- Frontier is a structural clone of Horizon and shares its z-level numbering.
-- These three tables were keyed only by (type,x,y,z) or z alone, so once both
-- maps are saved against the same database their rows would collide and
-- silently cross-contaminate. Scope them by map_path, mirroring the
-- convention already used by ss13_persistent_areas (V070). Existing rows
-- default to an empty map_path and get backfilled with the real value the
-- next time they're saved.
--

ALTER TABLE `ss13_worldstate_objects`
    ADD COLUMN `map_path` VARCHAR(64) NOT NULL DEFAULT '' AFTER `id`;

ALTER TABLE `ss13_worldstate_objects`
    DROP INDEX `idx_type_pos`;

ALTER TABLE `ss13_worldstate_objects`
    ADD UNIQUE INDEX `idx_type_pos` (`map_path`, `type`(64), `x`, `y`, `z`);

ALTER TABLE `ss13_zone_security`
    ADD COLUMN `map_path` VARCHAR(64) NOT NULL DEFAULT '' AFTER `z`;

ALTER TABLE `ss13_zone_security`
    DROP PRIMARY KEY;

ALTER TABLE `ss13_zone_security`
    ADD PRIMARY KEY (`map_path`, `z`);

ALTER TABLE `ss13_zlevel_persistence`
    ADD COLUMN `map_path` VARCHAR(64) NOT NULL DEFAULT '' AFTER `z`;

ALTER TABLE `ss13_zlevel_persistence`
    DROP PRIMARY KEY;

ALTER TABLE `ss13_zlevel_persistence`
    ADD PRIMARY KEY (`map_path`, `z`);
