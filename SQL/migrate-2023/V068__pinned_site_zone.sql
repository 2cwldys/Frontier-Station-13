--
-- Security zone stored per pinned overmap site: away-site z-numbers reshuffle
-- each boot, so a pinned site's zone lives on its pin row (re-applied at
-- spawn) instead of a z-keyed ss13_zone_security row that could leak onto a
-- different site next session. 0 = nullsec, 1 = midsec, 2 = highsec.
--
ALTER TABLE ss13_persistent_away_sites
    ADD COLUMN sec_zone TINYINT NOT NULL DEFAULT 0;
