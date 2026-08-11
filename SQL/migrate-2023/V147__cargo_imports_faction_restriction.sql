--
-- Adds an admin-managed FACTION RESTRICTION alongside the existing price
-- override on ss13_cargo_imports (V139 + V140, persistence_cargo_imports.dm).
--
-- Same row, same semantics as the price override it sits beside: sparse (a row
-- exists only for an item an admin actually changed), scoped per map_path, and
-- pruned at boot if the code definition is renamed or removed -- CODE WINS ON
-- CHANGE, exactly as the price column already behaves. An item with no row runs
-- entirely at its compile-time /singleton/cargo_item defaults.
--
-- restricted_to_faction NULL  = no faction override; the item's own
--                               compile-time restricted_to_faction applies.
-- restricted_to_faction set   = only a console shackled to that faction uid may
--                               see or order the item (_can_order_faction_item(),
--                               cargo_order.dm).
--
-- price becomes NULLABLE because a row may now exist purely to set a faction
-- restriction, with no repricing intended. NULL price means "no price override",
-- mirroring how an absent row already means "no override at all". Existing rows
-- are unaffected -- they all carry a real price and keep it.
--

ALTER TABLE `ss13_cargo_imports`
  ADD COLUMN `restricted_to_faction` VARCHAR(64) NULL DEFAULT NULL AFTER `price`;

ALTER TABLE `ss13_cargo_imports`
  MODIFY COLUMN `price` INT NULL DEFAULT NULL;
