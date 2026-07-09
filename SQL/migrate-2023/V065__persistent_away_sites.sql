--
-- Pinned persistent overmap sites: away-site templates an admin has chosen
-- to persist. Pinned sites always spawn (bypassing the away-site RNG budget)
-- in fixed id order so their z-numbers stay deterministic across boots, at
-- a fixed overmap position, and their contents save/load like station decks.
-- Managed by the "Persistent Overmap Sites" admin verb.
--
CREATE TABLE IF NOT EXISTS ss13_persistent_away_sites (
    id INT AUTO_INCREMENT PRIMARY KEY,
    template_name VARCHAR(128) NOT NULL UNIQUE,
    map_path VARCHAR(64) NOT NULL,
    overmap_x SMALLINT NOT NULL DEFAULT 0,
    overmap_y SMALLINT NOT NULL DEFAULT 0,
    last_z TINYINT NOT NULL DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    notes VARCHAR(128) NULL,
    saved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
