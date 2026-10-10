--
-- Per-character neural lace DNA/species snapshot.
--
-- A neural lace is a synthetic organ, but its DNA/species now get synced to
-- whichever body it's installed in every time it's surgically replaced()
-- (organs_internal.dm's real transplant path, and the resleever's own
-- resleever.dm _do_resleeve(), which now calls that same proc). Without this
-- table that sync only lives as long as the physical lace object does --
-- any save/restore (cryo, logout, restart) rebuilds the lace fresh via
-- persistence_mobs.dm's augment restore, which only ever reapplied
-- lace_damage/registered_name/registered_ckey/owner_faction, never dna/species.
--
-- Keyed (ckey, char_name) like every other ss13_char_* table -- this follows
-- the CHARACTER the lace is registered to (registered_ckey/registered_name),
-- not whatever body currently happens to house it, so it round-trips
-- correctly across an arbitrary number of resleeves.
--
-- dna_json is the full /datum/dna snapshot (uni_identity, struc_enzymes,
-- unique_enzymes, b_type, real_name, species string, SE/UI arrays,
-- body_markings) plus the organ's own species singleton typepath --
-- everything get_lace_dna_snapshot() (neural_lace.dm) captures.
--

CREATE TABLE IF NOT EXISTS `ss13_char_lace_dna` (
  `ckey`      VARCHAR(32)  NOT NULL,
  `char_name` VARCHAR(64)  NOT NULL,
  `dna_json`  MEDIUMTEXT   DEFAULT NULL,
  `saved_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`ckey`, `char_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
