--
-- Central mirror of ss13_char_skills.
--
-- Same shape and same (ckey, char_name) key as the local table, so the
-- existing character sync helpers (_centralCharacterWriteThrough /
-- _centralCharacterReadThrough / _centralCharacterSelfHealLocal,
-- persistence_mobs.dm) can carry skills exactly the way they already carry
-- ss13_char_identity -- a character who earned Professional on one server
-- keeps it when they play on another sharing this database.
--
-- Gated behind CENTRAL_SYNC_CHARACTERS along with the rest of the character
-- tables; with central sync off nothing ever touches this.
--

CREATE TABLE IF NOT EXISTS `ss13_char_skills` (
  `ckey`        VARCHAR(32)  NOT NULL,
  `char_name`   VARCHAR(64)  NOT NULL,
  `skills_json` MEDIUMTEXT   DEFAULT NULL,
  `saved_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
