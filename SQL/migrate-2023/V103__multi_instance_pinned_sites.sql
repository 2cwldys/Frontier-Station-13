--
-- ss13_persistent_away_sites previously had a column-level UNIQUE on
-- template_name alone, so only one pinned instance of any given away-site
-- template could ever exist (e.g. only one player-founded "station" total).
-- build_pinned_away_sites() (maps/_common/mapsystem/map.dm) already restores
-- every row for a template independently at boot -- the only actual blocker
-- was this constraint. Swapping to a composite key on (template_name,
-- overmap_x, overmap_y) allows many instances of the same template while
-- still refusing a literal duplicate at the exact same overmap coordinate.
--
ALTER TABLE ss13_persistent_away_sites DROP INDEX template_name;
ALTER TABLE ss13_persistent_away_sites ADD UNIQUE KEY uq_template_coords (template_name, overmap_x, overmap_y);
