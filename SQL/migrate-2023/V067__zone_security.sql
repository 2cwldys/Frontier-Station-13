--
-- Per-z-level security zones (EVE-style): 0 = nullsec (default, lawless),
-- 1 = midsec (factions enforce their own laws), 2 = highsec (Hub law,
-- combat outlawed, offenses escalate to admins). Managed by the
-- "Set Z-Level Security Zone" admin verb; z-only key mirrors
-- ss13_zlevel_persistence's convention.
--
CREATE TABLE IF NOT EXISTS ss13_zone_security (
    z TINYINT NOT NULL PRIMARY KEY,
    sec_level TINYINT NOT NULL DEFAULT 0,
    notes VARCHAR(128) NULL,
    saved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
