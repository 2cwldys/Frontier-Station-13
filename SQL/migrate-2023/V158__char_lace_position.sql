--
-- Loose (unvaulted, uninstalled) neural lace position persistence.
--
-- ss13_neural_lace_vault already persists a lace sitting in a lace_storage
-- vault, and the organ-augment save path already persists one installed in
-- a human. Neither covers a registered lace just sitting loose somewhere
-- (in a bag, a locker, a closet) that isn't directly on a floor tile
-- (the one case persistence_floor_items.dm's own sweep already catches).
--
-- Keyed (ckey, char_name) like every other ss13_char_* table -- the LACE's
-- own registered identity, same as ss13_char_lace_dna. Populated by a
-- periodic sweep (charLacePositionFinalize(), persistence_lace_dna.dm)
-- rather than event-driven writes, since there's no "store" moment for a
-- lace that's just been dropped in a bag the way lace_storage's own
-- store_lace() has.
--

CREATE TABLE IF NOT EXISTS `ss13_char_lace_position` (
  `ckey`          VARCHAR(32)  NOT NULL,
  `char_name`     VARCHAR(64)  NOT NULL,
  `map_path`      VARCHAR(255) NOT NULL,
  `pos_x`         SMALLINT     NOT NULL,
  `pos_y`         SMALLINT     NOT NULL,
  `pos_z`         SMALLINT     NOT NULL,
  `owner_faction` VARCHAR(64)  DEFAULT '',
  `lace_damage`   SMALLINT     NOT NULL DEFAULT 0,
  `saved_at`      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
