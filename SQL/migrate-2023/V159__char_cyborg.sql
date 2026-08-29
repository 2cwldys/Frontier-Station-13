--
-- Cyborg chassis persistence.
--
-- Cyborgs (/mob/living/silicon/robot) previously had ZERO persistence at
-- all -- a chassis was a fresh shell every round, confirmed via a full
-- sweep of this codebase's persistence subsystem. Synthetic Storage
-- (code/game/objects/structures/machinery/synthetic_storage.dm) is the
-- cyborg counterpart to a cryopod: store a piloted cyborg, get an
-- equivalent one back later.
--
-- Keyed by ckey ALONE, not (ckey, char_name) like every ss13_char_* table --
-- robots aren't chargen characters with a saved-slot roster the way humans
-- are (mind/ckey are plain base-/mob vars on a robot, no chargen-equivalent
-- concept exists), so there's no "which cyborg character" to disambiguate.
-- One stored cyborg slot per player.
--
-- cyborg_json is a flat blob of the fields actually worth persisting (name,
-- module type, law preset, cell type/charge, cosmetic/toggle vars) -- NOT a
-- byte-for-byte chassis snapshot. Module contents (specific tools/consumable
-- charge) and any custom (non-preset) law edits are deliberately out of
-- scope; see persistence_cyborg.dm's own doc comment for the exact field
-- list and why.
--

CREATE TABLE IF NOT EXISTS `ss13_char_cyborg` (
  `ckey`        VARCHAR(32)  NOT NULL,
  `cyborg_json` MEDIUMTEXT   DEFAULT NULL,
  `saved_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
