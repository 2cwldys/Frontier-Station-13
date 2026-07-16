--
-- Per-instance ship identity -- lets an owner/officer give their ship a
-- custom display name/class distinct from its template defaults, surfaced
-- anywhere the overmap marker's own name/class already render (Sensors IFF,
-- Helm sector info). NULL falls back to the template's own defaults.
--

ALTER TABLE `ss13_drydock_ships`
    ADD COLUMN `custom_name` VARCHAR(64) DEFAULT NULL,
    ADD COLUMN `custom_class` VARCHAR(32) DEFAULT NULL;
