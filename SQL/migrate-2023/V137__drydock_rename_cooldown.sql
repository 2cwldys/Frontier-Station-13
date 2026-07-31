--
-- Drydock ship rename cooldown -- the main ship name/class (drydockRename(),
-- persistence_shuttles.dm) can only be changed once every 30 real-world
-- days by a non-admin, tracked here the same way the faction cargo-category
-- cooldown tracks its own (cargo_category_changed_at, V129). NULL means
-- "never renamed" -- no cooldown yet. Sub-ship renaming is untouched.
--

ALTER TABLE `ss13_drydock_ships`
	ADD COLUMN `renamed_at` DATETIME NULL DEFAULT NULL;
