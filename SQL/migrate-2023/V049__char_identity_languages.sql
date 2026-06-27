ALTER TABLE `ss13_char_identity`
  ADD COLUMN IF NOT EXISTS `languages_json` TEXT DEFAULT NULL AFTER `flavor_texts`;
