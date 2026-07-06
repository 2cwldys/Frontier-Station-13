ALTER TABLE `ss13_characters_flavour`
  ADD COLUMN IF NOT EXISTS `neural_lace` TINYINT(1) NOT NULL DEFAULT 1 AFTER `char_id`;
