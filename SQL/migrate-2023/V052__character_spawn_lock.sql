-- Track when a character first enters the world.
-- NULL = never spawned (preferences editable).
-- Non-NULL = spawned at least once (preferences locked).
-- Cleared only when the character is soft-deleted (deleted_at set).

ALTER TABLE `ss13_characters`
    ADD COLUMN `first_spawned_at` DATETIME NULL DEFAULT NULL
        COMMENT 'Set on first PersistentAutoSpawn; NULL = never entered world';
