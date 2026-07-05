ALTER TABLE `ss13_mob_position`
  ADD COLUMN IF NOT EXISTS `char_state` VARCHAR(16) NOT NULL DEFAULT 'alive' AFTER `lace_pod_z`;
