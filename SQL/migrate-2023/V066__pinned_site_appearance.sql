--
-- Custom appearance for pinned persistent overmap sites: an admin-set display
-- name and overmap icon_state that survive reboots. Applied to the site's
-- overmap marker each boot by build_pinned_away_sites(), managed via the
-- Rename Site / Change Icon actions of the Persistent Overmap Sites verb.
--
ALTER TABLE ss13_persistent_away_sites
    ADD COLUMN custom_name VARCHAR(128) NULL,
    ADD COLUMN custom_icon_state VARCHAR(64) NULL;
