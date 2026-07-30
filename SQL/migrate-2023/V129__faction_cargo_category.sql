--
-- Faction cargo specialization (FACTION_CARGO_SPECIALIZATION, code/_compile_options.dm) --
-- a real (non-Hub) faction can only order from ONE cargo category at a time,
-- chosen at founding and changeable later (command rank + 1-month real-world
-- cooldown tracked here, or an unrestricted admin override). NULL means
-- "hasn't chosen one yet" -- nothing orderable from a faction console until
-- it does.
--

ALTER TABLE `ss13_factions`
	ADD COLUMN `allowed_cargo_category` VARCHAR(64) NULL DEFAULT NULL,
	ADD COLUMN `cargo_category_changed_at` DATETIME NULL DEFAULT NULL;

ALTER TABLE `ss13_faction_founding_petitions`
	ADD COLUMN `cargo_category` VARCHAR(64) NULL DEFAULT NULL;
