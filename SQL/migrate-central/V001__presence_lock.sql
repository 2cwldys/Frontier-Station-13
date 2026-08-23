--
-- Cross-server presence lock. Lives on the CENTRAL database, not the local
-- per-server one -- this table only means anything when more than one
-- server can see the same row.
--
-- Answers one question: "is this character/ship currently active on some
-- OTHER authorized server right now?" A row's existence IS the lock; there
-- is no separate enabled/disabled flag. Acquired when a character spawns
-- into play or a ship is retrieved from drydock; released when the
-- character enters cryo (or disconnects without cryoing) or the ship is
-- stashed. A second server checks for a row before allowing either to
-- happen locally, and refuses (naming server_id) if one is already held
-- elsewhere.
--
-- This is what makes sharing ss13_characters/ss13_money_accounts/faction
-- tables/ss13_drydock_ships across servers safe without rebuilding the
-- existing save model into something fully transactional: only the server
-- holding a subject's lock ever has a live copy of its data in memory, so
-- only one server is ever writing it back at a time. See the project's own
-- design notes for the one thing this does NOT cover on its own (faction
-- treasury, touched by multiple different characters/servers at once --
-- needs atomic SQL-side balance updates instead, independent of this table).
--
-- subject_id is a plain string rather than a typed foreign key: the central
-- copies of ss13_characters/ss13_drydock_ships don't exist yet as of this
-- migration (this table is being stood up ahead of them, as the foundation
-- everything else builds on), and a loose text key keeps this table's own
-- schema independent of tables that may still change shape before they
-- exist. For a character, the same "[ckey]|[char_name]" composite this
-- codebase's own in-memory persistence caches already key by
-- (persistence_position_cache and friends, persistence_mobs.dm); for a
-- ship, shuttle_id cast to text.
--
-- locked_at is for auditing and for spotting a lock that has been held
-- suspiciously long (e.g. a server that crashed without releasing) -- this
-- migration does not itself define any staleness/expiry behavior; that is
-- real product/behavior design (how long is "stale", auto-clear vs require
-- admin action, and whether characters and ships should even be treated the
-- same way) that hasn't been decided yet and does not belong silently
-- embedded in a schema migration.
--

CREATE TABLE IF NOT EXISTS `ss13_presence_lock` (
  `subject_type` ENUM('character','ship') NOT NULL,
  `subject_id`   VARCHAR(255) NOT NULL,
  `server_id`    VARCHAR(100) NOT NULL,
  `locked_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`subject_type`, `subject_id`),
  INDEX `idx_server_id` (`server_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
