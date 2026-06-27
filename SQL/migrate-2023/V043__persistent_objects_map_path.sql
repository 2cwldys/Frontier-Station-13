ALTER TABLE `ss13_persistent_objects`
  ADD COLUMN IF NOT EXISTS `map_path` VARCHAR(64) NOT NULL DEFAULT 'sccv_horizon' AFTER `z`,
  ADD INDEX IF NOT EXISTS `idx_map_path` (`map_path`);
