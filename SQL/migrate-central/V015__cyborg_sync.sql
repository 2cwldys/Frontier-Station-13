--
-- Central mirror of ss13_char_cyborg.
--
-- Same shape and same ckey key as the local table -- a stored cyborg's
-- name/module/laws/cosmetics are character-defining progression data, the
-- same category ss13_char_skills/ss13_char_lace_dna already sync, not raw
-- per-server position data (see ss13_char_lace_position's own migration for
-- why THAT one is deliberately not synced). Gated behind
-- CENTRAL_SYNC_CHARACTERS; inert with central sync off.
--

CREATE TABLE IF NOT EXISTS `ss13_char_cyborg` (
  `ckey`        VARCHAR(32)  NOT NULL,
  `cyborg_json` MEDIUMTEXT   DEFAULT NULL,
  `saved_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
