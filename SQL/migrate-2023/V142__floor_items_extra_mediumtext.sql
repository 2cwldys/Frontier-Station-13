--
-- ss13_floor_items.extra was the only persistence blob column declared JSON
-- (V034). Every other blob in this schema -- ss13_char_inventory.inventory_json,
-- ss13_persistent_objects.content, worldstate/turfs/atmos/mob health -- is
-- MEDIUMTEXT, read back as text, and decoded with json_decode(). The JSON type
-- does not come back as text, so the floor-item restore path could never decode
-- it and every item fell through to a stateless respawn: storage bags reverted
-- to their fill() defaults and faction-tagged equipment lost its tag/colour.
--
-- LONGTEXT (what MariaDB's JSON alias actually is) -> MEDIUMTEXT preserves every
-- existing value; item blobs are orders of magnitude below the 16MB limit. Rows
-- are NOT rewritten -- the stored JSON text is already correct.
--

ALTER TABLE `ss13_floor_items` MODIFY `extra` MEDIUMTEXT NULL;
