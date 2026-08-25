--
-- Per-character earned skill levels.
--
-- Distinct from ss13_characters.skills, which is CHARGEN-slot data keyed by
-- the slot's own id and only ever holds the Trained default fill. This table
-- is the round-to-round record of what a character has actually earned: the
-- Professional tiers gained from a cargo skill manual or from being taught by
-- somebody who already held them, and the tiers lost again to resleeving.
--
-- Keyed (ckey, char_name) to match every other ss13_char_* table, so it lines
-- up with the persistence layer's character identity rather than the prefs
-- slot -- and so the existing character delete sweep and rename paths can
-- carry it along with the rest.
--
-- skills_json is skill typepath -> integer level, the same shape
-- get_skill_snapshot() produces (code/datums/skills/skill_progression.dm).
--

CREATE TABLE IF NOT EXISTS `ss13_char_skills` (
  `ckey`        VARCHAR(32)  NOT NULL,
  `char_name`   VARCHAR(64)  NOT NULL,
  `skills_json` MEDIUMTEXT   DEFAULT NULL,
  `saved_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
