--
-- Records the cargo item's display name as it was when an admin set the price
-- override. cargoImportsInitialize() compares this against the item's live name
-- at boot: if the code has since renamed the item, the override is auto-pruned
-- and the item goes back to its compile-time price. Combined with pruning rows
-- whose type path no longer resolves at all, this means any change to an item's
-- code definition -- rename or outright removal -- hands that item back to the
-- code instead of leaving a stale override in force.
--
-- ss13_cargo_imports (V139) is new in the same release and has no rows to
-- backfill, so the column is simply added.
--

ALTER TABLE `ss13_cargo_imports`
  ADD COLUMN `item_name` VARCHAR(128) NULL;
