--
-- Central mirror of ss13_char_lace_dna.
--
-- Same shape and same (ckey, char_name) key as the local table, so the
-- existing character sync helpers (_centralCharacterWriteThrough /
-- _centralCharacterReadThrough / _centralCharacterSelfHealLocal,
-- persistence_mobs.dm) can carry a neural lace's synced DNA/species the same
-- way they already carry ss13_char_identity/ss13_char_skills -- a character
-- resleeved on one server keeps their lace's correctly-synced DNA when they
-- play on another sharing this database.
--
-- Gated behind CENTRAL_SYNC_CHARACTERS along with the rest of the character
-- tables; with central sync off nothing ever touches this.
--

CREATE TABLE IF NOT EXISTS `ss13_char_lace_dna` (
  `ckey`      VARCHAR(32)  NOT NULL,
  `char_name` VARCHAR(64)  NOT NULL,
  `dna_json`  MEDIUMTEXT   DEFAULT NULL,
  `saved_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
