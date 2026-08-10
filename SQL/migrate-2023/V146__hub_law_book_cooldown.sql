--
-- Persists the hub law book print cooldown (HUB_LAW_BOOK_PRINT_COOLDOWN,
-- code/modules/modular_computers/file_system/programs/command/card.dm)
-- across restarts -- previously an in-memory GLOBAL_LIST that reset every
-- server session. Mirrors ss13_personal_cargo_category's shape: a small,
-- ckey-keyed, real-calendar-time cooldown, queried live.
--

CREATE TABLE IF NOT EXISTS `ss13_hub_law_book_cooldown` (
	`ckey`             VARCHAR(32) NOT NULL,
	`last_printed_at`  DATETIME NOT NULL,
	PRIMARY KEY (`ckey`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
