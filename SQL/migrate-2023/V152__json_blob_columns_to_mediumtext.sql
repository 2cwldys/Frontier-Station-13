--
-- Same fix as V142 (ss13_floor_items.extra), applied to the two blob columns
-- it missed. V142's comment claimed `extra` "was the only persistence blob
-- column declared JSON" -- it was not. These two were also declared JSON:
--
--   ss13_faction_jobs.access_json   (V040) -- json_decode()'d in
--     factionInitialize() (persistence_factions.dm). Writes succeeded, but the
--     decode on boot never got text back, so every faction job silently loaded
--     with EMPTY access: access codes set through Faction Management appeared
--     to save and were gone again after every restart.
--
--   ss13_char_identity.flavor_texts (V037) -- json_decode()'d in
--     applyPersistentIdentityData() (persistence_mobs.dm). Same failure, so
--     character flavor text never survived a restart either.
--
-- The JSON type does not come back as text through this DB layer, which is
-- what breaks json_decode() on the read path. Every other persistence blob in
-- this schema is MEDIUMTEXT/TEXT and round-trips correctly.
--
-- LONGTEXT (what MariaDB's JSON alias actually is) -> MEDIUMTEXT preserves
-- every existing value; both blobs are orders of magnitude below the 16MB
-- limit. Rows are NOT rewritten -- the stored JSON text is already correct,
-- it simply could not be read back.
--
-- ss13_char_identity.languages_json (V049) is already TEXT and is untouched.
--

ALTER TABLE `ss13_faction_jobs`  MODIFY `access_json`  MEDIUMTEXT NULL;
ALTER TABLE `ss13_char_identity` MODIFY `flavor_texts` MEDIUMTEXT NULL;
