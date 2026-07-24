--
-- Marks a cargo export entry as illegal/black-market -- only sells at its
-- configured price (real sale, not just catalog display) while an
-- operational piracy beacon is present on that item's current Z-level.
-- Without one, it silently falls back to the normal base export price.
--

ALTER TABLE `ss13_cargo_exports`
  ADD COLUMN `is_illegal` TINYINT(1) NOT NULL DEFAULT 0;
