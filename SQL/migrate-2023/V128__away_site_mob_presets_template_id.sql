--
-- Optional away-site TEMPLATE scoping for away-site mob pool entries.
-- NULL (the default, and every pre-existing row) keeps today's behavior --
-- eligible on any away-site template. A non-null value restricts that pool
-- entry to only the one away-site template id it names (e.g. "station"),
-- so specific templates can be given their own dedicated pirates instead of
-- sharing one flat pool with every other away site on the map.
--

ALTER TABLE `ss13_away_site_mob_presets`
	ADD COLUMN `template_id` VARCHAR(64) NULL DEFAULT NULL;
